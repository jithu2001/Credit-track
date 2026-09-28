// Package api exposes the Tally data as a JSON REST API for the web frontend.
// It never deals with Tally XML; everything goes through tally.Service.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"wholeflow/internal/config"
	"wholeflow/internal/tally"
)

type Server struct {
	svc *tally.Service
	cfg *config.Config
	log *slog.Logger

	// snapshots hold the last shop list pulled from Tally per company. They are
	// replaced wholesale by "Refresh from Tally"; nothing is ever edited locally.
	mu        sync.Mutex
	loadMu    sync.Mutex
	snapshots map[string]*snapshot
	caches    caches
}

type snapshot struct {
	Company    tally.Company
	Customers  []tally.Customer
	FetchedAt  time.Time
	DurationMs int64
}

func New(svc *tally.Service, cfg *config.Config, log *slog.Logger) *Server {
	return &Server{svc: svc, cfg: cfg, log: log, snapshots: map[string]*snapshot{}, caches: newCaches()}
}

func (s *Server) Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/tally/status", s.handleStatus)
	mux.HandleFunc("POST /api/tally/refresh", s.handleRefresh)
	mux.HandleFunc("GET /api/companies", s.handleCompanies)
	mux.HandleFunc("GET /api/ledgers", s.handleLedgers)
	mux.HandleFunc("GET /api/customers", s.handleCustomers)
	mux.HandleFunc("GET /api/customers/balances", s.handleBalances)
	mux.HandleFunc("GET /api/customers/{id}", s.handleCustomer)
	mux.HandleFunc("GET /api/customers/{id}/transactions", s.handleTransactions)
	mux.HandleFunc("GET /api/dashboard", s.handleDashboard)
	mux.HandleFunc("GET /api/reports/outstanding", s.handleOutstanding)
	mux.HandleFunc("GET /api/suppliers", s.handleSuppliers)
	mux.HandleFunc("GET /api/suppliers/{id}", s.handleSupplier)
	mux.HandleFunc("GET /api/suppliers/{id}/transactions", s.handleSupplierTransactions)
	mux.HandleFunc("GET /api/purchases", s.handlePurchases)
	mux.HandleFunc("GET /api/purchases/items", s.handlePurchaseItems)
	mux.HandleFunc("GET /api/purchases/{id}", s.handlePurchase)
	mux.HandleFunc("GET /api/inventory", s.handleInventory)
	mux.HandleFunc("GET /api/inventory/{id}", s.handleStockItem)
	mux.HandleFunc("GET /api/inventory/{id}/purchases", s.handleStockItemPurchases)
	mux.HandleFunc("GET /api/export/{report}", s.handleExport)
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "Unknown API endpoint.", "")
	})
}

// ---------------------------------------------------------------- status

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	st := s.svc.TestConnection(r.Context())
	resp := map[string]any{
		"connected":      st.Connected,
		"state":          st.State,
		"host":           st.Host,
		"port":           st.Port,
		"portSource":     s.cfg.PortSource,
		"endpoint":       st.Endpoint,
		"processRunning": st.ProcessRunning,
		"responseMs":     st.ResponseMs,
		"companies":      st.Companies,
		"checkedAt":      st.CheckedAt,
		"shopGroups":     s.cfg.ShopGroups,
		"supplierGroups": s.svc.SupplierGroups(),
		"warnings":       s.cfg.Warnings,
	}
	if ini := s.cfg.TallyINI; ini != nil {
		resp["tallyIni"] = map[string]any{"path": ini.Path, "serverPort": ini.ServerPort, "clientServer": ini.ClientServer}
	}
	if st.Error != nil {
		code, msg, _ := s.describe(st.Error)
		resp["error"] = map[string]string{"code": code, "message": msg}
		resp["hints"] = s.hints(st)
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) hints(st tally.Status) []string {
	var h []string
	if st.ProcessRunning != nil && !*st.ProcessRunning {
		h = append(h, "TallyPrime is not running on this computer (tally.exe not found). Start TallyPrime and open the company.")
	} else if st.ProcessRunning != nil && *st.ProcessRunning {
		h = append(h, fmt.Sprintf("TallyPrime is running but did not answer on port %d.", st.Port))
	}
	h = append(h,
		"Server/data access may be disabled: in TallyPrime open Help (F1) > Settings > Connectivity > Client/Server configuration and set 'TallyPrime acts as' to Server or Both.",
		fmt.Sprintf("The port may be wrong: the app is using %d (from %s). It must match the port shown in that Connectivity screen.", st.Port, s.cfg.PortSource),
		"A firewall or security product may be blocking the connection.",
	)
	return h
}

// ---------------------------------------------------------------- companies & ledgers

func (s *Server) handleCompanies(w http.ResponseWriter, r *http.Request) {
	companies, err := s.svc.GetCompanies(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"companies": companies, "defaultCompany": s.cfg.DefaultCompany})
}

