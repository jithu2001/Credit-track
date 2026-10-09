package appapi

import (
	"sort"
	"strings"
	"time"
)

// Stock status and the stock alert (moved here from the app's stock_item.dart).
//
// An item's minimum is the owner's minimum stock if set, else Tally's reorder
// level (0 = none). It is "at or below minimum" when it has a minimum and its
// closing quantity is not above it; that is the stock alert, out of stock
// included. Status: negative, zero (out of stock), low (at or below the
// minimum), in stock.

type StockStatus string

const (
	StockInStock  StockStatus = "in_stock"
	StockLow      StockStatus = "low"
	StockZero     StockStatus = "zero"
	StockNegative StockStatus = "negative"
)

var stockStatuses = []StockStatus{StockInStock, StockLow, StockZero, StockNegative}

type StockItem struct {
	ID           string
	Name         string
	ClosingQty   float64
	ReorderLevel float64
	MinQty       *float64 // the owner's minimum; nil = not set
	ClosingValue *int64   // paise; owner only
	SyncedAt     *time.Time
}

func (i StockItem) EffectiveMin() float64 {
	switch {
	case i.MinQty != nil && *i.MinQty > 0:
		return *i.MinQty
	case i.ReorderLevel > 0:
		return i.ReorderLevel
	}
	return 0
}

func (i StockItem) AtOrBelowMinimum() bool {
	m := i.EffectiveMin()
	return m > 0 && i.ClosingQty <= m
}

// Shortfall is how much is needed to get back to the minimum.
func (i StockItem) Shortfall() float64 {
	if !i.AtOrBelowMinimum() {
		return 0
	}
	return i.EffectiveMin() - i.ClosingQty
}

func (i StockItem) Status() StockStatus {
	switch {
	case i.ClosingQty < 0:
		return StockNegative
	case i.ClosingQty == 0:
		return StockZero
	case i.AtOrBelowMinimum():
		return StockLow
	}
	return StockInStock
}

// StockAlerts lists the items at or below their minimum, the furthest below
// first (by how much of the minimum is missing), then by name.
func StockAlerts(items []StockItem) []StockItem {
	var out []StockItem
	for _, i := range items {
		if i.AtOrBelowMinimum() {
			out = append(out, i)
		}
	}
	missing := func(i StockItem) float64 { return i.Shortfall() / i.EffectiveMin() }
	sort.SliceStable(out, func(a, b int) bool {
		ma, mb := missing(out[a]), missing(out[b])
		if ma != mb {
			return ma > mb
		}
		return strings.ToLower(out[a].Name) < strings.ToLower(out[b].Name)
	})
	return out
}

// StockSummary totals a list: items, value (owner), count per status and the latest sync.
type StockSummary struct {
	Items    int
	Value    int64
	ByStatus map[StockStatus]int
	SyncedAt *time.Time
}

func SummariseStock(items []StockItem) StockSummary {
	s := StockSummary{Items: len(items), ByStatus: map[StockStatus]int{}}
	for _, st := range stockStatuses {
		s.ByStatus[st] = 0
	}
	for _, i := range items {
		if i.ClosingValue != nil {
			s.Value += *i.ClosingValue
		}
		s.ByStatus[i.Status()]++
		if i.SyncedAt != nil && (s.SyncedAt == nil || i.SyncedAt.After(*s.SyncedAt)) {
			t := *i.SyncedAt
			s.SyncedAt = &t
		}
	}
	return s
}
