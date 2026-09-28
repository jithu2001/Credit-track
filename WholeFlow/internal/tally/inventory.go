package tally

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
)

// Quantity is a Tally quantity such as " 17 Nos" or "-3 pc". Compound or
// alternate units ("6 Nos = 1 Box") keep only the first (base) part.
type Quantity struct {
	Value float64 `json:"value"`
	Unit  string  `json:"unit,omitempty"`
}

// ParseQuantity reads what Tally puts in TYPE="Quantity" elements. An empty
// string is zero.
func ParseQuantity(s string) (Quantity, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return Quantity{}, nil
	}
	if i := strings.Index(s, "="); i >= 0 { // alternate units
		s = strings.TrimSpace(s[:i])
	}
	num, unit := splitNumber(s)
	if strings.IndexFunc(unit, func(r rune) bool { return r >= '0' && r <= '9' }) >= 0 {
		// e.g. "1 Box 2 Nos" (compound unit): reading only "1" would be wrong
		return Quantity{}, fmt.Errorf("unsupported compound quantity %q", s)
	}
	if num == "" {
		return Quantity{}, fmt.Errorf("unrecognised quantity %q", s)
	}
	v, err := strconv.ParseFloat(num, 64)
	if err != nil {
		return Quantity{}, fmt.Errorf("unrecognised quantity %q", s)
	}
	return Quantity{Value: v, Unit: unit}, nil
}

// ParseRate reads TYPE="Rate" elements such as "844.15/Nos". Empty is zero.
func ParseRate(s string) (float64, string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, "", nil
	}
	val, unit, _ := strings.Cut(s, "/")
	num, _ := splitNumber(strings.TrimSpace(val))
	if num == "" {
		return 0, "", fmt.Errorf("unrecognised rate %q", s)
	}
	v, err := strconv.ParseFloat(num, 64)
	if err != nil {
		return 0, "", fmt.Errorf("unrecognised rate %q", s)
	}
	return v, strings.TrimSpace(unit), nil
}

// splitNumber separates a leading signed decimal (grouping commas allowed)
// from the rest of the string.
func splitNumber(s string) (num, rest string) {
	s = strings.TrimPrefix(strings.TrimSpace(s), "₹")
	end := 0
	for i, r := range s {
		if (r >= '0' && r <= '9') || r == '.' || r == ',' || (i == 0 && (r == '-' || r == '+')) {
			end = i + len(string(r))
			continue
		}
		break
	}
	return strings.ReplaceAll(s[:end], ",", ""), strings.TrimSpace(s[end:])
}

// StockItem is one inventory item with its current position in Tally.
type StockItem struct {
	ID       string   `json:"id"` // Tally GUID
	Name     string   `json:"name"`
	Aliases  []string `json:"aliases,omitempty"` // part numbers, alternate names
	Group    string   `json:"group"`             // stock group (PARENT)
	Category string   `json:"category,omitempty"`
	Unit     string   `json:"unit"`
	GST      bool     `json:"gstApplicable"`

	OpeningQty   float64 `json:"openingQty"`
	OpeningValue float64 `json:"openingValue"` // rupees, positive = stock value
	ClosingQty   float64 `json:"closingQty"`
	ClosingRate  float64 `json:"closingRate"`  // Tally's valuation rate per unit
	ClosingValue float64 `json:"closingValue"` // rupees, positive = stock value
	ReorderLevel float64 `json:"reorderLevel,omitempty"`
	MinOrderQty  float64 `json:"minOrderQty,omitempty"`

	// Status is "in_stock", "low" (at or below the reorder level), "zero" or "negative".
	Status        string   `json:"status"`
	ParseWarnings []string `json:"parseWarnings,omitempty"`
}

const stockFetch = `NAME,GUID,PARENT,CATEGORY,BASEUNITS,GSTAPPLICABLE,OPENINGBALANCE,OPENINGVALUE,` +
	`CLOSINGBALANCE,CLOSINGVALUE,CLOSINGRATE,REORDERBASE,MINIMUMORDERBASE,LANGUAGENAME`

