package syncer

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	gosync "sync"
	"testing"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/secrets"
)

// recordingHandler keeps every log message, to check what is logged once.
type recordingHandler struct {
	mu   gosync.Mutex
	msgs []string
}

func (h *recordingHandler) Enabled(context.Context, slog.Level) bool { return true }
func (h *recordingHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	h.msgs = append(h.msgs, r.Message)
	h.mu.Unlock()
	return nil
}
func (h *recordingHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *recordingHandler) WithGroup(string) slog.Handler      { return h }

func (h *recordingHandler) count(msg string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for _, m := range h.msgs {
		if m == msg {
			n++
		}
	}
	return n
}

// link turns the harness into a reference-key connection with the given plan.
func (h *harness) link(maxCompanies int) {
	h.t.Helper()
	if err := h.set.Update(func(s *Settings) error {
		s.Cloud.Provider = ProviderWholeFlow
		s.Cloud.Link = LinkSettings{BaseURL: "https://api.example/b/demo", DeviceKey: "pc-key", DeviceID: "dev-1",
			BusinessName: "JMJ Marketing", MaxCompanies: maxCompanies, SubscriptionState: "active"}
		return nil
	}); err != nil {
		h.t.Fatal(err)
	}
}

var errSubscriptionEnded = &cloud.Error{Kind: cloud.KindSubscriptionEnded, Op: "authenticate", Msg: "PT402 subscription_ended (Renew to continue)"}

// A 402 pauses the sync: no failure count, normal interval, nothing touched,
// logged once; it resumes by itself when requests succeed again.
func TestSubscriptionEndedPausesAndResumes(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.link(0)
	rec := &recordingHandler{}
	h.engine.Log = slog.New(rec)
	mustStatus(t, h.run(), "success")
	mustCounts(t, h.store, 3, 5)

	h.store.FailOn["Authenticate"] = errSubscriptionEnded
	s := NewScheduler(h.engine, h.set, h.engine.Log)
	var delays []time.Duration
	ctx, cancel := context.WithCancel(context.Background())
	s.Sleep = func(ctx context.Context, d time.Duration, wake <-chan struct{}) bool {
		delays = append(delays, d)
		h.clock = h.clock.Add(d)
		switch len(delays) {
		case 3:
			// A run while paused shows the paused state.
			if st := s.Status(); st.State != StatusSubscriptionEnded || st.Message != MsgSubscriptionEnded || st.ConsecutiveFailures != 0 ||
				st.Companies[0].Status != StatusSubscriptionEnded {
				t.Errorf("status while paused: %+v", st)
			}
			delete(h.store.FailOn, "Authenticate") // payment recorded
		case 4:
			cancel()
			return false
		}
		return true
	}
	s.Run(ctx)

	for i, d := range delays {
		if d != 5*time.Minute {
			t.Fatalf("delay %d = %s; a pause must keep the normal interval (all: %v)", i, d, delays)
		}
	}
	if n := rec.count(MsgSubscriptionEnded); n != 1 {
		t.Fatalf("pause logged %d times; want once", n)
	}
	if n := rec.count("sync run failed"); n != 0 {
		t.Fatalf("a pause must not be logged as a failure (%d)", n)
	}
	hist := s.History()
	if hist[0].Status != "success" || hist[1].Status != RunPaused || hist[1].ErrorMessage != MsgSubscriptionEnded {
		t.Fatalf("history: newest %s, before %s (%s)", hist[0].Status, hist[1].Status, hist[1].ErrorMessage)
	}
	if rec.count("the cloud accepts this PC again; sync resumed") != 1 {
		t.Fatal("resume not logged")
	}
	mustCounts(t, h.store, 3, 5)
	if st := s.Status(); st.State != StatusSynced || st.Message != "" {
		t.Fatalf("after resume: %+v", st)
	}
}

