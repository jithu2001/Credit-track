package syncer

import (
	"strings"
	"testing"
	"time"
)

// A ledger that becomes a shop later (moved into Sundry Debtors) gets its old
// vouchers (AlterIDs below the cursor) with the day's full read, not at once:
// re-reading every voucher would stop TallyPrime responding at a busy time.
func TestNewShopGetsHistory(t *testing.T) {
	c := sampleCompany("C1", "JMJ")
	c.Ledgers = append(c.Ledgers, fakeLedger{Name: "SHOP FOUR", GUID: "C1-L4", Parent: "Suspense", Closing: "-700.00"})
	c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: "C1-V9", AlterID: 106, Date: "20260406", Type: "B2c Gst Sales", Number: "CB/9",
		Entries: []fakeEntry{{"SHOP FOUR", "-700.00"}, {"Sales@18%", "700.00"}}})
	h := newHarness(t, c)
	h.run()
	if got := h.store.Transactions("C1-V9"); len(got) != 0 {
		t.Fatalf("not a shop yet, must not be synced: %+v", got)
	}
	h.fake.edit(func() { c.Ledgers[len(c.Ledgers)-1].Parent = "Sundry Debtors" })
	cr := h.run().Companies[0]
	if cr.Mode != "incremental" || cr.Shops.Created != 1 {
		t.Fatalf("a new shop must not force a full read: mode %s shops %+v", cr.Mode, cr.Shops)
	}
	if got := h.store.Transactions("C1-V9"); len(got) != 0 {
		t.Fatalf("old voucher read before the day's full read: %+v", got)
	}
	h.clock = h.clock.Add(24 * time.Hour) // the next day's window
	if cr = h.run().Companies[0]; cr.Mode != "reconcile" {
		t.Fatalf("next day: mode %s, want reconcile", cr.Mode)
	}
	if got := h.store.Transactions("C1-V9"); len(got) != 1 || got[0].Amount != 700 {
		t.Fatalf("old voucher of the new shop missing: %+v", got)
	}
}

// If Tally suddenly returns no shops (group renamed, SHOP_GROUPS typo), the
// cloud shops and their transactions are kept and a warning is shown.
func TestEmptyTallyReadDoesNotWipeCloud(t *testing.T) {
	c := sampleCompany("C1", "JMJ")
	h := newHarness(t, c)
	h.run()
	before := h.store.Counts()
	h.fake.edit(func() {
		for i := range c.Ledgers {
			if c.Ledgers[i].Parent == "Sundry Debtors" {
				c.Ledgers[i].Parent = "Sundry Debtors (old)"
			}
		}
	})
	res := h.run()
	cr := res.Companies[0]
	after := h.store.Counts()
	if after.Shops != before.Shops || after.ShopsDeleted != 0 {
		t.Fatalf("shops were deleted: before %+v after %+v", before, after)
	}
	if len(cr.Warnings) == 0 || !strings.Contains(cr.Warnings[0], "safety check") {
		t.Fatalf("expected a safety-check warning, got %v", cr.Warnings)
	}
	t.Setenv("SYNC_ALLOW_MASS_DELETE", "true")
	h.run()
	if got := h.store.Counts(); got.Shops != 0 || got.ShopsDeleted != before.Shops {
		t.Fatalf("with the override the deletions must go through: %+v", got)
	}
}
