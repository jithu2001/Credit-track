package appapi

import (
	"math"
	"testing"
	"time"
)

// The same cases as the app's former payment_analysis_test.dart.

func rs(r float64) int64 { return int64(math.Round(r * 100)) }

func d(s string) time.Time {
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		panic(err)
	}
	return t
}

func bill(date string, amount float64, voucher ...string) PaymentTxn {
	v := ""
	if len(voucher) > 0 {
		v = voucher[0]
	}
	return PaymentTxn{ShopID: "s", Date: d(date), Category: "sales", Debit: rs(amount), Voucher: v}
}

func pay(date string, amount float64) PaymentTxn {
	return PaymentTxn{ShopID: "s", Date: d(date), Category: "receipts", Credit: rs(amount)}
}

func ret(date string, amount float64) PaymentTxn {
	return PaymentTxn{ShopID: "s", Date: d(date), Category: "returns", Credit: rs(amount)}
}

func shopOf(opening, receivable float64) ShopOpening {
	return ShopOpening{ID: "s", Name: "Shop", Opening: rs(opening), Receivable: rs(receivable)}
}

type runOpts struct {
	opening, receivable float64
	days                int
	today               string
}

func run(txns []PaymentTxn, o runOpts) *ShopProfile {
	if o.days == 0 {
		o.days = 30
	}
	if o.today == "" {
		o.today = "2026-07-20"
	}
	return AnalyseShop(shopOf(o.opening, o.receivable), txns, o.days, d("2026-04-01"), d(o.today))
}

func near(t *testing.T, got *float64, want float64, what string) {
	t.Helper()
	if got == nil || math.Abs(*got-want) > 1e-9 {
		t.Fatalf("%s = %v, want %v", what, got, want)
	}
}

func eq[T comparable](t *testing.T, got, want T, what string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s = %v, want %v", what, got, want)
	}
}

func TestOldestBillFirst(t *testing.T) {
	// Bill A 1 Jun ₹10,000 (due 1 Jul), Bill B 15 Jun ₹8,000 (due 15 Jul), ₹12,000 paid 10 Jul.
	p := run([]PaymentTxn{bill("2026-06-01", 10000, "A"), bill("2026-06-15", 8000, "B"), pay("2026-07-10", 12000)}, runOpts{receivable: 6000})
	a, b := p.Bills[0], p.Bills[1]
	eq(t, a.IsOpen(), false, "A open")
	eq(t, *a.SettledOn, d("2026-07-10"), "A settled on")
	eq(t, a.SettledOnTime(), false, "A on time") // 9 days late
	eq(t, b.Remaining, rs(6000), "B remaining")
	eq(t, b.DaysOverdue(d("2026-07-20")), 5, "B days overdue")
	eq(t, p.Overdue(), rs(6000), "overdue")
	eq(t, p.MaxDaysOverdue(), 5, "max days overdue")
	near(t, p.OnTimeRate(), 0, "on-time rate")
	eq(t, p.Reconciled(), true, "reconciled")
	// ₹10,000 paid after 39 days, ₹2,000 after 25 days.
	near(t, p.AvgDaysToPay, (10000*39+2000*25)/12000.0, "avg days to pay")
	near(t, p.AvgDaysLate, (10000*9+2000*0)/12000.0, "avg days late")
	eq(t, *p.LastPaymentDate, d("2026-07-10"), "last payment")
}

func TestCreditDaysChangeWhatIsLate(t *testing.T) {
	txns := []PaymentTxn{bill("2026-06-01", 10000), pay("2026-07-10", 10000)}
	near(t, run(txns, runOpts{days: 30}).OnTimeRate(), 0, "30 days")
	near(t, run(txns, runOpts{days: 45}).OnTimeRate(), 1, "45 days")
}

func TestOpeningBalanceIsOldestBill(t *testing.T) {
	p := run([]PaymentTxn{bill("2026-05-01", 1000), pay("2026-05-10", 1500)}, runOpts{opening: 2000, receivable: 1500})
	eq(t, p.Bills[0].IsOpening, true, "opening bill")
	eq(t, p.Bills[0].Date, d("2026-04-01"), "opening date")
	eq(t, p.Bills[0].Remaining, rs(500), "opening remaining")
	eq(t, p.Bills[1].Remaining, rs(1000), "bill remaining")
	eq(t, p.Reconciled(), true, "reconciled")
}