func (s *Server) handleLedgers(w http.ResponseWriter, r *http.Request) {
	company, err := s.resolveCompany(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	ledgers, err := s.svc.GetLedgers(r.Context(), company.Name)
	if err != nil {
		s.fail(w, err)
		return
	}
	counts := map[string]int{}
	for _, l := range ledgers {
		counts[l.Group]++
	}
	type gc struct {
		Group string `json:"group"`
		Count int    `json:"count"`
	}
	groups := make([]gc, 0, len(counts))
	for g, n := range counts {
		groups = append(groups, gc{g, n})
	}
	sort.Slice(groups, func(i, j int) bool { return groups[i].Count > groups[j].Count })
	writeJSON(w, http.StatusOK, map[string]any{"company": company.Name, "count": len(ledgers), "groups": groups, "ledgers": ledgers})
}

// ---------------------------------------------------------------- snapshot

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	snap, err := s.snapshot(r, true)
	if err != nil {
		s.fail(w, err)
		return
	}
	// Suppliers, purchases and stock reload lazily on their next use.
	s.invalidate(snap.Company.Name)
	writeJSON(w, http.StatusOK, map[string]any{
		"company": snap.Company.Name, "fetchedAt": snap.FetchedAt, "customers": len(snap.Customers), "durationMs": snap.DurationMs,
	})
}

// snapshot returns the cached shop list for the requested company, pulling it
// from Tally on first use or when force is set.
func (s *Server) snapshot(r *http.Request, force bool) (*snapshot, error) {
	name := s.companyParam(r)
	if !force && name != "" {
		s.mu.Lock()
		snap := s.snapshots[strings.ToLower(name)]
		s.mu.Unlock()
		if snap != nil {
			return snap, nil
		}
	}

	s.loadMu.Lock()
	defer s.loadMu.Unlock()
	company, err := s.resolveCompany(r)
	if err != nil {
		return nil, err
	}
	key := strings.ToLower(company.Name)
	if !force { // another request may have loaded it while we waited
		s.mu.Lock()
		snap := s.snapshots[key]
		s.mu.Unlock()
		if snap != nil {
			return snap, nil
		}
	}
	start := time.Now()
	customers, err := s.svc.GetCustomers(r.Context(), company.Name)
	if err != nil {
		return nil, err
	}
	snap := &snapshot{Company: *company, Customers: customers, FetchedAt: time.Now(), DurationMs: time.Since(start).Milliseconds()}
	s.mu.Lock()
	s.snapshots[key] = snap
	s.mu.Unlock()
	s.log.Info("snapshot refreshed", "company", company.Name, "customers", len(customers), "duration_ms", snap.DurationMs)
	return snap, nil
}

func (s *Server) companyParam(r *http.Request) string {
	if c := strings.TrimSpace(r.URL.Query().Get("company")); c != "" {
		return c
	}
	return s.cfg.DefaultCompany
}

// resolveCompany validates the requested company against Tally. With no
// company given it only auto-selects when exactly one company is open.
func (s *Server) resolveCompany(r *http.Request) (*tally.Company, error) {
	name := s.companyParam(r)
	if name == "" {
		companies, err := s.svc.GetCompanies(r.Context())
		if err != nil {
			return nil, err
		}
		if len(companies) == 1 {
			return &companies[0], nil
		}
	}
	return s.svc.ResolveCompany(r.Context(), name)
}

// ---------------------------------------------------------------- customers

func (s *Server) handleCustomers(w http.ResponseWriter, r *http.Request) {
	snap, err := s.snapshot(r, false)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parseQuery(r, "name_asc")
	list := filterCustomers(snap.Customers, q)
	total := len(list)
	page, size := q.page, q.size
	from := pageStart(page, size, total)
	to := min(from+size, total)
	writeJSON(w, http.StatusOK, map[string]any{
		"company": snap.Company.Name, "fetchedAt": snap.FetchedAt,
		"total": total, "page": page, "pageSize": size, "pages": (total + size - 1) / size,
		"items": list[from:to],
	})
}

func (s *Server) handleBalances(w http.ResponseWriter, r *http.Request) {
	snap, err := s.snapshot(r, false)
	if err != nil {
		s.fail(w, err)
		return
	}
	type row struct {
		ID          string  `json:"id"`
		Customer    string  `json:"customer"`
		Balance     float64 `json:"balance"`
		BalanceType string  `json:"balanceType"`
	}
	out := make([]row, 0, len(snap.Customers))
	for _, c := range snap.Customers {
		out = append(out, row{c.ID, c.Name, c.Balance.Amount, c.Balance.Type})
	}
	writeJSON(w, http.StatusOK, map[string]any{"company": snap.Company.Name, "fetchedAt": snap.FetchedAt, "balances": out})
}

