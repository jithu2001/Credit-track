package api

import (
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"wholeflow/internal/export"
	"wholeflow/internal/tally"
)

// handleExport serves /api/export/{report}?format=csv|xlsx with the same
// filter parameters as the matching list endpoint:
//
//	customers, outstanding           → /api/customers, /api/reports/outstanding
//	suppliers                        → /api/suppliers
//	purchases, purchase-lines        → /api/purchases (one row per bill / per item line)
//	purchase-items                   → /api/purchases/items
//	inventory                        → /api/inventory
func (s *Server) handleExport(w http.ResponseWriter, r *http.Request) {
	report := r.PathValue("report")
	format := strings.ToLower(r.URL.Query().Get("format"))
	if format == "" {
		format = "csv"
	}
	if format != "csv" && format != "xlsx" {
		writeErr(w, http.StatusBadRequest, "BAD_FORMAT", "format must be csv or xlsx", "")
		return
	}

	var (
		t         export.Table
		company   string
		fetchedAt time.Time
		err       error
	)
	switch report {
	case "outstanding", "customers":
		t, company, fetchedAt, err = s.exportShops(r, report)
	case "suppliers":
		t, company, fetchedAt, err = s.exportSuppliers(r)
	case "purchases", "purchase-lines", "purchase-items":
		t, company, fetchedAt, err = s.exportPurchases(r, report)
	case "inventory":
		t, company, fetchedAt, err = s.exportInventory(r)
	default:
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "Unknown report.", "")
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}
	t.Title = fmt.Sprintf("%s - %s - data from Tally as of %s", t.Sheet, company, fetchedAt.Format("02-Jan-2006 15:04"))

	name := fmt.Sprintf("%s_%s_%s.%s", report, safeName(company), time.Now().Format("20060102-1504"), format)
	w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
	w.Header().Set("Cache-Control", "no-store")
	if format == "csv" {
		w.Header().Set("Content-Type", "text/csv; charset=utf-8")
		err = export.WriteCSV(w, t)
	} else {
		w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
		err = export.WriteXLSX(w, t)
	}
	if err != nil {
		s.log.Error("export failed", "report", report, "format", format, "error", err.Error())
	}
	s.log.Info("export served", "report", report, "format", format, "rows", len(t.Rows))
}

func (s *Server) exportShops(r *http.Request, report string) (export.Table, string, time.Time, error) {
	snap, err := s.snapshot(r, false)
	if err != nil {
		return export.Table{}, "", time.Time{}, err
	}
	var t export.Table
	if report == "outstanding" {
		q := parseQuery(r, "balance_desc")
		q.typ = "dr"
		list := filterCustomers(snap.Customers, q)
		t = export.Table{Sheet: "Outstanding", Headers: []string{"Shop", "Area", "Phone", "Outstanding (Rs)"}}
		var total tally.Amount
		for _, c := range list {
			t.Rows = append(t.Rows, []any{c.Name, c.Area, strings.Join(c.Phones, " / "), c.Balance.Amount})
			total += c.ClosingSigned
		}
		t.Rows = append(t.Rows, []any{"TOTAL", "", "", total.Rupees()})
	} else {
		list := filterCustomers(snap.Customers, parseQuery(r, "name_asc"))
		t = partyTable("Shops", "Shop", list)
	}
	return t, snap.Company.Name, snap.FetchedAt, nil
}

func partyTable(sheet, what string, list []tally.Customer) export.Table {
	t := export.Table{Sheet: sheet, Headers: []string{what, "Group", "Area", "Phone", "GSTIN", "State", "Pincode",
		"Opening Balance (Rs)", "Opening Dr/Cr", "Current Balance (Rs)", "Dr/Cr"}}
	for _, c := range list {
		t.Rows = append(t.Rows, []any{c.Name, c.Group, c.Area, strings.Join(c.Phones, " / "), c.GSTIN, c.State, c.Pincode,
			c.OpeningBalance.Amount, drcr(c.OpeningBalance.Type), c.Balance.Amount, drcr(c.Balance.Type)})
	}
	return t
}

func (s *Server) exportSuppliers(r *http.Request) (export.Table, string, time.Time, error) {
	c, err := s.suppliers(r)
	if err != nil {
		return export.Table{}, "", time.Time{}, err
	}
	t := partyTable("Suppliers", "Supplier", filterSuppliers(c.Data, parseQuery(r, "name_asc")))
	return t, c.Company.Name, c.FetchedAt, nil
}

