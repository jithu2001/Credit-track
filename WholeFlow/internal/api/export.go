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

// handleExport serves /api/export/{customers|outstanding}?format=csv|xlsx with
// the same filter parameters as the matching list endpoint.
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
	snap, err := s.snapshot(r, false)
	if err != nil {
		s.fail(w, err)
		return
	}

	var t export.Table
	var list []tally.Customer
	switch report {
	case "outstanding":
		q := parseQuery(r, "balance_desc")
		q.typ = "dr"
		list = filterCustomers(snap.Customers, q)
		t = export.Table{Sheet: "Outstanding", Headers: []string{"Shop", "Area", "Phone", "Outstanding (Rs)"}}
		var total tally.Amount
		for _, c := range list {
			t.Rows = append(t.Rows, []any{c.Name, c.Area, strings.Join(c.Phones, " / "), c.Balance.Amount})
			total += c.ClosingSigned
		}
		t.Rows = append(t.Rows, []any{"TOTAL", "", "", total.Rupees()})
	case "customers":
		q := parseQuery(r, "name_asc")
		list = filterCustomers(snap.Customers, q)
		t = export.Table{Sheet: "Shops", Headers: []string{"Shop", "Group", "Area", "Phone", "GSTIN", "State", "Pincode",
			"Opening Balance (Rs)", "Opening Dr/Cr", "Current Balance (Rs)", "Dr/Cr"}}
		for _, c := range list {
			t.Rows = append(t.Rows, []any{c.Name, c.Group, c.Area, strings.Join(c.Phones, " / "), c.GSTIN, c.State, c.Pincode,
				c.OpeningBalance.Amount, drcr(c.OpeningBalance.Type), c.Balance.Amount, drcr(c.Balance.Type)})
		}
	default:
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "Unknown report.", "")
		return
	}
	t.Title = fmt.Sprintf("%s - %s - data from Tally as of %s", t.Sheet, snap.Company.Name, snap.FetchedAt.Format("02-Jan-2006 15:04"))

	name := fmt.Sprintf("%s_%s_%s.%s", report, safeName(snap.Company.Name), time.Now().Format("20060102-1504"), format)
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
	s.log.Info("export served", "report", report, "format", format, "rows", len(list))
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
