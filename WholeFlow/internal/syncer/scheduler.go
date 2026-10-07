package syncer

import (
	"context"
	"log/slog"
	"strings"
	gosync "sync"
	"time"
)

// Overall service states (superset of the company statuses).
const (
	StateNotConfigured = "NOT_CONFIGURED"
	StateConnected     = "CONNECTED" // configured, no run yet
)

// Scheduler runs the engine forever: immediately at start, then every
// interval, with backoff after failures and an on-demand trigger.
type Scheduler struct {
	Engine   *Engine
	Settings *SettingsStore
	Log      *slog.Logger
	Backoff  Backoff
	// Heartbeat, when set, runs at start and after each run (it limits itself
	// to once per few minutes and to the reference-key connection).
	Heartbeat *Heartbeat
	// Sleep lets tests replace the wait; default is a timer.
	Sleep func(ctx context.Context, d time.Duration, wake <-chan struct{}) bool

	mu       gosync.Mutex
	running  bool
	failures int
	nextAt   time.Time
	lastRun  *RunResult
	history  []RunResult
	trigger  chan struct{}
	started  bool
	stopped  bool
}

const historyLen = 50

func NewScheduler(engine *Engine, settings *SettingsStore, log *slog.Logger) *Scheduler {
	return &Scheduler{Engine: engine, Settings: settings, Log: log, Backoff: DefaultBackoff(), trigger: make(chan struct{}, 1)}
}

// Run blocks until ctx is cancelled.
func (s *Scheduler) Run(ctx context.Context) {
	s.mu.Lock()
	s.started = true
	if st := s.Engine.State.Get(); st.LastRun != nil {
		s.lastRun = st.LastRun
	}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		s.stopped = true
		s.mu.Unlock()
	}()

	s.beat(ctx)
	first := true
	for ctx.Err() == nil {
		set := s.Settings.Get()
		if !set.Sync.Enabled && !s.pendingTrigger() {
			// Idle: re-check every few seconds or when kicked.
			s.beat(ctx)
			s.setNext(time.Time{})
			if !s.sleep(ctx, 5*time.Second) {
				return
			}
			first = true
			continue
		}
		s.drainTrigger()
		res := s.runOnce(ctx)
		normal := set.Sync.Interval()
		delay := normal
		if res.Failed() {
			delay = s.Backoff.Delay(s.failureCount(), normal)
		}
		if res.Status == "skipped" {
			delay = 30 * time.Second // not configured yet: look again soon
		}
		if first && res.Status != "skipped" {
			first = false
		}
		if s.beat(ctx) && res.Status == RunPaused {
			s.Log.Info("subscription active again; syncing now")
			delay = 0
		}
		s.setNext(time.Now().Add(delay))
		s.Log.Info("next sync scheduled", "in", delay.String(), "consecutive_failures", s.failureCount())
		if !s.sleep(ctx, delay) {
			return
		}
	}
}

func (s *Scheduler) runOnce(ctx context.Context) *RunResult {
	s.mu.Lock()
	s.running = true
	s.mu.Unlock()
	res := s.Engine.Run(ctx)
	s.mu.Lock()
	s.running = false
	s.lastRun = res
	if res.Failed() {
		s.failures++
	} else if res.Status == "success" || res.Status == RunPaused || res.Status == RunRevoked {
		s.failures = 0
	}
	s.history = append(s.history, *res)
	if len(s.history) > historyLen {
		s.history = s.history[len(s.history)-historyLen:]
	}
	s.mu.Unlock()
	return res
}

// sleep waits for d, a trigger, or cancellation; false means cancelled.
func (s *Scheduler) sleep(ctx context.Context, d time.Duration) bool {
	if s.Sleep != nil {
		return s.Sleep(ctx, d, s.trigger)
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	case <-s.trigger:
		// Re-queue the token so the loop sees a pending trigger whether it
		// takes the enabled path (drained before the run) or the idle path.
		s.TriggerNow()
		return true
	}
}

// TriggerNow asks for a run as soon as possible (also when sync is disabled:
// the developer's "Run initial sync" button).
func (s *Scheduler) TriggerNow() {
	select {
	case s.trigger <- struct{}{}:
	default:
	}
}

// beat sends a heartbeat if one is due; true means the subscription just came back.
func (s *Scheduler) beat(ctx context.Context) bool {
	if s.Heartbeat == nil {
		return false
	}
	return s.Heartbeat.Beat(ctx)
}

func (s *Scheduler) pendingTrigger() bool { return len(s.trigger) > 0 }

func (s *Scheduler) drainTrigger() {
	select {
	case <-s.trigger:
	default:
	}
}

func (s *Scheduler) setNext(t time.Time) {
	s.mu.Lock()
	s.nextAt = t
	s.mu.Unlock()
}

