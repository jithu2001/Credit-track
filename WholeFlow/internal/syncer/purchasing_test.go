package syncer

import (
	"context"
	"strings"
	"testing"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/memory"
)

// purchasingCompany is sampleCompany plus a supplier, two stock items and
// purchase bills (one from a party outside Sundry Creditors).
func purchasingCompany(guid, name string) *fakeCompany {
	c := sampleCompany(guid, name)
	c.Ledgers = append(c.Ledgers,
		fakeLedger{Name: "CEAT LIMITED", GUID: guid + "-SUP1", Parent: "Sundry Creditors", Opening: "0", Closing: "1180.00"},
		fakeLedger{Name: "LAVA LTD", GUID: guid + "-SUP2", Parent: "Sundry Creditors", Closing: "-500.00"},
	)
	c.Stock = []fakeStock{
		{Name: "TYRE A", GUID: guid + "-I1", Group: "Car", Qty: " 6 Nos", Value: "-600.00", Rate: "100.00/Nos"},
		{Name: "TYRE B", GUID: guid + "-I2", Group: "Scooter", Qty: "-2 Nos", Value: "200.00", Rate: "100.00/Nos"},
	}
	c.Vouchers = append(c.Vouchers,
		fakeVoucher{GUID: guid + "-P1", AlterID: 110, Date: "20260410", Type: "Purchase Tcs", Number: "935/1", Party: "CEAT LIMITED",
			Entries: []fakeEntry{{"CEAT LIMITED", "1180.00"}, {"Purchase@18%", "-1000.00"}, {"IGST", "-180.00"}},
			Items:   []fakeItem{{"TYRE A", " 6 Nos", "100.00/Nos", "-600.00"}, {"TYRE B", " 4 Nos", "100.00/Nos", "-400.00"}}},
		fakeVoucher{GUID: guid + "-P2", AlterID: 111, Date: "20260411", Type: "Purchase", Number: "P/2", Party: "MIDLAND TREADS",
			Entries: []fakeEntry{{"MIDLAND TREADS", "7600.00"}, {"Purchase@18%", "-7600.00"}},
			Items:   []fakeItem{{"TYRE C", " 1 Nos", "7600.00/Nos", "-7600.00"}}},
	)
	return c
}

func enablePurchasing(h *harness, on bool) {
	h.set.Update(func(s *Settings) error {
		s.Sync.Suppliers, s.Sync.Purchases, s.Sync.Inventory = on, on, on
		return nil
	})
}

