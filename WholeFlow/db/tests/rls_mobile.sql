-- RLS checks for staff company assignment (0002), with access by site (0005).
--
-- Seeds two businesses, impersonates each kind of user and asserts what they
-- can see. Everything runs in one transaction that is ROLLED BACK at the end,
-- so it is safe on a real business database. Run all tests with
-- tests/run_local.sh (throwaway Postgres in Docker), or with psql as `postgres`
-- against a business database.
-- A failed check aborts with "assertion failed: <label>".
--
-- Business A: companies A1 (shops in Rajakkad, Pala, no area) and A2 (Pala, Kply)
-- Business B: company B1 (one shop)
--   owner_a        OWNER of A
--   staff_a1       A1 only
--   staff_a2       A1 (everything) + A2 limited to the site "Pala", no transactions in A2
--   staff_none     no assignment
--   staff_off      A1, but disabled
--   staff_b        B1 (business B)

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

-- Impersonation: set_config(..., true) and SET LOCAL last until the end of the transaction.
create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- ------------------------------------------------------------------ seed (as postgres)

insert into public.businesses (id, name) values
  ('b0000000-0000-0000-0000-00000000000a', 'Business A'),
  ('b0000000-0000-0000-0000-00000000000b', 'Business B');

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'owner_a@test.local'),
  ('a0000000-0000-0000-0000-000000000002', 'staff_a1@test.local'),
  ('a0000000-0000-0000-0000-000000000003', 'staff_a2@test.local'),
  ('a0000000-0000-0000-0000-000000000004', 'staff_none@test.local'),
  ('a0000000-0000-0000-0000-000000000005', 'staff_off@test.local'),
  ('a0000000-0000-0000-0000-000000000006', 'staff_b@test.local'),
  ('a0000000-0000-0000-0000-000000000007', 'owner_b@test.local');

insert into public.users (id, business_id, role, name, email, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', 'OWNER', 'Owner A',    'owner_a@test.local',    true),
  ('a0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff A1',   'staff_a1@test.local',   true),
  ('a0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff A2',   'staff_a2@test.local',   true),
  ('a0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff None', 'staff_none@test.local', true),
  ('a0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff Off',  'staff_off@test.local',  false),
  ('a0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-00000000000b', 'STAFF', 'Staff B',    'staff_b@test.local',    true),
  ('a0000000-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-00000000000b', 'OWNER', 'Owner B',    'owner_b@test.local',    true);

insert into public.tally_companies (id, business_id, tally_company_id, company_name) values
  ('c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a', 'guid-a1', 'Company A1'),
  ('c0000000-0000-0000-0000-0000000000a2', 'b0000000-0000-0000-0000-00000000000a', 'guid-a2', 'Company A2'),
  ('c0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000b', 'guid-b1', 'Company B1');

insert into public.shops (id, business_id, company_id, tally_ledger_id, name, area, receivable, synced_at) values
  ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a1', 'l1', 'Shop 1 -- RAJAKKAD', 'Rajakkad', 100.00, now()),
  ('d0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a1', 'l2', 'Shop 2 -- PALA',     'Pala',     200.00, now()),
  ('d0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a1', 'l3', 'Shop 3',             null,       -50.00, now()),
  ('d0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', 'l4', 'Shop 4 -- PALA',     'PALA',     400.00, now()),
  ('d0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', 'l5', 'Shop 5 -- KPLY',     'KPLY',     500.00, now()),
  ('d0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-0000000000b1', 'l6', 'Shop 6',             'Pala',     600.00, now());

insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id, transaction_date, category, debit, amount, synced_at)
select s.business_id, s.company_id, s.id, 'v-' || s.tally_ledger_id, s.tally_ledger_id, current_date, 'sales', 10, 10, now()
from public.shops s
where s.business_id in ('b0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');

insert into public.sync_state (business_id, company_id, entity_type, last_successful_sync_at)
select business_id, id, 'company', now() from public.tally_companies
where business_id in ('b0000000-0000-0000-0000-00000000000a', 'b0000000-0000-0000-0000-00000000000b');

insert into public.sync_logs (business_id, company_id, started_at, status) values
  ('b0000000-0000-0000-0000-00000000000a', null,                                    now(), 'success'),
  ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a1', now(), 'success'),
  ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', now(), 'success');

-- Sites of A2: "Pala" holds shop 4, "Kply" holds shop 5.
insert into public.sites (id, business_id, company_id, name) values
  ('e0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', ' Pala '),
  ('e0000000-0000-0000-0000-0000000000a2', 'b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', 'Kply');
update public.shops set site_id = 'e0000000-0000-0000-0000-0000000000a1' where id = 'd0000000-0000-0000-0000-000000000004';
update public.shops set site_id = 'e0000000-0000-0000-0000-0000000000a2' where id = 'd0000000-0000-0000-0000-000000000005';

