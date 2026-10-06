-- WholeFlow — shops past their credit period, for the mobile Outstanding screen.
--
-- Additive and safe to run on the live database: one new read-only function,
-- nothing existing is changed.
--
-- overdue_shops(company, credit_days, today) ages each shop's unpaid bills the
-- same way the app's Analytics screen does (payment_analysis.dart):
--   * every credit (receipt, return, credit adjustment) settles the oldest
--     open bill first (FIFO);
--   * the opening balance counts as one bill dated where the synced vouchers
--     begin (the earlier of the Tally period start and the first voucher,
--     else the start of the books); a Cr opening balance is an advance;
--   * a bill is past the limit once today is more than credit_days after its
--     date.
-- With FIFO the bills left open are always the newest ones, so a bill's unpaid
-- part is its share of (all bills up to and including it) - (all credits).
--
-- It returns one row per shop with something past the limit. Staff need the
-- total and the days even when they may not see transactions, so the function
-- is SECURITY DEFINER and checks access itself:
--   * the company must belong to the caller's business and be visible to them
--     (owner, or staff assigned to it);
--   * shops are limited to the caller's areas (can_see_area), as RLS does;
--   * the bill list is filled only when can_see_transactions() allows it,
--     otherwise it is null and only the amounts and days are returned.
--
-- Apply in the Supabase dashboard: SQL Editor → paste this file → Run.

begin;

create or replace function public.overdue_shops(p_company_id uuid, p_credit_days integer, p_today date)
returns table (
  shop_id           uuid,
  name              text,
  area              text,
  phone             text,
  receivable        numeric,  -- total the shop owes (synced from Tally)
  overdue           numeric,  -- unpaid part of the bills past the limit
  max_days_overdue  integer,  -- days the oldest of them is past the limit
  overdue_bills     integer,
  bills_visible     boolean,
  bills             jsonb     -- oldest first; null when bills_visible is false
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
    select s.id, s.name, s.area, s.phone, s.receivable,
           case when s.opening_balance_type = 'CR' then -abs(s.opening_balance_amount)
                else abs(s.opening_balance_amount) end as opening
    from public.shops s
    where s.company_id = p_company_id and s.business_id = v_business and s.deleted_at is null
      and public.can_see_area(s.company_id, s.area)
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
         end
  from open_bills o
  join visible v on v.id = o.shop_id
  where o.remaining > 0 and o.days_overdue > 0
  group by v.id, v.name, v.area, v.phone, v.receivable;
end $$;

revoke all on function public.overdue_shops(uuid, integer, date) from public, anon;
grant execute on function public.overdue_shops(uuid, integer, date) to authenticated;

commit;
