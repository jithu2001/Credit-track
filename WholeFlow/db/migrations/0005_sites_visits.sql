-- WholeFlow — sites (owner-made groups of shops) and optional staff shop visits.
--
-- NOT additive: staff access by Tally area is replaced by access by site.
--   * A site is a named set of shops in one company, made by the owner. A shop
--     is in at most one site (shops.site_id). The Tally sync never writes
--     site_id, so a sync never moves a shop out of its site.
--   * Per company, a staff member has either the full company or a chosen set
--     of sites (staff_company_access.full_company + staff_site_access). Shops
--     in no site are visible only to owners and full-company staff.
--   * staff_company_access.areas and can_see_area() are dropped. The app and
--     the manage-staff Edge Function must be updated together with this file.
--
-- Visits (only for staff whose users.requires_check_in is on):
--   * the owner pins shops (shop_locations: point + radius); staff can suggest
--     a pin for an unpinned shop (shop_location_suggestions), the owner reviews;
--   * the owner plans a site for a staff member on a date or every week
--     (visit_plans); ensure_visit_tasks() turns plans into one task per shop
--     per day (visit_tasks), keeping past days as they were;
--   * staff check in only through check_in(), which re-reads the task and the
--     pin, measures the distance itself and stamps the time; rejected attempts
--     are kept in visit_failed_attempts. Visits are never edited by clients.
--
-- Apply in the Supabase dashboard: SQL Editor → paste this file → Run.
-- Checks: supabase/tests/sites_visits.sql (rolled back).

begin;

-- ---------------------------------------------------------------- business day

alter table public.businesses add column timezone text not null default 'Asia/Kolkata';

-- "Today" for the caller's business. Visit days follow the business clock, not UTC.
create or replace function public.business_today()
returns date language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce(
            (select b.timezone from public.businesses b where b.id = public.current_business_id()),
            'Asia/Kolkata'))::date
$$;
grant execute on function public.business_today() to authenticated;

-- ---------------------------------------------------------------- sites

create table public.sites (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null default public.current_business_id() references public.businesses (id) on delete cascade,
  company_id   uuid not null references public.tally_companies (id) on delete cascade,
  name         text not null check (btrim(name) <> '' and length(name) <= 80),
  created_by   uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index sites_company_name_idx on public.sites (company_id, lower(btrim(name)));
create index sites_business_idx on public.sites (business_id);
create trigger sites_set_updated_at before update on public.sites
  for each row execute function public.set_updated_at();

-- The site's company must belong to its business.
create or replace function public.sites_check()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.tally_companies c where c.id = new.company_id and c.business_id = new.business_id) then
    raise exception 'sites: company % is not in business %', new.company_id, new.business_id using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and new.company_id is distinct from old.company_id then
    raise exception 'sites: a site cannot move to another company' using errcode = 'check_violation';
  end if;
  new.name := btrim(new.name);
  return new;
end $$;
create trigger sites_check before insert or update on public.sites
  for each row execute function public.sites_check();

alter table public.shops add column site_id uuid references public.sites (id) on delete set null;
create index shops_site_idx on public.shops (site_id) where deleted_at is null;

-- Only fires when site_id itself is written (never by the sync, which does not send it).
create or replace function public.shops_site_check()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.site_id is not null
     and not exists (select 1 from public.sites s where s.id = new.site_id and s.company_id = new.company_id) then
    raise exception 'shops: site % is not in the shop''s company', new.site_id using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger shops_site_check before update of site_id on public.shops
  for each row execute function public.shops_site_check();

-- ---------------------------------------------------------------- staff access: full company or chosen sites

alter table public.users add column requires_check_in boolean not null default false;

alter table public.staff_company_access add column full_company boolean not null default true;

create table public.staff_site_access (
  user_id      uuid not null references public.users (id) on delete cascade,
  site_id      uuid not null references public.sites (id) on delete cascade,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  created_by   uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  primary key (user_id, site_id)
);
create index staff_site_access_site_idx on public.staff_site_access (site_id);

-- Drop everything that read areas, then the column itself.
drop policy shops_read on public.shops;
drop policy transactions_read on public.transactions;
drop function public.overdue_shops(uuid, integer, date);
drop function public.can_see_shop(uuid);
drop function public.can_see_area(uuid, text);

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
  return new;
end $$;

alter table public.staff_company_access drop column areas;

-- A site grant needs the staff member to have that company, without full access.
create or replace function public.staff_site_access_check()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists (
    select 1
    from public.sites s
    join public.staff_company_access a on a.company_id = s.company_id and a.user_id = new.user_id
    where s.id = new.site_id and s.business_id = new.business_id and a.business_id = new.business_id) then
    raise exception 'staff_site_access: site % is not in a company given to user %', new.site_id, new.user_id
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger staff_site_access_check before insert or update on public.staff_site_access
  for each row execute function public.staff_site_access_check();

