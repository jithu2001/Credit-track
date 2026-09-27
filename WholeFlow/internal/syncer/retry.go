package syncer

import "time"

// Backoff decides how long to wait after consecutive failed runs:
//
//	failure 1 → 30 s, failure 2 → 60 s, failure 3+ → 5 min,
//
// never longer than the normal interval, so a short interval is honoured.
// After a success the normal interval applies again.
type Backoff struct {
	Steps []time.Duration
}

func DefaultBackoff() Backoff {
	return Backoff{Steps: []time.Duration{30 * time.Second, 60 * time.Second, 5 * time.Minute}}
}

// Delay returns the wait before the next run given the number of consecutive
// failures so far (0 = last run succeeded).
func (b Backoff) Delay(consecutiveFailures int, normal time.Duration) time.Duration {
	if consecutiveFailures <= 0 || len(b.Steps) == 0 {
		return normal
	}
	i := consecutiveFailures - 1
	if i >= len(b.Steps) {
		i = len(b.Steps) - 1
	}
	d := b.Steps[i]
	if d > normal {
		d = normal
	}
	return d
}
