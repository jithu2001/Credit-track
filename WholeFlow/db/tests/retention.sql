-- Checks for public.purge_old_data() (migration 0009), as `postgres`.
-- Runs in one transaction that is ROLLED BACK.
-- A failed check aborts with "assertion failed: <label>".

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

insert into public.businesses (id, name) values ('b9000000-0000-0000-0000-00000000000a', 'Retention');
insert into auth.users (id, email) values
  ('a9000000-0000-0000-0000-000000000001', 'o@ret.test'), ('a9000000-0000-0000-0000-000000000002', 's@ret.test');
insert into public.users (id, business_id, role, name, email, requires_check_in) values
  ('a9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a', 'OWNER', 'Owner', 'o@ret.test', false),
  ('a9000000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff', 's@ret.test', true);
insert into public.tally_companies (id, business_id, tally_company_id, company_name) values
  ('c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a', 'g-ret', 'Ret Co');
insert into public.shops (id, business_id, company_id, tally_ledger_id, name, synced_at) values
  ('d9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'l1', 'Shop', now());
insert into public.visit_tasks (id, business_id, company_id, staff_id, shop_id, visit_date, shop_name, site_name) values
  ('f9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', current_date - 400, 'Shop', 'Site'),
  ('f9000000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', current_date - 10, 'Shop', 'Site');
insert into public.shop_visits (business_id, company_id, task_id, staff_id, shop_id, visit_date, checked_in_at,
                                device_lat, device_lng, accuracy_m, status) values
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', current_date - 400, now() - interval '400 days',
   9.85, 76.97, 10, 'verified'),
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000002',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', current_date - 10, now() - interval '10 days',
   9.85, 76.97, 10, 'verified');
insert into public.visit_failed_attempts (business_id, company_id, task_id, staff_id, shop_id, attempted_at, reason, device_lat, device_lng) values
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', now() - interval '400 days', 'out_of_range', 9.9, 76.9),
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000002',
   'a9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', now() - interval '10 days', 'out_of_range', 9.9, 76.9);
insert into public.shop_location_suggestions (business_id, company_id, shop_id, suggested_by, latitude, longitude, status, reviewed_at, created_at) values
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 9.8, 76.8, 'rejected', now() - interval '400 days', now() - interval '401 days'),
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 9.8, 76.8, 'rejected', now() - interval '10 days', now() - interval '11 days'),
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000001',
   'a9000000-0000-0000-0000-000000000002', 9.8, 76.8, 'pending', null, now() - interval '400 days');
insert into public.sync_logs (business_id, company_id, started_at, status) values
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', now() - interval '200 days', 'success'),
  ('b9000000-0000-0000-0000-00000000000a', 'c9000000-0000-0000-0000-000000000001', now() - interval '20 days', 'success');

-- As the server runs it (service_role works too).
create temp table res (r jsonb);
grant insert on res to service_role;
set local role service_role;
insert into res select public.purge_old_data();
reset role;

select pg_temp.check((select r->>'visit_locations_cleared' from res)::int >= 1, 'old visit positions cleared');
select pg_temp.check((select count(*) from public.shop_visits
                      where task_id = 'f9000000-0000-0000-0000-000000000001' and device_lat is null and device_lng is null
                        and status = 'verified' and accuracy_m = 10) = 1, 'old visit kept without its position');
select pg_temp.check((select device_lat from public.shop_visits where task_id = 'f9000000-0000-0000-0000-000000000002') = 9.85,
                     'recent visit keeps its position');
select pg_temp.check((select count(*) from public.visit_failed_attempts where business_id = 'b9000000-0000-0000-0000-00000000000a') = 1,
                     'only the recent failed attempt is kept');
select pg_temp.check((select count(*) from public.shop_location_suggestions where business_id = 'b9000000-0000-0000-0000-00000000000a') = 2,
                     'old rejected suggestion deleted; recent rejected and pending kept');
select pg_temp.check((select count(*) from public.sync_logs where business_id = 'b9000000-0000-0000-0000-00000000000a') = 1,
                     'sync logs older than 180 days deleted');
select pg_temp.check((public.purge_old_data()->>'sync_logs_deleted')::int = 0, 'a second run changes nothing');

-- Clients may not run it.
do $$
begin
  perform set_config('request.jwt.claims', '{"sub": "a9000000-0000-0000-0000-000000000001", "role": "authenticated"}', true);
  set local role authenticated;
  begin
    perform public.purge_old_data();
    raise exception 'assertion failed: authenticated ran purge_old_data';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

select 'retention: all checks passed' as result;

rollback;
