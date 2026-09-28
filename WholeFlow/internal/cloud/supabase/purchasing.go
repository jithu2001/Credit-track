package supabase

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"wholeflow/internal/cloud"
)

// Suppliers, stock items and purchases (migration 0003_purchasing.sql).

type supplierRow struct {
	BusinessID    string    `json:"business_id"`
	CompanyID     string    `json:"company_id"`
	TallyLedgerID string    `json:"tally_ledger_id"`
	TallyMasterID int       `json:"tally_master_id"`
	TallyAlterID  int64     `json:"tally_alter_id"`
	Name          string    `json:"name"`
	Aliases       []string  `json:"aliases"`
	LedgerGroup   string    `json:"ledger_group"`
	Phone         string    `json:"phone"`
	Phones        []string  `json:"phones"`
	ContactPerson string    `json:"contact_person"`
	Email         string    `json:"email"`
	GSTIN         string    `json:"gstin"`
	GSTRegType    string    `json:"gst_registration_type"`
	Address       string    `json:"address"`
	AddressLines  []string  `json:"address_lines"`
	State         string    `json:"state"`
	Pincode       string    `json:"pincode"`
	Country       string    `json:"country"`
	OpeningAmount float64   `json:"opening_balance_amount"`
	OpeningType   string    `json:"opening_balance_type"`
	BalanceAmount float64   `json:"balance_amount"`
	BalanceType   string    `json:"balance_type"`
	Payable       float64   `json:"payable"`
	SyncedAt      time.Time `json:"synced_at"`
	DeletedAt     *string   `json:"deleted_at"`
}

type stockItemRow struct {
	BusinessID    string    `json:"business_id"`
	CompanyID     string    `json:"company_id"`
	TallyItemID   string    `json:"tally_item_id"`
	Name          string    `json:"name"`
	Aliases       []string  `json:"aliases"`
	StockGroup    string    `json:"stock_group"`
	Category      string    `json:"category"`
	Unit          string    `json:"unit"`
	GSTApplicable bool      `json:"gst_applicable"`
	OpeningQty    float64   `json:"opening_qty"`
	OpeningValue  float64   `json:"opening_value"`
	ClosingQty    float64   `json:"closing_qty"`
	ClosingRate   float64   `json:"closing_rate"`
	ClosingValue  float64   `json:"closing_value"`
	ReorderLevel  float64   `json:"reorder_level"`
	MinOrderQty   float64   `json:"min_order_qty"`
	StockStatus   string    `json:"stock_status"`
	SyncedAt      time.Time `json:"synced_at"`
	DeletedAt     *string   `json:"deleted_at"`
}

type purchaseRow struct {
	BusinessID     string                      `json:"business_id"`
	CompanyID      string                      `json:"company_id"`
	TallyVoucherID string                      `json:"tally_voucher_id"`
	TallyAlterID   int64                       `json:"tally_alter_id"`
	SupplierID     *string                     `json:"supplier_id"`
	SupplierName   string                      `json:"supplier_name"`
	PurchaseDate   string                      `json:"purchase_date"`
	VoucherNumber  string                      `json:"voucher_number"`
	VoucherType    string                      `json:"voucher_type"`
	Reference      string                      `json:"supplier_bill_number"`
	Narration      string                      `json:"narration"`
	Taxable        float64                     `json:"taxable_amount"`
	Other          float64                     `json:"tax_and_other_amount"`
	Total          float64                     `json:"total_amount"`
	Qty            float64                     `json:"total_qty"`
	LineCount      int                         `json:"line_count"`
	LedgerEntries  []cloud.PurchaseLedgerEntry `json:"ledger_entries"`
	SyncedAt       time.Time                   `json:"synced_at"`
	DeletedAt      *string                     `json:"deleted_at"`
}

