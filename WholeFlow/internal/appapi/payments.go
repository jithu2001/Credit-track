package appapi

import (
	"sort"
	"time"
)

// Payment behaviour of shops (moved here from the app's payment_analysis.dart).
//
// Every credit (receipt, return, credit adjustment) settles the oldest open
// bill first (FIFO). A bill is due creditDays after its date. The shop's
// opening balance counts as one bill dated where the synced vouchers begin;
// a Cr opening balance is an advance. Credits that find no open bill wait as
// an advance and settle the next bills as they arrive.
//
// Only receipts count as paying for the timing figures (days to pay, on
// time); returns and adjustments still settle bills.
//
// Amounts are in paise; dates are calendar days (UTC midnight).

// PaymentTxn is one voucher line of a shop.
type PaymentTxn struct {
	ShopID    string
	Date      time.Time
	Category  string // sales, receipts, returns, adjustments
	Debit     int64
	Credit    int64
	Voucher   string
	CreatedAt *time.Time
}

// ShopOpening is a shop with its opening and synced balance (Dr positive).
type ShopOpening struct {
	ID         string
	Name       string
	SiteName   *string
	Phone      *string
	Opening    int64
	Receivable int64
}

type SettleKind string

const (
	SettlePayment    SettleKind = "payment"
	SettleReturned   SettleKind = "returned"
	SettleAdjustment SettleKind = "adjustment"
)

type Allocation struct {
	Date   time.Time
	Amount int64
	Kind   SettleKind
}

type Bill struct {
	Date        time.Time
	Amount      int64
	Due         time.Time
	Voucher     string
	IsOpening   bool
	Remaining   int64
	SettledOn   *time.Time
	Allocations []Allocation
}

func (b *Bill) IsOpen() bool { return b.Remaining > 0 }

func (b *Bill) PaidByReceipt() bool {
	for _, a := range b.Allocations {
		if a.Kind == SettlePayment {
			return true
		}
	}
	return false
}

func (b *Bill) SettledOnTime() bool { return b.SettledOn != nil && !b.SettledOn.After(b.Due) }

// DaysOverdue is the days past due on today (0 when not yet due).
func (b *Bill) DaysOverdue(today time.Time) int {
	if today.After(b.Due) {
		return days(b.Due, today)
	}
	return 0
}

// Age buckets of open amounts by days past due.
const (
	AgeNotDue = "not_due"
	Age1to30  = "d1_30"
	Age31to60 = "d31_60"
	Age61to90 = "d61_90"
	Age90plus = "d90_plus"
)

var ageBuckets = []string{AgeNotDue, Age1to30, Age31to60, Age61to90, Age90plus}

func ageBucket(daysOverdue int) string {
	switch {
	case daysOverdue <= 0:
		return AgeNotDue
	case daysOverdue <= 30:
		return Age1to30
	case daysOverdue <= 60:
		return Age31to60
	case daysOverdue <= 90:
		return Age61to90
	}
	return Age90plus
}

// ShopProfile is one shop's FIFO result.
type ShopProfile struct {
	Shop              ShopOpening
	Bills             []*Bill // oldest first
	Advance           int64
	Today             time.Time
	LastPaymentDate   *time.Time
	LastPaymentAmount int64
	AvgDaysToPay      *float64 // receipt-weighted days from bill to payment
	AvgDaysLate       *float64 // receipt-weighted days paid after due (early = 0)
	receiptsPaid      float64  // rupees paid by receipts, to weight business averages
}

func (p *ShopProfile) OpenAmount() int64 {
	var s int64
	for _, b := range p.Bills {
		s += b.Remaining
	}
	return s
}

func (p *ShopProfile) Overdue() int64 {
	var s int64
	for _, b := range p.Bills {
		if b.IsOpen() && b.DaysOverdue(p.Today) > 0 {
			s += b.Remaining
		}
	}
	return s
}

func (p *ShopProfile) MaxDaysOverdue() int {
	m := 0
	for _, b := range p.Bills {
		if b.IsOpen() && b.DaysOverdue(p.Today) > m {
			m = b.DaysOverdue(p.Today)
		}
	}
	return m
}

func (p *ShopProfile) OpenBills() int {
	n := 0
	for _, b := range p.Bills {
		if b.IsOpen() {
			n++
		}
	}
	return n
}

