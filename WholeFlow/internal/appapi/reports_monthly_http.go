package appapi

import (
	"net/http"
	"strconv"
	"time"
)

// Monthly business trend (owner only), for the owner's dashboard:
//
//	GET /b/{slug}/api/v1/reports/monthly?company=<id>[&months=12]
//
// One row per calendar month, oldest first, ending with the current month
// (months with no vouchers are included with zeros): sales (sales vouchers,
// debit), bills, returns, collections (receipts), purchases and the number
// of shops that bought. As the current month is only partly over, also the
// same days (1st to today's day) of last month and of the month a year ago,
// for a fair comparison; and the shops that bought most over the window.

const (
	defaultTrendMonths = 12
	maxTrendMonths     = 24
	topBuyersLimit     = 5
)

func (s *Server) monthlyReport(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	n := defaultTrendMonths
	if v := r.URL.Query().Get("months"); v != "" {
		n, err = strconv.Atoi(v)
		if err != nil || n < 1 || n > maxTrendMonths {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "months must be 1–"+strconv.Itoa(maxTrendMonths)+".")
		}
	}
	this := time.Date(r.today.Year(), r.today.Month(), 1, 0, 0, 0, 0, time.UTC)
	from := this.AddDate(0, 1-n, 0)
	to := this.AddDate(0, 1, 0) // exclusive
	ctx := r.Context()

	// The database's rules decide which companies this user sees.
	var visible bool
	if err := r.tx.QueryRow(ctx, `select exists (select 1 from public.tally_companies where id = $1::uuid)`, companyID).
		Scan(&visible); err != nil {
		return nil, err
	}
	if !visible {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "No such company.")
	}

	rows, err := r.tx.Query(ctx, `
		with months as (
			select generate_series($2::date, $3::date, interval '1 month')::date as m
		),
		t as (
			select date_trunc('month', transaction_date)::date as m,
			       sum(debit) filter (where category = 'sales' and debit > 0) as sales,
			       count(*) filter (where category = 'sales' and debit > 0) as bills,
			       sum(credit) filter (where category = 'returns') as returns,
			       sum(credit) filter (where category = 'receipts') as collections,
			       count(distinct shop_id) filter (where category = 'sales' and debit > 0) as buyers
			from public.transactions
			where company_id = $1::uuid and deleted_at is null
			  and transaction_date >= $2 and transaction_date < $4
			group by 1
		),
		p as (
			select date_trunc('month', purchase_date)::date as m, sum(total_amount) as purchases, count(*) as bills
			from public.purchases
			where company_id = $1::uuid and deleted_at is null
			  and purchase_date >= $2 and purchase_date < $4
			group by 1
		)
		select months.m,
		       round(coalesce(t.sales, 0) * 100)::bigint, coalesce(t.bills, 0)::int,
		       round(coalesce(t.returns, 0) * 100)::bigint, round(coalesce(t.collections, 0) * 100)::bigint,
		       coalesce(t.buyers, 0)::int,
		       round(coalesce(p.purchases, 0) * 100)::bigint, coalesce(p.bills, 0)::int
		from months
		left join t on t.m = months.m
		left join p on p.m = months.m
		order by months.m`, companyID, from, this, to)
	if err != nil {
		return nil, err
	}
	months := []map[string]any{}
	for rows.Next() {
		var m time.Time
		var sales, returns, collections, purchases int64
		var bills, buyers, purchaseBills int
		if err := rows.Scan(&m, &sales, &bills, &returns, &collections, &buyers, &purchases, &purchaseBills); err != nil {
			rows.Close()
			return nil, err
		}
		months = append(months, map[string]any{
			"month": date(m), "sales": money(sales), "bills": bills, "returns": money(returns),
			"collections": money(collections), "buyers": buyers,
			"purchases": money(purchases), "purchase_bills": purchaseBills,
		})
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// The current month is only partly over: compare it with the same days
	// (1st to today's day of the month) of last month and of a year ago.
	day := r.today.Day()
	sameDays := func(monthStart time.Time) (map[string]any, error) {
		end := monthStart.AddDate(0, 0, day) // exclusive
		if next := monthStart.AddDate(0, 1, 0); end.After(next) {
			end = next // 31 Mar → up to 28/29 Feb
		}
		var sales, collections, purchases int64
		err := r.tx.QueryRow(ctx, `select
				(select round(coalesce(sum(debit) filter (where category = 'sales' and debit > 0), 0) * 100)::bigint
				 from public.transactions where company_id = $1::uuid and deleted_at is null
				   and transaction_date >= $2 and transaction_date < $3),
				(select round(coalesce(sum(credit) filter (where category = 'receipts'), 0) * 100)::bigint
				 from public.transactions where company_id = $1::uuid and deleted_at is null
				   and transaction_date >= $2 and transaction_date < $3),
				(select round(coalesce(sum(total_amount), 0) * 100)::bigint
				 from public.purchases where company_id = $1::uuid and deleted_at is null
				   and purchase_date >= $2 and purchase_date < $3)`,
			companyID, monthStart, end).Scan(&sales, &collections, &purchases)
		return map[string]any{
			"from": date(monthStart), "to": date(end.AddDate(0, 0, -1)),
			"sales": money(sales), "collections": money(collections), "purchases": money(purchases),
		}, err
	}
	lastMonth, err := sameDays(this.AddDate(0, -1, 0))
	if err != nil {
		return nil, err
	}
	lastYear, err := sameDays(this.AddDate(-1, 0, 0))
	if err != nil {
		return nil, err
	}

	rows, err = r.tx.Query(ctx, `
		select s.id::text, s.name, si.name,
		       round(sum(t.debit) * 100)::bigint, count(*)::int, round(coalesce(s.receivable, 0) * 100)::bigint
		from public.transactions t
		join public.shops s on s.id = t.shop_id and s.deleted_at is null
		left join public.sites si on si.id = s.site_id
		where t.company_id = $1::uuid and t.deleted_at is null and t.category = 'sales' and t.debit > 0
		  and t.transaction_date >= $2 and t.transaction_date < $3
		group by s.id, s.name, si.name, s.receivable
		order by 4 desc, s.name, s.id
		limit $4`, companyID, from, to, topBuyersLimit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	top := []map[string]any{}
	for rows.Next() {
		var id, name string
		var site *string
		var sales, receivable int64
		var bills int
		if err := rows.Scan(&id, &name, &site, &sales, &bills, &receivable); err != nil {
			return nil, err
		}
		top = append(top, map[string]any{
			"shop_id": id, "name": name, "site_name": site, "sales": money(sales), "bills": bills,
			"receivable": money(receivable),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{
		"company_id": companyID, "from": date(from), "to": date(this),
		"months": months, "through_day": day,
		"same_days_last_month": lastMonth, "same_days_last_year": lastYear, "top_buyers": top,
	}, nil
}
