-- Checks for migration 0004 (overdue_shops).
--
-- Seeds one company with known bills and payments, calls the function as each
-- kind of user and asserts the amounts, days and bill visibility. Everything
-- runs in one transaction that is ROLLED BACK at the end, so it is safe on a
-- real business database. Run all tests with tests/run_local.sh (throwaway
-- Postgres in Docker), or with psql as `postgres` against a business database.
-- A failed check aborts with "assertion failed: <label>".
--
-- "Today" is 2026-09-29 throughout; the company's period starts 2026-04-01.
--   Shop X (Rajakkad): Dr opening 1000, sale S1 500 on 08-10, sale S2 300 on 09-19,
--                      receipt 1200 on 09-24 (plus a deleted receipt that must be ignored).
--                      FIFO: opening paid, S1 has 300 left, S2 300 left.
--   Shop Y (Pala):     Cr opening 200 (advance), sale 1000 on 06-21 → 800 left.
--   Shop Z (Pala):     sale 100 paid in full → never overdue.
--   Shop W (Rajakkad): sale 400 on 09-20 → within 30 days.
--   Shop V (no area):  Dr opening 250, no vouchers → dated 04-01.
-- Users: owner_a; staff_t (full company, may see transactions);
--        staff_p (site Pala only, may not see transactions); owner_b (other business).

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- ------------------------------------------------------------------ seed (as postgres)

insert into public.businesses (id, name) values
  ('b1000000-0000-0000-0000-00000000000a', 'Overdue A'),
  ('b1000000-0000-0000-0000-00000000000b', 'Overdue B');

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'od_owner_a@test.local'),
  ('a1000000-0000-0000-0000-000000000002', 'od_staff_t@test.local'),
  ('a1000000-0000-0000-0000-000000000003', 'od_staff_p@test.local'),
  ('a1000000-0000-0000-0000-000000000004', 'od_owner_b@test.local');

insert into public.users (id, business_id, role, name, email, is_active) values
  ('a1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-00000000000a', 'OWNER', 'Owner A', 'od_owner_a@test.local', true),
  ('a1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff T', 'od_staff_t@test.local', true),
  ('a1000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff P', 'od_staff_p@test.local', true),
  ('a1000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-00000000000b', 'OWNER', 'Owner B', 'od_owner_b@test.local', true);

insert into public.tally_companies (id, business_id, tally_company_id, company_name, period_from, books_from) values
  ('c1000000-0000-0000-0000-0000000000a1', 'b1000000-0000-0000-0000-00000000000a', 'od-guid-a1', 'Company A1', '2026-04-01', '2020-04-01');

insert into public.staff_company_access (user_id, company_id, business_id, full_company, can_view_transactions) values
  ('a1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-0000000000a1', 'b1000000-0000-0000-0000-00000000000a', true,  true),
  ('a1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-0000000000a1', 'b1000000-0000-0000-0000-00000000000a', false, false);

