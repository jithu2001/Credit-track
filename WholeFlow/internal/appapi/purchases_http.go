package appapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Purchases and suppliers (owner only):
//
//	GET /b/{slug}/api/v1/purchases?company=<id>[&supplier=<id>][&q=][&page=0]   pages of 50 bills, newest first
//	GET /b/{slug}/api/v1/purchases/{id}                                         one bill with lines and ledger entries
//	GET /b/{slug}/api/v1/purchases/months?company=<id>&from=YYYY-MM-DD[&supplier=<id>]
//	GET /b/{slug}/api/v1/suppliers?company=<id>                                 every active supplier
//	GET /b/{slug}/api/v1/suppliers/{id}
//
// Rows have the same fields as the tables.

const purchasePageSize = 50

const purchaseSummaryColumns = `p.id, p.purchase_date, p.supplier_id, p.supplier_name, p.voucher_number, p.voucher_type,
	p.supplier_bill_number, p.taxable_amount, p.total_amount, p.line_count`

func (s *Server) purchasesPage(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	if page < 0 || page > 10000 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "page is out of range.")
	}
	where := []string{"p.company_id = $1::uuid", "p.deleted_at is null"}
	args := []any{companyID}
	if v := q.Get("supplier"); v != "" {
		args = append(args, v)
		where = append(where, "p.supplier_id = $"+strconv.Itoa(len(args))+"::uuid")
	}
	if v := strings.TrimSpace(q.Get("q")); v != "" {
		args = append(args, likePattern(v))
		n := "$" + strconv.Itoa(len(args))
		where = append(where, "(p.supplier_name ilike "+n+" or p.voucher_number ilike "+n+" or p.supplier_bill_number ilike "+n+")")
	}
	var raw []byte
	err = r.tx.QueryRow(r.Context(), `select coalesce(json_agg(b), '[]') from (select `+purchaseSummaryColumns+`
		from public.purchases p where `+strings.Join(where, " and ")+`
		order by p.purchase_date desc, p.tally_alter_id desc, p.id
		limit `+strconv.Itoa(purchasePageSize)+` offset `+strconv.Itoa(page*purchasePageSize)+`) b`, args...).Scan(&raw)
	if err != nil {
		return nil, err
	}
	var n []json.RawMessage
	_ = json.Unmarshal(raw, &n)
	return map[string]any{"purchases": json.RawMessage(raw), "page": page, "page_size": purchasePageSize,
		"has_more": len(n) == purchasePageSize}, nil
}

func (s *Server) purchaseDetail(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select row_to_json(b) from (select `+purchaseSummaryColumns+`,
			p.narration, p.tax_and_other_amount, p.total_qty, p.ledger_entries, p.synced_at,
			(select coalesce(json_agg(json_build_object('line_no', l.line_no, 'stock_item_id', l.stock_item_id,
				'item_name', l.item_name, 'godown', l.godown, 'qty', l.qty, 'actual_qty', l.actual_qty, 'unit', l.unit,
				'rate', l.rate, 'discount_percent', l.discount_percent, 'amount', l.amount) order by l.line_no), '[]')
			 from public.purchase_lines l where l.purchase_id = p.id) as purchase_lines
		from public.purchases p where p.id = $1::uuid and p.deleted_at is null) b`, r.PathValue("id")).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "This purchase bill is not available.")
	} else if err != nil {
		return nil, err
	}
	return json.RawMessage(raw), nil
}

// purchaseMonths totals bills per month (newest first) since from, for the
// company or one supplier.
func (s *Server) purchaseMonths(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	from, err := optDate(r, "from")
	if err != nil {
		return nil, err
	}
	if from == nil {
		f := time.Date(r.today.Year()-1, r.today.Month(), 1, 0, 0, 0, 0, time.UTC)
		from = &f
	}
	args := []any{companyID, *from}
	where := "company_id = $1::uuid and month >= $2"
	if v := r.URL.Query().Get("supplier"); v != "" {
		args = append(args, v)
		where += " and supplier_id = $3::uuid"
	}
	var raw []byte
	err = r.tx.QueryRow(r.Context(), `select coalesce(json_agg(m order by m.month desc), '[]') from (
			select month, sum(bills)::int as bills, sum(total_amount) as total_amount
			from public.v_purchases_by_supplier_month where `+where+` group by month) m`, args...).Scan(&raw)
	if err != nil {
		return nil, err
	}
	return map[string]any{"months": json.RawMessage(raw)}, nil
}

const supplierColumns = `id, company_id, name, aliases, ledger_group, phone, phones, contact_person, email, gstin, address,
	address_lines, state, pincode, opening_balance_amount, opening_balance_type, payable, synced_at`

func (s *Server) suppliersList(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	var raw []byte
	err = r.tx.QueryRow(r.Context(), `select coalesce(json_agg(b order by b.name, b.id), '[]') from (select `+supplierColumns+`
		from public.suppliers where company_id = $1::uuid and deleted_at is null) b`, companyID).Scan(&raw)
	if err != nil {
		return nil, err
	}
	return map[string]any{"suppliers": json.RawMessage(raw)}, nil
}

func (s *Server) supplierDetail(r *request) (any, error) {
	if err := requireOwner(r); err != nil {
		return nil, err
	}
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select row_to_json(b) from (select `+supplierColumns+`
		from public.suppliers where id = $1::uuid and deleted_at is null) b`, r.PathValue("id")).Scan(&raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "This supplier is not available.")
	} else if err != nil {
		return nil, err
	}
	return json.RawMessage(raw), nil
}
