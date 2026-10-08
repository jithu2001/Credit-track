package appapi

import (
	"sort"
	"time"
)

// A shop's statement (moved here from the app's statement.dart): running
// balances from the opening balance, a check that they add up to the synced
// Tally balance, and a period view for the customer statement.

// StatementTxn is one active voucher line of a shop.
type StatementTxn struct {
	ID            string
	Date          time.Time
	VoucherType   *string
	VoucherNumber *string
	Category      string
	Narration     *string
	Debit         int64 // paise
	Credit        int64
	Amount        int64 // signed effect on the balance: debit - credit
	CreatedAt     *time.Time
}

// StatementLine is a voucher with the shop's balance after it (Dr positive).
type StatementLine struct {
	Txn          StatementTxn
	BalanceAfter int64
}

// Statement is the whole ledger of a shop, oldest first.
type Statement struct {
	Opening         int64 // the shop's opening balance in Tally
	Closing         int64 // the synced Tally balance (shops.receivable)
	ComputedClosing int64 // opening + every voucher
	Lines           []StatementLine
}

func (s *Statement) Reconciled() bool { return s.ComputedClosing == s.Closing }

// BuildStatement orders txns by date, then when they were synced, then
// voucher number (stable for the rest), and runs the balance from opening.
func BuildStatement(opening, closing int64, txns []StatementTxn) *Statement {
	ordered := append([]StatementTxn(nil), txns...)
	sort.SliceStable(ordered, func(i, j int) bool {
		a, b := ordered[i], ordered[j]
		if c := day(a.Date).Compare(day(b.Date)); c != 0 {
			return c < 0
		}
		if a.CreatedAt != nil && b.CreatedAt != nil && !a.CreatedAt.Equal(*b.CreatedAt) {
			return a.CreatedAt.Before(*b.CreatedAt)
		}
		return str(a.VoucherNumber) < str(b.VoucherNumber)
	})
	s := &Statement{Opening: opening, Closing: closing}
	running := opening
	for _, t := range ordered {
		running += t.Amount
		s.Lines = append(s.Lines, StatementLine{t, running})
	}
	s.ComputedClosing = running
	return s
}

func str(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// PeriodStatement is the statement between two days as sent to a customer:
// the balance brought forward, the period's lines (oldest first) and the
// balance at the end. From/To nil = from the first voucher / up to the last.
type PeriodStatement struct {
	From, To    *time.Time
	Opening     int64
	Lines       []StatementLine
	Closing     int64
	TotalDebit  int64
	TotalCredit int64
}

// Period cuts s to the calendar days from–to (both included).
func (s *Statement) Period(from, to *time.Time) *PeriodStatement {
	p := &PeriodStatement{Opening: s.Opening}
	if from != nil {
		f := day(*from)
		p.From = &f
	}
	if to != nil {
		t := day(*to)
		p.To = &t
	}
	for _, l := range s.Lines {
		d := day(l.Txn.Date)
		switch {
		case p.From != nil && d.Before(*p.From):
			p.Opening = l.BalanceAfter
		case p.To == nil || !d.After(*p.To):
			p.Lines = append(p.Lines, l)
			p.TotalDebit += l.Txn.Debit
			p.TotalCredit += l.Txn.Credit
		}
	}
	p.Closing = p.Opening
	if n := len(p.Lines); n > 0 {
		p.Closing = p.Lines[n-1].BalanceAfter
	}
	return p
}
