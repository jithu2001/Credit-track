-- Checks for migration 0005 (sites, site report, shop pins, visit plans, check-in).
--
-- Seeds one business, impersonates the owner and staff, and asserts results.
-- Everything runs in one transaction that is ROLLED BACK at the end, so it is
-- safe on a real business database. Run all tests with
-- tests/run_local.sh (throwaway Postgres in Docker), or with psql as `postgres`
-- against a business database.
-- A failed check aborts with "assertion failed: <label>".
--
-- Business S, companies S1 and S2.
--   S1 shops: P1, P2 (site "Town"), P3 (site "Hills"), P4 (no site); S2 shop Q1.
--   owner_s      OWNER
--   staff_town   S1 limited to site Town, check-in on, may see transactions
--   staff_full   S1 full company, check-in off, may not see transactions
--   staff_x      S1 limited to site Hills, check-in on

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

-- Expects the statement to fail with the given SQLSTATE.
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

-- ------------------------------------------------------------------ seed (as postgres)

insert into public.businesses (id, name) values ('b2000000-0000-0000-0000-00000000000a', 'Business S');

insert into auth.users (id, email) values
  ('a2000000-0000-0000-0000-000000000001', 'sv_owner@test.local'),
  ('a2000000-0000-0000-0000-000000000002', 'sv_town@test.local'),
  ('a2000000-0000-0000-0000-000000000003', 'sv_full@test.local'),
  ('a2000000-0000-0000-0000-000000000004', 'sv_x@test.local');