insert into public.shops (id, business_id, company_id, tally_ledger_id, name, area, opening_balance_amount, opening_balance_type, receivable, synced_at) values
  ('d1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'lx', 'Shop X', 'Rajakkad', 1000, 'DR', 600, now()),
  ('d1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'ly', 'Shop Y', 'Pala',      200, 'CR', 800, now()),
  ('d1000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'lz', 'Shop Z', 'Pala',        0, '',     0, now()),
  ('d1000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'lw', 'Shop W', 'Rajakkad',    0, '',   400, now()),
  ('d1000000-0000-0000-0000-000000000005', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'lv', 'Shop V', null,        250, 'DR', 250, now());

-- Site "Pala" holds Y and Z; staff_p has only that site.
insert into public.sites (id, business_id, company_id, name) values
  ('e1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', 'Pala');
update public.shops set site_id = 'e1000000-0000-0000-0000-000000000001'
where id in ('d1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000003');
insert into public.staff_site_access (user_id, site_id, business_id) values
  ('a1000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-00000000000a');

insert into public.transactions
  (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id, transaction_date, voucher_type, voucher_number, category, debit, credit, amount, synced_at, deleted_at)
select 'b1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', s.id, v.vid, s.tally_ledger_id, v.d::date, v.vt, v.vn, v.cat, v.dr, v.cr, v.dr - v.cr, now(), v.del
from (values
  ('lx', 'x-s1', '2026-08-10', 'Sales',   'S1', 'sales',       500,    0, null::timestamptz),
  ('lx', 'x-s2', '2026-09-19', 'Sales',   'S2', 'sales',       300,    0, null),
  ('lx', 'x-r1', '2026-09-24', 'Receipt', 'R1', 'receipts',      0, 1200, null),
  ('lx', 'x-r2', '2026-09-25', 'Receipt', 'R2', 'receipts',      0,  500, now()),
  ('ly', 'y-s1', '2026-06-21', 'Sales',   'S3', 'sales',      1000,    0, null),
  ('lz', 'z-s1', '2026-06-01', 'Sales',   'S4', 'sales',       100,    0, null),
  ('lz', 'z-r1', '2026-06-05', 'Receipt', 'R3', 'receipts',      0,  100, null),
  ('lw', 'w-s1', '2026-09-20', 'Sales',   'S5', 'sales',       400,    0, null)
) as v(ledger, vid, d, vt, vn, cat, dr, cr, del)
join public.shops s on s.tally_ledger_id = v.ledger and s.company_id = 'c1000000-0000-0000-0000-0000000000a1';

create temp table r as select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 30, '2026-09-29') limit 0;
grant all on r to authenticated;

-- ------------------------------------------------------------------ owner: everything, with bills

select pg_temp.act_as('a1000000-0000-0000-0000-000000000001');
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 30, '2026-09-29');

select pg_temp.check((select count(*) from r) = 3, 'owner, 30 days: shops X, Y and V');
select pg_temp.check((select overdue from r where name = 'Shop X') = 300, 'X: only 300 of S1 is past 30 days');
select pg_temp.check((select max_days_overdue from r where name = 'Shop X') = 20, 'X: S1 is 20 days past the limit');
select pg_temp.check((select overdue_bills from r where name = 'Shop X') = 1, 'X: one bill past the limit');
select pg_temp.check((select receivable from r where name = 'Shop X') = 600, 'X: total outstanding is returned');
select pg_temp.check((select bills_visible from r where name = 'Shop X'), 'owner sees bills');
select pg_temp.check((select bills->0->>'voucher' from r where name = 'Shop X') = 'Sales · S1', 'X: bill S1 named');
select pg_temp.check((select (bills->0->>'amount')::numeric from r where name = 'Shop X') = 500, 'X: S1 bill amount');
select pg_temp.check((select (bills->0->>'remaining')::numeric from r where name = 'Shop X') = 300, 'X: S1 unpaid part');
select pg_temp.check((select bills->0->>'date' from r where name = 'Shop X') = '2026-08-10', 'X: S1 date');
select pg_temp.check((select overdue from r where name = 'Shop Y') = 800, 'Y: Cr opening settles 200 of the sale');
select pg_temp.check((select max_days_overdue from r where name = 'Shop Y') = 70, 'Y: 100 days old, 70 past the limit');
select pg_temp.check((select overdue from r where name = 'Shop V') = 250, 'V: opening balance is a bill');
select pg_temp.check((select max_days_overdue from r where name = 'Shop V') = 151, 'V: opening dated at the period start');
select pg_temp.check((select bills->0->>'voucher' from r where name = 'Shop V') = 'Opening balance', 'V: opening bill named');

delete from r;
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 0, '2026-09-29');
select pg_temp.check((select overdue from r where name = 'Shop X') = 600, 'owner, 0 days: both X bills count');
select pg_temp.check((select max_days_overdue from r where name = 'Shop X') = 50, 'owner, 0 days: oldest X bill is 50 days');
select pg_temp.check((select jsonb_array_length(bills) from r where name = 'Shop X') = 2, 'owner, 0 days: two X bills listed');
select pg_temp.check((select bills->1->>'voucher' from r where name = 'Shop X') = 'Sales · S2', 'bills are oldest first');
select pg_temp.check((select count(*) from r where name = 'Shop W') = 1, 'owner, 0 days: W now counts');
select pg_temp.check((select count(*) from r where name = 'Shop Z') = 0, 'a paid shop never appears');

delete from r;
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 365, '2026-09-29');
select pg_temp.check((select count(*) from r) = 0, 'owner, 365 days: nothing is past the limit');

reset role;

-- ------------------------------------------------------------------ staff who may see transactions

delete from r;
select pg_temp.act_as('a1000000-0000-0000-0000-000000000002');
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 30, '2026-09-29');
select pg_temp.check((select count(*) from r) = 3, 'staff_t: all three shops');
select pg_temp.check((select bool_and(bills_visible) and bool_and(bills is not null) from r), 'staff_t: bills shown');
reset role;

-- ------------------------------------------------------------------ staff limited to Pala, no transactions

delete from r;
select pg_temp.act_as('a1000000-0000-0000-0000-000000000003');
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 30, '2026-09-29');
select pg_temp.check((select count(*) from r) = 1, 'staff_p: only the Pala site shop');
select pg_temp.check((select site_name from r where name = 'Shop Y') = 'Pala', 'staff_p: rows carry their site');
select pg_temp.check((select overdue from r where name = 'Shop Y') = 800, 'staff_p: amount still shown');
select pg_temp.check((select max_days_overdue from r where name = 'Shop Y') = 70, 'staff_p: days still shown');
select pg_temp.check((select not bills_visible and bills is null from r where name = 'Shop Y'), 'staff_p: no bills');
select pg_temp.check((select count(*) from public.transactions) = 0, 'staff_p: transactions stay hidden by RLS');
reset role;

-- ------------------------------------------------------------------ another business

delete from r;
select pg_temp.act_as('a1000000-0000-0000-0000-000000000004');
insert into r select * from public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', 30, '2026-09-29');
select pg_temp.check((select count(*) from r) = 0, 'owner_b: nothing from business A');
reset role;

-- ------------------------------------------------------------------ privileges and input checks

select pg_temp.check(not has_function_privilege('anon', 'public.overdue_shops(uuid, integer, date)', 'execute'), 'anon cannot call it');
select pg_temp.check(has_function_privilege('authenticated', 'public.overdue_shops(uuid, integer, date)', 'execute'), 'authenticated can call it');

do $$
begin
  perform public.overdue_shops('c1000000-0000-0000-0000-0000000000a1', -1, '2026-09-29');
  raise exception 'assertion failed: negative credit days rejected';
exception when invalid_parameter_value then null;
end $$;

select 'overdue: all checks passed' as result;

rollback;