// A 402 in the middle of a run (after Tally was read) must not delete
// anything and stops the remaining companies too.
func TestSubscriptionEndedMidRunDeletesNothing(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"), sampleCompany("B", "Co B"))
	h.link(0)
	mustStatus(t, h.run(), "success")
	c := h.fake.company("A")
	h.fake.edit(func() { c.Ledgers = c.Ledgers[1:] }) // a shop disappears from Tally…
	h.store.FailOn["ListShops"] = &cloud.Error{Kind: cloud.KindSubscriptionEnded, Op: "list-shops", Msg: "subscription_ended"}
	res := h.run() // …but the cloud refuses before it can be compared
	if res.Status != RunPaused || len(res.Companies) != 2 {
		t.Fatalf("run: %s, %d companies\n%s", res.Status, len(res.Companies), res)
	}
	for _, cr := range res.Companies {
		if cr.Status != StatusSubscriptionEnded || cr.Shops.Deleted != 0 {
			t.Fatalf("company: %+v", cr)
		}
	}
	if got := h.store.Counts(); got.ShopsDeleted != 0 || got.TransactionsDeleted != 0 {
		t.Fatalf("nothing may be deleted while paused: %+v", got)
	}
	if st := h.state.Company("A"); st.VoucherCursor != 105 || st.LastSuccessAt == nil {
		t.Fatalf("state lost: %+v", st)
	}
}

// A 403 device_revoked stops the sync for good: remembered in the settings,
// no further requests, and a clear message.
func TestDeviceRevokedStopsSync(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.link(0)
	h.store.FailOn["Authenticate"] = &cloud.Error{Kind: cloud.KindDeviceRevoked, Op: "authenticate", Msg: "PT403 device_revoked"}
	res := h.run()
	if res.Status != RunRevoked || res.ErrorMessage != MsgDeviceRevoked || res.Failed() {
		t.Fatalf("run: %+v", res)
	}
	if !h.set.Get().Cloud.Link.Revoked {
		t.Fatal("revoked state not saved")
	}
	ledgers := h.fake.count("ledgers")
	res = h.run()
	if res.Status != "skipped" || res.ErrorMessage != MsgDeviceRevoked || h.fake.count("ledgers") != ledgers {
		t.Fatalf("a revoked PC must not sync again: %+v", res)
	}
	s := NewScheduler(h.engine, h.set, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if st := s.Status(); st.State != StatusDeviceRevoked || !strings.Contains(st.Message, MsgDeviceRevoked) {
		t.Fatalf("status: %+v", st)
	}
	// Connecting again (a new activation) clears it.
	h.store.FailOn = map[string]error{}
	h.link(0)
	mustStatus(t, h.run(), "success")
}

// More companies ticked than the plan allows: only the first N (in the
// configured order) are synced, with a warning; Status marks the rest.
func TestCompanyLimitSyncsFirstN(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"), sampleCompany("B", "Co B"), sampleCompany("C", "Co C"))
	h.link(2)
	res := h.run()
	mustStatus(t, res, "success")
	if len(res.Companies) != 2 || res.Companies[0].TallyID != "A" || res.Companies[1].TallyID != "B" {
		t.Fatalf("synced: %+v", res.Companies)
	}
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], "Your plan allows 2 companies but 3 are ticked") {
		t.Fatalf("warnings: %v", res.Warnings)
	}
	if _, ok := h.store.Company("C"); ok {
		t.Fatal("company over the limit was synced")
	}
	s := NewScheduler(h.engine, h.set, slog.New(slog.NewTextHandler(io.Discard, nil)))
	st := s.Status()
	if st.Companies[2].Status != StatusOverLimit || !strings.Contains(st.Message, "Your plan allows 2") {
		t.Fatalf("status: %+v", st)
	}
	// The limit only applies to the reference-key connection.
	h.set.Update(func(s *Settings) error { s.Cloud.Provider = ProviderMemory; return nil })
	if res := h.run(); len(res.Companies) != 3 || len(res.Warnings) != 0 {
		t.Fatalf("legacy connection has no limit: %d companies, %v", len(res.Companies), res.Warnings)
	}
}

func TestCompanyLimitError(t *testing.T) {
	if got := CompanyLimitError(3).Error(); got != "Your plan allows 3 companies. Ask WholeFlow support to upgrade." {
		t.Fatal(got)
	}
}

// fakeHeartbeat answers /control/heartbeat with whatever answer holds.
type fakeHeartbeat struct {
	mu     gosync.Mutex
	calls  int
	status int
	answer string
	keys   []string
}

