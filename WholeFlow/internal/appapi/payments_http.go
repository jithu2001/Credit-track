package appapi

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
)

// Payment insights (owner only):
//
//	GET /b/{slug}/api/v1/payments?company=<id>&credit_days=30
//	    company totals and one line per shop with bills (no bill details)
//	GET /b/{slug}/api/v1/payments/shops/{id}?credit_days=30
//	    one shop with its unpaid bills and its latest paid bills
//
// Amounts are rupee strings ("1234.50", Dr positive); dates are YYYY-MM-DD.

const defaultCreditDays = 30

// maxClosedBills is how many settled bills the shop view gets (newest).
const maxClosedBills = 100

func creditDays(r *request) (int, error) {
	v := r.URL.Query().Get("credit_days")
	if v == "" {
		return defaultCreditDays, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 || n > 365 {
		return 0, fail(http.StatusBadRequest, "INVALID_INPUT", "credit_days must be 1–365.")
	}
	return n, nil
}

func requireOwner(r *request) error {
	var owner bool
	if err := r.tx.QueryRow(r.Context(), `select coalesce(public.is_owner(), false)`).Scan(&owner); err != nil {
		return err
	}
	if !owner {
		return fail(http.StatusForbidden, "NOT_OWNER", "Only the owner can see payment insights.")
	}
	return nil
}

// ---------------------------------------------------------------- loading

const shopColumns = `s.id::text, s.name, si.name, s.phone,
	round(coalesce(s.opening_balance_amount, 0) * 100)::bigint, coalesce(s.opening_balance_type, ''),
	round(coalesce(s.receivable, 0) * 100)::bigint`

func scanShop(row pgx.Row) (ShopOpening, error) {
	var s ShopOpening
	var opening int64
	var side string
	err := row.Scan(&s.ID, &s.Name, &s.SiteName, &s.Phone, &opening, &side, &s.Receivable)
	if opening < 0 {
		opening = -opening
	}
	if side == "CR" {
		opening = -opening
	}
	s.Opening = opening
	return s, err
}

// loadTxns loads the active vouchers whose column [where] (company_id or shop_id) is arg.
func loadTxns(r *request, where string, arg string) ([]PaymentTxn, error) {
	rows, err := r.tx.Query(r.Context(), `select shop_id::text, transaction_date, coalesce(voucher_type, ''), coalesce(voucher_number, ''),
			coalesce(category, ''), round(coalesce(debit, 0) * 100)::bigint, round(coalesce(credit, 0) * 100)::bigint, created_at
		from public.transactions where `+where+` = $1::uuid and deleted_at is null
		order by transaction_date, created_at, id`, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PaymentTxn
	for rows.Next() {
		var t PaymentTxn
		var vType, vNumber string
		if err := rows.Scan(&t.ShopID, &t.Date, &vType, &vNumber, &t.Category, &t.Debit, &t.Credit, &t.CreatedAt); err != nil {
			return nil, err
		}
		t.Voucher = joinVoucher(vType, vNumber)
		out = append(out, t)
	}
	return out, rows.Err()
}

func joinVoucher(parts ...string) string {
	out := ""
	for _, p := range parts {
		if p == "" {
			continue
		}
		if out != "" {
			out += " · "
		}
		out += p
	}
	return out
}

// booksFrom dates the opening balances where the synced vouchers begin: the
// current Tally period (the vouchers reconcile from there), else the first
// voucher, else the start of the books. Dating them at books_from would make
// balances carried forward look years old.
func booksFrom(r *request, companyID string) (time.Time, error) {
	var books, period, first *time.Time
	err := r.tx.QueryRow(r.Context(), `select c.books_from, c.period_from,
			(select min(t.transaction_date) from public.transactions t where t.company_id = c.id and t.deleted_at is null)
		from public.tally_companies c where c.id = $1::uuid`, companyID).Scan(&books, &period, &first)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, fail(http.StatusNotFound, "NOT_FOUND", "No such company.")
	} else if err != nil {
		return time.Time{}, err
	}
	switch {
	case period != nil && first != nil:
		if period.After(*first) {
			return *first, nil
		}
		return *period, nil
	case period != nil:
		return *period, nil
	case first != nil:
		return *first, nil
	case books != nil:
		return *books, nil
	}
	return r.today, nil
}

// ---------------------------------------------------------------- handlers

func (s *Server) paymentSummary(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	days, err := creditDays(r)
	if err != nil {
		return nil, err
	}
	companyID := r.URL.Query().Get("company")
	if companyID == "" {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "company is required.")
	}
	from, err := booksFrom(r, companyID)
	if err != nil {
		return nil, err
	}
	rows, err := r.tx.Query(r.Context(), `select `+shopColumns+`
		from public.shops s left join public.sites si on si.id = s.site_id
		where s.company_id = $1::uuid and s.deleted_at is null order by s.id`, companyID)
	if err != nil {
		return nil, err
	}
	var shops []ShopOpening
	for rows.Next() {
		sh, err := scanShop(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		shops = append(shops, sh)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	txns, err := loadTxns(r, "company_id", companyID)
	if err != nil {
		return nil, err
	}

	sum := AnalyseBusiness(shops, txns, days, from, r.today)
	monthAgo := OverdueDaysAgo(shops, txns, days, from, r.today, 30)
	out := map[string]any{
		"company_id":        companyID,
		"credit_days":       days,
		"today":             date(sum.Today),
		"books_from":        date(from),
		"overdue":           money(sum.Overdue),
		"overdue_shops":     sum.OverdueShops,
		"open_amount":       money(sum.OpenAmount),
		"ageing":            moneyMap(sum.Ageing),
		"on_time_rate":      sum.OnTimeRate,
		"avg_days_to_pay":   sum.AvgDaysToPay,
		"overdue_month_ago": optMoney(monthAgo),
	}
	list := make([]map[string]any, 0, len(sum.Shops))
	for _, p := range sum.Shops {
		list = append(list, profileJSON(p))
	}
	out["shops"] = list
	return out, nil
}

func (s *Server) shopPayments(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	days, err := creditDays(r)
	if err != nil {
		return nil, err
	}
	var companyID string
	row := r.tx.QueryRow(r.Context(), `select s.company_id::text, `+shopColumns+`
		from public.shops s left join public.sites si on si.id = s.site_id
		where s.id = $1::uuid and s.deleted_at is null`, r.PathValue("id"))
	var sh ShopOpening
	var opening int64
	var side string
	err = row.Scan(&companyID, &sh.ID, &sh.Name, &sh.SiteName, &sh.Phone, &opening, &side, &sh.Receivable)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "No such shop.")
	} else if err != nil {
		return nil, err
	}
	if opening < 0 {
		opening = -opening
	}
	if side == "CR" {
		opening = -opening
	}
	sh.Opening = opening
	from, err := booksFrom(r, companyID)
	if err != nil {
		return nil, err
	}
	txns, err := loadTxns(r, "shop_id", sh.ID)
	if err != nil {
		return nil, err
	}
	p := AnalyseShop(sh, txns, days, from, r.today)
	out := profileJSON(p)
	out["credit_days"] = days
	out["today"] = date(p.Today)

	// Every unpaid bill, and the newest settled ones.
	closed := 0
	for _, b := range p.Bills {
		if !b.IsOpen() {
			closed++
		}
	}
	skip := closed - maxClosedBills
	bills := []map[string]any{}
	for _, b := range p.Bills {
		if !b.IsOpen() && skip > 0 {
			skip--
			continue
		}
		bills = append(bills, billJSON(b))
	}
	out["bills"] = bills
	out["closed_bills"] = closed
	return out, nil
}

