-- WholeFlow — least-privilege grants, cheaper RLS, FK indexes and data retention.
--
-- Run ONLY once every app and PC talks to the WholeFlow app API (Go), never
-- to the old data API (PostgREST): that one served `anon` and wrote through
-- the table grants this file removes.
--
--   * Privileges. New-business setups used to give anon/authenticated ALL on
--     every new table (incl. TRUNCATE, which ignores RLS). Now:
--       anon           nothing (the app API never uses it);
--       authenticated  SELECT on every table and view (RLS decides the rows),
--                      plus only the writes the app API makes as a signed-in
--                      person (derived from internal/appapi):
--                        sites        INSERT (id, business_id, company_id, name),
--                                     UPDATE (name), DELETE      sites_http.go
--                        visit_plans  INSERT (id, business_id, site_id, staff_id,
--                                     plan_date, weekday, starts_on, ends_on),
--                                     UPDATE (active), DELETE    visits_http.go
--                        users        UPDATE (name, is_active, requires_check_in)
--                                     only, under users_owner_update (the API
--                                     itself changes staff as service_role)
--                      Everything else is written by SECURITY DEFINER functions
--                      (check_in, set_site_shops, …) or as service_role.
--       service_role   SELECT/INSERT/UPDATE/DELETE (Tally PC uploads, staff
--                      management); no TRUNCATE/TRIGGER/REFERENCES.
--     Default privileges for future migrations follow the same rule: new
--     tables get nothing for anon/authenticated — grant SELECT explicitly.
--   * The database: PUBLIC may not connect (only <slug>_api / <slug>_auth),
--     and no API role may create temporary tables.
--   * Function EXECUTE is taken from PUBLIC and anon on every WholeFlow
--     function (extension functions untouched); authenticated and
--     service_role keep exactly what they had.
--   * SECURITY DEFINER functions run with search_path = public, pg_temp.
--   * RLS policies call the no-argument helpers through (select …) so they
--     run once per query, not once per row. Owners skip the per-row
--     can_see_* checks (those functions return true for owners anyway).
--   * Indexes for foreign keys that had none (cascades, purges, joins).
--   * purge_old_data(): retention of location data and sync logs (DPDP);
--     run daily by the server, as postgres. Periods: docs/DATABASE_SCHEMA.md.
--
-- Applied by the WholeFlow server to every business (scripts/migrate.sh).
-- Checks: tests/privileges.sql, tests/retention.sql.

begin;

-- ---------------------------------------------------------------- table privileges

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke truncate, references, trigger on all tables in schema public from service_role;

grant select on all tables in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Not for clients at all.
revoke all on public.schema_migrations from public, anon, authenticated, service_role;
revoke all on public.revoked_devices from public, anon, authenticated, service_role;
-- Written only by the control service (postgres); read for the banners.
revoke insert, update, delete on public.service_status from service_role;

-- The writes the app API makes as a signed-in owner (RLS: owners only).
grant insert (id, business_id, company_id, name), update (name), delete on public.sites to authenticated;
grant insert (id, business_id, site_id, staff_id, plan_date, weekday, starts_on, ends_on),
      update (active), delete on public.visit_plans to authenticated;
-- users_owner_update may only touch these columns (never role, business_id,
-- email, permissions or id).
grant update (name, is_active, requires_check_in) on public.users to authenticated;

-- RLS on every table, also the bookkeeping one (postgres bypasses it).
alter table public.schema_migrations enable row level security;

-- Future objects made by migrations (run as postgres).
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
alter default privileges for role postgres in schema public revoke all on tables from service_role;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges for role postgres in schema public revoke all on sequences from service_role;
alter default privileges for role postgres in schema public grant usage, select on sequences to service_role;

revoke all on schema public from anon;
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'auth') then
    execute 'revoke all on schema auth from anon';
  end if;
end $$;

-- No temporary tables for API roles; only the business's own login roles
-- (<slug>_api, <slug>_auth, granted by new-business.sh) may connect.
do $$
declare
  v_slug text := substring(current_database() from '^biz_(.*)$');
  r text;
begin
  foreach r in array array[v_slug || '_api', v_slug || '_auth'] loop
    if r is not null and exists (select 1 from pg_roles where rolname = r) then
      execute format('grant connect on database %I to %I', current_database(), r);
    end if;
  end loop;
  execute format('revoke connect, temporary on database %I from public', current_database());
  execute format('revoke temporary on database %I from anon, authenticated, service_role', current_database());
