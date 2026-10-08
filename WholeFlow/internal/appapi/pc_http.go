package appapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"reflect"
	"strings"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/cloud/wire"
	"wholeflow/internal/control"
)

// The Tally PC's uploads (replaces its use of PostgREST). Only PC keys — the
// JWT from activation, role service_role with a device_id — may call these;
// the database's check_request() still refuses a revoked PC and a business
// whose subscription has ended. Rows are wire.* (JSON names = column names).
//
//	POST /b/{slug}/api/v1/pc/authenticate            {"business_id"}
//	POST /b/{slug}/api/v1/pc/connection              wire.Connection → {"id"}
//	POST /b/{slug}/api/v1/pc/company                 wire.Company    → {"id"}
//	POST /b/{slug}/api/v1/pc/shops                   {"rows": [wire.Shop]} → {"ids": {ledger: id}}
//	GET  /b/{slug}/api/v1/pc/shops?company=          → {"refs"}
//	POST /b/{slug}/api/v1/pc/shops/delete            {"ids"}
//	POST /b/{slug}/api/v1/pc/transactions            {"rows": [wire.Transaction]}
//	POST /b/{slug}/api/v1/pc/transactions/refs       {"company_id", "voucher_ids"} → {"refs"}
//	POST /b/{slug}/api/v1/pc/transactions/delete     {"ids"}
//	GET  /b/{slug}/api/v1/pc/sync-state?company=&entity=   → {"state"}
//	PUT  /b/{slug}/api/v1/pc/sync-state              wire.SyncState
//	POST /b/{slug}/api/v1/pc/sync-logs               wire.SyncLog
//	POST /b/{slug}/api/v1/pc/suppliers | stock-items {"rows"} → {"ids"}; GET …?company= → {"refs"}; POST …/delete
//	POST /b/{slug}/api/v1/pc/purchases               {"bills": [{"purchase", "lines"}]} (lines replaced, one transaction)
//	GET  /b/{slug}/api/v1/pc/purchases?company=      → {"refs"}; POST /pc/purchases/delete

// pcBodyLimit: a batch of 500 shops or voucher lines is well under this.
const pcBodyLimit = 16 << 20

// handlePC serves a Tally PC request: its key (role service_role with a
// device_id) runs as service_role — as through PostgREST — after
// check_request(), in one read-write transaction.
func (s *Server) handlePC(fn func(*request) (any, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := s.servePC(r, fn)
		if err != nil {
			ae := toAPIError(err)
			if ae == nil {
				s.Log.Error("PC request failed", "path", r.URL.Path, "error", err.Error())
				ae = fail(http.StatusInternalServerError, "SERVER_ERROR", "The server had a problem. Please try again in a moment.")
			}
			writeJSON(w, ae.Status, map[string]any{"error": ae})
			return
		}
		writeJSON(w, http.StatusOK, out)
	}
}

func (s *Server) servePC(r *http.Request, fn func(*request) (any, error)) (any, error) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		return nil, err
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		return nil, fail(http.StatusUnauthorized, "UNAUTHENTICATED", "This PC's key is missing.")
	}
	claims, err := control.VerifyJWT(t.Secret, token, s.Now())
	if err != nil {
		return nil, fail(http.StatusUnauthorized, "UNAUTHENTICATED", "This PC's key is not valid.")
	}
	if dev, _ := claims["device_id"].(string); claims["role"] != "service_role" || dev == "" {
		return nil, fail(http.StatusForbidden, "FORBIDDEN", "Only a Tally PC's key can upload.")
	}
	claimsJSON, _ := json.Marshal(claims)
	tx, err := t.pool.BeginTx(ctx, pgx.TxOptions{AccessMode: pgx.ReadWrite})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(context.WithoutCancel(ctx))
	for _, q := range []string{`set local role service_role`, `select set_config('request.jwt.claims', $1, true)`} {
		args := []any{}
		if strings.Contains(q, "$1") {
			args = append(args, string(claimsJSON))
		}
		if _, err := tx.Exec(ctx, q, args...); err != nil {
			return nil, err
		}
	}
	if _, err := tx.Exec(ctx, `select public.check_request()`); err != nil {
		return nil, err
	}
	r.Body = http.MaxBytesReader(nil, r.Body, pcBodyLimit)
	out, err := fn(&request{Request: r, tenant: t, claims: claims, tx: tx, today: control.Today(s.Now())})
	if err != nil {
		return nil, err
	}
	return out, tx.Commit(ctx)
}

