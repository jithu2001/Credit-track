package syncer

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"wholeflow/internal/tally"
)

func TestBackoffDelays(t *testing.T) {
	b := DefaultBackoff()
	normal := 5 * time.Minute
	cases := []struct {
		failures int
		want     time.Duration
	}{{0, 5 * time.Minute}, {1, 30 * time.Second}, {2, 60 * time.Second}, {3, 5 * time.Minute}, {10, 5 * time.Minute}}
	for _, c := range cases {
		if got := b.Delay(c.failures, normal); got != c.want {
			t.Errorf("Delay(%d) = %s; want %s", c.failures, got, c.want)
		}
	}
	if got := b.Delay(3, time.Minute); got != time.Minute {
		t.Errorf("backoff must never exceed the normal interval, got %s", got)
	}
}

// TestSchedulerRetriesThenRecovers drives the scheduler with a fake sleep:
// Tally is down for the first runs, then comes back.
func TestSchedulerRetriesThenRecovers(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	dead := tallyServiceFor(t, deadAddr(t), 200*time.Millisecond)
	live := h.fake.service(t, 2*time.Second)
	h.engine.Tally = dead

	s := NewScheduler(h.engine, h.set, slog.New(slog.NewTextHandler(io.Discard, nil)))
	var delays []time.Duration
	runs := 0
	ctx, cancel := context.WithCancel(context.Background())
	s.Sleep = func(ctx context.Context, d time.Duration, wake <-chan struct{}) bool {
		delays = append(delays, d)
		runs++
		if runs == 3 {
			h.engine.Tally = live // Tally starts
		}
		if runs == 5 {
			cancel()
			return false
		}
		return true
	}
	s.Run(ctx)

	want := []time.Duration{30 * time.Second, 60 * time.Second, 5 * time.Minute, 5 * time.Minute, 5 * time.Minute}
	if len(delays) != len(want) {
		t.Fatalf("delays = %v", delays)
	}
	for i := range want {
		if delays[i] != want[i] {
			t.Fatalf("delays = %v; want %v", delays, want)
		}
	}
	hist := s.History()
	if len(hist) != 5 || hist[0].Status != "success" || hist[4].Status != "failed" || hist[4].ErrorCode != string(tally.KindUnreachable) {
		t.Fatalf("history: %d runs, newest %s, oldest %s", len(hist), hist[0].Status, hist[len(hist)-1].Status)
	}
	st := s.Status()
	if st.State != StatusSynced || st.ConsecutiveFailures != 0 || st.Companies[0].Status != StatusSynced {
		t.Fatalf("status: %+v", st)
	}
}

func TestSchedulerIdleWhenDisabledButTriggerable(t *testing.T) {
	h := newHarness(t, sampleCompany("A", "Co A"))
	h.set.Update(func(s *Settings) error { s.Sync.Enabled = false; return nil })
	s := NewScheduler(h.engine, h.set, slog.New(slog.NewTextHandler(io.Discard, nil)))
	ctx, cancel := context.WithCancel(context.Background())
	idle := 0
	s.Sleep = func(ctx context.Context, d time.Duration, wake <-chan struct{}) bool {
		idle++
		switch idle {
		case 1:
			if d != 5*time.Second || h.fake.count("companies") != 0 {
				t.Errorf("should idle without syncing: d=%s tally calls=%d", d, h.fake.count("companies"))
			}
			s.TriggerNow() // developer presses "Sync now"
		case 2:
			if h.fake.count("companies") != 1 {
				t.Errorf("trigger should run a sync while disabled")
			}
			cancel()
			return false
		}
		return true
	}
	s.Run(ctx)
	if st := s.Status(); st.State != StatusDisabled || st.LastRun == nil || st.LastRun.Status != "success" {
		t.Fatalf("status: %+v", st)
	}
}

func TestOverallState(t *testing.T) {
	base := Status{Configured: true, Enabled: true}
	if got := overallState(Status{Configured: false}, nil); got != StateNotConfigured {
		t.Error(got)
	}
	if got := overallState(base, nil); got != StateConnected {
		t.Error(got)
	}
	if got := overallState(base, &RunResult{Status: "success"}); got != StatusSynced {
		t.Error(got)
	}
	if got := overallState(base, &RunResult{Status: "failed", ErrorCode: "TALLY_UNREACHABLE"}); got != StatusTallyOffline {
		t.Error(got)
	}
	if got := overallState(base, &RunResult{Status: "partial", Companies: []CompanyResult{{}, {ErrorCode: "CLOUD_TIMEOUT"}}}); got != StatusCloudOffline {
		t.Error(got)
	}
	r := Status{Configured: true, Enabled: true, Running: true}
	if got := overallState(r, nil); got != StatusSyncing {
		t.Error(got)
	}
}