end $$;

-- ---------------------------------------------------------------- function privileges and search_path

do $$
declare
  f regprocedure;
  a boolean;
  s boolean;
begin
  for f in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind in ('f', 'p')
      and not exists (select 1 from pg_depend d
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  loop
    a := has_function_privilege('authenticated', f, 'execute');
    s := has_function_privilege('service_role', f, 'execute');
    execute format('revoke all on function %s from public, anon', f);
    if a then execute format('grant execute on function %s to authenticated', f); end if;
    if s then execute format('grant execute on function %s to service_role', f); end if;
  end loop;

  for f in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('alter function %s set search_path = public, pg_temp', f);
  end loop;
end $$;

-- ---------------------------------------------------------------- RLS: helpers once per query

drop policy businesses_read on public.businesses;
create policy businesses_read on public.businesses for select to authenticated
  using (id = (select public.current_business_id()));

drop policy users_read on public.users;
create policy users_read on public.users for select to authenticated
  using (id = (select auth.uid())
         or (business_id = (select public.current_business_id()) and (select public.is_owner())));

drop policy users_owner_insert on public.users;
create policy users_owner_insert on public.users for insert to authenticated
  with check (business_id = (select public.current_business_id()) and (select public.is_owner()) and role = 'STAFF');

drop policy users_owner_update on public.users;
create policy users_owner_update on public.users for update to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()) and role = 'STAFF')
  with check (business_id = (select public.current_business_id()) and role = 'STAFF');

drop policy connections_owner_read on public.tally_connections;
create policy connections_owner_read on public.tally_connections for select to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy companies_read on public.tally_companies;
create policy companies_read on public.tally_companies for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_company(id)));

drop policy shops_read on public.shops;
create policy shops_read on public.shops for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_site_shop(company_id, site_id)));

-- For an owner, can_see_transactions() and can_see_shop() are true (the shop
-- always exists: transactions.shop_id is a NOT NULL foreign key).
drop policy transactions_read on public.transactions;
create policy transactions_read on public.transactions for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner())
              or (public.can_see_transactions(company_id) and public.can_see_shop(shop_id))));

drop policy sync_state_read on public.sync_state;
create policy sync_state_read on public.sync_state for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_company(company_id)));

drop policy sync_logs_read on public.sync_logs;
create policy sync_logs_read on public.sync_logs for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_company(company_id)));

drop policy staff_company_access_read on public.staff_company_access;
create policy staff_company_access_read on public.staff_company_access for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or user_id = (select auth.uid())));

drop policy suppliers_owner_read on public.suppliers;
create policy suppliers_owner_read on public.suppliers for select to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy purchases_owner_read on public.purchases;
create policy purchases_owner_read on public.purchases for select to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy purchase_lines_owner_read on public.purchase_lines;
create policy purchase_lines_owner_read on public.purchase_lines for select to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy stock_items_read on public.stock_items;
create policy stock_items_read on public.stock_items for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_company(company_id)));

drop policy stock_minimums_read on public.stock_minimums;
create policy stock_minimums_read on public.stock_minimums for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_company(company_id)));

drop policy sites_read on public.sites;
create policy sites_read on public.sites for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner())
              or exists (select 1 from public.staff_company_access a
                         where a.user_id = (select auth.uid()) and a.company_id = sites.company_id and a.full_company)
              or exists (select 1 from public.staff_site_access ss
                         where ss.user_id = (select auth.uid()) and ss.site_id = sites.id)));
drop policy sites_owner_insert on public.sites;
create policy sites_owner_insert on public.sites for insert to authenticated
  with check (business_id = (select public.current_business_id()) and (select public.is_owner()));
drop policy sites_owner_update on public.sites;
create policy sites_owner_update on public.sites for update to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()))
  with check (business_id = (select public.current_business_id()));
drop policy sites_owner_delete on public.sites;
create policy sites_owner_delete on public.sites for delete to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy staff_site_access_read on public.staff_site_access;
create policy staff_site_access_read on public.staff_site_access for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or user_id = (select auth.uid())));

-- shop_locations.shop_id is a NOT NULL foreign key: can_see_shop() is true for owners.
drop policy shop_locations_read on public.shop_locations;
create policy shop_locations_read on public.shop_locations for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or public.can_see_shop(shop_id)));

