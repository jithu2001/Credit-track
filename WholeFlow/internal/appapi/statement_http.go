package appapi

import (
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// A shop's statement (owner, and staff allowed to see that company's
// transactions):
//
//	GET /b/{slug}/api/v1/shops/{id}/statement[?from=YYYY-MM-DD&to=YYYY-MM-DD]
//
// Without dates: the whole ledger. With dates: the period, with the balance
// brought forward. Lines are newest first, each with the balance after it.

func optDate(r *request, key string) (*time.Time, error) {
	v := r.URL.Query().Get(key)
	if v == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", v)
	if err != nil {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", key+" must be a date (YYYY-MM-DD).")
	}
	return &t, nil
}

func (s *Server) shopStatement(r *request) (any, error) {
	from, err := optDate(r, "from")
	if err != nil {
		return nil, err
	}
	to, err := optDate(r, "to")
	if err != nil {
		return nil, err
	}
	if from != nil && to != nil && from.After(*to) {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "from must not be after to.")
	}

	var companyID string
	var opening, receivable int64
	var side string
	var allowed bool
	err = r.tx.QueryRow(r.Context(), `select s.company_id::text, round(s.opening_balance_amount * 100)::bigint,
			s.opening_balance_type, round(s.receivable * 100)::bigint, public.can_see_transactions(s.company_id)
		from public.shops s where s.id = $1::uuid and s.deleted_at is null`, r.PathValue("id")).
		Scan(&companyID, &opening, &side, &receivable, &allowed)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "No such shop.")
	} else if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, fail(http.StatusForbidden, "NO_TRANSACTIONS", "You can't see this company's transactions.")
	}
	if opening < 0 {
		opening = -opening
	}
	if side == "CR" {
		opening = -opening
	}

	rows, err := r.tx.Query(r.Context(), `select id::text, transaction_date, voucher_type, voucher_number, category, narration,
			round(debit * 100)::bigint, round(credit * 100)::bigint, round(amount * 100)::bigint, created_at
		from public.transactions where shop_id = $1::uuid and deleted_at is null
		order by transaction_date, created_at, id`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	var txns []StatementTxn
	for rows.Next() {
		var t StatementTxn
		if err := rows.Scan(&t.ID, &t.Date, &t.VoucherType, &t.VoucherNumber, &t.Category, &t.Narration,
			&t.Debit, &t.Credit, &t.Amount, &t.CreatedAt); err != nil {
			rows.Close()
			return nil, err
		}
		txns = append(txns, t)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	st := BuildStatement(opening, receivable, txns)
	p := st.Period(from, to)
	lines := make([]map[string]any, 0, len(p.Lines))
	for i := len(p.Lines) - 1; i >= 0; i-- { // newest first
		l := p.Lines[i]
		var created any
		if l.Txn.CreatedAt != nil {
			created = l.Txn.CreatedAt.UTC().Format(time.RFC3339Nano)
		}
		lines = append(lines, map[string]any{
			"id": l.Txn.ID, "transaction_date": date(l.Txn.Date), "voucher_type": l.Txn.VoucherType,
			"voucher_number": l.Txn.VoucherNumber, "category": l.Txn.Category, "narration": l.Txn.Narration,
			"debit": money(l.Txn.Debit), "credit": money(l.Txn.Credit), "amount": money(l.Txn.Amount),
			"created_at": created, "balance_after": money(l.BalanceAfter),
		})
	}
	optDay := func(t *time.Time) any {
		if t == nil {
			return nil
		}
		return date(*t)
	}
	return map[string]any{
		"shop_id":          r.PathValue("id"),
		"company_id":       companyID,
		"from":             optDay(p.From),
		"to":               optDay(p.To),
		"opening":          money(p.Opening),
		"closing":          money(p.Closing),
		"total_debit":      money(p.TotalDebit),
		"total_credit":     money(p.TotalCredit),
		"ledger_opening":   money(st.Opening),
		"tally_balance":    money(st.Closing),
		"computed_balance": money(st.ComputedClosing),
		"reconciled":       st.Reconciled(),
		"lines":            lines,
	}, nil
}
