package auth

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestHashAndVerify(t *testing.T) {
	h, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword(h, "correct horse battery") {
		t.Fatal("valid password rejected")
	}
	if VerifyPassword(h, "correct horse batter") || VerifyPassword("", "x") || VerifyPassword("bcrypt$1$2$3", "x") {
		t.Fatal("invalid password accepted")
	}
	h2, _ := HashPassword("correct horse battery")
	if h == h2 {
		t.Fatal("salt must differ between hashes")
	}
	if _, err := HashPassword("short"); err != ErrWeakPassword {
		t.Fatal("weak password accepted")
	}
}

func TestSessions(t *testing.T) {
	s := NewSessions(50 * time.Millisecond)
	tok, _ := s.Create("dev")
	if u, ok := s.Validate(tok); !ok || u != "dev" {
		t.Fatal("fresh session invalid")
	}
	if _, ok := s.Validate("nope"); ok {
		t.Fatal("unknown token accepted")
	}
	time.Sleep(80 * time.Millisecond)
	if _, ok := s.Validate(tok); ok {
		t.Fatal("expired session accepted")
	}
	tok, _ = s.Create("dev")
	s.Revoke(tok)
	if _, ok := s.Validate(tok); ok {
		t.Fatal("revoked session accepted")
	}
}

func TestLimiterLocksOut(t *testing.T) {
	l := NewLimiter(3, time.Minute, time.Hour)
	now := time.Now()
	l.now = func() time.Time { return now }
	for i := 0; i < 3; i++ {
		if err := l.Allow("dev"); err != nil {
			t.Fatalf("attempt %d blocked early", i)
		}
		l.Failure("dev")
	}
	if err := l.Allow("dev"); err != ErrLocked {
		t.Fatal("should be locked")
	}
	if err := l.Allow("other"); err != nil {
		t.Fatal("other users unaffected")
	}
	now = now.Add(2 * time.Hour)
	if err := l.Allow("dev"); err != nil {
		t.Fatal("lockout should expire")
	}
	l.Success("dev")
}

func TestLimiterCaseAndBurst(t *testing.T) {
	l := NewLimiter(3, time.Minute, time.Hour)
	// Case variants share one bucket.
	for _, u := range []string{"admin", "Admin", "ADMIN"} {
		if err := l.Allow(u); err != nil {
			t.Fatalf("attempt %s refused early: %v", u, err)
		}
	}
	if err := l.Allow("aDmIn"); err != ErrLocked {
		t.Fatalf("4th attempt under another case must be locked, got %v", err)
	}
	// Attempts count before the password check: a burst without any Failure
	// call still stops at maxFailures.
	l2 := NewLimiter(3, time.Minute, time.Hour)
	ok := 0
	for i := 0; i < 10; i++ {
		if l2.Allow("admin") == nil {
			ok++
		}
	}
	if ok != 3 {
		t.Fatalf("burst let %d attempts through, want 3", ok)
	}
}

func TestSessionsMaxAge(t *testing.T) {
	s := NewSessions(time.Hour)
	now := time.Now()
	s.now = func() time.Time { return now }
	tok, _ := s.Create("dev")
	// Used every 30 minutes, the session still ends at MaxSessionAge.
	for i := 0; i < 23; i++ {
		now = now.Add(30 * time.Minute)
		if _, ok := s.Validate(tok); !ok {
			t.Fatalf("active session ended early at %d", i)
		}
	}
	now = now.Add(30 * time.Minute)
	if _, ok := s.Validate(tok); ok {
		t.Fatal("session outlived MaxSessionAge")
	}
	now = time.Now()
	s2 := NewSessions(time.Hour)
	a, _ := s2.Create("u")
	b, _ := s2.Create("u")
	c, _ := s2.Create("v")
	s2.RevokeUser("u", a)
	if _, ok := s2.Validate(a); !ok {
		t.Fatal("kept session revoked")
	}
	if _, ok := s2.Validate(b); ok {
		t.Fatal("other session of the user survived")
	}
	if _, ok := s2.Validate(c); !ok {
		t.Fatal("another user's session revoked")
	}
}

func TestClientIP(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil) // RemoteAddr 192.0.2.1:1234
	r.Header.Set("X-Real-IP", "203.0.113.9")
	if got := ClientIP(r); got != "192.0.2.1" {
		t.Fatalf("X-Real-IP from a remote peer trusted: %s", got)
	}
	r.RemoteAddr = "127.0.0.1:5555"
	if got := ClientIP(r); got != "203.0.113.9" {
		t.Fatalf("X-Real-IP from nginx ignored: %s", got)
	}
	r.RemoteAddr = "[::1]:5555"
	r.Header.Set("X-Real-IP", "junk")
	if got := ClientIP(r); got != "::1" {
		t.Fatalf("bad X-Real-IP: %s", got)
	}
	if got := IPKey("2001:db8:1:2:3:4:5:6"); got != "2001:db8:1:2::/64" {
		t.Fatalf("IPv6 key %s", got)
	}
	if IPKey("2001:db8:1:2::9") != IPKey("2001:db8:1:2:ffff::1") {
		t.Fatal("same /64, different keys")
	}
	if got := IPKey("198.51.100.7"); got != "198.51.100.7" {
		t.Fatalf("IPv4 key %s", got)
	}
}