func (f *fakeHeartbeat) handler(w http.ResponseWriter, r *http.Request) {
	var body map[string]string
	json.NewDecoder(r.Body).Decode(&body)
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	f.keys = append(f.keys, r.Header.Get("Authorization")+" "+body["app_version"])
	if f.status != 0 {
		w.WriteHeader(f.status)
		io.WriteString(w, `{"error":{"code":"SUSPENDED","message":"WholeFlow is paused for this business."}}`)
		return
	}
	io.WriteString(w, f.answer)
}

func TestHeartbeat(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	fake := &fakeHeartbeat{answer: `{"subscription_state":"renewal_due","max_companies":4,"revoked":false}`}
	srv := httptest.NewServer(http.HandlerFunc(fake.handler))
	defer srv.Close()
	hb := NewHeartbeat(h.set, slog.New(slog.NewTextHandler(io.Discard, nil)))
	now := h.clock
	hb.Now = func() time.Time { return now }

	// Not connected by reference key: no heartbeat at all.
	hb.Beat(context.Background())
	if fake.calls != 0 {
		t.Fatal("heartbeat without a reference-key connection")
	}
	h.link(1)
	h.set.Update(func(s *Settings) error { s.Cloud.ControlURL = srv.URL; return nil })
	hb.Beat(context.Background())
	l := h.set.Get().Cloud.Link
	if fake.calls != 1 || fake.keys[0] != "Bearer pc-key "+Version || l.MaxCompanies != 4 || l.SubscriptionState != "renewal_due" {
		t.Fatalf("calls %d %v, link %+v", fake.calls, fake.keys, l)
	}
	// At most once per Every.
	now = now.Add(time.Minute)
	hb.Beat(context.Background())
	if fake.calls != 1 {
		t.Fatal("heartbeat sent again too soon")
	}
	// 402: the business is suspended.
	fake.status = http.StatusPaymentRequired
	now = now.Add(5 * time.Minute)
	if hb.Beat(context.Background()) || h.set.Get().Cloud.Link.SubscriptionState != "ended" {
		t.Fatalf("402 → %+v", h.set.Get().Cloud.Link)
	}
	// Payment recorded: Beat reports the resume so the scheduler syncs at once.
	fake.status, fake.answer = 0, `{"subscription_state":"active","max_companies":4,"revoked":false}`
	now = now.Add(5 * time.Minute)
	if !hb.Beat(context.Background()) {
		t.Fatal("resume from ended not reported")
	}
	// Revoked in the admin app.
	fake.answer = `{"subscription_state":"active","max_companies":4,"revoked":true}`
	now = now.Add(5 * time.Minute)
	hb.Beat(context.Background())
	if !h.set.Get().Cloud.Link.Revoked {
		t.Fatal("revoked not saved")
	}
	calls := fake.calls
	now = now.Add(5 * time.Minute)
	hb.Beat(context.Background())
	if fake.calls != calls {
		t.Fatal("a revoked PC keeps sending heartbeats")
	}
}

func TestLinkedSettingsKeepKeyEncrypted(t *testing.T) {
	dir := t.TempDir()
	set, _ := LoadSettings(dir, secrets.Plain{})
	if err := set.Update(func(s *Settings) error {
		s.Business.ID = bizA
		s.Cloud.Provider = ProviderWholeFlow
		s.Cloud.Link = LinkSettings{BaseURL: "https://api.example/b/demo", DeviceKey: "pc-secret-key", MaxCompanies: 2}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(set.Path())
	raw := string(b)
	if strings.Contains(raw, "pc-secret-key") || !strings.Contains(raw, `"deviceKeyEnc"`) {
		t.Fatalf("PC key stored in clear text: %s", raw)
	}
	again, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if got := again.Get(); got.Cloud.Link.DeviceKey != "pc-secret-key" || !got.Linked() || got.CompanyLimit() != 2 {
		t.Fatalf("reload: %+v", got.Cloud.Link)
	}
	if ok, why := again.Get().Configured(); ok || why != "no company selected" {
		t.Fatalf("configured without a local password: %v %s", ok, why)
	}
	if err := set.Update(func(s *Settings) error { s.Cloud.Link.BaseURL = "http://api.example"; return nil }); err == nil {
		t.Fatal("plain http business address accepted")
	}
}