insert into public.users (id, business_id, role, name, email, requires_check_in) values
  ('a2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'OWNER', 'Owner S',    'sv_owner@test.local', false),
  ('a2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff Town', 'sv_town@test.local',  true),
  ('a2000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff Full', 'sv_full@test.local',  false),
  ('a2000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-00000000000a', 'STAFF', 'Staff X',    'sv_x@test.local',     true);

insert into public.tally_companies (id, business_id, tally_company_id, company_name) values
  ('c2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-00000000000a', 'sv-guid-1', 'Company S1'),
  ('c2000000-0000-0000-0000-0000000000a2', 'b2000000-0000-0000-0000-00000000000a', 'sv-guid-2', 'Company S2');

insert into public.shops (id, business_id, company_id, tally_ledger_id, name, area, receivable, synced_at) values
  ('d2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'p1', 'Shop P1', 'Pala', 1000, now()),
  ('d2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'p2', 'Shop P2', 'Pala', -200, now()),
  ('d2000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'p3', 'Shop P3', 'Kply',  300, now()),
  ('d2000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'p4', 'Shop P4', null,    400, now()),
  ('d2000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a2', 'q1', 'Shop Q1', null,    500, now());

-- This month: P1 sale 700 + receipt 300, P3 sale 100 + return 20, P4 receipt 50. Last year: P1 sale 999.
insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id, transaction_date, category, debit, credit, amount, synced_at)
values
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000001', 'v1', 'p1', date_trunc('month', current_date)::date, 'sales',    700,   0,  700, now()),
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000001', 'v2', 'p1', date_trunc('month', current_date)::date, 'receipts',   0, 300, -300, now()),
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000003', 'v3', 'p3', date_trunc('month', current_date)::date, 'sales',    100,   0,  100, now()),
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000003', 'v4', 'p3', date_trunc('month', current_date)::date, 'returns',    0,  20,  -20, now()),
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000004', 'v5', 'p4', date_trunc('month', current_date)::date, 'receipts',   0,  50,  -50, now()),
  ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'd2000000-0000-0000-0000-000000000001', 'v6', 'p1', (current_date - 400),                    'sales',    999,   0,  999, now());

-- ------------------------------------------------------------------ owner builds sites

select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
insert into public.sites (id, business_id, company_id, name) values
  ('e2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'Town'),
  ('e2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'Hills');
-- The app leaves business_id out: it defaults to the caller's business.
insert into public.sites (company_id, name) values ('c2000000-0000-0000-0000-0000000000a2', 'Elsewhere');
select pg_temp.check((select business_id from public.sites where name = 'Elsewhere') = 'b2000000-0000-0000-0000-00000000000a',
                     'site business defaults to the caller''s');
delete from public.sites where name = 'Elsewhere';
select pg_temp.check(public.set_site_shops('e2000000-0000-0000-0000-000000000001',
                       array['d2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000003']::uuid[]) = 3,
                     'owner: Town gets three shops');
-- Moving P3 to Hills takes it out of Town (one site per shop).
select pg_temp.check(public.set_site_shops('e2000000-0000-0000-0000-000000000002', array['d2000000-0000-0000-0000-000000000003']::uuid[]) = 1,
                     'owner: Hills gets P3');
select pg_temp.check((select count(*) from public.shops where site_id = 'e2000000-0000-0000-0000-000000000001') = 2,
                     'moving a shop removes it from its old site');
select pg_temp.fails($$select public.set_site_shops('e2000000-0000-0000-0000-000000000001', array['d2000000-0000-0000-0000-000000000005']::uuid[])$$,
                     '23514', 'a shop of another company cannot join');
-- Sync-style upsert of a shop keeps its site.
reset role;
insert into public.shops (business_id, company_id, tally_ledger_id, name, receivable, synced_at)
values ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'p1', 'Shop P1 renamed', 1000, now())
on conflict (company_id, tally_ledger_id) do update set name = excluded.name, receivable = excluded.receivable, synced_at = excluded.synced_at;
select pg_temp.check((select site_id from public.shops where id = 'd2000000-0000-0000-0000-000000000001') = 'e2000000-0000-0000-0000-000000000001',
                     'a sync upsert does not move a shop out of its site');

-- Staff access, as manage-staff writes it.
set local role service_role;
select public.admin_set_staff_companies('a2000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-00000000000a', 'a2000000-0000-0000-0000-000000000001',
  '[{"company_id": "c2000000-0000-0000-0000-0000000000a1", "full_company": false, "site_ids": ["e2000000-0000-0000-0000-000000000001"], "can_view_transactions": true}]');
select public.admin_set_staff_companies('a2000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-00000000000a', 'a2000000-0000-0000-0000-000000000001',
  '[{"company_id": "c2000000-0000-0000-0000-0000000000a1", "full_company": true, "site_ids": ["e2000000-0000-0000-0000-000000000001"], "can_view_transactions": false}]');
select public.admin_set_staff_companies('a2000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-00000000000a', 'a2000000-0000-0000-0000-000000000001',
  '[{"company_id": "c2000000-0000-0000-0000-0000000000a1", "full_company": false, "site_ids": ["e2000000-0000-0000-0000-000000000002"]}]');
select pg_temp.check((select count(*) from public.staff_site_access where user_id = 'a2000000-0000-0000-0000-000000000003') = 0,
                     'full company ignores listed sites');
reset role;

-- ------------------------------------------------------------------ what each one sees

select pg_temp.act_as('a2000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.shops) = 2, 'staff_town: only the two Town shops');
select pg_temp.check((select count(*) from public.sites) = 1, 'staff_town: only the Town site');
select pg_temp.check((select count(*) from public.transactions) = 3, 'staff_town: only Town transactions (P1 has three)');
select pg_temp.fails($$insert into public.sites (business_id, company_id, name) values ('b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1', 'Mine')$$,
                     '42501', 'staff cannot create sites');
select pg_temp.fails($$select public.set_site_shops('e2000000-0000-0000-0000-000000000001', '{}'::uuid[])$$, '42501', 'staff cannot change site shops');
reset role;

select pg_temp.act_as('a2000000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) from public.shops) = 4, 'staff_full: every S1 shop, including the one in no site');
select pg_temp.check((select count(*) from public.sites) = 2, 'staff_full: both S1 sites');
reset role;

-- ------------------------------------------------------------------ site report

select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
create temp table rep as
  select * from public.site_report('c2000000-0000-0000-0000-0000000000a1', date_trunc('month', current_date)::date, current_date);
grant select on rep to authenticated;
select pg_temp.check((select count(*) from rep) = 3, 'owner report: Town, Hills and no site');
select pg_temp.check((select shops = 2 and shops_with_dues = 1 and outstanding = 1000 and advance = 200 and sales = 700 and collections = 300
                      from rep where site_name = 'Town'), 'owner report: Town figures (last year''s sale left out)');
select pg_temp.check((select sales = 100 and returns = 20 and outstanding = 300 from rep where site_name = 'Hills'), 'owner report: Hills figures');
select pg_temp.check((select site_id is null and shops = 1 and collections = 50 from rep where site_name is null), 'owner report: no-site row');
reset role;
drop table rep;

select pg_temp.act_as('a2000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.site_report('c2000000-0000-0000-0000-0000000000a1', current_date - 30, current_date)) = 1,
                     'staff_town report: only Town');
reset role;
select pg_temp.act_as('a2000000-0000-0000-0000-000000000003');
select pg_temp.check((select bool_and(sales is null and collections is null)
                      from public.site_report('c2000000-0000-0000-0000-0000000000a1', current_date - 30, current_date)),
                     'staff_full report: no money figures without transaction access');
reset role;

-- ------------------------------------------------------------------ pins

select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
-- P1 pinned (radius 100 m); P2 left unpinned for the suggestion flow.
select public.set_shop_location('d2000000-0000-0000-0000-000000000001', 9.85, 76.97, 100);
select pg_temp.fails($$select public.set_shop_location('d2000000-0000-0000-0000-000000000001', 9.85, 76.97, 4)$$, '23514', 'radius below 5 m refused');
select public.set_shop_location('d2000000-0000-0000-0000-000000000001', 9.85, 76.97, 5);
select public.set_shop_location('d2000000-0000-0000-0000-000000000001', 9.85, 76.97, 100);
reset role;
select pg_temp.act_as('a2000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.shop_locations) = 1, 'staff_town: sees the P1 pin');
select pg_temp.fails($$select public.set_shop_location('d2000000-0000-0000-0000-000000000002', 9.85, 76.97, 100)$$, '42501', 'staff cannot pin');
reset role;
select pg_temp.act_as('a2000000-0000-0000-0000-000000000004');
select pg_temp.check((select count(*) from public.shop_locations) = 0, 'staff_x: cannot see a Town pin');
reset role;

-- ------------------------------------------------------------------ plans

select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
insert into public.visit_plans (id, business_id, site_id, staff_id, plan_date)
values ('f2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-000000000001',
        'a2000000-0000-0000-0000-000000000002', public.business_today());
-- Weekly plan for the same site on today's weekday: no duplicate tasks.
insert into public.visit_plans (business_id, site_id, staff_id, weekday, starts_on)
values ('b2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002',
        extract(isodow from public.business_today())::int, public.business_today() - 7);
select pg_temp.fails($$insert into public.visit_plans (business_id, site_id, staff_id, plan_date) values
                       ('b2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000003', current_date)$$,
                     '23514', 'no plan for staff with check-in off');
select pg_temp.fails($$insert into public.visit_plans (business_id, site_id, staff_id, plan_date) values
                       ('b2000000-0000-0000-0000-00000000000a', 'e2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000004', current_date)$$,
                     '23514', 'no plan for a site the staff member does not have');
-- Today P1, P2 (both plans ask, one task each) and 7 days ago P1, P2 (weekly plan).
select pg_temp.check(public.ensure_visit_tasks(public.business_today() - 7, public.business_today()) = 4,
                     'owner ensure: two days × two shops');
select pg_temp.check(public.ensure_visit_tasks(public.business_today() - 7, public.business_today()) = 0,
                     'ensure is idempotent');
reset role;

-- ------------------------------------------------------------------ check-in

create temp table ids (name text primary key, id uuid);
grant select, insert on ids to authenticated;
insert into ids select 'p1_today', id from public.visit_tasks
  where shop_id = 'd2000000-0000-0000-0000-000000000001' and visit_date = (now() at time zone 'Asia/Kolkata')::date;
insert into ids select 'p2_today', id from public.visit_tasks
  where shop_id = 'd2000000-0000-0000-0000-000000000002' and visit_date = (now() at time zone 'Asia/Kolkata')::date;
insert into ids select 'p1_past', id from public.visit_tasks
  where shop_id = 'd2000000-0000-0000-0000-000000000001' and visit_date = (now() at time zone 'Asia/Kolkata')::date - 7;

select pg_temp.act_as('a2000000-0000-0000-0000-000000000002');
-- P1 pin is (9.85, 76.97), radius 100 m. 0.0027° of latitude is about 300 m; 0.00045° about 50 m.
select pg_temp.check((public.check_in((select id from ids where name = 'p1_today'), 9.85, 76.97, 10, true)->>'reason') = 'mock_location',
                     'mock location rejected');
select pg_temp.check((public.check_in((select id from ids where name = 'p1_today'), 9.85, 76.97, 10, false, true)->>'reason') = 'developer_options',
                     'developer options rejected');
select pg_temp.check((public.check_in((select id from ids where name = 'p1_today'), 9.85, 76.97, 80, false)->>'reason') = 'poor_accuracy',
                     'GPS accuracy worse than 50 m rejected');
select pg_temp.check((public.check_in((select id from ids where name = 'p1_today'), 9.8527, 76.97, 10, false)->>'reason') = 'out_of_range',
                     '300 m away rejected');
select pg_temp.check((select count(*) from public.visit_failed_attempts) = 0, 'staff cannot read failed attempts');
select pg_temp.check((public.check_in((select id from ids where name = 'p1_today'), 9.85045, 76.97, 10, false, false, '  Paid half  ')->>'result') = 'verified',
                     '50 m away verified');
select pg_temp.check((select status = 'verified' and note = 'Paid half' and round(distance_m) between 45 and 55 from public.shop_visits),
                     'visit stored with server distance and trimmed note');
select pg_temp.fails($$select public.check_in((select id from ids where name = 'p1_today'), 9.85, 76.97, 10, false)$$, '23505', 'second check-in refused');
select pg_temp.fails($$select public.check_in((select id from ids where name = 'p1_past'), 9.85, 76.97, 10, false)$$, '22023', 'a past day cannot be checked in');
select pg_temp.fails($$update public.shop_visits set note = 'changed'$$, '42501', 'staff cannot edit visits');
select pg_temp.fails($$delete from public.shop_visits$$, '42501', 'staff cannot delete visits');
select pg_temp.fails($$select public.add_visit_note((select id from public.shop_visits limit 1), 'again')$$, '42501', 'a note cannot be replaced');

-- P2 has no pin: the visit waits for the owner, and a suggestion is made.
select pg_temp.check((public.check_in((select id from ids where name = 'p2_today'), 9.86, 76.98, 12, false)->>'result') = 'location_pending',
                     'unpinned shop: location pending');
select public.add_visit_note((select id from public.shop_visits where status = 'location_pending'), 'New shop front');
select pg_temp.check((select count(*) from public.shop_location_suggestions) = 1, 'staff sees own suggestion');
select pg_temp.check((select count(*) from public.v_visit_tasks where state = 'missed') = 2, 'last week''s two unvisited tasks are missed');
reset role;

select pg_temp.act_as('a2000000-0000-0000-0000-000000000004');
select pg_temp.fails($$select public.check_in((select id from ids where name = 'p2_today'), 9.86, 76.98, 12, false)$$, 'P0002',
                     'another staff member''s task refused');
select pg_temp.check((select count(*) from public.shop_visits) = 0, 'staff_x sees no visits of others');
reset role;

select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) from public.visit_failed_attempts) = 4, 'owner sees the four rejected attempts');
select pg_temp.check((select count(*) from public.v_visit_tasks where state = 'verified') = 1, 'owner view: one verified');
select public.review_location_suggestion((select id from public.shop_location_suggestions), true, 100);
select pg_temp.check((select status = 'verified' and distance_m = 0 from public.shop_visits where shop_id = 'd2000000-0000-0000-0000-000000000002'),
                     'approving the pin verifies the waiting visit');
select pg_temp.check((select source from public.shop_locations where shop_id = 'd2000000-0000-0000-0000-000000000002') = 'suggestion',
                     'approved pin is marked as from a suggestion');

-- Turning the weekly plan off drops today's unvisited tasks but keeps history.
update public.visit_plans set active = false;
select public.ensure_visit_tasks(public.business_today() - 7, public.business_today());
select pg_temp.check((select count(*) from public.visit_tasks) = 4, 'visited tasks and past tasks stay when plans stop');
select pg_temp.check((select count(*) from ids) = 3, 'test setup found the three tasks');
reset role;

-- A rejected suggestion leaves its visit unverified.
reset role;
update public.shop_visits set status = 'location_pending', suggestion_id = null where shop_id = 'd2000000-0000-0000-0000-000000000002';
insert into public.shop_location_suggestions (id, business_id, company_id, shop_id, suggested_by, latitude, longitude)
values ('99000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000000a', 'c2000000-0000-0000-0000-0000000000a1',
        'd2000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 9.86, 76.98);
update public.shop_visits set suggestion_id = '99000000-0000-0000-0000-000000000001' where shop_id = 'd2000000-0000-0000-0000-000000000002';
select pg_temp.act_as('a2000000-0000-0000-0000-000000000001');
select public.review_location_suggestion('99000000-0000-0000-0000-000000000001', false);
select pg_temp.check((select status from public.shop_visits where shop_id = 'd2000000-0000-0000-0000-000000000002') = 'unverified',
                     'rejecting the suggestion leaves the visit unverified');
reset role;

select 'sites_visits: all checks passed' as result;

rollback;
