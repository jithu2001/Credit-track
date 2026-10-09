package appapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

// Stock (owner: with cost and last purchase; staff: quantities only, for the
// companies they are assigned to):
//
//	GET /b/{slug}/api/v1/stock?company=<id>          every item, the summary and the stock alert
//	GET /b/{slug}/api/v1/stock/{id}                  one item
//	GET /b/{slug}/api/v1/stock/{id}/purchases        its latest purchase bills (owner)
//	PUT /b/{slug}/api/v1/stock/minimum               {"company", "items": [...], "min": n|null} (owner)
//
// Each item carries min_qty (the owner's), effective_min, status,
// at_or_below_minimum and shortfall, worked out here.

type stockRow struct {
	item             StockItem
	aliases          []string
	group, unit      *string
	closingRate      *int64
	lastPurchaseDate *time.Time
	lastPurchaseRate *int64
	lastSupplier     *string
	withCosts        bool
}

func (s stockRow) json() map[string]any {
	i := s.item
	aliases := s.aliases
	if aliases == nil {
		aliases = []string{}
	}
	out := map[string]any{
		"stock_item_id": i.ID, "name": i.Name, "aliases": aliases, "stock_group": s.group, "unit": s.unit,
		"closing_qty": i.ClosingQty, "reorder_level": i.ReorderLevel, "synced_at": optTime(i.SyncedAt),
		"min_qty": i.MinQty, "effective_min": i.EffectiveMin(), "status": i.Status(),
		"at_or_below_minimum": i.AtOrBelowMinimum(), "shortfall": i.Shortfall(),
	}
	if s.withCosts {
		var lastDate any
		if s.lastPurchaseDate != nil {
			lastDate = date(*s.lastPurchaseDate)
		}
		out["closing_rate"] = optMoney(s.closingRate)
		out["closing_value"] = optMoney(i.ClosingValue)
		out["last_purchase_date"] = lastDate
		out["last_purchase_rate"] = optMoney(s.lastPurchaseRate)
		out["last_supplier"] = s.lastSupplier
	}
	return out
}

func isOwner(r *request) (bool, error) {
	var owner bool
	err := r.tx.QueryRow(r.Context(), `select coalesce(public.is_owner(), false)`).Scan(&owner)
	return owner, err
}

// stockQuery selects items as stockRow columns: owners from v_stock_items
// (cost, last purchase), staff from stock_items (quantities only).
func stockQuery(owner bool, where string) string {
	if owner {
		return `select v.stock_item_id::text, v.name, v.aliases, v.stock_group, v.unit, coalesce(v.closing_qty, 0)::float8,
				coalesce(v.reorder_level, 0)::float8, m.min_qty::float8, round(v.closing_value * 100)::bigint, v.synced_at,
				round(v.closing_rate * 100)::bigint, v.last_purchase_date, round(v.last_purchase_rate * 100)::bigint, v.last_supplier
			from public.v_stock_items v left join public.stock_minimums m on m.stock_item_id = v.stock_item_id
			where ` + where + ` order by v.name, v.stock_item_id`
	}
	return `select i.id::text, i.name, i.aliases, i.stock_group, i.unit, coalesce(i.closing_qty, 0)::float8,
			coalesce(i.reorder_level, 0)::float8, m.min_qty::float8, null::bigint, i.synced_at,
			null::bigint, null::date, null::bigint, null::text
		from public.stock_items i left join public.stock_minimums m on m.stock_item_id = i.id
		where i.deleted_at is null and ` + where + ` order by i.name, i.id`
}

func scanStock(rows pgx.Rows, owner bool) ([]stockRow, error) {
	defer rows.Close()
	var out []stockRow
	for rows.Next() {
		s := stockRow{withCosts: owner}
		if err := rows.Scan(&s.item.ID, &s.item.Name, &s.aliases, &s.group, &s.unit, &s.item.ClosingQty, &s.item.ReorderLevel,
			&s.item.MinQty, &s.item.ClosingValue, &s.item.SyncedAt, &s.closingRate, &s.lastPurchaseDate, &s.lastPurchaseRate,
			&s.lastSupplier); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func (s *Server) stockList(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	if _, err := companyName(r, companyID); err != nil {
		return nil, err
	}
	owner, err := isOwner(r)
	if err != nil {
		return nil, err
	}
	col := "i.company_id"
	if owner {
		col = "v.company_id"
	}
	rows, err := r.tx.Query(r.Context(), stockQuery(owner, col+" = $1::uuid"), companyID)
	if err != nil {
		return nil, err
	}
	list, err := scanStock(rows, owner)
	if err != nil {
		return nil, err
	}
	items := make([]StockItem, len(list))
	out := make([]map[string]any, len(list))
	for i, s := range list {
		items[i] = s.item
		out[i] = s.json()
	}
	sum := SummariseStock(items)
	byStatus := map[string]int{}
	for k, v := range sum.ByStatus {
		byStatus[string(k)] = v
	}
	alerts := []string{}
	for _, a := range StockAlerts(items) {
		alerts = append(alerts, a.ID)
	}
	return map[string]any{
		"items": out,
		"summary": map[string]any{"items": sum.Items, "value": money(sum.Value), "by_status": byStatus,
			"synced_at": optTime(sum.SyncedAt)},
		"alerts": alerts,
	}, nil
}

func (s *Server) stockItem(r *request) (any, error) {
	owner, err := isOwner(r)
	if err != nil {
		return nil, err
	}
	col := "i.id"
	if owner {
		col = "v.stock_item_id"
	}
	rows, err := r.tx.Query(r.Context(), stockQuery(owner, col+" = $1::uuid"), r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	list, err := scanStock(rows, owner)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "This item is not available.")
	}
	return list[0].json(), nil
}

const itemPurchasesLimit = 20

func (s *Server) stockItemPurchases(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select coalesce(json_agg(b order by b.purchase_date desc, b.tally_alter_id desc), '[]')
		from (select p.id, p.purchase_date, p.supplier_name, p.voucher_number, p.tally_alter_id,
				(select json_agg(json_build_object('qty', l.qty, 'unit', l.unit, 'rate', l.rate, 'amount', l.amount) order by l.line_no)
				   from public.purchase_lines l where l.purchase_id = p.id and l.stock_item_id = $1::uuid) as purchase_lines
			from public.purchases p
			where p.deleted_at is null
			  and exists (select 1 from public.purchase_lines l where l.purchase_id = p.id and l.stock_item_id = $1::uuid)
			order by p.purchase_date desc, p.tally_alter_id desc limit $2) b`, r.PathValue("id"), itemPurchasesLimit).Scan(&raw)
	if err != nil {
		return nil, err
	}
	return map[string]any{"purchases": json.RawMessage(raw)}, nil
}

func (s *Server) setStockMinimum(r *request) (any, error) {
	var in struct {
		Company string   `json:"company"`
		Items   []string `json:"items"`
		Min     *float64 `json:"min"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	if in.Company == "" || len(in.Items) == 0 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Choose at least one item.")
	}
	// set_stock_minimum() checks the owner, the items and the value.
	var changed int
	err := r.tx.QueryRow(r.Context(), `select public.set_stock_minimum($1::uuid, $2::uuid[], $3)`, in.Company, in.Items, in.Min).
		Scan(&changed)
	if err != nil {
		var ae *apiError
		if errors.As(toAPIError(err), &ae) && ae.Status == http.StatusForbidden {
			return nil, fail(http.StatusForbidden, "NOT_OWNER", "Only the owner can set minimum stock.")
		}
		return nil, err
	}
	return map[string]any{"changed": changed}, nil
}
