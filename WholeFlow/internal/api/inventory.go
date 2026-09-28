package api

import (
	"context"
	"net/http"
	"sort"
	"strings"
	"time"

	"wholeflow/internal/tally"
)

// Suppliers, purchases and stock items are cached per company like the shop
// list: pulled from Tally on first use, replaced by "Refresh from Tally".

type cached[T any] struct {
	Company    tally.Company
	Data       T
	FetchedAt  time.Time
	DurationMs int64
}

type caches struct {
	suppliers map[string]*cached[[]tally.Customer]
	purchases map[string]*cached[*tally.PurchaseList]
	stock     map[string]*cached[[]tally.StockItem]
}

func newCaches() caches {
	return caches{
		suppliers: map[string]*cached[[]tally.Customer]{},
		purchases: map[string]*cached[*tally.PurchaseList]{},
		stock:     map[string]*cached[[]tally.StockItem]{},
	}
}

// load returns the cached value for the requested company, fetching it from
// Tally when missing. Loads are serialised with the shop snapshot (Tally
// answers one request at a time anyway).
func load[T any](s *Server, r *http.Request, what string, store map[string]*cached[T],
	fetch func(ctx context.Context, c *tally.Company) (T, error)) (*cached[T], error) {
	if name := s.companyParam(r); name != "" {
		s.mu.Lock()
		c := store[strings.ToLower(name)]
		s.mu.Unlock()
		if c != nil {
			return c, nil
		}
	}
	s.loadMu.Lock()
	defer s.loadMu.Unlock()
	company, err := s.resolveCompany(r)
	if err != nil {
		return nil, err
	}
	key := strings.ToLower(company.Name)
	s.mu.Lock()
	c := store[key]
	s.mu.Unlock()
	if c != nil {
		return c, nil
	}
	start := time.Now()
	data, err := fetch(r.Context(), company)
	if err != nil {
		return nil, err
	}
	c = &cached[T]{Company: *company, Data: data, FetchedAt: time.Now(), DurationMs: time.Since(start).Milliseconds()}
	s.mu.Lock()
	store[key] = c
	s.mu.Unlock()
	s.log.Info("cache loaded", "what", what, "company", company.Name, "duration_ms", c.DurationMs)
	return c, nil
}

// invalidate drops the supplier, purchase and stock caches of one company.
func (s *Server) invalidate(company string) {
	key := strings.ToLower(company)
	s.mu.Lock()
	delete(s.caches.suppliers, key)
	delete(s.caches.purchases, key)
	delete(s.caches.stock, key)
	s.mu.Unlock()
}

func (s *Server) suppliers(r *http.Request) (*cached[[]tally.Customer], error) {
	return load(s, r, "suppliers", s.caches.suppliers, func(ctx context.Context, c *tally.Company) ([]tally.Customer, error) {
		return s.svc.GetSuppliers(ctx, c.Name)
	})
}

func (s *Server) purchases(r *http.Request) (*cached[*tally.PurchaseList], error) {
	return load(s, r, "purchases", s.caches.purchases, s.svc.GetPurchases)
}

func (s *Server) stock(r *http.Request) (*cached[[]tally.StockItem], error) {
	return load(s, r, "stock", s.caches.stock, func(ctx context.Context, c *tally.Company) ([]tally.StockItem, error) {
		return s.svc.GetStockItems(ctx, c.Name)
	})
}

// ---------------------------------------------------------------- suppliers