func (p *ShopProfile) OldestOpenBillDate() *time.Time {
	for _, b := range p.Bills {
		if b.IsOpen() {
			d := b.Date
			return &d
		}
	}
	return nil
}

func (p *ShopProfile) Ageing() map[string]int64 {
	out := map[string]int64{}
	for _, k := range ageBuckets {
		out[k] = 0
	}
	for _, b := range p.Bills {
		if b.IsOpen() {
			out[ageBucket(b.DaysOverdue(p.Today))] += b.Remaining
		}
	}
	return out
}

// PaidBills counts bills fully settled with at least one receipt, and of
// those how many were settled by their due date.
func (p *ShopProfile) PaidBills() (paid, onTime int) {
	for _, b := range p.Bills {
		if !b.IsOpen() && b.PaidByReceipt() {
			paid++
			if b.SettledOnTime() {
				onTime++
			}
		}
	}
	return
}

func (p *ShopProfile) OnTimeRate() *float64 {
	paid, onTime := p.PaidBills()
	if paid == 0 {
		return nil
	}
	r := float64(onTime) / float64(paid)
	return &r
}

// ComputedBalance is open bills minus advance; it equals the synced balance
// when the data is complete.
func (p *ShopProfile) ComputedBalance() int64 { return p.OpenAmount() - p.Advance }
func (p *ShopProfile) Reconciled() bool       { return p.ComputedBalance() == p.Shop.Receivable }
func (p *ShopProfile) HasActivity() bool      { return len(p.Bills) > 0 || p.Advance > 0 }

func day(t time.Time) time.Time { return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC) }

func days(from, to time.Time) int { return int(day(to).Sub(day(from)).Hours() / 24) }

func later(a, b time.Time) time.Time {
	if a.Before(b) {
		return b
	}
	return a
}

type credit struct {
	date   time.Time
	amount int64
	kind   SettleKind
}

// AnalyseShop runs FIFO for one shop.
func AnalyseShop(shop ShopOpening, txns []PaymentTxn, creditDays int, booksFrom, today time.Time) *ShopProfile {
	p := &ShopProfile{Shop: shop, Today: day(today)}
	var pool []credit // advances waiting for a bill, oldest first
	var paidWeighted, lateWeighted, paidTotal float64

	record := func(b *Bill, date time.Time, amount int64, kind SettleKind) {
		b.Allocations = append(b.Allocations, Allocation{date, amount, kind})
		b.Remaining -= amount
		if !b.IsOpen() {
			s := later(date, b.Date)
			b.SettledOn = &s
		}
		if kind == SettlePayment {
			paidOn := later(date, b.Date)
			rupees := float64(amount) / 100
			paidWeighted += rupees * float64(days(b.Date, paidOn))
			if late := days(b.Due, paidOn); late > 0 {
				lateWeighted += rupees * float64(late)
			}
			paidTotal += rupees
		}
	}
	addBill := func(b *Bill) {
		p.Bills = append(p.Bills, b)
		for b.IsOpen() && len(pool) > 0 {
			c := pool[0]
			use := min(c.amount, b.Remaining)
			record(b, c.date, use, c.kind)
			if left := c.amount - use; left > 0 {
				pool[0].amount = left
			} else {
				pool = pool[1:]
			}
		}
	}
	addCredit := func(date time.Time, amount int64, kind SettleKind) {
		left := amount
		for _, b := range p.Bills {
			if left <= 0 {
				break
			}
			if !b.IsOpen() {
				continue
			}
			use := min(left, b.Remaining)
			record(b, date, use, kind)
			left -= use
		}
		if left > 0 {
			pool = append(pool, credit{date, left, kind})
		}
	}

	start := day(booksFrom)
	switch {
	case shop.Opening > 0:
		addBill(&Bill{Date: start, Amount: shop.Opening, Remaining: shop.Opening,
			Due: start.AddDate(0, 0, creditDays), IsOpening: true, Voucher: "Opening balance"})
	case shop.Opening < 0:
		pool = append(pool, credit{start, -shop.Opening, SettleAdjustment})
	}

	// Same day: bills before credits, so a same-day payment can settle that day's bill.
	ordered := append([]PaymentTxn(nil), txns...)
	sort.SliceStable(ordered, func(i, j int) bool {
		a, b := ordered[i], ordered[j]
		if d := day(a.Date).Compare(day(b.Date)); d != 0 {
			return d < 0
		}
		ab, bb := billFirst(a), billFirst(b)
		if ab != bb {
			return ab < bb
		}
		if a.CreatedAt != nil && b.CreatedAt != nil {
			return a.CreatedAt.Before(*b.CreatedAt)
		}
		return false
	})

	for _, t := range ordered {
		date := day(t.Date)
		if t.Debit > 0 {
			addBill(&Bill{Date: date, Amount: t.Debit, Remaining: t.Debit,
				Due: date.AddDate(0, 0, creditDays), Voucher: t.Voucher})
		}
		if t.Credit > 0 {
			kind := SettleAdjustment
			switch t.Category {
			case "receipts":
				kind = SettlePayment
			case "returns":
				kind = SettleReturned
			}
			if kind == SettlePayment {
				d := date
				p.LastPaymentDate = &d
				p.LastPaymentAmount = t.Credit
			}
			addCredit(date, t.Credit, kind)
		}
	}

	for _, c := range pool {
		p.Advance += c.amount
	}
	if paidTotal > 0 {
		toPay, late := paidWeighted/paidTotal, lateWeighted/paidTotal
		p.AvgDaysToPay, p.AvgDaysLate = &toPay, &late
	}
	p.receiptsPaid = paidTotal
	return p
}

