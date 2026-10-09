package appapi

import (
	"encoding/json"
	"net/http"
	"strconv"
)

// The signed-in user and the business around them (owner and staff):
//
//	GET /b/{slug}/api/v1/me                      {"user": users row | null, "business_name"}
//	GET /b/{slug}/api/v1/me/access               the caller's own company assignments (staff)
//	GET /b/{slug}/api/v1/companies               the companies the caller may see
//	GET /b/{slug}/api/v1/companies/{id}/areas    distinct Tally areas of its active shops
//	GET /b/{slug}/api/v1/service-status          {"service_status": row | null}
//	GET /b/{slug}/api/v1/sync/connections        Tally PCs (owner; others get none)
//	GET /b/{slug}/api/v1/sync/logs?limit=20      recent syncs
//
// Rows have the same fields as the tables; row-level security decides what
// each caller gets.

// jsonRows runs a query wrapped as "select coalesce(json_agg(x), '[]') from (<query>) x".
func jsonRows(r *request, query string, args ...any) (json.RawMessage, error) {
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select coalesce(json_agg(x), '[]') from (`+query+`) x`, args...).Scan(&raw)
	return raw, err
}

// jsonRow is jsonRows for at most one row: the row, or JSON null.
func jsonRow(r *request, query string, args ...any) (json.RawMessage, error) {
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select coalesce((select row_to_json(x) from (`+query+`) x limit 1), 'null'::json)`, args...).Scan(&raw)
	return raw, err
}

func (s *Server) me(r *request) (any, error) {
	user, err := jsonRow(r, `select id, business_id, role, name, email, is_active, requires_check_in
		from public.users where id = auth.uid()`)
	if err != nil {
		return nil, err
	}
	var name *string
	if err := r.tx.QueryRow(r.Context(), `select (select name from public.businesses where id = public.current_business_id())`).
		Scan(&name); err != nil {
		return nil, err
	}
	return map[string]any{"user": user, "business_name": name}, nil
}

func (s *Server) myAccess(r *request) (any, error) {
	rows, err := jsonRows(r, `select user_id, company_id, full_company, can_view_transactions
		from public.staff_company_access where user_id = auth.uid() order by company_id`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"access": rows}, nil
}

func (s *Server) companies(r *request) (any, error) {
	rows, err := jsonRows(r, `select id, company_name, sync_status, last_sync_at from public.tally_companies order by company_name, id`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"companies": rows}, nil
}

func (s *Server) companyAreas(r *request) (any, error) {
	if _, err := companyName(r, r.PathValue("id")); err != nil {
		return nil, err
	}
	// Exact values: lists filter by them. Sorted ignoring case.
	rows, err := r.tx.Query(r.Context(), `select distinct area from public.shops
		where company_id = $1::uuid and deleted_at is null and area is not null and area <> ''
		order by area`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	areas := []string{}
	for rows.Next() {
		var a string
		if err := rows.Scan(&a); err != nil {
			return nil, err
		}
		areas = append(areas, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sortFold(areas)
	return map[string]any{"areas": areas}, nil
}

func (s *Server) serviceStatus(r *request) (any, error) {
	row, err := jsonRow(r, `select status, paid_until, grace_until, remind_from, plan_name, message, contact from public.service_status`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"service_status": row}, nil
}

func (s *Server) syncConnections(r *request) (any, error) {
	rows, err := jsonRows(r, `select machine_identifier, hostname, status, app_version, last_seen_at
		from public.tally_connections order by last_seen_at desc nulls last`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"connections": rows}, nil
}

func (s *Server) syncLogs(r *request) (any, error) {
	limit := 20
	if v := r.URL.Query().Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 200 {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "limit must be 1–200.")
		}
		limit = n
	}
	rows, err := jsonRows(r, `select id, company_id, started_at, completed_at, status, mode, records_processed, records_created,
			records_updated, records_deleted, records_failed, shops_processed, transactions_fetched, error_code, error_message
		from public.sync_logs order by started_at desc limit $1`, limit)
	if err != nil {
		return nil, err
	}
	return map[string]any{"logs": rows}, nil
}