// readPC decodes a PC request body (unknown fields allowed: newer PCs may send more).
func readPC(r *request, v any) error {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		return fail(http.StatusBadRequest, "INVALID_INPUT", "The request body is not valid JSON: "+err.Error())
	}
	return nil
}

// columnsOf lists the JSON names of a wire struct: the columns it writes.
func columnsOf(row any) []string {
	t := reflect.TypeOf(row)
	cols := make([]string, 0, t.NumField())
	for i := 0; i < t.NumField(); i++ {
		if name, _, _ := strings.Cut(t.Field(i).Tag.Get("json"), ","); name != "" && name != "-" {
			cols = append(cols, name)
		}
	}
	return cols
}

// upsertRows inserts rows into table, updating the given columns of rows that
// already exist (conflict on conflictCols) — PostgREST's merge-duplicates —
// and returns the returning columns of every row written. Every row must be
// for this database's business.
func upsertRows[T any](r *request, table, conflictCols string, rows []T, returning ...string) ([]map[string]string, error) {
	if len(rows) == 0 {
		return nil, nil
	}
	var zero T
	cols := columnsOf(zero)
	raw, err := json.Marshal(rows)
	if err != nil {
		return nil, err
	}
	var foreign int
	if err := r.tx.QueryRow(r.Context(), `select count(*) from jsonb_populate_recordset(null::public.`+table+`, $1::jsonb) x
		where x.business_id is distinct from $2::uuid`, string(raw), r.tenant.BusinessID).Scan(&foreign); err != nil {
		return nil, err
	}
	if foreign > 0 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Rows must be for this business.")
	}
	conflict := map[string]bool{}
	for _, c := range strings.Split(conflictCols, ",") {
		conflict[c] = true
	}
	var set []string
	for _, c := range cols {
		if !conflict[c] {
			set = append(set, c+" = excluded."+c)
		}
	}
	list := strings.Join(cols, ", ")
	sql := `insert into public.` + table + ` (` + list + `) select ` + list +
		` from jsonb_populate_recordset(null::public.` + table + `, $1::jsonb) on conflict (` + conflictCols + `) do update set ` +
		strings.Join(set, ", ")
	if len(returning) == 0 {
		_, err := r.tx.Exec(r.Context(), sql, string(raw))
		return nil, err
	}
	casts := make([]string, len(returning))
	for i, c := range returning {
		casts[i] = c + "::text"
	}
	res, err := r.tx.Query(r.Context(), sql+` returning `+strings.Join(casts, ", "), string(raw))
	if err != nil {
		return nil, err
	}
	defer res.Close()
	var out []map[string]string
	for res.Next() {
		vals := make([]string, len(returning))
		ptrs := make([]any, len(returning))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := res.Scan(ptrs...); err != nil {
			return nil, err
		}
		m := make(map[string]string, len(returning))
		for i, c := range returning {
			m[c] = vals[i]
		}
		out = append(out, m)
	}
	return out, res.Err()
}

// idsBy maps key → id over upsert results.
func idsBy(rows []map[string]string, key string) wire.IDs {
	out := wire.IDs{IDs: make(map[string]string, len(rows))}
	for _, r := range rows {
		out.IDs[r[key]] = r["id"]
	}
	return out
}

func listRefs(r *request, table, keyColumn string) (any, error) {
	company := r.URL.Query().Get("company")
	if company == "" {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "company is required.")
	}
	rows, err := r.tx.Query(r.Context(), `select id::text, `+keyColumn+` from public.`+table+`
		where company_id = $1::uuid and deleted_at is null order by id`, company)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := wire.Refs{Refs: []wire.Ref{}}
	for rows.Next() {
		var ref wire.Ref
		if err := rows.Scan(&ref.ID, &ref.Key); err != nil {
			return nil, err
		}
		out.Refs = append(out.Refs, ref)
	}
	return out, rows.Err()
}

func softDelete(r *request, table string) (any, error) {
	var in wire.Delete
	if err := readPC(r, &in); err != nil {
		return nil, err
	}
	if len(in.IDs) == 0 {
		return ok(), nil
	}
	_, err := r.tx.Exec(r.Context(), `update public.`+table+` set deleted_at = now() where id = any($1::uuid[])`, in.IDs)
	return ok(), err
}

// ---------------------------------------------------------------- handlers