// handleCustomer always reads live from Tally so the detail page is current.
func (s *Server) handleCustomer(w http.ResponseWriter, r *http.Request) {
	company, err := s.resolveCompany(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	c, err := s.svc.GetCustomer(r.Context(), company.Name, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"company": company, "fetchedAt": time.Now(), "customer": c})
}

func (s *Server) handleTransactions(w http.ResponseWriter, r *http.Request) {
	company, err := s.resolveCompany(r)
	if err != nil {
		s.fail(w, err)
		return
	}
	c, err := s.svc.GetCustomer(r.Context(), company.Name, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	sum, err := s.svc.GetCustomerTransactions(r.Context(), company, c)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, sum)
}

// ---------------------------------------------------------------- dashboard & reports

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	snap, err := s.snapshot(r, false)
	if err != nil {
		s.fail(w, err)
		return
	}
	var dues, credit, settled int
	var outstanding, creditTotal tally.Amount
	areas := map[string]*areaRow{}
	for _, c := range snap.Customers {
		switch {
		case c.ClosingSigned < 0:
			dues++
			outstanding += c.ClosingSigned
			a := c.Area
			if a == "" {
				a = "(unknown)"
			}
			if areas[a] == nil {
				areas[a] = &areaRow{Area: a}
			}
			areas[a].Shops++
			areas[a].paise += -c.ClosingSigned
		case c.ClosingSigned > 0:
			credit++
			creditTotal += c.ClosingSigned
		default:
			settled++
		}
	}
	top := filterCustomers(snap.Customers, query{typ: "dr", sort: "balance_desc"})
	if len(top) > 10 {
		top = top[:10]
	}
	byArea := make([]areaRow, 0, len(areas))
	for _, a := range areas {
		a.Outstanding = float64(a.paise) / 100
		byArea = append(byArea, *a)
	}
	sort.Slice(byArea, func(i, j int) bool { return byArea[i].paise > byArea[j].paise })
	if len(byArea) > 10 {
		byArea = byArea[:10]
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"company":           snap.Company,
		"fetchedAt":         snap.FetchedAt,
		"totalShops":        len(snap.Customers),
		"shopsWithDues":     dues,
		"shopsWithCredit":   credit,
		"shopsSettled":      settled,
		"totalOutstanding":  outstanding.Rupees(),
		"totalCredit":       creditTotal.Rupees(),
		"netReceivable":     (outstanding + creditTotal).Balance(),
		"topOutstanding":    top,
		"outstandingByArea": byArea,
	})
}

type areaRow struct {
	Area        string  `json:"area"`
	Shops       int     `json:"shops"`
	Outstanding float64 `json:"outstanding"`
	paise       tally.Amount
}

func (s *Server) handleOutstanding(w http.ResponseWriter, r *http.Request) {
	snap, err := s.snapshot(r, false)
	if err != nil {
		s.fail(w, err)
		return
	}
	q := parseQuery(r, "balance_desc")
	q.typ = "dr"
	list := filterCustomers(snap.Customers, q)
	var total tally.Amount
	for _, c := range list {
		total += c.ClosingSigned
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"company": snap.Company.Name, "fetchedAt": snap.FetchedAt,
		"count": len(list), "totalOutstanding": total.Rupees(), "items": list,
	})
}

// ---------------------------------------------------------------- filtering

type query struct {
	q, field, typ, sort string
	minAmount           float64
	page, size          int
}

func parseQuery(r *http.Request, defSort string) query {
	v := r.URL.Query()
	q := query{
		q:     strings.TrimSpace(v.Get("q")),
		field: strings.ToLower(v.Get("field")),
		typ:   strings.ToLower(v.Get("type")),
		sort:  strings.ToLower(v.Get("sort")),
		page:  atoiDef(v.Get("page"), 1),
		size:  atoiDef(v.Get("pageSize"), 25),
	}
	q.minAmount, _ = strconv.ParseFloat(v.Get("min"), 64)
	if q.sort == "" {
		q.sort = defSort
	}
	q.page = max(q.page, 1)
	q.size = min(max(q.size, 1), 500)
	return q
}

