package syncer

import (
	"context"
	"log/slog"
	"net/http"
	gosync "sync"
	"time"

	"wholeflow/internal/controlclient"
)

// DefaultHeartbeatEvery is the least time between two heartbeats.
const DefaultHeartbeatEvery = 5 * time.Minute

// Heartbeat reports this PC's app version to the control service (which
// records it as "last seen") and keeps the plan's company limit and the
// subscription state up to date. It only runs for the reference-key
// connection, and at most once per Every.
type Heartbeat struct {
	Settings *SettingsStore
	Log      *slog.Logger
	Every    time.Duration
	Timeout  time.Duration
	Now      func() time.Time

	mu      gosync.Mutex
	last    time.Time
	lastErr string
}

func NewHeartbeat(settings *SettingsStore, log *slog.Logger) *Heartbeat {
	return &Heartbeat{Settings: settings, Log: log, Every: DefaultHeartbeatEvery, Timeout: 20 * time.Second}
}

func (h *Heartbeat) now() time.Time {
	if h.Now != nil {
		return h.Now()
	}
	return time.Now()
}

// Last is when the last heartbeat was sent (zero if never).
func (h *Heartbeat) Last() time.Time {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.last
}

// Beat sends a heartbeat if one is due and applies the answer. It returns
// true when the subscription has just come back from "ended", so the caller
// can sync straight away instead of waiting for the next interval.
func (h *Heartbeat) Beat(ctx context.Context) (resumed bool) {
	set := h.Settings.Get()
	l := set.Cloud.Link
	if !set.Linked() || l.Revoked || l.DeviceKey == "" {
		return false
	}
	h.mu.Lock()
	if !h.last.IsZero() && h.now().Sub(h.last) < h.Every {
		h.mu.Unlock()
		return false
	}
	h.last = h.now()
	h.mu.Unlock()

	c, err := controlclient.New(set.ControlURL(), h.Timeout)
	if err != nil {
		h.note(err.Error())
		return false
	}
	ctx, cancel := context.WithTimeout(ctx, h.Timeout)
	defer cancel()
	hb, err := c.Heartbeat(ctx, l.DeviceKey, Version)
	if err != nil {
		if controlclient.StatusOf(err) == http.StatusPaymentRequired {
			// The business is suspended or its subscription ended.
			hb = controlclient.HeartbeatResult{SubscriptionState: "ended"}
		} else {
			h.note(err.Error())
			return false
		}
	}
	h.note("")

	prev := l.SubscriptionState
	changed := hb.SubscriptionState != "" && hb.SubscriptionState != l.SubscriptionState ||
		hb.MaxCompanies > 0 && hb.MaxCompanies != l.MaxCompanies || hb.Revoked && !l.Revoked
	if !changed {
		return false
	}
	err = h.Settings.Update(func(s *Settings) error {
		if !s.Linked() {
			return nil
		}
		if hb.SubscriptionState != "" {
			s.Cloud.Link.SubscriptionState = hb.SubscriptionState
		}
		if hb.MaxCompanies > 0 {
			s.Cloud.Link.MaxCompanies = hb.MaxCompanies
		}
		if hb.Revoked {
			s.Cloud.Link.Revoked = true
		}
		return nil
	})
	if err != nil {
		h.Log.Warn("could not save the heartbeat answer", "error", err.Error())
		return false
	}
	h.Log.Info("heartbeat", "subscription", hb.SubscriptionState, "max_companies", hb.MaxCompanies, "revoked", hb.Revoked)
	if hb.Revoked {
		h.Log.Warn(MsgDeviceRevoked)
	}
	return prev == "ended" && hb.SubscriptionState != "" && hb.SubscriptionState != "ended" && !hb.Revoked
}

// note logs a heartbeat problem once, and its recovery.
func (h *Heartbeat) note(problem string) {
	h.mu.Lock()
	prev := h.lastErr
	h.lastErr = problem
	h.mu.Unlock()
	switch {
	case problem != "" && problem != prev:
		h.Log.Warn("heartbeat to the WholeFlow server failed", "error", problem)
	case problem == "" && prev != "":
		h.Log.Info("heartbeat to the WholeFlow server works again")
	}
}