func (s *Server) pcAuthenticate(r *request) (any, error) {
	var in wire.Authenticate
	if err := readPC(r, &in); err != nil {
		return nil, err
	}
	var found bool
	if err := r.tx.QueryRow(r.Context(), `select exists(select 1 from public.businesses where id::text = $1)`, in.BusinessID).
		Scan(&found); err != nil {
		return nil, err
	}
	if !found || in.BusinessID != r.tenant.BusinessID {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "business "+in.BusinessID+" does not exist")
	}
	return ok(), nil
}

func upsertOne[T any](r *request, table, conflict string) (any, error) {
	var row T
	if err := readPC(r, &row); err != nil {
		return nil, err
	}
	out, err := upsertRows(r, table, conflict, []T{row}, "id")
	if err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return nil, errors.New(table + ": upsert returned no id")
	}
	return wire.ID{ID: out[0]["id"]}, nil
}

func upsertBatch[T any](r *request, table, conflict, key string) (any, error) {
	var in wire.Batch[T]
	if err := readPC(r, &in); err != nil {
		return nil, err
	}
	if key == "" {
		_, err := upsertRows(r, table, conflict, in.Rows)
		return ok(), err
	}
	out, err := upsertRows(r, table, conflict, in.Rows, "id", key)
	if err != nil {
		return nil, err
	}
	return idsBy(out, key), nil
}

