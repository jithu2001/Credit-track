package syncer

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"testing"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/memory"
	"wholeflow/internal/secrets"
	"wholeflow/internal/tally"
)

const bizA = "11111111-1111-1111-1111-111111111111"

type harness struct {
	t      *testing.T
	fake   *fakeTally
	store  *memory.Store
	engine *Engine
	set    *SettingsStore
	state  *StateStore
	clock  time.Time
}

func newHarness(t *testing.T, companies ...*fakeCompany) *harness {
	t.Helper()
	fake := newFakeTally(t)
	fake.companies = companies
	h := &harness{t: t, fake: fake, store: memory.New(bizA), clock: time.Date(2026, 9, 27, 10, 0, 0, 0, time.UTC)}
	h.set, h.state = newStores(t)
	h.set.Update(func(s *Settings) error {
		s.Business = BusinessSettings{ID: bizA, Name: "JMJ Marketing"}
		s.Cloud.Provider = ProviderMemory
		s.Sync = SyncSettings{Enabled: true, IntervalSeconds: 300, Transactions: true, FullReconcileHours: 24}
		for _, c := range companies {
			s.Companies = append(s.Companies, CompanySetting{TallyID: c.GUID, Name: c.Name, Enabled: true})
		}
		return nil
	})
	h.engine = h.newEngine(fake.service(t, 2*time.Second))
	return h
}

func (h *harness) newEngine(svc *tally.Service) *Engine {
	return &Engine{Tally: svc, Provider: func(Settings) (cloud.Provider, error) { return h.store, nil },
		Settings: h.set, State: h.state, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		TallyHost: "localhost", TallyPort: 9000, Hostname: "TEST-PC", Now: func() time.Time { return h.clock }}
}

func newStores(t *testing.T) (*SettingsStore, *StateStore) {
	t.Helper()
	dir := t.TempDir()
	set, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	st, err := LoadState(dir)
	if err != nil {
		t.Fatal(err)
	}
	return set, st
}

func (h *harness) run() *RunResult {
	h.clock = h.clock.Add(time.Minute)
	return h.engine.Run(context.Background())
}

func (h *harness) enable(guid string, on bool) {
	h.set.Update(func(s *Settings) error {
		for i := range s.Companies {
			if s.Companies[i].TallyID == guid {
				s.Companies[i].Enabled = on
			}
		}
		return nil
	})
}

func mustStatus(t *testing.T, res *RunResult, want string) {
	t.Helper()
	if res.Status != want {
		t.Fatalf("run status = %s (%s: %s); want %s\n%s", res.Status, res.ErrorCode, res.ErrorMessage, want, res)
	}
}

func mustCounts(t *testing.T, store *memory.Store, shops, txns int) {
	t.Helper()
	c := store.Counts()
	if c.Shops != shops || c.Transactions != txns {
		t.Fatalf("cloud has %d shops / %d transactions; want %d / %d (deleted: %d / %d)", c.Shops, c.Transactions, shops, txns, c.ShopsDeleted, c.TransactionsDeleted)
	}
}

// ---------------------------------------------------------------- happy path

