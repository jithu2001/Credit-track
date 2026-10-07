-- Checks for migration 0008 (minimum stock per item).
--
-- Runs in one transaction that is ROLLED BACK at the end, so it is safe on a
-- real business database. Run all tests with tests/run_local.sh (throwaway
-- Postgres in Docker), or with psql as `postgres` against a business database.
-- A failed check aborts with "assertion failed: <label>".

begin;

create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'assertion failed: %', label; end if;
end $$;

create function pg_temp.fails(stmt text, state text, label text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlstate = state then return; end if;
    raise exception 'assertion failed: % (got % %)', label, sqlstate, sqlerrm;
  end;
  raise exception 'assertion failed: % (no error)', label;
end $$;

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

insert into public.businesses (id, name) values
  ('b0000000-0000-0000-0000-0000000000f1', 'Stock Biz'),
  ('b0000000-0000-0000-0000-0000000000f2', 'Other Biz');
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000f1', 'owner@stock.test'),
  ('a0000000-0000-0000-0000-0000000000f2', 'staff@stock.test'),
  ('a0000000-0000-0000-0000-0000000000f3', 'nobody@stock.test'),
  ('a0000000-0000-0000-0000-0000000000f4', 'owner@other.test');
insert into public.users (id, business_id, role, name, email, is_active) values
  ('a0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000f1', 'OWNER', 'Owner', 'owner@stock.test', true),
  ('a0000000-0000-0000-0000-0000000000f2', 'b0000000-0000-0000-0000-0000000000f1', 'STAFF', 'Staff', 'staff@stock.test', true),
  ('a0000000-0000-0000-0000-0000000000f3', 'b0000000-0000-0000-0000-0000000000f1', 'STAFF', 'Unassigned', 'nobody@stock.test', true),
  ('a0000000-0000-0000-0000-0000000000f4', 'b0000000-0000-0000-0000-0000000000f2', 'OWNER', 'Other owner', 'owner@other.test', true);
insert into public.tally_companies (id, business_id, tally_company_id, company_name) values
  ('c0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000f1', 'gf1', 'Stock Co'),
  ('c0000000-0000-0000-0000-0000000000f2', 'b0000000-0000-0000-0000-0000000000f1', 'gf2', 'Second Co'),
  ('c0000000-0000-0000-0000-0000000000f3', 'b0000000-0000-0000-0000-0000000000f2', 'gf3', 'Other Co');
insert into public.stock_items (id, business_id, company_id, tally_item_id, name, closing_qty, synced_at) values
  ('e0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f1', 'i1', 'TYRE A', 40, now()),
  ('e0000000-0000-0000-0000-0000000000f2', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f1', 'i2', 'TYRE B', 5, now()),
  ('e0000000-0000-0000-0000-0000000000f3', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f1', 'i3', 'OIL 1L', 2.5, now()),
  ('e0000000-0000-0000-0000-0000000000f4', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f2', 'i4', 'TUBE', 1, now()),
  ('e0000000-0000-0000-0000-0000000000f5', 'b0000000-0000-0000-0000-0000000000f2', 'c0000000-0000-0000-0000-0000000000f3', 'i5', 'OTHER', 1, now());
insert into public.staff_company_access (user_id, business_id, company_id, full_company)
values ('a0000000-0000-0000-0000-0000000000f2', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f1', true);

-- ------------------------------------------------------------------ owner
select pg_temp.act_as('a0000000-0000-0000-0000-0000000000f1');
select pg_temp.check(public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f1']::uuid[], 50) = 1, 'owner sets one item');
select pg_temp.check(public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1',
  array['e0000000-0000-0000-0000-0000000000f2', 'e0000000-0000-0000-0000-0000000000f3', 'e0000000-0000-0000-0000-0000000000f3']::uuid[], 10.5) = 2,
  'owner sets the same minimum on many items (duplicates ignored)');
select pg_temp.check((select min_qty from public.stock_minimums where stock_item_id = 'e0000000-0000-0000-0000-0000000000f3') = 10.5, 'decimal minimum kept');
select pg_temp.check(public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f1']::uuid[], 60) = 1, 'changing a minimum');
select pg_temp.check((select min_qty from public.stock_minimums where stock_item_id = 'e0000000-0000-0000-0000-0000000000f1') = 60, 'minimum updated');
select pg_temp.check(public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f2']::uuid[], 0) = 1, 'minimum 0 clears it');
select pg_temp.check(public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f3']::uuid[], null) = 1, 'null clears it');
select pg_temp.check((select count(*) from public.stock_minimums) = 1, 'owner reads the minimums');
select pg_temp.fails($$select public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f4']::uuid[], 5)$$,
  '22023', 'item of another company refused');
select pg_temp.fails($$select public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f3', array['e0000000-0000-0000-0000-0000000000f5']::uuid[], 5)$$,
  '22023', 'item of another business refused');
select pg_temp.fails($$select public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f1']::uuid[], -1)$$,
  '22023', 'negative minimum refused');
select pg_temp.fails($$select public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array[]::uuid[], 5)$$,
  '22023', 'no items refused');
select pg_temp.fails($$insert into public.stock_minimums (stock_item_id, business_id, company_id, min_qty)
  values ('e0000000-0000-0000-0000-0000000000f2', 'b0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000f1', 3)$$,
  '42501', 'no direct writes, even for the owner');
reset role;

-- ------------------------------------------------------------------ staff
select pg_temp.act_as('a0000000-0000-0000-0000-0000000000f2');
select pg_temp.check((select count(*) from public.stock_minimums) = 1, 'assigned staff read the minimums');
select pg_temp.fails($$select public.set_stock_minimum('c0000000-0000-0000-0000-0000000000f1', array['e0000000-0000-0000-0000-0000000000f2']::uuid[], 5)$$,
  '42501', 'staff cannot set a minimum');
reset role;

select pg_temp.act_as('a0000000-0000-0000-0000-0000000000f3');
select pg_temp.check((select count(*) from public.stock_minimums) = 0, 'unassigned staff see none');
reset role;

-- ------------------------------------------------------------------ another business's owner
select pg_temp.act_as('a0000000-0000-0000-0000-0000000000f4');
select pg_temp.check((select count(*) from public.stock_minimums) = 0, 'another business sees none');
reset role;

-- Items removed from Tally take their minimum with them.
delete from public.stock_items where id = 'e0000000-0000-0000-0000-0000000000f1';
select pg_temp.check((select count(*) from public.stock_minimums) = 0, 'minimum removed with its item');

rollback;