func (s *Server) pcTransactionRefs(r *request) (any, error) {
	var in wire.TxnQuery
	if err := readPC(r, &in); err != nil {
		return nil, err
	}
	where, args := "company_id = $1::uuid and deleted_at is null", []any{in.CompanyID}
	if in.VoucherIDs != nil {
		where += " and tally_voucher_id = any($2::text[])"
		args = append(args, in.VoucherIDs)
	}
	rows, err := r.tx.Query(r.Context(), `select id::text, tally_voucher_id, tally_ledger_id from public.transactions
		where `+where+` order by id`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := wire.TxnRefs{Refs: []wire.TxnRef{}}
	for rows.Next() {
		var t wire.TxnRef
		if err := rows.Scan(&t.ID, &t.TallyVoucherID, &t.TallyLedgerID); err != nil {
			return nil, err
		}
		out.Refs = append(out.Refs, t)
	}
	return out, rows.Err()
}

func (s *Server) pcGetSyncState(r *request) (any, error) {
	q := r.URL.Query()
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select row_to_json(x) from (select business_id, company_id, entity_type, last_successful_sync_at,
			last_attempt_at, coalesce(last_cursor, '') as last_cursor, records_processed, status, coalesce(error_code, '') as error_code,
			coalesce(error_message, '') as error_message, updated_at
		from public.sync_state where company_id = $1::uuid and entity_type = $2) x`, q.Get("company"), q.Get("entity")).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return wire.SyncStateAnswer{}, nil
	} else if err != nil {
		return nil, err
	}
	var st wire.SyncState
	if err := json.Unmarshal(raw, &st); err != nil {
		return nil, err
	}
	return wire.SyncStateAnswer{State: &st}, nil
}

func (s *Server) pcPutSyncState(r *request) (any, error) {
	var st wire.SyncState
	if err := readPC(r, &st); err != nil {
		return nil, err
	}
	st.UpdatedAt = s.Now().UTC()
	_, err := upsertRows(r, "sync_state", "company_id,entity_type", []wire.SyncState{st})
	return ok(), err
}

func (s *Server) pcSyncLog(r *request) (any, error) {
	var l wire.SyncLog
	if err := readPC(r, &l); err != nil {
		return nil, err
	}
	raw, _ := json.Marshal([]wire.SyncLog{l})
	cols := strings.Join(columnsOf(l), ", ")
	_, err := r.tx.Exec(r.Context(), `insert into public.sync_logs (`+cols+`) select `+cols+`
		from jsonb_populate_recordset(null::public.sync_logs, $1::jsonb)`, string(raw))
	return ok(), err
}

// pcPurchases upserts bills and replaces their lines, all in this transaction.
func (s *Server) pcPurchases(r *request) (any, error) {
	var in wire.Purchases
	if err := readPC(r, &in); err != nil {
		return nil, err
	}
	if len(in.Bills) == 0 {
		return ok(), nil
	}
	bills := make([]wire.Purchase, len(in.Bills))
	for i, b := range in.Bills {
		bills[i] = b.Purchase
	}
	out, err := upsertRows(r, "purchases", "company_id,tally_voucher_id", bills, "id", "tally_voucher_id")
	if err != nil {
		return nil, err
	}
	ids := idsBy(out, "tally_voucher_id").IDs
	var purchaseIDs []string
	var lines []wire.PurchaseLine
	for _, b := range in.Bills {
		id := ids[b.Purchase.TallyVoucherID]
		if id == "" {
			return nil, fmt.Errorf("purchases: no id for voucher %s", b.Purchase.TallyVoucherID)
		}
		purchaseIDs = append(purchaseIDs, id)
		for _, l := range b.Lines {
			l.PurchaseID = id
			lines = append(lines, l)
		}
	}
	if _, err := r.tx.Exec(r.Context(), `delete from public.purchase_lines where purchase_id = any($1::uuid[])`, purchaseIDs); err != nil {
		return nil, err
	}
	for _, l := range lines {
		if l.BusinessID != r.tenant.BusinessID {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Rows must be for this business.")
		}
	}
	if len(lines) > 0 {
		raw, _ := json.Marshal(lines)
		cols := strings.Join(columnsOf(wire.PurchaseLine{}), ", ")
		if _, err := r.tx.Exec(r.Context(), `insert into public.purchase_lines (`+cols+`) select `+cols+`
			from jsonb_populate_recordset(null::public.purchase_lines, $1::jsonb)`, string(raw)); err != nil {
			return nil, err
		}
	}
	return ok(), nil
}

func (s *Server) pcRoutes(mux *http.ServeMux) {
	h := func(pattern string, fn func(*request) (any, error)) {
		mux.HandleFunc(pattern, s.handlePC(fn))
	}
	const p = "/b/{slug}/api/v1/pc/"
	h("POST "+p+"authenticate", s.pcAuthenticate)
	h("POST "+p+"connection", func(r *request) (any, error) {
		return upsertOne[wire.Connection](r, "tally_connections", "business_id,machine_identifier")
	})
	h("POST "+p+"company", func(r *request) (any, error) {
		return upsertOne[wire.Company](r, "tally_companies", "business_id,tally_company_id")
	})
	h("POST "+p+"shops", func(r *request) (any, error) {
		return upsertBatch[wire.Shop](r, "shops", "company_id,tally_ledger_id", "tally_ledger_id")
	})
	h("GET "+p+"shops", func(r *request) (any, error) { return listRefs(r, "shops", "tally_ledger_id") })
	h("POST "+p+"shops/delete", func(r *request) (any, error) { return softDelete(r, "shops") })
	h("POST "+p+"transactions", func(r *request) (any, error) {
		return upsertBatch[wire.Transaction](r, "transactions", "company_id,tally_voucher_id,tally_ledger_id", "")
	})
	h("POST "+p+"transactions/refs", s.pcTransactionRefs)
	h("POST "+p+"transactions/delete", func(r *request) (any, error) { return softDelete(r, "transactions") })
	h("GET "+p+"sync-state", s.pcGetSyncState)
	h("PUT "+p+"sync-state", s.pcPutSyncState)
	h("POST "+p+"sync-logs", s.pcSyncLog)
	h("POST "+p+"suppliers", func(r *request) (any, error) {
		return upsertBatch[wire.Supplier](r, "suppliers", "company_id,tally_ledger_id", "tally_ledger_id")
	})
	h("GET "+p+"suppliers", func(r *request) (any, error) { return listRefs(r, "suppliers", "tally_ledger_id") })
	h("POST "+p+"suppliers/delete", func(r *request) (any, error) { return softDelete(r, "suppliers") })
	h("POST "+p+"stock-items", func(r *request) (any, error) {
		return upsertBatch[wire.StockItem](r, "stock_items", "company_id,tally_item_id", "tally_item_id")
	})
	h("GET "+p+"stock-items", func(r *request) (any, error) { return listRefs(r, "stock_items", "tally_item_id") })
	h("POST "+p+"stock-items/delete", func(r *request) (any, error) { return softDelete(r, "stock_items") })
	h("POST "+p+"purchases", s.pcPurchases)
	h("GET "+p+"purchases", func(r *request) (any, error) { return listRefs(r, "purchases", "tally_voucher_id") })
	h("POST "+p+"purchases/delete", func(r *request) (any, error) { return softDelete(r, "purchases") })
}