func (s *Scheduler) failureCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.failures
}

// ---------------------------------------------------------------- status

type Status struct {
	State               string          `json:"state"`
	Enabled             bool            `json:"enabled"`
	Running             bool            `json:"running"`
	IntervalSeconds     int             `json:"intervalSeconds"`
	NextRunAt           *time.Time      `json:"nextRunAt,omitempty"`
	ConsecutiveFailures int             `json:"consecutiveFailures"`
	LastRun             *RunResult      `json:"lastRun,omitempty"`
	Companies           []CompanyStatus `json:"companies"`
	Configured          bool            `json:"configured"`
	ConfigMessage       string          `json:"configMessage,omitempty"`
	Provider            string          `json:"provider"`
	Version             string          `json:"version"`
	// Message is the plain-English reason when the state needs attention:
	// subscription ended, PC revoked, or companies over the plan's limit.
	Message string `json:"message,omitempty"`
	// Reference-key connection only.
	BusinessName      string `json:"businessName,omitempty"`
	SubscriptionState string `json:"subscriptionState,omitempty"`
	MaxCompanies      int    `json:"maxCompanies,omitempty"`
}

type CompanyStatus struct {
	CompanyState
	Enabled bool `json:"enabled"`
}

// Status combines settings, persisted state and the live scheduler.
func (s *Scheduler) Status() Status {
	set := s.Settings.Get()
	st := s.Engine.State.Get()
	s.mu.Lock()
	running, failures, next, last := s.running, s.failures, s.nextAt, s.lastRun
	s.mu.Unlock()
	// A run started outside the scheduler ("sync" from the CLI) is only in the state file.
	if st.LastRun != nil && (last == nil || st.LastRun.StartedAt.After(last.StartedAt)) {
		last = st.LastRun
	}

	out := Status{Enabled: set.Sync.Enabled, Running: running, IntervalSeconds: set.Sync.IntervalSeconds,
		ConsecutiveFailures: failures, LastRun: last, Provider: set.Cloud.Provider, Version: Version, Companies: []CompanyStatus{}}
	out.Configured, out.ConfigMessage = set.Configured()
	if !next.IsZero() && set.Sync.Enabled {
		out.NextRunAt = &next
	}
	if set.Linked() {
		out.BusinessName, out.SubscriptionState, out.MaxCompanies = set.Business.Name, set.Cloud.Link.SubscriptionState, set.Cloud.Link.MaxCompanies
	}
	var msgs []string
	limit, ticked := set.CompanyLimit(), 0
	_, over := set.SyncCompanies()
	if over > 0 {
		msgs = append(msgs, CompanyLimitWarning(limit, limit+over))
	}
	for _, cs := range set.Companies {
		c := st.Companies[cs.TallyID]
		var cst CompanyState
		if c != nil {
			cst = *c
		} else {
			cst = CompanyState{TallyID: cs.TallyID, Status: StatusPending}
		}
		if cst.Name == "" {
			cst.Name = cs.Name
		}
		if !cs.Enabled {
			cst.Status = StatusDisabled
		} else if cs.TallyID != "" {
			ticked++
			if limit > 0 && ticked > limit {
				cst.Status = StatusOverLimit
			}
		}
		out.Companies = append(out.Companies, CompanyStatus{CompanyState: cst, Enabled: cs.Enabled})
	}
	out.State = overallState(out, last)
	if set.Linked() && set.Cloud.Link.Revoked {
		out.State = StatusDeviceRevoked
	}
	switch out.State {
	case StatusDeviceRevoked:
		msgs = append([]string{MsgDeviceRevoked}, msgs...)
	case StatusSubscriptionEnded:
		msgs = append([]string{MsgSubscriptionEnded}, msgs...)
	}
	out.Message = strings.Join(msgs, " ")
	return out
}

func overallState(st Status, last *RunResult) string {
	switch {
	case !st.Configured:
		return StateNotConfigured
	case st.Running:
		return StatusSyncing
	case !st.Enabled && last == nil:
		return StatusDisabled
	case last == nil:
		return StateConnected
	}
	if last.Status == "success" {
		if !st.Enabled {
			return StatusDisabled
		}
		return StatusSynced
	}
	if last.Status == "skipped" {
		return StateNotConfigured
	}
	if last.Status == RunPaused {
		return StatusSubscriptionEnded
	}
	// Failed or partial: report the most specific cause.
	code := last.ErrorCode
	for _, c := range last.Companies {
		if c.ErrorCode != "" && code == "" {
			code = c.ErrorCode
		}
	}
	return statusFor(code)
}

// History returns recent run results, newest first.
func (s *Scheduler) History() []RunResult {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]RunResult, 0, len(s.history))
	for i := len(s.history) - 1; i >= 0; i-- {
		out = append(out, s.history[i])
	}
	return out
}