func TestSuccessfulSync(t *testing.T) {
	h := newHarness(t, sampleCompany("C1", "JMJ Marketing - (FY 2024-25)"))
	res := h.run()
	mustStatus(t, res, "success")
	cr := res.Companies[0]
	if cr.Status != StatusSynced || cr.Mode != "full" {
		t.Fatalf("company result: %+v", cr)
	}
	// 3 shops (non-shop ledgers ignored); 4 live vouchers → 5 (voucher, shop) rows; cancelled voucher excluded
	if cr.Shops.Fetched != 3 || cr.Shops.Created != 3 || cr.Transactions.Fetched != 5 || cr.Transactions.Created != 5 || cr.Excluded != 1 {
		t.Fatalf("stats: %+v", cr)
	}
	mustCounts(t, h.store, 3, 5)

	shop, ok := h.store.Shop("C1-L1")
	if !ok || shop.BusinessID != bizA || shop.BalanceAmount != 45000 || shop.BalanceType != "DR" || shop.Receivable != 45000 ||
		shop.OpeningAmount != 100 || shop.Area != "Pala" || shop.Phone != "9876543210" {
		t.Fatalf("shop: %+v", shop)
	}
	txns := h.store.Transactions("C1-V1")
	if len(txns) != 1 || txns[0].Debit != 6724 || txns[0].Credit != 0 || txns[0].Amount != 6724 || txns[0].Category != tally.CatSales ||
		txns[0].BaseVoucherType != "Sales" || txns[0].ShopID == "" || txns[0].Date != "2026-04-01" {
		t.Fatalf("sales txn: %+v", txns)
	}
	rcpt := h.store.Transactions("C1-V2")
	if len(rcpt) != 1 || rcpt[0].Credit != 5000 || rcpt[0].Amount != -5000 || rcpt[0].Category != tally.CatReceipts {
		t.Fatalf("receipt txn: %+v", rcpt)
	}
	if j := h.store.Transactions("C1-V4"); len(j) != 2 {
		t.Fatalf("journal touching two shops should give two rows, got %d", len(j))
	}
	cmp, _ := h.store.Company("C1")
	if cmp.SyncStatus != StatusSynced || cmp.LastSyncAt == nil || cmp.BooksFrom != "2024-04-01" {
		t.Fatalf("company: %+v", cmp)
	}
	st := h.state.Company("C1")
	if st.Status != StatusSynced || st.VoucherCursor != 105 || st.ShopCount != 3 || st.TransactionCount != 5 || st.LastSuccessAt == nil {
		t.Fatalf("local state: %+v", st)
	}
	if cs, ok := h.store.State(cr.CloudID, cloud.EntityTransactions); !ok || cs.LastCursor != "105" || cs.Status != "ok" {
		t.Fatalf("cloud sync state: %+v", cs)
	}
	if len(h.store.Logs) != 1 || h.store.Logs[0].Status != "success" || h.store.Logs[0].RecordsCreated != 8 {
		t.Fatalf("sync log: %+v", h.store.Logs)
	}
}

func TestIdempotentRepeatedSync(t *testing.T) {
	h := newHarness(t, sampleCompany("C1", "Co"))
	for i := 0; i < 3; i++ {
		res := h.run()
		mustStatus(t, res, "success")
		mustCounts(t, h.store, 3, 5)
		cr := res.Companies[0]
		if i > 0 && (cr.Mode != "incremental" || cr.Transactions.Fetched != 0 || cr.Shops.Created != 0 || cr.Shops.Updated != 3) {
			t.Fatalf("run %d should be a no-op incremental: %+v", i, cr)
		}
	}
	if n := h.fake.count("vouchers"); n != 3 {
		t.Fatalf("voucher fetches = %d; want 3 (one per run, incremental after the first)", n)
	}
}