func TestPurchasingSync(t *testing.T) {
	c := purchasingCompany("C1", "JMJ Marketing")
	h := newHarness(t, c)
	enablePurchasing(h, true)

	// 1. first run: everything full
	res := h.run()
	if res.Status != "success" {
		t.Fatalf("run 1: %s", res)
	}
	cr := res.Companies[0]
	if cr.Status != StatusSynced || len(cr.Warnings) != 0 {
		t.Fatalf("run 1 company: %+v", cr)
	}
	if cr.Suppliers == nil || cr.Suppliers.Fetched != 2 || cr.StockItems == nil || cr.StockItems.Fetched != 2 ||
		cr.Purchases == nil || cr.Purchases.Created != 2 || cr.PurchaseMode != "full" {
		t.Fatalf("run 1 stats: suppliers %+v items %+v purchases %+v mode %s", cr.Suppliers, cr.StockItems, cr.Purchases, cr.PurchaseMode)
	}
	counts := h.store.PurchasingCounts()
	if counts.Suppliers != 2 || counts.StockItems != 2 || counts.Purchases != 2 || counts.PurchaseLines != 3 {
		t.Fatalf("cloud counts after run 1: %+v", counts)
	}
	p1, ok := h.store.Purchase("C1-P1")
	if !ok || p1.SupplierID == "" || p1.Total != 1180 || p1.Taxable != 1000 || p1.Other != 180 || len(p1.LedgerEntries) != 2 {
		t.Fatalf("bill P1: %+v", p1)
	}
	if p1.Lines[0].LineNo != 1 || p1.Lines[0].StockItemID == "" || p1.Lines[0].Qty != 6 || p1.Lines[1].ItemName != "TYRE B" {
		t.Fatalf("bill P1 lines: %+v", p1.Lines)
	}
	p2, _ := h.store.Purchase("C1-P2")
	if p2.SupplierID != "" || p2.SupplierName != "MIDLAND TREADS" || p2.Lines[0].StockItemID != "" {
		t.Fatalf("bill from a non-supplier party must keep names only: %+v", p2)
	}
	if it, _ := h.store.StockItem("C1-I2"); it.Status != "negative" || it.ClosingValue != -200 {
		t.Fatalf("stock item: %+v", it)
	}
	st := h.state.Company("C1")
	if st.PurchaseCursor != 111 || st.PurchaseCount != 2 || st.SupplierCount != 2 || st.StockItemCount != 2 || st.LastPurchaseReconcileAt == nil {
		t.Fatalf("local state after run 1: %+v", st)
	}
	if s, ok := h.store.State(cr.CloudID, cloud.EntityPurchases); !ok || s.LastCursor != "111" || s.Status != "ok" {
		t.Fatalf("cloud sync_state purchases: %+v", s)
	}

	// 2. incremental: one new bill, one bill cancelled; only those are fetched
	h.fake.edit(func() {
		c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: "C1-P3", AlterID: 112, Date: "20260412", Type: "Purchase", Number: "P/3",
			Party: "LAVA LTD", Entries: []fakeEntry{{"LAVA LTD", "50.00"}, {"Purchase@18%", "-50.00"}},
			Items: []fakeItem{{"TYRE A", " 1 Nos", "50.00/Nos", "-50.00"}}})
		for i := range c.Vouchers {
			if c.Vouchers[i].GUID == "C1-P2" {
				c.Vouchers[i].Cancelled, c.Vouchers[i].AlterID = true, 113
			}
		}
	})
	res = h.run()
	cr = res.Companies[0]
	if cr.PurchaseMode != "incremental" || cr.Purchases.Fetched != 1 || cr.Purchases.Created != 1 || cr.Purchases.Deleted != 1 {
		t.Fatalf("run 2 purchases: %+v mode %s", cr.Purchases, cr.PurchaseMode)
	}
	if _, ok := h.store.Purchase("C1-P2"); ok {
		t.Fatal("cancelled bill still active in the cloud")
	}
	if st := h.state.Company("C1"); st.PurchaseCursor != 113 || st.PurchaseCount != 2 {
		t.Fatalf("local state after run 2: %+v", st)
	}

	// 3. a bill deleted in Tally disappears at the next reconcile (after FullReconcileHours)
	h.fake.edit(func() {
		var keep []fakeVoucher
		for _, v := range c.Vouchers {
			if v.GUID != "C1-P1" {
				keep = append(keep, v)
			}
		}
		c.Vouchers = keep
	})
	if res = h.run(); res.Companies[0].PurchaseMode != "incremental" || res.Companies[0].Purchases.Deleted != 0 {
		t.Fatalf("run 3 should be incremental and not notice the deletion yet: %+v", res.Companies[0])
	}
	h.clock = h.clock.Add(25 * time.Hour)
	res = h.run()
	cr = res.Companies[0]
	if cr.PurchaseMode != "reconcile" || cr.Purchases.Deleted != 1 {
		t.Fatalf("run 4 reconcile: %+v mode %s", cr.Purchases, cr.PurchaseMode)
	}
	if got := h.store.PurchasingCounts(); got.Purchases != 1 || got.PurchasesDeleted != 2 {
		t.Fatalf("cloud counts after reconcile: %+v", got)
	}

	// 4. a stock item deleted in Tally is soft-deleted on the next run
	h.fake.edit(func() { c.Stock = c.Stock[:1] })
	if cr = h.run().Companies[0]; cr.StockItems.Deleted != 1 {
		t.Fatalf("stock item deletion: %+v", cr.StockItems)
	}
}

