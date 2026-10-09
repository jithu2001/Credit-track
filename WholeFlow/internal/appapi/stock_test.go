package appapi

import "testing"

// Same cases as the app's former stock_domain_test.dart (minimum stock and the alert).

func fp(v float64) *float64 { return &v }

func TestEffectiveMinimum(t *testing.T) {
	eq(t, StockItem{ClosingQty: 8, MinQty: fp(10), ReorderLevel: 5}.EffectiveMin(), 10.0, "owner's minimum wins")
	eq(t, StockItem{ClosingQty: 8, ReorderLevel: 5}.EffectiveMin(), 5.0, "Tally reorder level otherwise")
	eq(t, StockItem{ClosingQty: 8, MinQty: fp(0), ReorderLevel: 5}.EffectiveMin(), 5.0, "0 is no minimum")
	eq(t, StockItem{ClosingQty: 8}.EffectiveMin(), 0.0, "none")
}

func TestStockStatus(t *testing.T) {
	eq(t, StockItem{ClosingQty: -1, MinQty: fp(5)}.Status(), StockNegative, "negative")
	eq(t, StockItem{ClosingQty: 0, MinQty: fp(5)}.Status(), StockZero, "zero")
	eq(t, StockItem{ClosingQty: 5, MinQty: fp(5)}.Status(), StockLow, "at minimum is low")
	eq(t, StockItem{ClosingQty: 5.5, MinQty: fp(5)}.Status(), StockInStock, "above")
	eq(t, StockItem{ClosingQty: 1}.Status(), StockInStock, "no minimum: never low")
	eq(t, StockItem{ClosingQty: 0, MinQty: fp(4)}.AtOrBelowMinimum(), true, "out of stock is in the alert")
	eq(t, StockItem{ClosingQty: 2, MinQty: fp(10)}.Shortfall(), 8.0, "shortfall")
	eq(t, StockItem{ClosingQty: 20, MinQty: fp(10)}.Shortfall(), 0.0, "no shortfall")
}

func TestStockAlertsOrder(t *testing.T) {
	alerts := StockAlerts([]StockItem{
		{Name: "TYRE A", ClosingQty: 9, MinQty: fp(10)}, // 10% missing
		{Name: "TUBE", ClosingQty: 0, MinQty: fp(4)},    // 100%
		{Name: "OIL", ClosingQty: 50, MinQty: fp(10)},   // fine
		{Name: "BELT", ClosingQty: 2, ReorderLevel: 6},  // 67%
		{Name: "axle", ClosingQty: 0, MinQty: fp(2)},    // 100%, sorts before TUBE by name
	})
	names := ""
	for _, a := range alerts {
		names += a.Name + ","
	}
	eq(t, names, "axle,TUBE,BELT,TYRE A,", "furthest below first, then name")
}

func TestStockSummary(t *testing.T) {
	v := int64(500)
	s := SummariseStock([]StockItem{{ClosingQty: 0}, {ClosingQty: 3, MinQty: fp(5), ClosingValue: &v}, {ClosingQty: 9}})
	eq(t, s.Items, 3, "items")
	eq(t, s.Value, int64(500), "value")
	eq(t, s.ByStatus[StockZero], 1, "zero")
	eq(t, s.ByStatus[StockLow], 1, "low")
	eq(t, s.ByStatus[StockInStock], 1, "in stock")
}