type purchaseLineRow struct {
	BusinessID  string  `json:"business_id"`
	CompanyID   string  `json:"company_id"`
	PurchaseID  string  `json:"purchase_id"`
	LineNo      int     `json:"line_no"`
	StockItemID *string `json:"stock_item_id"`
	ItemName    string  `json:"item_name"`
	Godown      string  `json:"godown"`
	Qty         float64 `json:"qty"`
	ActualQty   float64 `json:"actual_qty"`
	Unit        string  `json:"unit"`
	Rate        float64 `json:"rate"`
	Discount    float64 `json:"discount_percent"`
	Amount      float64 `json:"amount"`
}

func (s *Storage) UpsertSuppliers(ctx context.Context, sups []cloud.Supplier) (map[string]string, error) {
	ids := make(map[string]string, len(sups))
	for _, batch := range chunk(sups, s.c.batch) {
		rows := make([]supplierRow, 0, len(batch))
		for _, x := range batch {
			rows = append(rows, supplierRow{
				BusinessID: x.BusinessID, CompanyID: x.CompanyID, TallyLedgerID: x.TallyLedgerID, TallyMasterID: x.TallyMasterID,
				TallyAlterID: x.TallyAlterID, Name: x.Name, Aliases: nonNil(x.Aliases), LedgerGroup: x.Group, Phone: x.Phone,
				Phones: nonNil(x.Phones), ContactPerson: x.ContactPerson, Email: x.Email, GSTIN: x.GSTIN, GSTRegType: x.GSTRegType,
				Address: strings.Join(x.Address, "\n"), AddressLines: nonNil(x.Address), State: x.State, Pincode: x.Pincode,
				Country: x.Country, OpeningAmount: x.OpeningAmount, OpeningType: x.OpeningType, BalanceAmount: x.BalanceAmount,
				BalanceType: x.BalanceType, Payable: x.Payable, SyncedAt: x.SyncedAt.UTC(),
			})
		}
		if err := s.upsertIDs(ctx, "upsert-suppliers", "suppliers", "company_id,tally_ledger_id", "tally_ledger_id", rows, ids); err != nil {
			return nil, err
		}
	}
	return ids, nil
}

func (s *Storage) ListSuppliers(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.listRefs(ctx, "list-suppliers", "suppliers", "tally_ledger_id", companyID)
}

func (s *Storage) SoftDeleteSuppliers(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-suppliers", "suppliers", ids)
}

func (s *Storage) UpsertStockItems(ctx context.Context, items []cloud.StockItem) (map[string]string, error) {
	ids := make(map[string]string, len(items))
	for _, batch := range chunk(items, s.c.batch) {
		rows := make([]stockItemRow, 0, len(batch))
		for _, x := range batch {
			rows = append(rows, stockItemRow{
				BusinessID: x.BusinessID, CompanyID: x.CompanyID, TallyItemID: x.TallyItemID, Name: x.Name, Aliases: nonNil(x.Aliases),
				StockGroup: x.Group, Category: x.Category, Unit: x.Unit, GSTApplicable: x.GST, OpeningQty: x.OpeningQty,
				OpeningValue: x.OpeningValue, ClosingQty: x.ClosingQty, ClosingRate: x.ClosingRate, ClosingValue: x.ClosingValue,
				ReorderLevel: x.ReorderLevel, MinOrderQty: x.MinOrderQty, StockStatus: x.Status, SyncedAt: x.SyncedAt.UTC(),
			})
		}
		if err := s.upsertIDs(ctx, "upsert-stock-items", "stock_items", "company_id,tally_item_id", "tally_item_id", rows, ids); err != nil {
			return nil, err
		}
	}
	return ids, nil
}

func (s *Storage) ListStockItems(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.listRefs(ctx, "list-stock-items", "stock_items", "tally_item_id", companyID)
}

func (s *Storage) SoftDeleteStockItems(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-stock-items", "stock_items", ids)
}