func (s *Server) handleSuppliers(w http.ResponseWriter, r *http.Request) {
	c, err := s.suppliers(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parseQuery(r, "name_asc")
	list := filterSuppliers(c.Data, q)
	var payable, advance tally.Amount
	var nPayable, nAdvance int
	for _, x := range c.Data {
		switch {
		case x.ClosingSigned > 0:
			payable += x.ClosingSigned
			nPayable++
		case x.ClosingSigned < 0:
			advance += x.ClosingSigned
			nAdvance++
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"company": c.Company.Name, "fetchedAt": c.FetchedAt, "groups": s.svc.SupplierGroups(),
		"total": len(list), "items": list, "totalSuppliers": len(c.Data),
		"totalPayable": payable.Rupees(), "suppliersPayable": nPayable,
		"totalAdvance": advance.Rupees(), "suppliersAdvance": nAdvance,
		"netPayable": (payable + advance).Balance(),
	})
}

// filterSuppliers reuses the shop filters. For suppliers "cr" (payable) is
// the interesting side, so the balance sorts put the largest Cr first.
func filterSuppliers(all []tally.Customer, q query) []tally.Customer {
	sortKey := q.sort
	switch q.sort {
	case "balance_desc", "balance_asc":
		q.sort = "name_asc"
	}
	list := filterCustomers(all, q)
	switch sortKey {
	case "balance_desc":
		sort.SliceStable(list, func(i, j int) bool { return list[i].ClosingSigned > list[j].ClosingSigned })
	case "balance_asc":
		sort.SliceStable(list, func(i, j int) bool { return list[i].ClosingSigned < list[j].ClosingSigned })
	}
	return list
}

func (s *Server) handleSupplier(w http.ResponseWriter, r *http.Request) {
	company, err := s.resolveCompany(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	c, err := s.svc.GetSupplier(r.Context(), company.Name, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"company": company, "fetchedAt": time.Now(), "supplier": c})
}

func (s *Server) handleSupplierTransactions(w http.ResponseWriter, r *http.Request) {
	company, err := s.resolveCompany(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	c, err := s.svc.GetSupplier(r.Context(), company.Name, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	sum, err := s.svc.GetSupplierTransactions(r.Context(), company, c)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, sum)
}

// ---------------------------------------------------------------- purchases

type purchaseQuery struct {
	from, to, q, supplier, item string
	page, size                  int
}

func parsePurchaseQuery(r *http.Request) purchaseQuery {
	v := r.URL.Query()
	return purchaseQuery{
		from: strings.TrimSpace(v.Get("from")), to: strings.TrimSpace(v.Get("to")),
		q: strings.ToLower(strings.TrimSpace(v.Get("q"))), supplier: strings.TrimSpace(v.Get("supplier")),
		item: strings.TrimSpace(v.Get("item")),
		page: max(atoiDef(v.Get("page"), 1), 1), size: min(max(atoiDef(v.Get("pageSize"), 50), 1), 1000),
	}
}

// filterPurchases applies the date range (inclusive, YYYY-MM-DD), supplier,
// exact item and free-text filters. Order stays newest first.
func filterPurchases(all []tally.Purchase, q purchaseQuery) []tally.Purchase {
	out := make([]tally.Purchase, 0, len(all))
	for _, p := range all {
		if (q.from != "" && p.Date < q.from) || (q.to != "" && p.Date > q.to) {
			continue
		}
		if q.supplier != "" && !strings.EqualFold(p.Supplier, q.supplier) {
			continue
		}
		if q.item != "" && !hasItem(p, q.item) {
			continue
		}
		if q.q != "" && !purchaseMatches(p, q.q) {
			continue
		}
		out = append(out, p)
	}
	return out
}

func hasItem(p tally.Purchase, item string) bool {
	for _, l := range p.Lines {
		if strings.EqualFold(l.Item, item) {
			return true
		}
	}
	return false
}

func purchaseMatches(p tally.Purchase, needle string) bool {
	for _, f := range []string{p.Supplier, p.Number, p.Reference, p.VoucherType, p.Narration} {
		if strings.Contains(strings.ToLower(f), needle) {
			return true
		}
	}
	for _, l := range p.Lines {
		if strings.Contains(strings.ToLower(l.Item), needle) {
			return true
		}
	}
	return false
}

type purchaseTotals struct {
	Bills   int     `json:"bills"`
	Total   float64 `json:"total"`
	Taxable float64 `json:"taxable"`
	Other   float64 `json:"other"`
	Qty     float64 `json:"qty"`
	total   tally.Amount
	taxable tally.Amount
}

func (t *purchaseTotals) add(p tally.Purchase) {
	t.Bills++
	t.total += rupeesToPaise(p.Total)
	t.taxable += rupeesToPaise(p.Taxable)
	t.Qty += p.Qty
}

func (t *purchaseTotals) done() {
	t.Total = float64(t.total) / 100
	t.Taxable = float64(t.taxable) / 100
	t.Other = float64(t.total-t.taxable) / 100
	t.Qty = float64(rupeesToPaise(t.Qty)) / 100
}

func rupeesToPaise(f float64) tally.Amount {
	if f < 0 {
		return tally.Amount(f*100 - 0.5)
	}
	return tally.Amount(f*100 + 0.5)
}

// purchaseRow is a register row: the bill without its lines.
type purchaseRow struct {
	tally.Purchase
	LineCount int `json:"lineCount"`
}

func (s *Server) handlePurchases(w http.ResponseWriter, r *http.Request) {
	c, err := s.purchases(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parsePurchaseQuery(r)
	list := filterPurchases(c.Data.Purchases, q)

	var totals purchaseTotals
	bySupplier := map[string]*purchaseTotals{}
	for _, p := range list {
		totals.add(p)
		if bySupplier[p.Supplier] == nil {
			bySupplier[p.Supplier] = &purchaseTotals{}
		}
		bySupplier[p.Supplier].add(p)
	}
	totals.done()
	type supRow struct {
		Supplier string `json:"supplier"`
		purchaseTotals
	}
	sups := make([]supRow, 0, len(bySupplier))
	for name, t := range bySupplier {
		t.done()
		sups = append(sups, supRow{name, *t})
	}
	sort.Slice(sups, func(i, j int) bool { return sups[i].total > sups[j].total })

	total := len(list)
	from := min((q.page-1)*q.size, total)
	to := min(from+q.size, total)
	rows := make([]purchaseRow, 0, to-from)
	for _, p := range list[from:to] {
		n := len(p.Lines)
		p.Lines, p.Ledgers = nil, nil
		rows = append(rows, purchaseRow{p, n})
	}
	first, last := dateRange(c.Data.Purchases)
	writeJSON(w, http.StatusOK, map[string]any{
		"company": c.Company.Name, "fetchedAt": c.FetchedAt,
		"total": total, "page": q.page, "pageSize": q.size, "pages": (total + q.size - 1) / q.size,
		"totals": totals, "bySupplier": sups, "items": rows,
		"excluded":  map[string]int{"cancelled": c.Data.Cancelled, "optional": c.Data.Optional},
		"firstDate": first, "lastDate": last, "suppliers": supplierNames(c.Data.Purchases),
	})
}

func dateRange(ps []tally.Purchase) (string, string) {
	if len(ps) == 0 {
		return "", ""
	}
	return ps[len(ps)-1].Date, ps[0].Date // newest first
}

func supplierNames(ps []tally.Purchase) []string {
	seen := map[string]bool{}
	var out []string
	for _, p := range ps {
		if p.Supplier != "" && !seen[p.Supplier] {
			seen[p.Supplier] = true
			out = append(out, p.Supplier)
		}
	}
	sort.Strings(out)
	return out
}

func (s *Server) handlePurchase(w http.ResponseWriter, r *http.Request) {
	c, err := s.purchases(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	id := r.PathValue("id")
	for _, p := range c.Data.Purchases {
		if p.ID == id {
			writeJSON(w, http.StatusOK, map[string]any{"company": c.Company.Name, "fetchedAt": c.FetchedAt, "purchase": p})
			return
		}
	}
	writeErr(w, http.StatusNotFound, "NOT_FOUND", "That purchase was not found. It may have been deleted in Tally — refresh from Tally.", "")
}

// itemPurchase is one item's purchases over the selected bills.
type itemPurchase struct {
	Item     string  `json:"item"`
	Unit     string  `json:"unit,omitempty"`
	Qty      float64 `json:"qty"`
	Amount   float64 `json:"amount"`
	AvgRate  float64 `json:"avgRate"`
	Bills    int     `json:"bills"`
	LastDate string  `json:"lastDate"`
	LastRate float64 `json:"lastRate"`
	amount   tally.Amount
}

func aggregateItems(list []tally.Purchase, q string) []itemPurchase {
	by := map[string]*itemPurchase{}
	for _, p := range list { // newest first, so the first line seen is the latest
		counted := map[string]bool{}
		for _, l := range p.Lines {
			if q != "" && !strings.Contains(strings.ToLower(l.Item), q) {
				continue
			}
			it := by[l.Item]
			if it == nil {
				it = &itemPurchase{Item: l.Item, Unit: l.Unit, LastDate: p.Date, LastRate: l.Rate}
				by[l.Item] = it
			}
			it.Qty += l.Qty
			it.amount += rupeesToPaise(l.Amount)
			if !counted[l.Item] {
				counted[l.Item] = true
				it.Bills++
			}
		}
	}
	out := make([]itemPurchase, 0, len(by))
	for _, it := range by {
		it.Amount = float64(it.amount) / 100
		if it.Qty != 0 {
			it.AvgRate = float64(rupeesToPaise(it.Amount/it.Qty)) / 100
		}
		out = append(out, *it)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].amount > out[j].amount })
	return out
}

func (s *Server) handlePurchaseItems(w http.ResponseWriter, r *http.Request) {
	c, err := s.purchases(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parsePurchaseQuery(r)
	text := q.q
	q.q = "" // the text filter applies to item names only here
	items := aggregateItems(filterPurchases(c.Data.Purchases, q), text)
	var total tally.Amount
	for _, it := range items {
		total += it.amount
	}
	writeJSON(w, http.StatusOK, map[string]any{"company": c.Company.Name, "fetchedAt": c.FetchedAt,
		"count": len(items), "totalAmount": float64(total) / 100, "items": items})
}

// ---------------------------------------------------------------- inventory

type stockQuery struct {
	q, group, status, sort string
	page, size             int
}

func parseStockQuery(r *http.Request) stockQuery {
	v := r.URL.Query()
	return stockQuery{q: strings.ToLower(strings.TrimSpace(v.Get("q"))), group: strings.TrimSpace(v.Get("group")),
		status: strings.ToLower(v.Get("status")), sort: strings.ToLower(v.Get("sort")),
		page: max(atoiDef(v.Get("page"), 1), 1), size: min(max(atoiDef(v.Get("pageSize"), 50), 1), 1000)}
}

func filterStock(all []tally.StockItem, q stockQuery) []tally.StockItem {
	out := make([]tally.StockItem, 0, len(all))
	for _, it := range all {
		if q.group != "" && !strings.EqualFold(it.Group, q.group) {
			continue
		}
		switch q.status {
		case "":
		case "available": // anything on hand
			if it.ClosingQty <= 0 {
				continue
			}
		default:
			if it.Status != q.status {
				continue
			}
		}
		if q.q != "" && !stockMatches(it, q.q) {
			continue
		}
		out = append(out, it)
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		switch q.sort {
		case "value_desc":
			if a.ClosingValue != b.ClosingValue {
				return a.ClosingValue > b.ClosingValue
			}
		case "qty_desc":
			if a.ClosingQty != b.ClosingQty {
				return a.ClosingQty > b.ClosingQty
			}
		case "qty_asc":
			if a.ClosingQty != b.ClosingQty {
				return a.ClosingQty < b.ClosingQty
			}
		case "group_asc":
			if a.Group != b.Group {
				return strings.ToLower(a.Group) < strings.ToLower(b.Group)
			}
		case "name_desc":
			return strings.ToLower(a.Name) > strings.ToLower(b.Name)
		}
		return strings.ToLower(a.Name) < strings.ToLower(b.Name)
	})
	return out
}

func stockMatches(it tally.StockItem, needle string) bool {
	if strings.Contains(strings.ToLower(it.Name), needle) || strings.Contains(strings.ToLower(it.Group), needle) {
		return true
	}
	for _, a := range it.Aliases {
		if strings.Contains(strings.ToLower(a), needle) {
			return true
		}
	}
	return false
}

func (s *Server) handleInventory(w http.ResponseWriter, r *http.Request) {
	c, err := s.stock(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parseStockQuery(r)
	list := filterStock(c.Data, q)

	type summary struct {
		Items    int     `json:"items"`
		Value    float64 `json:"value"`
		Qty      float64 `json:"qty"`
		InStock  int     `json:"inStock"`
		Low      int     `json:"low"`
		Zero     int     `json:"zero"`
		Negative int     `json:"negative"`
		value    tally.Amount
	}
	count := func(items []tally.StockItem) summary {
		var sm summary
		for _, it := range items {
			sm.Items++
			sm.value += rupeesToPaise(it.ClosingValue)
			sm.Qty += it.ClosingQty
			switch it.Status {
			case "in_stock":
				sm.InStock++
			case "low":
				sm.Low++
			case "zero":
				sm.Zero++
			case "negative":
				sm.Negative++
			}
		}
		sm.Value = float64(sm.value) / 100
		return sm
	}
	groups := map[string]int{}
	for _, it := range c.Data {
		groups[it.Group]++
	}
	type gc struct {
		Group string `json:"group"`
		Items int    `json:"items"`
	}
	gl := make([]gc, 0, len(groups))
	for g, n := range groups {
		gl = append(gl, gc{g, n})
	}
	sort.Slice(gl, func(i, j int) bool { return strings.ToLower(gl[i].Group) < strings.ToLower(gl[j].Group) })

	total := len(list)
	from := min((q.page-1)*q.size, total)
	to := min(from+q.size, total)
	writeJSON(w, http.StatusOK, map[string]any{
		"company": c.Company.Name, "fetchedAt": c.FetchedAt,
		"total": total, "page": q.page, "pageSize": q.size, "pages": (total + q.size - 1) / q.size,
		"all": count(c.Data), "filtered": count(list), "groups": gl, "items": list[from:to],
	})
}

func (s *Server) handleStockItem(w http.ResponseWriter, r *http.Request) {
	c, err := s.stock(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	id := r.PathValue("id")
	for _, it := range c.Data {
		if it.ID == id || strings.EqualFold(it.Name, id) { // Tally GUID, or the item name (links from purchase lines)
			writeJSON(w, http.StatusOK, map[string]any{"company": c.Company.Name, "fetchedAt": c.FetchedAt, "item": it})
			return
		}
	}
	writeErr(w, http.StatusNotFound, "NOT_FOUND", "That stock item was not found. It may have been renamed or deleted — refresh from Tally.", "")
}

// handleStockItemPurchases lists every purchase line of one item, newest first.
func (s *Server) handleStockItemPurchases(w http.ResponseWriter, r *http.Request) {
	st, err := s.stock(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	var item *tally.StockItem
	for i := range st.Data {
		if id := r.PathValue("id"); st.Data[i].ID == id || strings.EqualFold(st.Data[i].Name, id) {
			item = &st.Data[i]
			break
		}
	}
	if item == nil {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "That stock item was not found — refresh from Tally.", "")
		return
	}
	pc, err := s.purchases(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	type row struct {
		PurchaseID string  `json:"purchaseId"`
		Date       string  `json:"date"`
		Supplier   string  `json:"supplier"`
		Number     string  `json:"number"`
		Qty        float64 `json:"qty"`
		Unit       string  `json:"unit,omitempty"`
		Rate       float64 `json:"rate"`
		Amount     float64 `json:"amount"`
	}
	rows := []row{}
	var qty float64
	var amt tally.Amount
	for _, p := range pc.Data.Purchases {
		for _, l := range p.Lines {
			if l.Item != item.Name {
				continue
			}
			rows = append(rows, row{p.ID, p.Date, p.Supplier, p.Number, l.Qty, l.Unit, l.Rate, l.Amount})
			qty += l.Qty
			amt += rupeesToPaise(l.Amount)
		}
	}
	avg := 0.0
	if qty != 0 {
		avg = float64(rupeesToPaise(float64(amt)/100/qty)) / 100
	}
	writeJSON(w, http.StatusOK, map[string]any{"company": pc.Company.Name, "fetchedAt": pc.FetchedAt, "item": item.Name,
		"count": len(rows), "qty": qty, "amount": float64(amt) / 100, "avgRate": avg, "purchases": rows})
}
