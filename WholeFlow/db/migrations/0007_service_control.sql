-- WholeFlow — subscription status and per-PC keys, for businesses hosted on
-- the WholeFlow server (see docs/MULTI_TENANT_PLAN.md, sections 3 and 5.4).
--
-- Additive. On a database without a service_status row everything behaves as
-- "active" (no subscription to enforce).
--
--   * service_status: one row, written only by the control service (it
--     connects as postgres), read by signed-in users for the app banners.
--   * revoked_devices: Tally PCs whose own key has been revoked.
--   * check_request(): run by the data API (PostgREST db-pre-request) before
--     every request. Refuses a revoked PC's key (HTTP 403) and every request
--     once the subscription has ended (HTTP 402), with the message and
--     contact for the apps' block screen.
--
-- Apply with scripts/migrate.sh (server) or the SQL editor.

begin;

create table public.service_status (
  id             boolean primary key default true check (id),  -- exactly one row
  status         text not null default 'active' check (status in ('active', 'suspended', 'closed')),
  paid_until     date,            -- null: no end date (e.g. not hosted by the WholeFlow server)
  grace_until    date,            -- apps keep working until this day, with a red banner
  remind_from    date,            -- owners see "renewal due" from this day
  plan_name      text,
  max_companies  integer,
  message        text,            -- shown to owners (e.g. how to pay)
  contact        text,            -- your phone / UPI id
  updated_at     timestamptz not null default now()
);

alter table public.service_status enable row level security;
create policy service_status_read on public.service_status for select to authenticated using (true);
revoke all on public.service_status from anon, authenticated, service_role;
grant select on public.service_status to authenticated, service_role;

create table public.revoked_devices (
  device_id   uuid primary key,
  revoked_at  timestamptz not null default now()
);
alter table public.revoked_devices enable row level security;
revoke all on public.revoked_devices from anon, authenticated, service_role;

-- 'active' | 'renewal_due' | 'grace' | 'ended', by the business clock.
create or replace function public.access_state()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
             when s.status <> 'active' then 'ended'
             when s.grace_until is not null and public.business_today() > s.grace_until then 'ended'
             when s.paid_until is not null and public.business_today() > s.paid_until then 'grace'
             when s.remind_from is not null and public.business_today() >= s.remind_from then 'renewal_due'
             else 'active'
           end
    from public.service_status s), 'active')
$$;
grant execute on function public.access_state() to anon, authenticated, service_role;

-- PostgREST db-pre-request. SQLSTATE PTxyz makes PostgREST answer HTTP xyz.
create or replace function public.check_request()
returns void language plpgsql stable security definer set search_path = public as $$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_device text := v_claims ->> 'device_id';
  s public.service_status;
begin
  if v_device is not null
     and exists (select 1 from public.revoked_devices d where d.device_id::text = v_device) then
    raise sqlstate 'PT403' using message = 'device_revoked',
      detail = 'This PC has been removed from WholeFlow. Ask for a new activation code.';
  end if;
  if public.access_state() = 'ended' then
    select * into s from public.service_status;
    raise sqlstate 'PT402' using message = 'subscription_ended',
      detail = coalesce(s.message, 'The WholeFlow subscription for this business has ended.'),
      hint = coalesce(s.contact, '');
  end if;
end $$;
grant execute on function public.check_request() to anon, authenticated, service_role;

commit;