// A failing purchasing step (e.g. migration 0003 not applied) must not stop
// shops and transactions: the company is SYNCED with a warning.
func TestPurchasingFailureIsAWarning(t *testing.T) {
	h := newHarness(t, purchasingCompany("C1", "JMJ Marketing"))
	enablePurchasing(h, true)
	h.store.FailOn["UpsertPurchases"] = &cloud.Error{Kind: cloud.KindNotFound, Op: "upsert-purchases",
		Msg: "HTTP 404: PGRST205 Could not find the table 'public.purchases' in the schema cache"}

	res := h.run()
	cr := res.Companies[0]
	if res.Status != "success" || cr.Status != StatusSynced {
		t.Fatalf("company must still be synced: %s", res)
	}
	if cr.Purchases != nil || len(cr.Warnings) != 1 || !strings.HasPrefix(cr.Warnings[0], "purchases: CLOUD_NOT_FOUND") {
		t.Fatalf("expected one purchases warning: %+v", cr.Warnings)
	}
	if cr.Suppliers == nil || cr.StockItems == nil || h.store.Counts().Shops != 3 {
		t.Fatalf("other steps must still run: suppliers %+v items %+v counts %+v", cr.Suppliers, cr.StockItems, h.store.Counts())
	}
	st := h.state.Company("C1")
	if st.PurchaseCursor != 0 || len(st.Warnings) != 1 {
		t.Fatalf("cursor must not advance after a failed step: %+v", st)
	}
	if s, ok := h.store.State(cr.CloudID, cloud.EntityPurchases); !ok || s.Status != "error" {
		t.Fatalf("cloud sync_state must record the error: %+v", s)
	}
	if l := h.store.Logs[len(h.store.Logs)-1]; l.Status != "success" || l.ErrorCode != "STEP_WARNINGS" {
		t.Fatalf("sync log: %+v", l)
	}
	if !strings.Contains(res.String(), "warning: purchases") {
		t.Fatalf("run summary lacks the warning:\n%s", res)
	}

	// Once the table exists the next run is a full purchase sync.
	delete(h.store.FailOn, "UpsertPurchases")
	cr = h.run().Companies[0]
	if cr.PurchaseMode != "full" || cr.Purchases == nil || cr.Purchases.Created != 2 || len(cr.Warnings) != 0 {
		t.Fatalf("recovery run: %+v mode %s warnings %v", cr.Purchases, cr.PurchaseMode, cr.Warnings)
	}
}

func TestPurchasingOff(t *testing.T) {
	h := newHarness(t, purchasingCompany("C1", "JMJ Marketing"))
	enablePurchasing(h, false)
	cr := h.run().Companies[0]
	if cr.Suppliers != nil || cr.StockItems != nil || cr.Purchases != nil {
		t.Fatalf("steps ran although switched off: %+v", cr)
	}
	if h.fake.count("stock-items") != 0 || h.fake.count("purchases") != 0 {
		t.Fatal("Tally was asked for stock or purchases although switched off")
	}
	for _, op := range []string{"UpsertSuppliers", "UpsertStockItems", "UpsertPurchases"} {
		if h.store.Calls[op] != 0 {
			t.Fatalf("%s called although switched off", op)
		}
	}
}

// Config files written before the options existed get them switched on;
// an explicit false is kept.
func TestNewSyncOptionsDefaultOn(t *testing.T) {
	s := Settings{}
	defaultNewSyncOptions([]byte(`{"sync":{"enabled":true,"transactions":true}}`), &s)
	if !s.Sync.Suppliers || !s.Sync.Purchases || !s.Sync.Inventory {
		t.Fatalf("absent options must default to on: %+v", s.Sync)
	}
	s = Settings{}
	defaultNewSyncOptions([]byte(`{"sync":{"suppliers":false,"purchases":false,"inventory":false}}`), &s)
	if s.Sync.Suppliers || s.Sync.Purchases || s.Sync.Inventory {
		t.Fatalf("explicit false must be kept: %+v", s.Sync)
	}
}

// Switching to another business (or wiping the cloud) gives the company a new
// cloud id; the next run must be full, not incremental from the old cursor.
func TestNewCloudCompanyResetsCursors(t *testing.T) {
	h := newHarness(t, purchasingCompany("C1", "JMJ Marketing"))
	enablePurchasing(h, true)
	if cr := h.run().Companies[0]; cr.Mode != "full" || cr.Transactions.Created == 0 {
		t.Fatalf("run 1: %+v", cr)
	}
	if cr := h.run().Companies[0]; cr.Mode != "incremental" || cr.Transactions.Fetched != 0 {
		t.Fatalf("run 2 should be incremental with nothing new: %+v", cr)
	}

	// New business: fresh cloud store, same local state.
	const bizB = "22222222-2222-2222-2222-222222222222"
	h.store = memory.New(bizB)
	h.store.UpsertCompany(context.Background(), cloud.Company{BusinessID: bizB, TallyCompanyID: "other"}) // ids differ from the old store, as UUIDs would
	h.set.Update(func(s *Settings) error { s.Business.ID = bizB; return nil })
	cr := h.run().Companies[0]
	if cr.Mode != "full" || cr.PurchaseMode != "full" || cr.Transactions.Created == 0 || cr.Purchases.Created != 2 {
		t.Fatalf("run for the new business must be full: mode %s/%s txns %+v purchases %+v", cr.Mode, cr.PurchaseMode, cr.Transactions, cr.Purchases)
	}
	if got := h.store.Counts(); got.Transactions != cr.Transactions.Created {
		t.Fatalf("new business cloud must hold every transaction: %+v", got)
	}
}