func TestIncrementalNewAlteredAndDeletedVouchers(t *testing.T) {
	h := newHarness(t, sampleCompany("C1", "Co"))
	mustStatus(t, h.run(), "success")

	// New voucher and an altered one (amount changed, AlterID bumped).
	c := h.fake.company("C1")
	h.fake.edit(func() {
		c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: "C1-V6", AlterID: 106, Date: "20260501", Type: "B2c Gst Sales", Number: "CB/3",
			Entries: []fakeEntry{{"SHOP THREE", "-1500.00"}, {"Sales@18%", "1500.00"}}})
		c.Vouchers[0].AlterID = 107
		c.Vouchers[0].Entries[0].Amount = "-7000.00"
	})
	res := h.run()
	mustStatus(t, res, "success")
	cr := res.Companies[0]
	if cr.Mode != "incremental" || cr.Vouchers != 2 || cr.Transactions.Created != 1 || cr.Transactions.Updated != 1 || cr.Transactions.Deleted != 0 {
		t.Fatalf("incremental stats: %+v", cr)
	}
	mustCounts(t, h.store, 3, 6)
	if v1 := h.store.Transactions("C1-V1"); v1[0].Debit != 7000 {
		t.Fatalf("altered voucher not updated: %+v", v1)
	}
	if h.state.Company("C1").VoucherCursor != 107 {
		t.Fatalf("cursor = %d", h.state.Company("C1").VoucherCursor)
	}

	// Alter a voucher so it no longer touches a shop: its row must go.
	h.fake.edit(func() {
		c.Vouchers[1].AlterID = 108
		c.Vouchers[1].Entries = []fakeEntry{{"Cash", "-5000.00"}, {"Sales@18%", "5000.00"}}
	})
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Transactions.Deleted != 1 {
		t.Fatalf("expected 1 deletion: %+v", cr)
	}
	mustCounts(t, h.store, 3, 5)

	// Delete a voucher outright: invisible to incremental, found by the periodic reconcile.
	h.fake.edit(func() { c.Vouchers = c.Vouchers[:len(c.Vouchers)-1] }) // removes V6
	res = h.run()
	mustStatus(t, res, "success")
	mustCounts(t, h.store, 3, 5) // not yet: reconcile not due
	h.clock = h.clock.Add(25 * time.Hour)
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Mode != "reconcile" || cr.Transactions.Deleted != 1 {
		t.Fatalf("reconcile: %+v", cr)
	}
	mustCounts(t, h.store, 3, 4)
	if h.store.Counts().TransactionsDeleted != 2 {
		t.Fatalf("soft-deleted rows should be kept, got %+v", h.store.Counts())
	}
}

func TestShopRemovedAndReadded(t *testing.T) {
	h := newHarness(t, sampleCompany("C1", "Co"))
	mustStatus(t, h.run(), "success")
	c := h.fake.company("C1")
	var removed fakeLedger
	h.fake.edit(func() { removed = c.Ledgers[2]; c.Ledgers = append(c.Ledgers[:2], c.Ledgers[3:]...) })
	res := h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Shops.Deleted != 1 || cr.Shops.Updated != 2 {
		t.Fatalf("shop deletion: %+v", cr)
	}
	mustCounts(t, h.store, 2, 5)
	h.fake.edit(func() { c.Ledgers = append(c.Ledgers, removed) })
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Shops.Created != 1 {
		t.Fatalf("re-added shop should count as created: %+v", cr)
	}
	mustCounts(t, h.store, 3, 5)
	if _, ok := h.store.Shop("C1-L3"); !ok {
		t.Fatal("re-added shop should be active again")
	}
}

func TestEmptyCompany(t *testing.T) {
	h := newHarness(t, &fakeCompany{Name: "Empty Co", GUID: "E1", BooksFrom: "20260401"})
	res := h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Shops.Fetched != 0 || cr.Transactions.Fetched != 0 || cr.Status != StatusSynced {
		t.Fatalf("%+v", cr)
	}
	mustCounts(t, h.store, 0, 0)
}

func TestLargeDataset(t *testing.T) {
	c := &fakeCompany{Name: "Big Co", GUID: "B1", BooksFrom: "20240401"}
	for i := 0; i < 400; i++ {
		c.Ledgers = append(c.Ledgers, fakeLedger{Name: fmt.Sprintf("SHOP %04d -- TOWN%d", i, i%20), GUID: fmt.Sprintf("B1-L%d", i), Parent: "Sundry Debtors", Closing: "-10.00"})
	}
	for i := 0; i < 6000; i++ {
		c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: fmt.Sprintf("B1-V%d", i), AlterID: int64(1000 + i), Date: "20260401", Type: "Sales", Number: fmt.Sprintf("S/%d", i),
			Entries: []fakeEntry{{fmt.Sprintf("SHOP %04d -- TOWN%d", i%400, (i%400)%20), "-100.00"}, {"Sales", "100.00"}}})
	}
	h := newHarness(t, c)
	res := h.run()
	mustStatus(t, res, "success")
	mustCounts(t, h.store, 400, 6000)
	if h.state.Company("B1").VoucherCursor != 6999 {
		t.Fatalf("cursor = %d", h.state.Company("B1").VoucherCursor)
	}
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Transactions.Fetched != 0 {
		t.Fatalf("second run should fetch nothing: %+v", cr)
	}
}