func (s *Server) exportPurchases(r *http.Request, report string) (export.Table, string, time.Time, error) {
	c, err := s.purchases(r)
	if err != nil {
		return export.Table{}, "", time.Time{}, err
	}
	q := parsePurchaseQuery(r)
	var t export.Table
	switch report {
	case "purchases":
		list := filterPurchases(c.Data.Purchases, q)
		t = export.Table{Sheet: "Purchases", Headers: []string{"Date", "Voucher type", "Voucher no.", "Supplier bill no.", "Supplier",
			"Items", "Qty", "Taxable (Rs)", "Tax & other (Rs)", "Bill total (Rs)", "Narration"}}
		var tot purchaseTotals
		for _, p := range list {
			t.Rows = append(t.Rows, []any{p.Date, p.VoucherType, p.Number, p.Reference, p.Supplier, len(p.Lines), p.Qty,
				p.Taxable, p.Other, p.Total, p.Narration})
			tot.add(p)
		}
		tot.done()
		t.Rows = append(t.Rows, []any{"TOTAL", "", "", "", fmt.Sprintf("%d bills", tot.Bills), "", tot.Qty, tot.Taxable, tot.Other, tot.Total, ""})
	case "purchase-lines":
		list := filterPurchases(c.Data.Purchases, q)
		t = export.Table{Sheet: "Purchase lines", Headers: []string{"Date", "Voucher no.", "Supplier bill no.", "Supplier", "Item",
			"Godown", "Qty", "Unit", "Rate (Rs)", "Discount %", "Amount (Rs)"}}
		for _, p := range list {
			for _, l := range p.Lines {
				t.Rows = append(t.Rows, []any{p.Date, p.Number, p.Reference, p.Supplier, l.Item, l.Godown, l.Qty, l.Unit,
					l.Rate, l.Discount, l.Amount})
			}
		}
	default: // purchase-items
		text := q.q
		q.q = ""
		items := aggregateItems(filterPurchases(c.Data.Purchases, q), text)
		t = export.Table{Sheet: "Purchases by item", Headers: []string{"Item", "Unit", "Qty", "Amount (Rs)", "Average rate (Rs)",
			"Bills", "Last purchased", "Last rate (Rs)"}}
		for _, it := range items {
			t.Rows = append(t.Rows, []any{it.Item, it.Unit, it.Qty, it.Amount, it.AvgRate, it.Bills, it.LastDate, it.LastRate})
		}
	}
	return t, c.Company.Name, c.FetchedAt, nil
}

func (s *Server) exportInventory(r *http.Request) (export.Table, string, time.Time, error) {
	c, err := s.stock(r)
	if err != nil {
		return export.Table{}, "", time.Time{}, err
	}
	list := filterStock(c.Data, parseStockQuery(r))
	t := export.Table{Sheet: "Inventory", Headers: []string{"Item", "Part no. / alias", "Stock group", "Unit", "Opening qty",
		"Closing qty", "Rate (Rs)", "Closing value (Rs)", "Reorder level", "Status"}}
	var value tally.Amount
	for _, it := range list {
		t.Rows = append(t.Rows, []any{it.Name, strings.Join(it.Aliases, " / "), it.Group, it.Unit, it.OpeningQty,
			it.ClosingQty, it.ClosingRate, it.ClosingValue, it.ReorderLevel, stockStatusLabel(it.Status)})
		value += rupeesToPaise(it.ClosingValue)
	}
	t.Rows = append(t.Rows, []any{"TOTAL", "", fmt.Sprintf("%d items", len(list)), "", "", "", "", float64(value) / 100, "", ""})
	return t, c.Company.Name, c.FetchedAt, nil
}

func stockStatusLabel(s string) string {
	switch s {
	case "in_stock":
		return "In stock"
	case "low":
		return "Low (at/below reorder level)"
	case "zero":
		return "Out of stock"
	case "negative":
		return "Negative stock"
	}
	return s
}

func drcr(t string) string {
	switch t {
	case "DR":
		return "Dr"
	case "CR":
		return "Cr"
	}
	return ""
}

var unsafeRe = regexp.MustCompile(`[^A-Za-z0-9]+`)

func safeName(s string) string { return strings.Trim(unsafeRe.ReplaceAllString(s, "-"), "-") }