func billFirst(t PaymentTxn) int {
	if t.Debit > 0 {
		return 0
	}
	return 1
}

// BusinessSummary is FIFO over every shop of a company, with totals.
type BusinessSummary struct {
	Shops        []*ShopProfile // shops with any bill or advance
	CreditDays   int
	Today        time.Time
	Overdue      int64
	OverdueShops int
	OpenAmount   int64
	Ageing       map[string]int64
	OnTimeRate   *float64
	AvgDaysToPay *float64
}

// AnalyseBusiness runs FIFO for every shop and totals the results.
func AnalyseBusiness(shops []ShopOpening, txns []PaymentTxn, creditDays int, booksFrom, today time.Time) *BusinessSummary {
	byShop := map[string][]PaymentTxn{}
	for _, t := range txns {
		byShop[t.ShopID] = append(byShop[t.ShopID], t)
	}
	s := &BusinessSummary{CreditDays: creditDays, Today: day(today), Ageing: map[string]int64{}}
	for _, k := range ageBuckets {
		s.Ageing[k] = 0
	}
	var paid, onTime int
	var weighted, total float64
	for _, shop := range shops {
		p := AnalyseShop(shop, byShop[shop.ID], creditDays, booksFrom, today)
		if !p.HasActivity() {
			continue
		}
		s.Shops = append(s.Shops, p)
		o := p.Overdue()
		s.Overdue += o
		if o > 0 {
			s.OverdueShops++
		}
		s.OpenAmount += p.OpenAmount()
		for k, v := range p.Ageing() {
			s.Ageing[k] += v
		}
		pb, ot := p.PaidBills()
		paid += pb
		onTime += ot
		if p.AvgDaysToPay != nil {
			// Weight each shop's average by the receipts it made.
			weighted += *p.AvgDaysToPay * p.receiptsPaid
			total += p.receiptsPaid
		}
	}
	if paid > 0 {
		r := float64(onTime) / float64(paid)
		s.OnTimeRate = &r
	}
	if total > 0 {
		a := weighted / total
		s.AvgDaysToPay = &a
	}
	return s
}

// OverdueDaysAgo is the overdue as it stood daysAgo before today, from the
// vouchers dated up to then; nil when the synced books don't reach back that far.
func OverdueDaysAgo(shops []ShopOpening, txns []PaymentTxn, creditDays int, booksFrom, today time.Time, daysAgo int) *int64 {
	then := day(today).AddDate(0, 0, -daysAgo)
	if then.Before(day(booksFrom)) {
		return nil
	}
	var earlier []PaymentTxn
	for _, t := range txns {
		if !day(t.Date).After(then) {
			earlier = append(earlier, t)
		}
	}
	o := AnalyseBusiness(shops, earlier, creditDays, booksFrom, then).Overdue
	return &o
}