func TestAdvancesUsedByLaterBills(t *testing.T) {
	p := run([]PaymentTxn{pay("2026-05-01", 300), bill("2026-05-20", 1000)}, runOpts{opening: -200, receivable: 500})
	if len(p.Bills) != 1 {
		t.Fatalf("bills = %d", len(p.Bills))
	}
	b := p.Bills[0]
	eq(t, b.Remaining, rs(500), "remaining")
	eq(t, len(b.Allocations), 2, "allocations")
	eq(t, b.Allocations[0].Kind, SettleAdjustment, "first allocation")
	eq(t, b.Allocations[1].Kind, SettlePayment, "second allocation")
	near(t, p.AvgDaysToPay, 0, "avg days to pay") // paid before the bill counts as same day
	eq(t, p.Advance, 0, "advance")
}

func TestReturnsSettleButDoNotPay(t *testing.T) {
	p := run([]PaymentTxn{bill("2026-06-01", 1000), ret("2026-06-05", 1000)}, runOpts{})
	eq(t, p.Bills[0].IsOpen(), false, "open")
	paid, _ := p.PaidBills()
	eq(t, paid, 0, "paid bills")
	eq(t, p.OnTimeRate() == nil, true, "on-time rate nil")
	eq(t, p.AvgDaysToPay == nil, true, "avg days nil")
}

func TestSameDayBillFirst(t *testing.T) {
	p := run([]PaymentTxn{pay("2026-06-01", 1000), bill("2026-06-01", 1000)}, runOpts{})
	eq(t, p.Bills[0].IsOpen(), false, "open")
	eq(t, len(p.Bills[0].Allocations), 1, "allocations")
	eq(t, p.Bills[0].Allocations[0].Kind, SettlePayment, "kind")
	eq(t, p.Advance, 0, "advance")
}

func TestAgeing(t *testing.T) {
	p := run([]PaymentTxn{bill("2026-07-10", 100), bill("2026-06-10", 200), bill("2026-05-10", 300), bill("2026-03-01", 400)}, runOpts{})
	a := p.Ageing()
	eq(t, a[AgeNotDue], rs(100), "not due") // due 9 Aug
	eq(t, a[Age1to30], rs(200), "1-30")     // due 10 Jul, 10 days late
	eq(t, a[Age31to60], rs(300), "31-60")   // due 9 Jun, 41 days late
	eq(t, a[Age90plus], rs(400), "90+")     // due 31 Mar
	eq(t, p.MaxDaysOverdue() > 60, true, "very late")
}

func TestBusinessSummary(t *testing.T) {
	s := AnalyseBusiness(
		[]ShopOpening{{ID: "a", Name: "A", Receivable: 100000}, {ID: "b", Name: "B"}, {ID: "c", Name: "Idle"}},
		[]PaymentTxn{
			{ShopID: "a", Date: d("2026-05-01"), Category: "sales", Debit: rs(1000)},
			{ShopID: "b", Date: d("2026-05-01"), Category: "sales", Debit: rs(500)},
			{ShopID: "b", Date: d("2026-05-11"), Category: "receipts", Credit: rs(500)},
		},
		30, d("2026-04-01"), d("2026-07-20"),
	)
	eq(t, len(s.Shops), 2, "shops (idle left out)")
	eq(t, s.Shops[0].Shop.ID+s.Shops[1].Shop.ID, "ab", "shop order")
	eq(t, s.Overdue, rs(1000), "overdue")
	eq(t, s.OverdueShops, 1, "overdue shops")
	near(t, s.OnTimeRate, 1, "on-time rate")
	near(t, s.AvgDaysToPay, 10, "avg days to pay")
}

func TestOverdueMonthAgo(t *testing.T) {
	txns := []PaymentTxn{bill("2026-05-01", 100), bill("2026-06-15", 50), pay("2026-07-10", 100)}
	shops := []ShopOpening{shopOf(0, 0)}
	// On 20 Jun the May bill was 50 days old and unpaid.
	ago := OverdueDaysAgo(shops, txns, 30, d("2026-04-01"), d("2026-07-20"), 30)
	if ago == nil || *ago != rs(100) {
		t.Fatalf("month ago = %v", ago)
	}
	// Today the payment has cleared it; the June bill is 35 days old.
	eq(t, AnalyseBusiness(shops, txns, 30, d("2026-04-01"), d("2026-07-20")).Overdue, rs(50), "overdue today")
	// Before the synced books begin there is nothing to compare with.
	if OverdueDaysAgo(shops, txns, 30, d("2026-04-01"), d("2026-04-20"), 30) != nil {
		t.Fatal("expected nil before the books begin")
	}
}