-- True when the caller may see a shop of this company that is in this site (null = no site).
create or replace function public.can_see_site_shop(p_company_id uuid, p_site_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (
    select 1
    from public.staff_company_access a
    join public.users u on u.id = a.user_id
    where a.user_id = auth.uid() and u.is_active and a.company_id = p_company_id
      and (a.full_company
           or (p_site_id is not null
               and exists (select 1 from public.staff_site_access ss
                           where ss.user_id = a.user_id and ss.site_id = p_site_id))))
$$;

create or replace function public.can_see_shop(p_shop_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select public.can_see_site_shop(s.company_id, s.site_id) from public.shops s where s.id = p_shop_id), false)
$$;

grant execute on function public.can_see_site_shop(uuid, uuid) to authenticated;
grant execute on function public.can_see_shop(uuid) to authenticated;

create policy shops_read on public.shops for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_site_shop(company_id, site_id));

create policy transactions_read on public.transactions for select to authenticated
  using (business_id = public.current_business_id()
         and public.can_see_transactions(company_id)
         and public.can_see_shop(shop_id));

-- Sites: owners manage them; staff read the sites they can open shops in.
alter table public.sites enable row level security;
create policy sites_read on public.sites for select to authenticated
  using (business_id = public.current_business_id()
         and (public.is_owner()
              or exists (select 1 from public.staff_company_access a
                         where a.user_id = auth.uid() and a.company_id = sites.company_id and a.full_company)
              or exists (select 1 from public.staff_site_access ss
                         where ss.user_id = auth.uid() and ss.site_id = sites.id)));
create policy sites_owner_insert on public.sites for insert to authenticated
  with check (business_id = public.current_business_id() and public.is_owner());
create policy sites_owner_update on public.sites for update to authenticated
  using (business_id = public.current_business_id() and public.is_owner())
  with check (business_id = public.current_business_id());
create policy sites_owner_delete on public.sites for delete to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

alter table public.staff_site_access enable row level security;
create policy staff_site_access_read on public.staff_site_access for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or user_id = auth.uid()));
-- No write policies: manage-staff writes with the service role.

revoke all on public.sites, public.staff_site_access from anon;
grant select, insert, update, delete on public.sites to authenticated;
grant select on public.staff_site_access to authenticated;

-- Replaces a site's shops: the given shops move into it (out of any other
-- site), shops of the site not in the list leave it. Owners only.
create or replace function public.set_site_shops(p_site_id uuid, p_shop_ids uuid[])
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_company uuid;
  v_count integer;
begin
  if not public.is_owner() then
    raise exception 'set_site_shops: owners only' using errcode = '42501';
  end if;
  select s.company_id into v_company from public.sites s
  where s.id = p_site_id and s.business_id = public.current_business_id();
  if v_company is null then
    raise exception 'set_site_shops: no such site' using errcode = 'no_data_found';
  end if;
  if exists (select 1 from unnest(coalesce(p_shop_ids, '{}')) x
             where not exists (select 1 from public.shops s where s.id = x and s.company_id = v_company)) then
    raise exception 'set_site_shops: every shop must be in the site''s company' using errcode = 'check_violation';
  end if;
  update public.shops set site_id = null
  where site_id = p_site_id and not (id = any (coalesce(p_shop_ids, '{}')));
  update public.shops set site_id = p_site_id
  where id = any (coalesce(p_shop_ids, '{}')) and site_id is distinct from p_site_id;
  select count(*) into v_count from public.shops where site_id = p_site_id and deleted_at is null;
  return v_count;