drop policy shop_location_suggestions_read on public.shop_location_suggestions;
create policy shop_location_suggestions_read on public.shop_location_suggestions for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or suggested_by = (select auth.uid())));

drop policy visit_plans_read on public.visit_plans;
create policy visit_plans_read on public.visit_plans for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or staff_id = (select auth.uid())));
drop policy visit_plans_owner_insert on public.visit_plans;
create policy visit_plans_owner_insert on public.visit_plans for insert to authenticated
  with check (business_id = (select public.current_business_id()) and (select public.is_owner()));
drop policy visit_plans_owner_update on public.visit_plans;
create policy visit_plans_owner_update on public.visit_plans for update to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()))
  with check (business_id = (select public.current_business_id()));
drop policy visit_plans_owner_delete on public.visit_plans;
create policy visit_plans_owner_delete on public.visit_plans for delete to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

drop policy visit_tasks_read on public.visit_tasks;
create policy visit_tasks_read on public.visit_tasks for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or staff_id = (select auth.uid())));

drop policy shop_visits_read on public.shop_visits;
create policy shop_visits_read on public.shop_visits for select to authenticated
  using (business_id = (select public.current_business_id())
         and ((select public.is_owner()) or staff_id = (select auth.uid())));

drop policy visit_failed_attempts_owner_read on public.visit_failed_attempts;
create policy visit_failed_attempts_owner_read on public.visit_failed_attempts for select to authenticated
  using (business_id = (select public.current_business_id()) and (select public.is_owner()));

-- ---------------------------------------------------------------- foreign-key indexes

-- transactions_shop_date_idx is partial (live rows only), so cascades from
-- shops could not use it.
create index if not exists transactions_shop_idx                 on public.transactions (shop_id);
create index if not exists visit_tasks_plan_idx                  on public.visit_tasks (plan_id);
create index if not exists visit_tasks_shop_idx                  on public.visit_tasks (shop_id);
create index if not exists visit_tasks_site_idx                  on public.visit_tasks (site_id);
create index if not exists visit_plans_site_idx                  on public.visit_plans (site_id);
create index if not exists shop_visits_shop_idx                  on public.shop_visits (shop_id);
create index if not exists shop_visits_suggestion_idx            on public.shop_visits (suggestion_id);
create index if not exists shop_location_suggestions_shop_idx    on public.shop_location_suggestions (shop_id);
create index if not exists visit_failed_attempts_task_idx        on public.visit_failed_attempts (task_id);
create index if not exists visit_failed_attempts_shop_idx        on public.visit_failed_attempts (shop_id);

-- ---------------------------------------------------------------- data retention (DPDP)

-- A visit outlives its staff member's GPS position: after the retention
-- period the position is removed, the visit (time, result, distance) stays.
alter table public.shop_visits alter column device_lat drop not null;
alter table public.shop_visits alter column device_lng drop not null;

-- Deletes or blanks personal data past its retention period. Run daily, as
-- postgres, by the server (select public.purge_old_data();). Returns what it
-- changed, for the log. Keep the periods in step with docs/DATABASE_SCHEMA.md.
create or replace function public.purge_old_data()
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare
  c_location_retention constant interval := interval '12 months';  -- staff GPS positions
  c_sync_log_retention constant interval := interval '180 days';   -- Tally sync run logs
  v_visits     integer;
  v_failed     integer;
  v_rejected   integer;
  v_sync_logs  integer;
begin
  update public.shop_visits
  set device_lat = null, device_lng = null
  where checked_in_at < now() - c_location_retention
    and (device_lat is not null or device_lng is not null);
  get diagnostics v_visits = row_count;

  delete from public.visit_failed_attempts
  where attempted_at < now() - c_location_retention;
  get diagnostics v_failed = row_count;

  delete from public.shop_location_suggestions
  where status = 'rejected' and coalesce(reviewed_at, created_at) < now() - c_location_retention;
  get diagnostics v_rejected = row_count;

  delete from public.sync_logs
  where started_at < now() - c_sync_log_retention;
  get diagnostics v_sync_logs = row_count;

  return jsonb_build_object('visit_locations_cleared', v_visits,
                            'failed_attempts_deleted', v_failed,
                            'rejected_suggestions_deleted', v_rejected,
                            'sync_logs_deleted', v_sync_logs);
end $$;
revoke all on function public.purge_old_data() from public, anon, authenticated;
grant execute on function public.purge_old_data() to service_role;

commit;