insert into public.staff_company_access (user_id, company_id, business_id, full_company, can_view_transactions) values
  ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a', true,  true),
  ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a', true,  true),
  ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-0000000000a2', 'b0000000-0000-0000-0000-00000000000a', false, false),
  ('a0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a', true,  true),
  ('a0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000b', true,  true);
insert into public.staff_site_access (user_id, site_id, business_id) values
  ('a0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a');

-- ------------------------------------------------------------------ integrity (as postgres)

select pg_temp.check((select name from public.sites where id = 'e0000000-0000-0000-0000-0000000000a1') = 'Pala',
                     'site names are trimmed');

do $$
begin
  begin
    insert into public.staff_company_access (user_id, company_id, business_id)
    values ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a');
    raise exception 'assertion failed: an OWNER could be assigned';
  exception when check_violation then null;
  end;
  begin
    insert into public.staff_company_access (user_id, company_id, business_id)
    values ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000a');
    raise exception 'assertion failed: a company of another business could be assigned';
  exception when check_violation then null;
  end;
  begin
    insert into public.staff_site_access (user_id, site_id, business_id)
    values ('a0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a');
    raise exception 'assertion failed: a site of a company the staff member does not have could be given';
  exception when check_violation then null;
  end;
  begin
    update public.shops set site_id = 'e0000000-0000-0000-0000-0000000000a1' where id = 'd0000000-0000-0000-0000-000000000001';
    raise exception 'assertion failed: a shop joined a site of another company';
  exception when check_violation then null;
  end;
  begin
    insert into public.sites (business_id, company_id, name)
    values ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a2', 'pala');
    raise exception 'assertion failed: two sites with the same name in one company';
  exception when unique_violation then null;
  end;
end $$;

-- ------------------------------------------------------------------ owner A

select pg_temp.act_as('a0000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) from public.tally_companies) = 2, 'owner: 2 companies');
select pg_temp.check((select count(*) from public.shops) = 5,           'owner: 5 shops');
select pg_temp.check((select count(*) from public.transactions) = 5,    'owner: 5 transactions');
select pg_temp.check((select count(*) from public.sync_logs) = 3,       'owner: 3 sync logs incl. run-level');
select pg_temp.check((select count(*) from public.users) = 5,           'owner: all 5 users of A');
select pg_temp.check((select count(*) from public.staff_company_access) = 4, 'owner: all 4 assignments of A');
select pg_temp.check((select count(*) from public.sites) = 2,           'owner: both sites');
select pg_temp.check((select count(*) from public.staff_site_access) = 1, 'owner: the one site grant');
select pg_temp.check((select count(*) from public.tally_connections) = 0, 'owner: connections readable (none seeded)');
select pg_temp.check((select total_outstanding from public.v_company_summary where company_id = 'c0000000-0000-0000-0000-0000000000a2') = 900,
                     'owner: A2 outstanding 900');
reset role;

-- ------------------------------------------------------------------ staff_a1: A1 only

select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.tally_companies) = 1, 'staff_a1: 1 company');
select pg_temp.check((select count(*) from public.sites) = 0,           'staff_a1: A1 has no sites');
select pg_temp.check((select company_name from public.tally_companies) = 'Company A1', 'staff_a1: sees A1');
select pg_temp.check((select count(*) from public.shops) = 3,           'staff_a1: 3 shops');
select pg_temp.check((select count(*) from public.transactions) = 3,    'staff_a1: 3 transactions');
select pg_temp.check((select count(*) from public.sync_state) = 1,      'staff_a1: 1 sync_state');
select pg_temp.check((select count(*) from public.sync_logs) = 1,       'staff_a1: only the A1 sync log');
select pg_temp.check((select count(*) from public.users) = 1,           'staff_a1: only own users row');
select pg_temp.check((select count(*) from public.staff_company_access) = 1, 'staff_a1: own assignment only');
select pg_temp.check((select count(*) from public.v_company_summary) = 1, 'staff_a1: 1 summary row');
select pg_temp.check((select count(*) from public.v_shop_outstanding where company_id = 'c0000000-0000-0000-0000-0000000000a2') = 0,
                     'staff_a1: no A2 rows through the view');
reset role;

-- ------------------------------------------------------------------ staff_a2: A1 + A2 (Pala, no transactions)

select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) from public.tally_companies) = 2, 'staff_a2: 2 companies');
select pg_temp.check((select count(*) from public.shops) = 4,           'staff_a2: 3 A1 shops + the Pala site shop in A2');
select pg_temp.check((select count(*) from public.sites) = 1,           'staff_a2: sees only the Pala site');
select pg_temp.check((select count(*) from public.shops where company_id = 'c0000000-0000-0000-0000-0000000000a2' and area = 'KPLY') = 0,
                     'staff_a2: KPLY hidden');