func filterCustomers(all []tally.Customer, q query) []tally.Customer {
	needle := strings.ToLower(q.q)
	digits := onlyDigits(q.q)
	out := make([]tally.Customer, 0, len(all))
	for _, c := range all {
		switch q.typ {
		case "dr":
			if c.ClosingSigned >= 0 {
				continue
			}
		case "cr":
			if c.ClosingSigned <= 0 {
				continue
			}
		case "zero":
			if c.ClosingSigned != 0 {
				continue
			}
		}
		if q.minAmount > 0 && c.Balance.Amount < q.minAmount {
			continue
		}
		if needle != "" && !matches(c, q.field, needle, digits) {
			continue
		}
		out = append(out, c)
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		switch q.sort {
		case "balance_desc":
			if a.ClosingSigned != b.ClosingSigned {
				return a.ClosingSigned < b.ClosingSigned // more negative = larger receivable
			}
		case "balance_asc":
			if a.ClosingSigned != b.ClosingSigned {
				return a.ClosingSigned > b.ClosingSigned
			}
		case "name_desc":
			return strings.ToLower(a.Name) > strings.ToLower(b.Name)
		case "area_asc":
			if a.Area != b.Area {
				return a.Area < b.Area
			}
		}
		return strings.ToLower(a.Name) < strings.ToLower(b.Name)
	})
	return out
}

func matches(c tally.Customer, field, needle, digits string) bool {
	has := func(s string) bool { return strings.Contains(strings.ToLower(s), needle) }
	byName := func() bool {
		if has(c.Name) {
			return true
		}
		for _, a := range c.Aliases {
			if has(a) {
				return true
			}
		}
		return false
	}
	byPhone := func() bool {
		if len(digits) < 3 {
			return false
		}
		for _, p := range c.Phones {
			if strings.Contains(p, digits) {
				return true
			}
		}
		return false
	}
	byArea := func() bool {
		if has(c.Area) {
			return true
		}
		for _, a := range c.Address {
			if has(a) {
				return true
			}
		}
		return false
	}
	switch field {
	case "name":
		return byName()
	case "phone":
		return byPhone()
	case "area_exact": // dashboard area links: exactly the rows behind the bar
		if needle == "(unknown)" {
			return c.Area == ""
		}
		return strings.EqualFold(c.Area, needle)
	case "area":
		return byArea()
	}
	return byName() || byPhone() || byArea() || has(c.GSTIN)
}

// ---------------------------------------------------------------- errors & helpers

func (s *Server) fail(w http.ResponseWriter, err error) {
	code, msg, status := s.describe(err)
	s.log.Error("api request failed", "code", code, "error", err.Error())
	details := ""
	var te *tally.Error
	if errors.As(err, &te) {
		switch te.Kind {
		case tally.KindUnreachable, tally.KindTimeout:
			details = fmt.Sprintf("Tried %s (port from %s, timeout %s).", s.svc.Endpoint(), s.cfg.PortSource, s.cfg.TallyTimeout)
		case tally.KindCompanyNotFound, tally.KindNotFound:
			details = te.Msg
		}
	}
	writeErr(w, status, code, msg, details)
}

// describe maps an error to (code, user-facing message, HTTP status).
// Technical detail stays in the log.
func (s *Server) describe(err error) (string, string, int) {
	var te *tally.Error
	if !errors.As(err, &te) {
		if errors.Is(err, context.Canceled) {
			return "CANCELLED", "The request was cancelled.", 499
		}
		return "INTERNAL", "Something went wrong. The technical details have been logged.", http.StatusInternalServerError
	}
	switch te.Kind {
	case tally.KindUnreachable:
		return string(te.Kind), "Unable to connect to TallyPrime. Please make sure TallyPrime is running and the server/data-access option is enabled.", http.StatusServiceUnavailable
	case tally.KindTimeout:
		return string(te.Kind), "Tally did not respond within the expected time.", http.StatusGatewayTimeout
	case tally.KindNoCompany:
		return string(te.Kind), "No company selected. Open a company in TallyPrime and select it here.", http.StatusBadRequest
	case tally.KindCompanyNotFound:
		return string(te.Kind), "The selected company is not open in TallyPrime. Open it in TallyPrime or choose another company.", http.StatusConflict
	case tally.KindWriteBlocked:
		return string(te.Kind), "This request was stopped before reaching TallyPrime: the app only ever reads from Tally, and a name containing \"$$\" cannot be sent safely.", http.StatusBadRequest
	case tally.KindNotFound:
		return string(te.Kind), "That record was not found in Tally. It may have been renamed or deleted — refresh from Tally.", http.StatusNotFound
	}
	return string(te.Kind), "TallyPrime returned an unexpected response. The technical details have been logged.", http.StatusBadGateway
}

func writeErr(w http.ResponseWriter, status int, code, msg, details string) {
	body := map[string]string{"code": code, "message": msg}
	if details != "" {
		body["details"] = details
	}
	writeJSON(w, status, map[string]any{"error": body})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	enc.Encode(v)
}

func atoiDef(s string, def int) int {
	if n, err := strconv.Atoi(s); err == nil {
		return n
	}
	return def
}

func onlyDigits(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, s)
}

// pageStart is (page-1)*size clamped to [0, total], safe for huge page numbers.
func pageStart(page, size, total int) int {
	if size <= 0 || page <= 1 {
		return 0
	}
	if page-1 > total/size {
		return total
	}
	return min((page-1)*size, total)
}