end $$;
revoke all on function public.set_site_shops(uuid, uuid[]) from public, anon;
grant execute on function public.set_site_shops(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------- service-role writers (manage-staff)

-- p_companies: [{"company_id": uuid, "full_company": bool, "site_ids": [uuid], "can_view_transactions": bool}, ...]
create or replace function public.admin_set_staff_companies(
  p_user_id uuid, p_business_id uuid, p_actor uuid, p_companies jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.users where id = p_user_id and business_id = p_business_id and role = 'STAFF') then
    raise exception 'admin_set_staff_companies: no such staff user in this business' using errcode = 'no_data_found';
  end if;
  delete from public.staff_site_access where user_id = p_user_id;
  delete from public.staff_company_access where user_id = p_user_id;
  insert into public.staff_company_access (user_id, company_id, business_id, full_company, can_view_transactions, created_by)
  select p_user_id,
         (c->>'company_id')::uuid,
         p_business_id,
         coalesce((c->>'full_company')::boolean, true),
         coalesce((c->>'can_view_transactions')::boolean, true),
         p_actor
  from jsonb_array_elements(coalesce(p_companies, '[]'::jsonb)) c;
  -- Sites only count where the company is limited to chosen sites.
  insert into public.staff_site_access (user_id, site_id, business_id, created_by)
  select distinct p_user_id, (sid #>> '{}')::uuid, p_business_id, p_actor
  from jsonb_array_elements(coalesce(p_companies, '[]'::jsonb)) c
  cross join lateral jsonb_array_elements(coalesce(c->'site_ids', '[]'::jsonb)) sid
  where not coalesce((c->>'full_company')::boolean, true);
end $$;

-- ---------------------------------------------------------------- shop lists by site

create or replace view public.v_shop_outstanding with (security_invoker = true) as
  select s.business_id, s.company_id, c.company_name, s.id as shop_id, s.name, s.area, s.phone, s.gstin,
         s.balance_amount, s.balance_type, s.receivable, s.synced_at, s.site_id, st.name as site_name
  from public.shops s
  join public.tally_companies c on c.id = s.company_id
  left join public.sites st on st.id = s.site_id
  where s.deleted_at is null;

-- Same ageing as 0004_overdue.sql; shops are now limited by site, and each
-- row carries its site so the app can group by it.
create function public.overdue_shops(p_company_id uuid, p_credit_days integer, p_today date)
returns table (
  shop_id           uuid,
  name              text,
  area              text,
  phone             text,
  receivable        numeric,
  overdue           numeric,
  max_days_overdue  integer,
  overdue_bills     integer,
  bills_visible     boolean,
  bills             jsonb,
  site_id           uuid,
  site_name         text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_business uuid := public.current_business_id();
  v_start date;
  v_bills boolean;
begin
  if p_credit_days is null or p_credit_days < 0 or p_credit_days > 3650 or p_today is null then
    raise exception 'overdue_shops: credit days must be 0 to 3650 and today is required' using errcode = '22023';
  end if;
  if v_business is null
     or not exists (select 1 from public.tally_companies c where c.id = p_company_id and c.business_id = v_business)
     or not public.can_see_company(p_company_id) then
    return;
  end if;
  v_bills := public.can_see_transactions(p_company_id);

  select coalesce(
           least(c.period_from,
                 (select min(t.transaction_date) from public.transactions t
                  where t.company_id = p_company_id and t.deleted_at is null)),
           c.books_from,
           p_today)
    into v_start
  from public.tally_companies c
  where c.id = p_company_id;

  return query
  with visible as (
    select s.id, s.name, s.area, s.phone, s.receivable, s.site_id,
           case when s.opening_balance_type = 'CR' then -abs(s.opening_balance_amount)
                else abs(s.opening_balance_amount) end as opening
    from public.shops s
    where s.company_id = p_company_id and s.business_id = v_business and s.deleted_at is null
      and public.can_see_site_shop(s.company_id, s.site_id)
  ),
  txns as (
    select t.shop_id, t.id, t.transaction_date, t.created_at, t.voucher_type, t.voucher_number, t.debit, t.credit
    from public.transactions t
    join visible v on v.id = t.shop_id
    where t.company_id = p_company_id and t.deleted_at is null
  ),
  credits as (
    select v.id as shop_id,
           greatest(-v.opening, 0) + coalesce(sum(t.credit) filter (where t.credit > 0), 0) as total
    from visible v
    left join txns t on t.shop_id = v.id
    group by v.id, v.opening
  ),
  bills as (
    select v.id as shop_id, v_start as bill_date, 0 as ord, null::timestamptz as created_at, null::uuid as txn_id,
           'Opening balance'::text as voucher, v.opening as amount
    from visible v
    where v.opening > 0
    union all
    select t.shop_id, t.transaction_date, 1, t.created_at, t.id,
           nullif(concat_ws(' · ', nullif(t.voucher_type, ''), nullif(t.voucher_number, '')), ''), t.debit
    from txns t
    where t.debit > 0
  ),
  open_bills as (
    select b.shop_id, b.bill_date, b.ord, b.created_at, b.txn_id, b.voucher, b.amount,
           least(b.amount,
                 greatest(sum(b.amount) over (partition by b.shop_id
                                              order by b.bill_date, b.ord, b.created_at nulls first, b.txn_id
                                              rows unbounded preceding) - c.total, 0)) as remaining,
           p_today - (b.bill_date + p_credit_days) as days_overdue
    from bills b
    join credits c on c.shop_id = b.shop_id
  )
  select v.id, v.name, v.area, v.phone, v.receivable,
         sum(o.remaining),
         max(o.days_overdue),
         count(*)::integer,
         v_bills,
         case when v_bills then
           jsonb_agg(jsonb_build_object(
                       'date', o.bill_date,
                       'voucher', o.voucher,
                       'amount', o.amount,
                       'remaining', o.remaining,
                       'days_overdue', o.days_overdue)
                     order by o.bill_date, o.ord, o.created_at nulls first, o.txn_id)
         end,
         v.site_id,
         st.name
  from open_bills o
  join visible v on v.id = o.shop_id
  left join public.sites st on st.id = v.site_id
  where o.remaining > 0 and o.days_overdue > 0
  group by v.id, v.name, v.area, v.phone, v.receivable, v.site_id, st.name;
end $$;

revoke all on function public.overdue_shops(uuid, integer, date) from public, anon;
grant execute on function public.overdue_shops(uuid, integer, date) to authenticated;

-- ---------------------------------------------------------------- site report

-- One row per site of the company the caller can see, plus one row with a
-- null site for shops in no site (owners and full-company staff only).
-- Sales, returns and collections are summed over [p_from, p_to]; they are null
-- when the caller may not see transactions.
create or replace function public.site_report(p_company_id uuid, p_from date, p_to date)
returns table (
  site_id           uuid,
  site_name         text,
  shops             integer,
  shops_with_dues   integer,
  outstanding       numeric,  -- sum of what shops owe (receivable > 0)
  advance           numeric,  -- sum of credit balances (receivable < 0), as a positive number
  sales             numeric,
  returns           numeric,
  collections       numeric
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_business uuid := public.current_business_id();
  v_txns boolean;
begin
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then
    raise exception 'site_report: a valid period is required' using errcode = '22023';
  end if;
  if v_business is null
     or not exists (select 1 from public.tally_companies c where c.id = p_company_id and c.business_id = v_business)
     or not public.can_see_company(p_company_id) then
    return;
  end if;
  v_txns := public.can_see_transactions(p_company_id);

  return query
  with groups as (
    select st.id as site_id, st.name as site_name
    from public.sites st
    where st.company_id = p_company_id and public.can_see_site_shop(p_company_id, st.id)
    union all
    select null::uuid, null::text
    where public.can_see_site_shop(p_company_id, null)
  ),
  shop_rows as (
    select s.id, s.site_id, s.receivable
    from public.shops s
    where s.company_id = p_company_id and s.deleted_at is null
  ),
  money as (
    select s.site_id,
           sum(t.debit)  filter (where t.category = 'sales')    as sales,
           sum(t.credit) filter (where t.category = 'returns')  as returns,
           sum(t.credit) filter (where t.category = 'receipts') as collections
    from public.transactions t
    join shop_rows s on s.id = t.shop_id
    where v_txns and t.company_id = p_company_id and t.deleted_at is null
      and t.transaction_date between p_from and p_to
    group by s.site_id
  )
  select g.site_id, g.site_name,
         count(s.id)::integer,
         (count(s.id) filter (where s.receivable > 0))::integer,
         coalesce(sum(s.receivable) filter (where s.receivable > 0), 0),
         coalesce(-sum(s.receivable) filter (where s.receivable < 0), 0),
         case when v_txns then coalesce(max(m.sales), 0) end,
         case when v_txns then coalesce(max(m.returns), 0) end,
         case when v_txns then coalesce(max(m.collections), 0) end
  from groups g
  left join shop_rows s on s.site_id is not distinct from g.site_id
  left join money m on m.site_id is not distinct from g.site_id
  group by g.site_id, g.site_name
  order by g.site_name nulls last;
end $$;

revoke all on function public.site_report(uuid, date, date) from public, anon;
grant execute on function public.site_report(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------- shop pins

create table public.shop_locations (
  shop_id      uuid primary key references public.shops (id) on delete cascade,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  company_id   uuid not null references public.tally_companies (id) on delete cascade,
  latitude     double precision not null check (latitude between -90 and 90),
  longitude    double precision not null check (longitude between -180 and 180),
  radius_m     integer not null default 100 check (radius_m between 20 and 2000),
  source       text not null default 'owner' check (source in ('owner', 'suggestion')),
  set_by       uuid references public.users (id) on delete set null,
  set_at       timestamptz not null default now()
);
create index shop_locations_company_idx on public.shop_locations (company_id);

create table public.shop_location_suggestions (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  company_id    uuid not null references public.tally_companies (id) on delete cascade,
  shop_id       uuid not null references public.shops (id) on delete cascade,
  suggested_by  uuid references public.users (id) on delete set null,
  latitude      double precision not null check (latitude between -90 and 90),
  longitude     double precision not null check (longitude between -180 and 180),
  accuracy_m    double precision,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by   uuid references public.users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index shop_location_suggestions_pending_idx on public.shop_location_suggestions (business_id, created_at)
  where status = 'pending';

-- ---------------------------------------------------------------- visit plans and tasks

-- A plan is either one date (plan_date) or a weekday (1 = Monday … 7 = Sunday,
-- ISO) from starts_on until ends_on (open-ended when null).
create table public.visit_plans (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null default public.current_business_id() references public.businesses (id) on delete cascade,
  company_id   uuid not null references public.tally_companies (id) on delete cascade,  -- filled from the site by the trigger
  site_id      uuid not null references public.sites (id) on delete cascade,
  staff_id     uuid not null references public.users (id) on delete cascade,
  plan_date    date,
  weekday      smallint check (weekday between 1 and 7),
  starts_on    date,
  ends_on      date,
  active       boolean not null default true,
  created_by   uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check ((plan_date is not null and weekday is null and starts_on is null and ends_on is null)
      or (plan_date is null and weekday is not null and starts_on is not null
          and (ends_on is null or ends_on >= starts_on)))
);
create index visit_plans_staff_idx on public.visit_plans (staff_id) where active;
create index visit_plans_business_idx on public.visit_plans (business_id);
create trigger visit_plans_set_updated_at before update on public.visit_plans
  for each row execute function public.set_updated_at();

-- The staff member must be active staff of the business with check-in on, and
-- have the site (full company or the site itself).
create or replace function public.visit_plans_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select s.company_id into new.company_id from public.sites s
  where s.id = new.site_id and s.business_id = new.business_id;
  if new.company_id is null then
    raise exception 'visit_plans: no such site in this business' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.users u
                 where u.id = new.staff_id and u.business_id = new.business_id and u.role = 'STAFF'
                   and u.is_active and u.requires_check_in) then
    raise exception 'visit_plans: staff member must be active and have check-in turned on' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.staff_company_access a
                 where a.user_id = new.staff_id and a.company_id = new.company_id
                   and (a.full_company
                        or exists (select 1 from public.staff_site_access ss
                                   where ss.user_id = new.staff_id and ss.site_id = new.site_id))) then
    raise exception 'visit_plans: staff member does not have this site' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger visit_plans_check before insert or update on public.visit_plans
  for each row execute function public.visit_plans_check();

-- One shop to visit on one day. Past tasks are kept as they were planned;
-- the shop and site names are copied so history still reads after changes.
create table public.visit_tasks (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references public.businesses (id) on delete cascade,
  company_id   uuid not null references public.tally_companies (id) on delete cascade,
  plan_id      uuid references public.visit_plans (id) on delete set null,
  staff_id     uuid not null references public.users (id) on delete cascade,
  shop_id      uuid not null references public.shops (id) on delete cascade,
  site_id      uuid references public.sites (id) on delete set null,
  visit_date   date not null,
  shop_name    text not null,
  site_name    text not null,
  created_at   timestamptz not null default now(),
  unique (staff_id, shop_id, visit_date)
);
create index visit_tasks_business_date_idx on public.visit_tasks (business_id, visit_date);
create index visit_tasks_staff_date_idx on public.visit_tasks (staff_id, visit_date);

-- ---------------------------------------------------------------- visits

create table public.shop_visits (
  id             uuid primary key default gen_random_uuid(),
  business_id    uuid not null references public.businesses (id) on delete cascade,
  company_id     uuid not null references public.tally_companies (id) on delete cascade,
  task_id        uuid not null unique references public.visit_tasks (id) on delete cascade,
  staff_id       uuid not null references public.users (id) on delete cascade,
  shop_id        uuid not null references public.shops (id) on delete cascade,
  visit_date     date not null,
  checked_in_at  timestamptz not null default now(),
  device_lat     double precision not null,
  device_lng     double precision not null,
  accuracy_m     double precision not null,
  shop_lat       double precision,          -- the pin used; null while the location is pending
  shop_lng       double precision,
  radius_m       integer,
  distance_m     double precision,
  status         text not null check (status in ('verified', 'location_pending', 'unverified')),
  suggestion_id  uuid references public.shop_location_suggestions (id) on delete set null,
  note           text check (length(note) <= 500),
  created_at     timestamptz not null default now()
);
create index shop_visits_business_date_idx on public.shop_visits (business_id, visit_date);
create index shop_visits_staff_date_idx on public.shop_visits (staff_id, visit_date);

create table public.visit_failed_attempts (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  company_id    uuid not null references public.tally_companies (id) on delete cascade,
  task_id       uuid references public.visit_tasks (id) on delete cascade,
  staff_id      uuid not null references public.users (id) on delete cascade,
  shop_id       uuid not null references public.shops (id) on delete cascade,
  attempted_at  timestamptz not null default now(),
  reason        text not null check (reason in ('out_of_range', 'poor_accuracy', 'mock_location', 'developer_options')),
  device_lat    double precision,
  device_lng    double precision,
  accuracy_m    double precision,
  distance_m    double precision,
  radius_m      integer
);
create index visit_failed_attempts_business_idx on public.visit_failed_attempts (business_id, attempted_at desc);

-- ---------------------------------------------------------------- visit RLS

alter table public.shop_locations             enable row level security;
alter table public.shop_location_suggestions  enable row level security;
alter table public.visit_plans                enable row level security;
alter table public.visit_tasks                enable row level security;
alter table public.shop_visits                enable row level security;
alter table public.visit_failed_attempts      enable row level security;

create policy shop_locations_read on public.shop_locations for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_shop(shop_id));

create policy shop_location_suggestions_read on public.shop_location_suggestions for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or suggested_by = auth.uid()));

create policy visit_plans_read on public.visit_plans for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or staff_id = auth.uid()));
create policy visit_plans_owner_insert on public.visit_plans for insert to authenticated
  with check (business_id = public.current_business_id() and public.is_owner());