// ---------------------------------------------------------------- JSON

func profileJSON(p *ShopProfile) map[string]any {
	paid, onTime := p.PaidBills()
	var oldest any
	if d := p.OldestOpenBillDate(); d != nil {
		oldest = date(*d)
	}
	var lastPaid any
	if p.LastPaymentDate != nil {
		lastPaid = date(*p.LastPaymentDate)
	}
	return map[string]any{
		"shop": map[string]any{
			"id": p.Shop.ID, "name": p.Shop.Name, "site_name": p.Shop.SiteName, "phone": p.Shop.Phone,
			"opening": money(p.Shop.Opening), "receivable": money(p.Shop.Receivable),
		},
		"advance":               money(p.Advance),
		"overdue":               money(p.Overdue()),
		"open_amount":           money(p.OpenAmount()),
		"open_bills":            p.OpenBills(),
		"max_days_overdue":      p.MaxDaysOverdue(),
		"oldest_open_bill_date": oldest,
		"ageing":                moneyMap(p.Ageing()),
		"paid_bills":            paid,
		"on_time_bills":         onTime,
		"on_time_rate":          p.OnTimeRate(),
		"avg_days_to_pay":       p.AvgDaysToPay,
		"avg_days_late":         p.AvgDaysLate,
		"last_payment_date":     lastPaid,
		"last_payment_amount":   money(p.LastPaymentAmount),
		"computed_balance":      money(p.ComputedBalance()),
		"reconciled":            p.Reconciled(),
	}
}

func billJSON(b *Bill) map[string]any {
	var settled any
	if b.SettledOn != nil {
		settled = date(*b.SettledOn)
	}
	allocs := make([]map[string]any, 0, len(b.Allocations))
	for _, a := range b.Allocations {
		allocs = append(allocs, map[string]any{"date": date(a.Date), "amount": money(a.Amount), "kind": a.Kind})
	}
	return map[string]any{
		"date": date(b.Date), "due": date(b.Due), "amount": money(b.Amount), "remaining": money(b.Remaining),
		"voucher": b.Voucher, "is_opening": b.IsOpening, "settled_on": settled, "allocations": allocs,
	}
}

func date(t time.Time) string { return t.Format("2006-01-02") }

// money writes paise as a rupee string: 123456 → "1234.56", -5 → "-0.05".
func money(paise int64) string {
	sign := ""
	if paise < 0 {
		sign, paise = "-", -paise
	}
	return fmt.Sprintf("%s%d.%02d", sign, paise/100, paise%100)
}

func optMoney(p *int64) any {
	if p == nil {
		return nil
	}
	return money(*p)
}

func moneyMap(m map[string]int64) map[string]string {
	out := make(map[string]string, len(m))
	for k, v := range m {
		out[k] = money(v)
	}
	return out
}