// UpsertPurchases writes bills in batches, then replaces the lines of each
// batch: delete the old lines of those bills, insert the new ones. Lines are
// derived data (a bill's items), so they are replaced rather than soft-deleted.
func (s *Storage) UpsertPurchases(ctx context.Context, ps []cloud.Purchase) error {
	for _, batch := range chunk(ps, 200) {
		rows := make([]purchaseRow, 0, len(batch))
		for _, p := range batch {
			le := p.LedgerEntries
			if le == nil {
				le = []cloud.PurchaseLedgerEntry{}
			}
			rows = append(rows, purchaseRow{
				BusinessID: p.BusinessID, CompanyID: p.CompanyID, TallyVoucherID: p.TallyVoucherID, TallyAlterID: p.TallyAlterID,
				SupplierID: nullable(p.SupplierID), SupplierName: p.SupplierName, PurchaseDate: p.Date, VoucherNumber: p.VoucherNumber,
				VoucherType: p.VoucherType, Reference: p.Reference, Narration: p.Narration, Taxable: p.Taxable, Other: p.Other,
				Total: p.Total, Qty: p.Qty, LineCount: len(p.Lines), LedgerEntries: le, SyncedAt: p.SyncedAt.UTC(),
			})
		}
		ids := map[string]string{}
		if err := s.upsertIDs(ctx, "upsert-purchases", "purchases", "company_id,tally_voucher_id", "tally_voucher_id", rows, ids); err != nil {
			return err
		}
		purchaseIDs := make([]string, 0, len(ids))
		var lines []purchaseLineRow
		for _, p := range batch {
			id := ids[p.TallyVoucherID]
			if id == "" {
				return &cloud.Error{Kind: cloud.KindError, Op: "upsert-purchases", Msg: "no id returned for voucher " + p.TallyVoucherID}
			}
			purchaseIDs = append(purchaseIDs, id)
			for _, l := range p.Lines {
				lines = append(lines, purchaseLineRow{BusinessID: p.BusinessID, CompanyID: p.CompanyID, PurchaseID: id, LineNo: l.LineNo,
					StockItemID: nullable(l.StockItemID), ItemName: l.ItemName, Godown: l.Godown, Qty: l.Qty, ActualQty: l.ActualQty,
					Unit: l.Unit, Rate: l.Rate, Discount: l.Discount, Amount: l.Amount})
			}
		}
		q := url.Values{"purchase_id": {inList(purchaseIDs)}}
		if _, _, err := s.c.do(ctx, "replace-purchase-lines", http.MethodDelete, "purchase_lines", q, "return=minimal", "", nil); err != nil {
			return err
		}
		for _, lb := range chunk(lines, s.c.batch) {
			if _, _, err := s.c.do(ctx, "insert-purchase-lines", http.MethodPost, "purchase_lines", nil, "return=minimal", "", lb); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Storage) ListPurchases(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.listRefs(ctx, "list-purchases", "purchases", "tally_voucher_id", companyID)
}

func (s *Storage) SoftDeletePurchases(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-purchases", "purchases", ids)
}

// upsertIDs upserts rows and adds keyColumn → id for every returned row to ids.
func (s *Storage) upsertIDs(ctx context.Context, op, table, onConflict, keyColumn string, rows any, ids map[string]string) error {
	raw, err := s.c.upsert(ctx, op, table, onConflict, rows, "id,"+keyColumn)
	if err != nil {
		return err
	}
	var out []map[string]string
	if err := json.Unmarshal(raw, &out); err != nil {
		return &cloud.Error{Kind: cloud.KindError, Op: op, Msg: "unexpected response", Err: err}
	}
	for _, r := range out {
		ids[r[keyColumn]] = r["id"]
	}
	return nil
}

// listRefs pages through the active rows of a company table.
func (s *Storage) listRefs(ctx context.Context, op, table, keyColumn, companyID string) ([]cloud.Ref, error) {
	q := url.Values{"company_id": {"eq." + companyID}, "deleted_at": {"is.null"}, "select": {"id," + keyColumn}, "order": {"id"}}
	var out []cloud.Ref
	err := s.c.selectAll(ctx, op, table, q, func(raw []byte) (int, error) {
		var rows []map[string]string
		if err := json.Unmarshal(raw, &rows); err != nil {
			return 0, err
		}
		for _, r := range rows {
			out = append(out, cloud.Ref{ID: r["id"], Key: r[keyColumn]})
		}
		return len(rows), nil
	})
	return out, err
}

var _ cloud.PurchasingProvider = (*Storage)(nil)
