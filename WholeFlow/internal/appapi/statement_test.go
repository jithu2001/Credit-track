package appapi

import "testing"

// The same cases as the app's former statement tests (domain_test.dart,
// customer_statement_test.dart).

func stx(id, date string, paise int64) StatementTxn {
	t := StatementTxn{ID: id, Date: d(date), Amount: paise, Category: "sales"}
	if paise > 0 {
		t.Debit = paise
	} else {
		t.Credit, t.Category = -paise, "receipts"
	}
	return t
}

func ids(lines []StatementLine) string {
	out := ""
	for _, l := range lines {
		out += l.Txn.ID
	}
	return out
}

func TestStatementRunningBalance(t *testing.T) {
	txns := []StatementTxn{stx("r", "2026-04-10", -30000), stx("a", "2026-04-01", 50000), stx("b", "2026-04-20", 20000)}
	s := BuildStatement(10000, 50000, txns)
	eq(t, ids(s.Lines), "arb", "oldest first")
	eq(t, s.Lines[0].BalanceAfter, 60000, "after a")
	eq(t, s.Lines[1].BalanceAfter, 30000, "after r")
	eq(t, s.Lines[2].BalanceAfter, 50000, "after b")
	eq(t, s.Reconciled(), true, "reconciled")
	eq(t, BuildStatement(10000, 55000, txns).Reconciled(), false, "mismatch flagged")
}

func TestPeriodStatement(t *testing.T) {
	// Opening 100; +500 (1 Mar), -300 (10 Apr), +200 (20 Apr), -50 (5 May).
	s := BuildStatement(10000, 45000, []StatementTxn{
		stx("a", "2026-03-01", 50000), stx("b", "2026-04-10", -30000), stx("c", "2026-04-20", 20000), stx("d", "2026-05-05", -5000),
	})
	from, to := d("2026-04-01"), d("2026-04-30")
	p := s.Period(&from, &to)
	eq(t, p.Opening, 60000, "brought forward")
	eq(t, ids(p.Lines), "bc", "April only")
	eq(t, p.Closing, 50000, "closing")
	eq(t, p.TotalDebit, 20000, "debits")
	eq(t, p.TotalCredit, 30000, "credits")

	all := s.Period(nil, nil)
	eq(t, all.Opening, 10000, "whole ledger opening")
	eq(t, len(all.Lines), 4, "whole ledger lines")
	eq(t, all.Closing, 45000, "whole ledger closing")

	jf, jt := d("2026-06-01"), d("2026-06-30")
	empty := s.Period(&jf, &jt)
	eq(t, len(empty.Lines), 0, "no vouchers")
	eq(t, empty.Opening, 45000, "empty opening")
	eq(t, empty.Closing, 45000, "empty closing")

	// Both ends included, whatever the time of day.
	f, e := d("2026-04-10").Add(18*3600e9), d("2026-04-20").Add(9*3600e9)
	eq(t, ids(s.Period(&f, &e).Lines), "bc", "ends included")
}
