-- WholeFlow — minimum stock per item, set by the owner in the Owner app.
--
-- Kept apart from stock_items, which the Tally PC rewrites on every sync and
-- the app never writes. An item is "at or below minimum" when its closing
-- quantity is at or below this minimum, or, with no minimum set here, at or
-- below Tally's reorder level (the apps decide that; see StockItem).
--
--   * stock_minimums: one row per item that has a minimum.
--   * set_stock_minimum(company, items[], min): owner only; sets the same
--     minimum on one or many items, or clears it (min null or 0).
--   * Everyone who can see the company can read the minimums.
--
-- Applied by the WholeFlow server to every business (scripts/migrate.sh, or the
-- admin app → Settings → Update all businesses). Checks: tests/stock_minimums.sql.

begin;

create table public.stock_minimums (
  stock_item_id  uuid primary key references public.stock_items (id) on delete cascade,
  business_id    uuid not null references public.businesses (id) on delete cascade,
  company_id     uuid not null references public.tally_companies (id) on delete cascade,
  min_qty        numeric(16,3) not null check (min_qty > 0),
  updated_by     uuid references public.users (id) on delete set null,
  updated_at     timestamptz not null default now()
);
create index stock_minimums_company_idx on public.stock_minimums (company_id);

alter table public.stock_minimums enable row level security;
create policy stock_minimums_read on public.stock_minimums for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_company(company_id));
revoke all on public.stock_minimums from anon, authenticated;
grant select on public.stock_minimums to authenticated;
grant all on public.stock_minimums to service_role;

-- Sets [p_min] as the minimum of every item in [p_items] (all of company
-- [p_company]); null or 0 removes their minimum. Returns how many items changed.
create or replace function public.set_stock_minimum(p_company uuid, p_items uuid[], p_min numeric)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_business uuid := public.current_business_id();
  v_found    integer;
  v_changed  integer;
begin
  if v_business is null or not public.is_owner() then
    raise exception 'set_stock_minimum: only the owner can set minimum stock' using errcode = '42501';
  end if;
  if p_items is null or cardinality(p_items) = 0 then
    raise exception 'set_stock_minimum: choose at least one item' using errcode = '22023';
  end if;
  if cardinality(p_items) > 5000 then
    raise exception 'set_stock_minimum: at most 5000 items at a time' using errcode = '22023';
  end if;
  if p_min is not null and (p_min < 0 or p_min > 999999999) then
    raise exception 'set_stock_minimum: the minimum must be 0 or more' using errcode = '22023';
  end if;

  select count(*) into v_found
  from public.stock_items i
  where i.id = any (p_items) and i.company_id = p_company and i.business_id = v_business;
  if v_found <> (select count(distinct x) from unnest(p_items) x) then
    raise exception 'set_stock_minimum: some items are not in this company' using errcode = '22023';
  end if;

  if p_min is null or p_min = 0 then
    delete from public.stock_minimums m where m.stock_item_id = any (p_items) and m.company_id = p_company;
    get diagnostics v_changed = row_count;
  else
    insert into public.stock_minimums (stock_item_id, business_id, company_id, min_qty, updated_by, updated_at)
    select distinct x, v_business, p_company, p_min, auth.uid(), now() from unnest(p_items) x
    on conflict (stock_item_id) do update
      set min_qty = excluded.min_qty, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
    get diagnostics v_changed = row_count;
  end if;
  return v_changed;
end $$;
revoke all on function public.set_stock_minimum(uuid, uuid[], numeric) from public, anon;
grant execute on function public.set_stock_minimum(uuid, uuid[], numeric) to authenticated;

commit;
