package appapi

import (
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// The dashboard in one call (owner and staff; staff see only their shops):
//
//	GET /b/{slug}/api/v1/dashboard?company=<id>[&month=YYYY-MM]
//
// company totals, the company's sync state, this month's sales (null for
// staff who may not see transactions) and the ten shops owing most.

const topDuesLimit = 10

func (s *Server) dashboard(r *request) (any, error) {
	companyID := r.URL.Query().Get("company")
	if companyID == "" {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "company is required.")
	}
	month := time.Date(r.today.Year(), r.today.Month(), 1, 0, 0, 0, 0, time.UTC)
	if v := r.URL.Query().Get("month"); v != "" {
		m, err := time.Parse("2006-01", v)
		if err != nil {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "month must be YYYY-MM.")
		}
		month = m
	}
	ctx := r.Context()

	var name string
	var shops, withDues int
	var outstanding, credit int64
	var canSeeTxns bool
	err := r.tx.QueryRow(ctx, `select company_name, shops, shops_with_dues,
			round(total_outstanding * 100)::bigint, round(total_credit * 100)::bigint,
			public.can_see_transactions(company_id)
		from public.v_company_summary where company_id = $1::uuid`, companyID).
		Scan(&name, &shops, &withDues, &outstanding, &credit, &canSeeTxns)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "No such company.")
	} else if err != nil {
		return nil, err
	}
	out := map[string]any{
		"summary": map[string]any{
			"company_id": companyID, "company_name": name, "shops": shops, "shops_with_dues": withDues,
			"total_outstanding": money(outstanding), "total_credit": money(credit),
		},
		"sync_state":  nil,
		"month_sales": nil,
	}

	var lastOK, lastTry *time.Time
	var status string
	var errCode, errMsg *string
	err = r.tx.QueryRow(ctx, `select last_successful_sync_at, last_attempt_at, coalesce(status, 'ok'), error_code, error_message
		from public.sync_state where company_id = $1::uuid and entity_type = 'company'`, companyID).
		Scan(&lastOK, &lastTry, &status, &errCode, &errMsg)
	switch {
	case err == nil:
		out["sync_state"] = map[string]any{
			"last_successful_sync_at": optTime(lastOK), "last_attempt_at": optTime(lastTry),
			"status": status, "error_code": errCode, "error_message": errMsg,
		}
	case !errors.Is(err, pgx.ErrNoRows):
		return nil, err
	}

	if canSeeTxns {
		var amount int64
		var bills int
		if err := r.tx.QueryRow(ctx, `select coalesce(round(sum(debit) * 100), 0)::bigint, count(*)
			from public.transactions
			where company_id = $1::uuid and category = 'sales' and deleted_at is null and debit > 0
			  and transaction_date >= $2 and transaction_date < $3`,
			companyID, month, month.AddDate(0, 1, 0)).Scan(&amount, &bills); err != nil {
			return nil, err
		}
		out["month_sales"] = map[string]any{"month": date(month), "amount": money(amount), "bills": bills}
	}

	rows, err := r.tx.Query(ctx, `select shop_id::text, name, area, phone, round(receivable * 100)::bigint, site_id::text, site_name
		from public.v_shop_outstanding where company_id = $1::uuid and receivable > 0
		order by receivable desc, shop_id limit $2`, companyID, topDuesLimit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	top := []map[string]any{}
	for rows.Next() {
		var id, shopName string
		var area, phone, siteID, siteName *string
		var receivable int64
		if err := rows.Scan(&id, &shopName, &area, &phone, &receivable, &siteID, &siteName); err != nil {
			return nil, err
		}
		top = append(top, map[string]any{
			"shop_id": id, "name": shopName, "area": area, "phone": phone,
			"receivable": money(receivable), "site_id": siteID, "site_name": siteName,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out["top_dues"] = top
	return out, nil
}

func optTime(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.UTC().Format(time.RFC3339Nano)
}
