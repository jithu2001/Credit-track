package control

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// App and Tally PC versions.
//
// The phone apps send X-App-Version: <name>+<build> (e.g. 1.0.0+3) and
// X-App-Platform: android|ios. When the setting min_app_build is above the
// build number, the request is refused with 426 so the app asks for an
// update. A request without the header (Tally PCs, scripts) is let through.

// UpgradeMessage is what an outdated app shows.
const UpgradeMessage = "A new version of WholeFlow is required. Please update the app."

// AppBuild reads the build number from X-App-Version ("1.0.0+3" → 3); ok is
// false when the header is missing or has no readable build number.
func AppBuild(r *http.Request) (int, bool) {
	v := strings.TrimSpace(r.Header.Get("X-App-Version"))
	if v == "" {
		return 0, false
	}
	_, build, found := strings.Cut(v, "+")
	if !found {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(build))
	if err != nil || n < 0 {
		return 0, false
	}
	return n, true
}

// TooOld reports whether the request comes from an app build below min (0 = no minimum).
func TooOld(r *http.Request, min int) bool {
	if min <= 0 {
		return false
	}
	build, ok := AppBuild(r)
	return ok && build < min
}

// VersionLess compares dotted version numbers ("0.5.1" < "0.6.0" < "0.10");
// a leading "v" and anything after "-" or "+" are ignored. Unreadable
// versions are never "less" (nothing is flagged by mistake).
func VersionLess(a, b string) bool {
	pa, okA := versionParts(a)
	pb, okB := versionParts(b)
	if !okA || !okB {
		return false
	}
	for i := 0; i < len(pa) || i < len(pb); i++ {
		var x, y int
		if i < len(pa) {
			x = pa[i]
		}
		if i < len(pb) {
			y = pb[i]
		}
		if x != y {
			return x < y
		}
	}
	return false
}

func versionParts(v string) ([]int, bool) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	if i := strings.IndexAny(v, "-+ "); i >= 0 {
		v = v[:i]
	}
	if v == "" {
		return nil, false
	}
	var out []int
	for _, p := range strings.Split(v, ".") {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return nil, false
		}
		out = append(out, n)
	}
	return out, true
}

// settingCache keeps one integer setting for a minute.
type settingCache struct {
	mu   sync.Mutex
	val  int
	at   time.Time
	load func(ctx context.Context) (int, error)
}

const settingTTL = time.Minute

func (c *settingCache) get(ctx context.Context) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.at.IsZero() && time.Since(c.at) < settingTTL {
		return c.val
	}
	if v, err := c.load(ctx); err == nil {
		c.val = v
	}
	// On an error keep the last value, and try again in a minute.
	c.at = time.Now()
	return c.val
}