type xmlStockItem struct {
	Name      string   `xml:"NAME,attr"`
	GUID      string   `xml:"GUID"`
	Parent    string   `xml:"PARENT"`
	Category  string   `xml:"CATEGORY"`
	Unit      string   `xml:"BASEUNITS"`
	GST       string   `xml:"GSTAPPLICABLE"`
	OpenQty   string   `xml:"OPENINGBALANCE"`
	OpenVal   string   `xml:"OPENINGVALUE"`
	CloseQty  string   `xml:"CLOSINGBALANCE"`
	CloseVal  string   `xml:"CLOSINGVALUE"`
	CloseRate string   `xml:"CLOSINGRATE"`
	Reorder   string   `xml:"REORDERBASE"`
	MinOrder  string   `xml:"MINIMUMORDERBASE"`
	Names     []string `xml:"LANGUAGENAME.LIST>NAME.LIST>NAME"`
}

// GetStockItems returns every stock item of the company, sorted by name.
// Verified on TallyPrime 6 (Sep 2026): 549 items in one ~650 KB response.
func (s *Service) GetStockItems(ctx context.Context, company string) ([]StockItem, error) {
	const op = "stock-items"
	tdl := `<COLLECTION NAME="WFC"><TYPE>StockItem</TYPE><FETCH>` + stockFetch + `</FETCH></COLLECTION>`
	body, err := s.client.post(ctx, op, Request{Company: company, TDL: tdl}.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlStockItem `xml:"BODY>DATA>COLLECTION>STOCKITEM"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]StockItem, 0, len(env.Items))
	for _, x := range env.Items {
		out = append(out, s.toStockItem(x))
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out, nil
}

func (s *Service) toStockItem(x xmlStockItem) StockItem {
	it := StockItem{ID: clean(x.GUID), Name: clean(x.Name), Group: clean(x.Parent), Unit: clean(x.Unit),
		Category: notApplicable(x.Category), GST: strings.EqualFold(clean(x.GST), "Applicable")}
	for _, n := range x.Names {
		if n = clean(n); n != "" && n != it.Name {
			it.Aliases = append(it.Aliases, n)
		}
	}
	warn := func(field string, err error) {
		it.ParseWarnings = append(it.ParseWarnings, field+": "+err.Error())
		s.log.Warn("unparsed stock value", "item", it.Name, "field", field, "error", err.Error())
	}
	qty := func(field, v string) float64 {
		q, err := ParseQuantity(v)
		if err != nil {
			warn(field, err)
		}
		if it.Unit == "" {
			it.Unit = q.Unit
		}
		return q.Value
	}
	// Stock values use the ledger sign: negative = Dr = an asset we hold.
	value := func(field, v string) float64 {
		a, err := ParseAmount(v)
		if err != nil {
			warn(field, err)
		}
		return -float64(a) / 100
	}
	it.OpeningQty = qty("opening quantity", x.OpenQty)
	it.ClosingQty = qty("closing quantity", x.CloseQty)
	it.ReorderLevel = qty("reorder level", x.Reorder)
	it.MinOrderQty = qty("minimum order", x.MinOrder)
	it.OpeningValue = value("opening value", x.OpenVal)
	it.ClosingValue = value("closing value", x.CloseVal)
	if r, _, err := ParseRate(x.CloseRate); err != nil {
		warn("closing rate", err)
	} else {
		it.ClosingRate = r
	}
	switch {
	case it.ClosingQty < 0:
		it.Status = "negative"
	case it.ClosingQty == 0:
		it.Status = "zero"
	case it.ReorderLevel > 0 && it.ClosingQty <= it.ReorderLevel:
		it.Status = "low"
	default:
		it.Status = "in_stock"
	}
	return it
}

// notApplicable blanks Tally's placeholder for an unset reference.
func notApplicable(s string) string {
	s = clean(s)
	if strings.EqualFold(s, "Not Applicable") {
		return ""
	}
	return s
}

func round2(f float64) float64 { return math.Round(f*100) / 100 }
