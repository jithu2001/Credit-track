-- An invented business for trying the phone apps on this computer
-- (cmd/localapi). Only for the throwaway database of db/tests/run_local.sh;
-- every name and amount is made up. Re-running replaces it.
--
--   psql postgres://postgres:pw@127.0.0.1:55432/wf_local -v ON_ERROR_STOP=1 -f db/local/seed.sql
--
-- Owner owner@local.test (cmd/localapi sets the password from LOCAL_PASSWORD).
-- 24 shops on 3 sites, 3 suppliers, and sales, receipts, returns and
-- purchases from September 2025 to today, with a slow start, a festive peak
-- in October and steady growth, so trends have something to show.

\set biz '\'b0000000-0000-0000-0000-0000000010ca\''
\set owner '\'a0000000-0000-0000-0000-0000000010ca\''
\set co '\'c0000000-0000-0000-0000-0000000010ca\''

begin;
delete from public.businesses where id = :biz;
delete from auth.users where id = :owner;

insert into public.businesses (id, name) values (:biz, 'Local Test Distributors');
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values (:owner, 'authenticated', 'authenticated', 'owner@local.test', now(), now(), now());
insert into public.users (id, business_id, role, name, email) values (:owner, :biz, 'OWNER', 'Local Owner', 'owner@local.test');
insert into public.tally_companies (id, business_id, tally_company_id, company_name, books_from, period_from)
values (:co, :biz, 'local-co', 'Local Test Distributors', '2025-04-01', '2026-04-01');

insert into public.sites (id, business_id, company_id, name)
select ('e0000000-0000-0000-0000-00000000100' || n)::uuid, :biz, :co, name
from (values (1, 'Kottayam Town'), (2, 'Pala'), (3, 'Changanassery')) s(n, name);

select setseed(0.42);

-- 24 shops; a few big buyers, most small.
create temp table seed_shops as
select ('d0000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid as id, n,
       (array['City', 'Royal', 'Sree', 'New', 'Metro', 'Classic', 'Prime', 'Star'])[1 + n % 8] || ' ' ||
       (array['Battery House', 'Auto Spares', 'Motors', 'Power Centre', 'Traders', 'Agencies'])[1 + n % 6] ||
       ' ' || n as name,
       ('e0000000-0000-0000-0000-00000000100' || (1 + n % 3))::uuid as site_id,
       case when n <= 4 then 3.0 when n <= 10 then 1.6 else 0.8 end as size
from generate_series(1, 24) n;

insert into public.shops (id, business_id, company_id, tally_ledger_id, name, phone, opening_balance_amount,
                          opening_balance_type, receivable, site_id, synced_at)
select id, :biz, :co, 'local-l' || n, name, '98470' || lpad(n::text, 5, '0'), 0, 'DR', 0, site_id, now()
from seed_shops;

-- Month factor: quiet September, festive October–November 2025, steady growth since.
create temp table seed_months as
select m::date as m,
       case extract(month from m)::int when 9 then 0.8 when 10 then 1.35 when 11 then 1.2 when 12 then 1.0 else 1.0 end
       * (1 + 0.025 * (extract(year from m) * 12 + extract(month from m) - (2025 * 12 + 9))) as factor
from generate_series('2025-09-01'::date, date_trunc('month', current_date), interval '1 month') m;

-- Sales: 1–4 bills per shop per month (none after today).
create temp table seed_sales as
select * from (
select s.id as shop_id, s.n, mo.m,
       mo.m + (random() * 27)::int as d,
       round(((8000 + random() * 22000) * s.size * mo.factor)::numeric, 2) as amount
from seed_shops s
cross join seed_months mo
cross join lateral generate_series(1, 1 + (random() * 3)::int) b
) x where d <= current_date;

insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id,
                                 transaction_date, voucher_type, voucher_number, category, debit, credit, amount, synced_at)
select :biz, :co, shop_id, 'local-s-' || row_number() over (), 'local-l' || n, d, 'Sales',
       'S' || row_number() over (order by d), 'sales', amount, 0, amount, now()
from seed_sales;

-- Receipts: each month's sales paid 15–50 days later at 80–100% (none in the future).
insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id,
                                 transaction_date, voucher_type, voucher_number, category, debit, credit, amount, synced_at)
select :biz, :co, shop_id, 'local-r-' || row_number() over (), 'local-l' || n, d, 'Receipt',
       'R' || row_number() over (order by d), 'receipts', 0, amount, -amount, now()
from (
  select shop_id, n, m + 15 + (random() * 35)::int as d, round(sum(amount) * (0.8 + random() * 0.2)::numeric, 2) as amount
  from seed_sales group by shop_id, n, m
) r
where d <= current_date;

-- A few returns.
insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id,
                                 transaction_date, voucher_type, voucher_number, category, debit, credit, amount, synced_at)
select :biz, :co, shop_id, 'local-c-' || row_number() over (), 'local-l' || n, d, 'Credit Note',
       'C' || row_number() over (order by d), 'returns', 0, round(amount * 0.3, 2), -round(amount * 0.3, 2), now()
from seed_sales where random() < 0.04;

update public.shops s set receivable = t.bal
from (select shop_id, sum(debit) - sum(credit) as bal from public.transactions
      where company_id = :co group by shop_id) t
where t.shop_id = s.id;

-- Purchases: 4–7 bills a month from 3 suppliers, about 75% of sales.
insert into public.suppliers (id, business_id, company_id, tally_ledger_id, name, payable, synced_at)
select ('f0000000-0000-0000-0000-00000000100' || n)::uuid, :biz, :co, 'local-sup' || n, name, 0, now()
from (values (1, 'Amara Batteries Ltd'), (2, 'Exide Distributors South'), (3, 'Kerala Auto Components')) s(n, name);

insert into public.purchases (business_id, company_id, tally_voucher_id, supplier_id, supplier_name, purchase_date,
                              taxable_amount, tax_and_other_amount, total_amount, synced_at)
select :biz, :co, 'local-p-' || row_number() over (), ('f0000000-0000-0000-0000-00000000100' || sup)::uuid,
       (array['Amara Batteries Ltd', 'Exide Distributors South', 'Kerala Auto Components'])[sup],
       d, round(total / 1.18, 2), total - round(total / 1.18, 2), total, now()
from (
  select mo.m, mo.m + (random() * 27)::int as d, 1 + (random() * 2)::int as sup,
         round(sales.total * 0.75 / bills.k * (0.8 + random() * 0.4)::numeric, 2) as total
  from seed_months mo
  join (select m, sum(amount) as total from seed_sales group by m) sales on sales.m = mo.m
  cross join lateral (select 4 + (random() * 3)::int as k) bills
  cross join lateral generate_series(1, bills.k) b
) p
where d <= current_date;

insert into public.sync_state (business_id, company_id, entity_type, last_successful_sync_at, last_attempt_at, status)
values (:biz, :co, 'company', now(), now(), 'ok');
commit;

select to_char(date_trunc('month', transaction_date), 'YYYY-MM') as month,
       round(sum(debit) filter (where category = 'sales')) as sales,
       round(sum(credit) filter (where category = 'receipts')) as receipts
from public.transactions where company_id = :co group by 1 order by 1;