// ---------------------------------------------------------------- companies

func TestMultipleCompaniesAndPartialFailure(t *testing.T) {
	a, b, c := sampleCompany("A", "Co A"), sampleCompany("B", "Co B"), sampleCompany("C", "Co C")
	h := newHarness(t, a, b, c)
	res := h.run()
	mustStatus(t, res, "success")
	mustCounts(t, h.store, 9, 15)

	// Company B disappears from Tally (closed): A and C still sync, B is reported.
	h.fake.edit(func() { h.fake.companies = []*fakeCompany{a, c} })
	res = h.run()
	mustStatus(t, res, "partial")
	if res.Companies[1].Status != StatusNotOpen || res.Companies[1].ErrorCode != string(tally.KindCompanyNotFound) {
		t.Fatalf("B: %+v", res.Companies[1])
	}
	if res.Companies[0].Status != StatusSynced || res.Companies[2].Status != StatusSynced {
		t.Fatalf("A/C should still sync: %s", res)
	}
	mustCounts(t, h.store, 9, 15) // B's data untouched
	if st := h.state.Company("B"); st.Status != StatusNotOpen || st.LastSuccessAt == nil {
		t.Fatalf("B state must keep last success: %+v", st)
	}
}

func TestDisabledCompanyIsNeverRead(t *testing.T) {
	a, b := sampleCompany("A", "Co A"), sampleCompany("B", "Co B")
	h := newHarness(t, a, b)
	h.enable("B", false)
	res := h.run()
	mustStatus(t, res, "success")
	if len(res.Companies) != 1 || res.Companies[0].TallyID != "A" {
		t.Fatalf("only A should sync: %s", res)
	}
	mustCounts(t, h.store, 3, 5)
	if _, ok := h.store.Company("B"); ok {
		t.Fatal("disabled company must not reach the cloud")
	}
	st := h.engine.State.Get()
	if st.Companies["B"] != nil {
		t.Fatal("disabled company should have no state")
	}
}

func TestCompanyAddedAndRemoved(t *testing.T) {
	a, b := sampleCompany("A", "Co A"), sampleCompany("B", "Co B")
	h := newHarness(t, a, b)
	h.enable("B", false)
	mustStatus(t, h.run(), "success")
	mustCounts(t, h.store, 3, 5)

	h.enable("B", true)
	res := h.run()
	mustStatus(t, res, "success")
	if len(res.Companies) != 2 || res.Companies[1].Mode != "full" {
		t.Fatalf("B should get a full first sync: %s", res)
	}
	mustCounts(t, h.store, 6, 10)

	h.enable("A", false)
	res = h.run()
	mustStatus(t, res, "success")
	if len(res.Companies) != 1 || res.Companies[0].TallyID != "B" {
		t.Fatalf("only B: %s", res)
	}
	mustCounts(t, h.store, 6, 10) // A's cloud data is kept, just no longer refreshed
}

func TestNoCompanySelected(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.enable("A", false)
	res := h.run()
	mustStatus(t, res, "skipped")
	if res.ErrorCode != "NOT_CONFIGURED" || h.fake.count("companies") != 0 {
		t.Fatalf("%+v tally calls=%d", res, h.fake.count("companies"))
	}
}

// ---------------------------------------------------------------- outages

