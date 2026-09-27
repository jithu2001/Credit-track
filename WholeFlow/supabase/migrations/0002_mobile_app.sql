-- WholeFlow Mobile — staff company assignment and per-company permissions.
--
-- Additive and safe to run on the live database (the sync service keeps
-- writing with the service-role key, which bypasses RLS):
--   * new table staff_company_access: which companies each STAFF user works
--     for, with an area limit and transaction visibility per company;
--   * helper functions used by the read policies;
--   * read policies on tally_companies, shops, transactions, sync_state,
--     sync_logs and users are recreated with the staff restrictions;
--   * two service-role-only functions used by the manage-staff Edge Function
--     so staff rows and their assignments are written atomically.
--
-- Owners always see every company of their business. A staff member sees a
-- company only through a staff_company_access row: no row, no data. A newly
-- synced company stays hidden from staff until the owner assigns it.
-- users.permissions is left untouched and reserved.

begin;

-- ---------------------------------------------------------------- table

create table public.staff_company_access (
  user_id                uuid not null references public.users (id) on delete cascade,
  company_id             uuid not null references public.tally_companies (id) on delete cascade,
  business_id            uuid not null references public.businesses (id) on delete cascade,
  areas                  text[] not null default '{}',   -- empty = every area of this company
  can_view_transactions  boolean not null default true,
  created_by             uuid references public.users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (user_id, company_id)
);
create index staff_company_access_company_idx on public.staff_company_access (company_id);
create index staff_company_access_business_idx on public.staff_company_access (business_id);

create trigger staff_company_access_set_updated_at before update on public.staff_company_access
  for each row execute function public.set_updated_at();

-- The user must be STAFF, and user, company and row must share one business.
-- Area names are trimmed and de-duplicated; blanks are dropped.
create or replace function public.staff_company_access_check()
returns trigger language plpgsql set search_path = public as $$
declare
  u_business uuid;
  u_role     text;
  c_business uuid;
begin
  select business_id, role into u_business, u_role from public.users where id = new.user_id;
  if u_role is distinct from 'STAFF' then
    raise exception 'staff_company_access: user % is not a STAFF user', new.user_id
      using errcode = 'check_violation';
  end if;
  select business_id into c_business from public.tally_companies where id = new.company_id;
  if c_business is distinct from u_business or new.business_id is distinct from u_business then
    raise exception 'staff_company_access: company % does not belong to the business of user %', new.company_id, new.user_id
      using errcode = 'check_violation';
  end if;
  new.areas := coalesce(
    (select array_agg(distinct btrim(a) order by btrim(a)) from unnest(new.areas) a where btrim(a) <> ''),
    '{}');
  return new;
end $$;

create trigger staff_company_access_check before insert or update on public.staff_company_access
  for each row execute function public.staff_company_access_check();

create index shops_company_lower_area_idx on public.shops (company_id, lower(area)) where deleted_at is null;

-- ---------------------------------------------------------------- helpers

-- True for an active owner, or an active staff member assigned to the company.
create or replace function public.can_see_company(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (
    select 1
    from public.staff_company_access a
    join public.users u on u.id = a.user_id
    where a.user_id = auth.uid() and u.is_active and a.company_id = p_company_id)
$$;

-- True when the caller may see a shop of this company in this area.
create or replace function public.can_see_area(p_company_id uuid, p_area text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (
    select 1
    from public.staff_company_access a
    join public.users u on u.id = a.user_id
    where a.user_id = auth.uid() and u.is_active and a.company_id = p_company_id
      and (cardinality(a.areas) = 0
           or lower(p_area) in (select lower(x) from unnest(a.areas) x)))
$$;

create or replace function public.can_see_shop(p_shop_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select public.can_see_area(s.company_id, s.area) from public.shops s where s.id = p_shop_id), false)
$$;

create or replace function public.can_see_transactions(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (
    select 1
    from public.staff_company_access a
    join public.users u on u.id = a.user_id
    where a.user_id = auth.uid() and u.is_active and a.company_id = p_company_id and a.can_view_transactions)
$$;

grant execute on function public.can_see_company(uuid)       to authenticated;
grant execute on function public.can_see_area(uuid, text)    to authenticated;
grant execute on function public.can_see_shop(uuid)          to authenticated;
grant execute on function public.can_see_transactions(uuid)  to authenticated;

-- ---------------------------------------------------------------- policies

alter table public.staff_company_access enable row level security;

-- Owners read every assignment of their business; staff read their own.
create policy staff_company_access_read on public.staff_company_access for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or user_id = auth.uid()));
-- No write policies: the manage-staff Edge Function writes with the service role.

revoke all on public.staff_company_access from anon;
grant select on public.staff_company_access to authenticated;

-- Staff read their own users row (even when disabled, so the app can say so);
-- owners read every user of the business.
drop policy users_read on public.users;
create policy users_read on public.users for select to authenticated
  using (id = auth.uid() or (business_id = public.current_business_id() and public.is_owner()));

drop policy companies_read on public.tally_companies;
create policy companies_read on public.tally_companies for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_company(id));

drop policy shops_read on public.shops;
create policy shops_read on public.shops for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_area(company_id, area));

drop policy transactions_read on public.transactions;
create policy transactions_read on public.transactions for select to authenticated
  using (business_id = public.current_business_id()
         and public.can_see_transactions(company_id)
         and public.can_see_shop(shop_id));

drop policy sync_state_read on public.sync_state;
create policy sync_state_read on public.sync_state for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_company(company_id));

-- sync_logs.company_id may be null (run-level rows): owners only, since
-- can_see_company(null) is false for staff.
drop policy sync_logs_read on public.sync_logs;
create policy sync_logs_read on public.sync_logs for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_company(company_id));

-- ---------------------------------------------------------------- service-role writers (manage-staff)

-- p_companies: [{"company_id": uuid, "areas": [text], "can_view_transactions": bool}, ...]
create or replace function public.admin_insert_staff(
  p_id uuid, p_business_id uuid, p_name text, p_email text, p_created_by uuid, p_companies jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, business_id, role, name, email, is_active, created_by)
  values (p_id, p_business_id, 'STAFF', coalesce(p_name, ''), p_email, true, p_created_by);
  perform public.admin_set_staff_companies(p_id, p_business_id, p_created_by, p_companies);
end $$;

-- Replaces the staff member's whole assignment set in one transaction.
create or replace function public.admin_set_staff_companies(
  p_user_id uuid, p_business_id uuid, p_actor uuid, p_companies jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.users where id = p_user_id and business_id = p_business_id and role = 'STAFF') then
    raise exception 'admin_set_staff_companies: no such staff user in this business' using errcode = 'no_data_found';
  end if;
  delete from public.staff_company_access where user_id = p_user_id;
  insert into public.staff_company_access (user_id, company_id, business_id, areas, can_view_transactions, created_by)
  select p_user_id,
         (c->>'company_id')::uuid,
         p_business_id,
         coalesce(array(select jsonb_array_elements_text(coalesce(c->'areas', '[]'::jsonb))), '{}'),
         coalesce((c->>'can_view_transactions')::boolean, true),
         p_actor
  from jsonb_array_elements(coalesce(p_companies, '[]'::jsonb)) c;
end $$;

revoke all on function public.admin_insert_staff(uuid, uuid, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.admin_set_staff_companies(uuid, uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.admin_insert_staff(uuid, uuid, text, text, uuid, jsonb) to service_role;
grant execute on function public.admin_set_staff_companies(uuid, uuid, uuid, jsonb) to service_role;

commit;