select pg_temp.check((select count(*) from public.transactions) = 3,    'staff_a2: A1 transactions only');
select pg_temp.check((select total_outstanding from public.v_company_summary where company_id = 'c0000000-0000-0000-0000-0000000000a2') = 400,
                     'staff_a2: A2 total covers only the Pala site');
select pg_temp.check((select site_name from public.v_shop_outstanding where shop_id = 'd0000000-0000-0000-0000-000000000004') = 'Pala',
                     'staff_a2: shop rows carry their site');
select pg_temp.check((select count(*) from public.tally_connections) = 0, 'staff_a2: no connections');
reset role;

-- ------------------------------------------------------------------ staff_none: no assignment

select pg_temp.act_as('a0000000-0000-0000-0000-000000000004');
select pg_temp.check((select count(*) from public.tally_companies) = 0, 'staff_none: no companies');
select pg_temp.check((select count(*) from public.shops) = 0,           'staff_none: no shops');
select pg_temp.check((select count(*) from public.transactions) = 0,    'staff_none: no transactions');
select pg_temp.check((select count(*) from public.sync_logs) = 0,       'staff_none: no sync logs');
select pg_temp.check((select count(*) from public.users) = 1,           'staff_none: still reads own row');
reset role;

-- ------------------------------------------------------------------ staff_off: disabled

select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');
select pg_temp.check((select count(*) from public.tally_companies) = 0, 'staff_off: no companies');
select pg_temp.check((select count(*) from public.shops) = 0,           'staff_off: no shops');
select pg_temp.check((select is_active from public.users) = false,      'staff_off: reads own row showing disabled');
reset role;

-- ------------------------------------------------------------------ staff_b: other business

select pg_temp.act_as('a0000000-0000-0000-0000-000000000006');
select pg_temp.check((select count(*) from public.tally_companies) = 1, 'staff_b: 1 company');
select pg_temp.check((select count(*) from public.shops) = 1,           'staff_b: 1 shop');
select pg_temp.check((select count(*) from public.shops where business_id = 'b0000000-0000-0000-0000-00000000000a') = 0,
                     'staff_b: nothing of business A');
reset role;

-- ------------------------------------------------------------------ writes are not open to authenticated users

select pg_temp.act_as('a0000000-0000-0000-0000-000000000001');
do $$
begin
  begin
    insert into public.staff_company_access (user_id, company_id, business_id)
    values ('a0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000a');
    raise exception 'assertion failed: owner inserted an assignment directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.admin_set_staff_companies('a0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-00000000000a',
                                             'a0000000-0000-0000-0000-000000000001', '[]'::jsonb);
    raise exception 'assertion failed: authenticated could call admin_set_staff_companies';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ------------------------------------------------------------------ service-role writers

insert into auth.users (id, email) values ('a0000000-0000-0000-0000-000000000008', 'new@test.local');
set local role service_role;
select public.admin_set_staff_companies(
  'a0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000001',
  '[{"company_id": "c0000000-0000-0000-0000-0000000000a2", "full_company": false,
     "site_ids": ["e0000000-0000-0000-0000-0000000000a2"], "can_view_transactions": true}]'::jsonb);
select pg_temp.check((select count(*) from public.staff_company_access where user_id = 'a0000000-0000-0000-0000-000000000002') = 1,
                     'set_companies replaces the whole set');

select public.admin_insert_staff(
  'a0000000-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-00000000000a', 'New Staff', 'new@test.local',
  'a0000000-0000-0000-0000-000000000001',
  '[{"company_id": "c0000000-0000-0000-0000-0000000000a1"}]'::jsonb);
select pg_temp.check((select count(*) from public.staff_company_access where user_id = 'a0000000-0000-0000-0000-000000000008') = 1,
                     'insert_staff writes user and assignment');

do $$
begin
  perform public.admin_set_staff_companies(
    'a0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000001',
    '[{"company_id": "c0000000-0000-0000-0000-0000000000a1"}, {"company_id": "c0000000-0000-0000-0000-0000000000b1"}]'::jsonb);
  raise exception 'assertion failed: cross-business company accepted by set_companies';
exception when check_violation then null;
end $$;
select pg_temp.check((select company_id from public.staff_company_access where user_id = 'a0000000-0000-0000-0000-000000000002')
                     = 'c0000000-0000-0000-0000-0000000000a2', 'failed set_companies left the previous set intact');
select pg_temp.check((select site_id from public.staff_site_access where user_id = 'a0000000-0000-0000-0000-000000000002')
                     = 'e0000000-0000-0000-0000-0000000000a2', 'failed set_companies left the previous site set intact');
reset role;

select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.shops) = 1, 'staff_a1 after reassignment: only the Kply site shop of A2');
reset role;

select 'rls_mobile: all checks passed' as result;

rollback;