func TestTallyUnavailableKeepsCloudData(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	mustStatus(t, h.run(), "success")
	before := h.store.Counts()

	h.engine = h.newEngine(tallyServiceFor(t, deadAddr(t), time.Second))
	res := h.run()
	mustStatus(t, res, "failed")
	if res.ErrorCode != string(tally.KindUnreachable) || res.Companies[0].Status != StatusTallyOffline {
		t.Fatalf("%+v", res)
	}
	if after := h.store.Counts(); after != before {
		t.Fatalf("cloud data changed during a Tally outage: %+v → %+v", before, after)
	}
	st := h.state.Company("A")
	if st.Status != StatusTallyOffline || st.LastSuccessAt == nil || st.VoucherCursor != 105 {
		t.Fatalf("state must keep last success and cursor: %+v", st)
	}
	if cs, ok := h.store.State(st.CloudID, cloud.EntityCompany); !ok || cs.Status != "error" || cs.ErrorCode != string(tally.KindUnreachable) || cs.LastSuccessfulSyncAt == nil {
		t.Fatalf("cloud company state should record the outage but keep last success: %+v", cs)
	}
	if n := len(h.store.Logs); n != 1 {
		t.Fatalf("outages must not spam sync_logs: %d rows", n)
	}

	// Tally back: normal incremental run, nothing re-created.
	h.engine = h.newEngine(h.fake.service(t, 2*time.Second))
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Mode != "incremental" || cr.Transactions.Created != 0 {
		t.Fatalf("%+v", cr)
	}
}

func TestTallyTimeout(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.fake.edit(func() { h.fake.delay = 300 * time.Millisecond })
	h.engine = h.newEngine(h.fake.service(t, 50*time.Millisecond))
	res := h.run()
	mustStatus(t, res, "failed")
	if res.ErrorCode != string(tally.KindTimeout) || res.Companies[0].Status != StatusTallyOffline {
		t.Fatalf("%+v", res)
	}
	mustCounts(t, h.store, 0, 0)
}

func TestCloudUnavailable(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	mustStatus(t, h.run(), "success")
	h.store.Fail = &cloud.Error{Kind: cloud.KindUnreachable, Op: "test", Msg: "dial tcp: no route"}
	res := h.run()
	mustStatus(t, res, "failed")
	if res.ErrorCode != string(cloud.KindUnreachable) || res.Companies[0].Status != StatusCloudOffline {
		t.Fatalf("%+v", res)
	}
	if h.fake.count("ledgers") != 1 {
		t.Fatal("Tally must not be read when the cloud is unreachable")
	}
	st := h.state.Company("A")
	if st.LastSuccessAt == nil || st.VoucherCursor != 105 {
		t.Fatalf("state lost: %+v", st)
	}
	h.store.Fail = nil
	mustStatus(t, h.run(), "success")
}

func TestCloudTimeoutMidway(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.store.FailOn["UpsertTransactions"] = &cloud.Error{Kind: cloud.KindTimeout, Op: "upsert-transactions"}
	res := h.run()
	mustStatus(t, res, "failed")
	cr := res.Companies[0]
	if cr.Status != StatusCloudOffline || cr.Shops.Created != 3 {
		t.Fatalf("shops should be written before the failure: %+v", cr)
	}
	if st := h.state.Company("A"); st.VoucherCursor != 0 || st.LastSuccessAt != nil {
		t.Fatalf("cursor must not advance on failure: %+v", st)
	}
	cmp, _ := h.store.Company("A")
	if cmp.SyncStatus == StatusSynced {
		t.Fatal("company must not be marked synced")
	}
	delete(h.store.FailOn, "UpsertTransactions")
	res = h.run()
	mustStatus(t, res, "success")
	if cr := res.Companies[0]; cr.Mode != "full" || cr.Transactions.Created != 5 {
		t.Fatalf("retry should complete the full sync: %+v", cr)
	}
	mustCounts(t, h.store, 3, 5)
}

