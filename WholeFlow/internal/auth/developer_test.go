package auth

import (
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