create policy visit_plans_owner_update on public.visit_plans for update to authenticated
  using (business_id = public.current_business_id() and public.is_owner())
  with check (business_id = public.current_business_id());
create policy visit_plans_owner_delete on public.visit_plans for delete to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

create policy visit_tasks_read on public.visit_tasks for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or staff_id = auth.uid()));

create policy shop_visits_read on public.shop_visits for select to authenticated
  using (business_id = public.current_business_id() and (public.is_owner() or staff_id = auth.uid()));

create policy visit_failed_attempts_owner_read on public.visit_failed_attempts for select to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

revoke all on public.shop_locations, public.shop_location_suggestions, public.visit_plans,
              public.visit_tasks, public.shop_visits, public.visit_failed_attempts from anon, authenticated;
grant select on public.shop_locations, public.shop_location_suggestions, public.visit_tasks,
                public.shop_visits, public.visit_failed_attempts to authenticated;
grant select, insert, update, delete on public.visit_plans to authenticated;

-- ---------------------------------------------------------------- visit functions

-- Great-circle distance in metres (haversine).
create or replace function public.distance_m(lat1 double precision, lng1 double precision,
                                             lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2)
           + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;
grant execute on function public.distance_m(double precision, double precision, double precision, double precision) to authenticated;

-- Owners pin a shop (or move its pin).
create or replace function public.set_shop_location(p_shop_id uuid, p_lat double precision, p_lng double precision, p_radius_m integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  s public.shops;
begin
  if not public.is_owner() then
    raise exception 'set_shop_location: owners only' using errcode = '42501';
  end if;
  select * into s from public.shops where id = p_shop_id and business_id = public.current_business_id();
  if s.id is null then
    raise exception 'set_shop_location: no such shop' using errcode = 'no_data_found';
  end if;
  insert into public.shop_locations (shop_id, business_id, company_id, latitude, longitude, radius_m, source, set_by, set_at)
  values (s.id, s.business_id, s.company_id, p_lat, p_lng, coalesce(p_radius_m, 100), 'owner', auth.uid(), now())
  on conflict (shop_id) do update
    set latitude = excluded.latitude, longitude = excluded.longitude, radius_m = excluded.radius_m,
        source = 'owner', set_by = excluded.set_by, set_at = now();
end $$;

create or replace function public.clear_shop_location(p_shop_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then
    raise exception 'clear_shop_location: owners only' using errcode = '42501';
  end if;
  delete from public.shop_locations where shop_id = p_shop_id and business_id = public.current_business_id();
end $$;

-- Owners approve (pin the shop there) or reject a staff suggestion. Visits
-- waiting on the shop's location are settled against the approved pin; on
-- rejection, the visits that relied on this suggestion become unverified.
create or replace function public.review_location_suggestion(p_id uuid, p_approve boolean, p_radius_m integer default 100)
returns void language plpgsql security definer set search_path = public as $$
declare
  g public.shop_location_suggestions;
  r integer := coalesce(p_radius_m, 100);
begin
  if not public.is_owner() then
    raise exception 'review_location_suggestion: owners only' using errcode = '42501';
  end if;
  select * into g from public.shop_location_suggestions
  where id = p_id and business_id = public.current_business_id() and status = 'pending'
  for update;
  if g.id is null then
    raise exception 'review_location_suggestion: no such pending suggestion' using errcode = 'no_data_found';
  end if;

  if not p_approve then
    update public.shop_location_suggestions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
    where id = g.id;
    update public.shop_visits set status = 'unverified'
    where suggestion_id = g.id and status = 'location_pending';
    return;
  end if;

  perform public.set_shop_location(g.shop_id, g.latitude, g.longitude, r);
  update public.shop_locations set source = 'suggestion' where shop_id = g.shop_id;
  update public.shop_location_suggestions set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  where id = g.id;
  -- Other pending suggestions for this shop are settled by this decision.
  update public.shop_location_suggestions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
  where shop_id = g.shop_id and status = 'pending';
  update public.shop_visits v
  set shop_lat = g.latitude, shop_lng = g.longitude, radius_m = r,
      distance_m = public.distance_m(v.device_lat, v.device_lng, g.latitude, g.longitude),
      status = case when public.distance_m(v.device_lat, v.device_lng, g.latitude, g.longitude) <= r
                    then 'verified' else 'unverified' end
  where v.shop_id = g.shop_id and v.status = 'location_pending';
end $$;

-- Turns plans into tasks for [p_from, p_to] (at most 62 days) for the caller's
-- scope: owners → every staff member, staff → themselves. Days before today
-- are only ever added to; from today on, tasks without a visit are rebuilt
-- from the current plans and sites, so edits to plans and sites show up.
-- Idempotent. Returns the number of tasks added.
create or replace function public.ensure_visit_tasks(p_from date, p_to date)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_owner boolean := public.is_owner();
  v_today date := public.business_today();
  v_added integer;
begin
  if v_business is null then
    return 0;
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'ensure_visit_tasks: a range of at most 62 days is required' using errcode = '22023';
  end if;

  -- One statement: every CTE sees the same snapshot. The delete only removes
  -- tasks that are not wanted, so it never meets the insert's rows.
  with wanted as (
    select distinct on (p.staff_id, s.id, d::date)
           p.staff_id, s.id as shop_id, d::date as visit_date, p.id as plan_id, p.company_id,
           st.id as site_id, s.name as shop_name, st.name as site_name
    from public.visit_plans p
    join public.users u on u.id = p.staff_id and u.is_active and u.requires_check_in
    join public.sites st on st.id = p.site_id
    join public.shops s on s.site_id = st.id and s.deleted_at is null
    cross join generate_series(p_from, p_to, interval '1 day') d
    where p.business_id = v_business and p.active
      and (v_owner or p.staff_id = auth.uid())
      and (p.plan_date = d::date
           or (p.weekday = extract(isodow from d)::int and d::date >= p.starts_on
               and (p.ends_on is null or d::date <= p.ends_on)))
    order by p.staff_id, s.id, d::date, p.created_at
  ),
  -- From today on, drop unvisited tasks that no plan asks for any more.
  dropped as (
    delete from public.visit_tasks t
    where t.business_id = v_business
      and (v_owner or t.staff_id = auth.uid())
      and t.visit_date between greatest(p_from, v_today) and p_to
      and not exists (select 1 from public.shop_visits v where v.task_id = t.id)
      and not exists (select 1 from wanted w
                      where w.staff_id = t.staff_id and w.shop_id = t.shop_id and w.visit_date = t.visit_date)
    returning t.id
  )
  insert into public.visit_tasks (business_id, company_id, plan_id, staff_id, shop_id, site_id, visit_date, shop_name, site_name)
  select v_business, w.company_id, w.plan_id, w.staff_id, w.shop_id, w.site_id, w.visit_date, w.shop_name, w.site_name
  from wanted w
  on conflict (staff_id, shop_id, visit_date) do nothing;
  get diagnostics v_added = row_count;
  return v_added;
end $$;

-- The only way a visit is recorded. Rejections are logged and returned (not
-- raised) so the log row is kept. Result:
--   {"result": "verified" | "location_pending" | "rejected", "reason": ...,
--    "visit_id": ..., "distance_m": ..., "radius_m": ...}
create or replace function public.check_in(
  p_task_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m double precision,
  p_is_mocked boolean,
  p_developer_mode boolean default false,
  p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t public.visit_tasks;
  loc public.shop_locations;
  v_reason text;
  v_distance double precision;
  v_visit uuid;
  v_suggestion uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  c_max_accuracy constant double precision := 50;
begin
  select * into t from public.visit_tasks where id = p_task_id and staff_id = auth.uid() for update;
  if t.id is null then
    raise exception 'check_in: no such visit for you' using errcode = 'no_data_found';
  end if;
  if t.visit_date <> public.business_today() then
    raise exception 'check_in: this visit is not for today' using errcode = '22023';
  end if;
  if exists (select 1 from public.shop_visits v where v.task_id = t.id) then
    raise exception 'check_in: already checked in' using errcode = '23505';
  end if;
  if not public.can_see_shop(t.shop_id) then
    raise exception 'check_in: you no longer have this shop' using errcode = '42501';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'check_in: a location is required' using errcode = '22023';
  end if;
  if v_note is not null and length(v_note) > 500 then
    raise exception 'check_in: the note is too long' using errcode = '22023';
  end if;

  select * into loc from public.shop_locations where shop_id = t.shop_id;
  if loc.shop_id is not null then
    v_distance := public.distance_m(p_lat, p_lng, loc.latitude, loc.longitude);
  end if;

  v_reason := case
    when coalesce(p_is_mocked, false) then 'mock_location'
    when coalesce(p_developer_mode, false) then 'developer_options'
    when p_accuracy_m is null or p_accuracy_m > c_max_accuracy then 'poor_accuracy'
    when loc.shop_id is not null and v_distance > loc.radius_m then 'out_of_range'
  end;
  if v_reason is not null then
    insert into public.visit_failed_attempts (business_id, company_id, task_id, staff_id, shop_id, reason,
                                              device_lat, device_lng, accuracy_m, distance_m, radius_m)
    values (t.business_id, t.company_id, t.id, t.staff_id, t.shop_id, v_reason,
            p_lat, p_lng, p_accuracy_m, v_distance, loc.radius_m);
    return jsonb_build_object('result', 'rejected', 'reason', v_reason, 'distance_m', v_distance, 'radius_m', loc.radius_m);
  end if;

  if loc.shop_id is null then
    insert into public.shop_location_suggestions (business_id, company_id, shop_id, suggested_by, latitude, longitude, accuracy_m)
    values (t.business_id, t.company_id, t.shop_id, t.staff_id, p_lat, p_lng, p_accuracy_m)
    returning id into v_suggestion;
  end if;

  insert into public.shop_visits (business_id, company_id, task_id, staff_id, shop_id, visit_date,
                                  device_lat, device_lng, accuracy_m, shop_lat, shop_lng, radius_m, distance_m,
                                  status, suggestion_id, note)
  values (t.business_id, t.company_id, t.id, t.staff_id, t.shop_id, t.visit_date,
          p_lat, p_lng, p_accuracy_m, loc.latitude, loc.longitude, loc.radius_m, v_distance,
          case when loc.shop_id is null then 'location_pending' else 'verified' end, v_suggestion, v_note)
  returning id into v_visit;

  return jsonb_build_object('result', case when loc.shop_id is null then 'location_pending' else 'verified' end,
                            'visit_id', v_visit, 'distance_m', v_distance, 'radius_m', loc.radius_m);
end $$;

-- A note can be added once, on the day of the visit, if none was given at check-in.
create or replace function public.add_visit_note(p_visit_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if v_note is null or length(v_note) > 500 then
    raise exception 'add_visit_note: a note of 1 to 500 characters is required' using errcode = '22023';
  end if;
  update public.shop_visits set note = v_note
  where id = p_visit_id and staff_id = auth.uid() and note is null and visit_date = public.business_today();
  if not found then
    raise exception 'add_visit_note: this visit cannot take a note' using errcode = '42501';
  end if;
end $$;

-- Owner view of a day (or staff: their own day): every task with its visit.
create view public.v_visit_tasks with (security_invoker = true) as
  select t.id as task_id, t.business_id, t.company_id, t.staff_id, u.name as staff_name,
         t.shop_id, t.shop_name, t.site_id, t.site_name, t.visit_date, t.plan_id,
         v.id as visit_id, v.checked_in_at, v.status as visit_status, v.distance_m, v.radius_m,
         v.accuracy_m, v.note,
         case when v.id is not null then v.status
              when t.visit_date < public.business_today() then 'missed'
              else 'pending' end as state
  from public.visit_tasks t
  join public.users u on u.id = t.staff_id
  left join public.shop_visits v on v.task_id = t.id;
grant select on public.v_visit_tasks to authenticated;

revoke all on function public.set_shop_location(uuid, double precision, double precision, integer) from public, anon;
revoke all on function public.clear_shop_location(uuid) from public, anon;
revoke all on function public.review_location_suggestion(uuid, boolean, integer) from public, anon;
revoke all on function public.ensure_visit_tasks(date, date) from public, anon;
revoke all on function public.check_in(uuid, double precision, double precision, double precision, boolean, boolean, text) from public, anon;
revoke all on function public.add_visit_note(uuid, text) from public, anon;
grant execute on function public.set_shop_location(uuid, double precision, double precision, integer) to authenticated;
grant execute on function public.clear_shop_location(uuid) to authenticated;
grant execute on function public.review_location_suggestion(uuid, boolean, integer) to authenticated;
grant execute on function public.ensure_visit_tasks(date, date) to authenticated;
grant execute on function public.check_in(uuid, double precision, double precision, double precision, boolean, boolean, text) to authenticated;
grant execute on function public.add_visit_note(uuid, text) to authenticated;

commit;