func TestCloudAuthError(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.store.FailOn["Authenticate"] = &cloud.Error{Kind: cloud.KindAuth, Op: "authenticate", Msg: "HTTP 401"}
	res := h.run()
	mustStatus(t, res, "failed")
	if res.Companies[0].Status != StatusAuthError {
		t.Fatalf("%+v", res)
	}
}

func TestCancelledRunStopsCleanly(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"), sampleCompany("B", "Co B"))
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	res := h.engine.Run(ctx)
	if res.Status == "success" {
		t.Fatalf("cancelled run reported success: %s", res)
	}
}

// ---------------------------------------------------------------- tenancy

func TestEveryRecordCarriesBusinessID(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	mustStatus(t, h.run(), "success")
	for _, tx := range h.store.Transactions("") {
		if tx.BusinessID != bizA {
			t.Fatalf("transaction without tenant: %+v", tx)
		}
	}
	for _, l := range h.store.Logs {
		if l.BusinessID != bizA {
			t.Fatalf("log without tenant: %+v", l)
		}
	}
}

func TestWrongBusinessIsRejectedByProvider(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	// The provider is bound to business A; configure the service for business B.
	h.set.Update(func(s *Settings) error { s.Business.ID = "22222222-2222-2222-2222-222222222222"; return nil })
	res := h.run()
	mustStatus(t, res, "failed")
	if res.ErrorCode != string(cloud.KindAuth) {
		t.Fatalf("%+v", res)
	}
	mustCounts(t, h.store, 0, 0)
}

// ---------------------------------------------------------------- transformer details

func TestTransformSkipsExcludedAndSumsPerShop(t *testing.T) {
	v := []tally.Voucher{
		{GUID: "V1", AlterID: 3, Date: "2026-04-01", Type: "Sales", BaseType: "Sales", Category: tally.CatSales, Number: "1",
			Entries: []tally.VoucherEntry{{Ledger: "S1", Amount: -1000}, {Ledger: "S1", Amount: -500}, {Ledger: "Tax", Amount: 1500}}},
		{GUID: "V2", AlterID: 9, Optional: true, Entries: []tally.VoucherEntry{{Ledger: "S1", Amount: -100}}},
		{GUID: "V3", AlterID: 4, Category: tally.CatAdjustments, Entries: []tally.VoucherEntry{{Ledger: "S1", Amount: -700}, {Ledger: "S1", Amount: 700}}},
	}
	names := map[string]string{"S1": "L1"}
	ids := map[string]string{"L1": "shop-1"}
	txns, st := transactionsFromVouchers(bizA, "cmp", v, names, ids, time.Now())
	if len(txns) != 1 || txns[0].Debit != 15 || txns[0].Amount != 15 || txns[0].ShopID != "shop-1" {
		t.Fatalf("txns: %+v", txns)
	}
	if st.Vouchers != 3 || st.Excluded != 1 || st.Unmapped != 1 || st.MaxAlterID != 9 {
		t.Fatalf("stats: %+v", st)
	}
}

func TestStatusMapping(t *testing.T) {
	cases := map[string]string{
		"": StatusSynced, "TALLY_UNREACHABLE": StatusTallyOffline, "TALLY_TIMEOUT": StatusTallyOffline,
		"CLOUD_UNREACHABLE": StatusCloudOffline, "CLOUD_TIMEOUT": StatusCloudOffline, "CLOUD_AUTH_ERROR": StatusAuthError,
		"CLOUD_NOT_CONFIGURED": StatusAuthError, "COMPANY_NOT_FOUND": StatusNotOpen, "TALLY_ERROR": StatusSyncError,
		"CLOUD_ERROR": StatusSyncError, "INTERNAL": StatusSyncError,
	}
	for code, want := range cases {
		if got := statusFor(code); got != want {
			t.Errorf("statusFor(%q) = %s; want %s", code, got, want)
		}
	}
}
