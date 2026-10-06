// Package auth implements the developer login for the local setup interface.
// It is deliberately separate from the owner/staff accounts, which live in
// the cloud (Supabase Auth) and never touch this service.
package auth

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	pbkdf2Iterations = 600_000
	saltBytes        = 16
	keyBytes         = 32
	MinPasswordLen   = 10
)

var ErrWeakPassword = fmt.Errorf("password must be at least %d characters", MinPasswordLen)

// HashPassword returns "pbkdf2-sha256$<iter>$<salt>$<hash>".
func HashPassword(password string) (string, error) {
	if utf8.RuneCountInString(password) < MinPasswordLen {
		return "", ErrWeakPassword
	}
	return HashSecret(password)
}

// HashSecret is HashPassword without the length rule, for passwords whose
// rules are set elsewhere (WholeFlow accounts remembered for offline login).
func HashSecret(password string) (string, error) {
	if password == "" {
		return "", errors.New("empty password")
	}
	salt := make([]byte, saltBytes)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, pbkdf2Iterations, keyBytes)
	if err != nil {
		return "", err
	}
	return "pbkdf2-sha256$" + strconv.Itoa(pbkdf2Iterations) + "$" +
		base64.RawStdEncoding.EncodeToString(salt) + "$" + base64.RawStdEncoding.EncodeToString(key), nil
}

// VerifyPassword is constant-time in the comparison; a malformed hash never verifies.
func VerifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2-sha256" {
		return false
	}
	iter, err := strconv.Atoi(parts[1])
	if err != nil || iter < 1000 {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[2])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	got, err := pbkdf2.Key(sha256.New, password, salt, iter, len(want))
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(got, want) == 1
}

// ---------------------------------------------------------------- sessions

type session struct {
	user    string
	expires time.Time
}

// Sessions is an in-memory session table: restarting the service logs
// everyone out, which is fine for a local admin tool.
type Sessions struct {
	mu   sync.Mutex
	ttl  time.Duration
	toks map[string]session
}

func NewSessions(ttl time.Duration) *Sessions {
	return &Sessions{ttl: ttl, toks: map[string]session{}}
}

func (s *Sessions) Create(user string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	tok := base64.RawURLEncoding.EncodeToString(b)
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for k, v := range s.toks {
		if now.After(v.expires) {
			delete(s.toks, k)
		}
	}
	s.toks[tok] = session{user: user, expires: now.Add(s.ttl)}
	return tok, nil
}

// Validate returns the user for a live token and slides its expiry.
func (s *Sessions) Validate(tok string) (string, bool) {
	if tok == "" {
		return "", false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	v, ok := s.toks[tok]
	if !ok || time.Now().After(v.expires) {
		delete(s.toks, tok)
		return "", false
	}
	v.expires = time.Now().Add(s.ttl)
	s.toks[tok] = v
	return v.user, true
}

func (s *Sessions) Revoke(tok string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.toks, tok)
}

// ---------------------------------------------------------------- login throttling

// Limiter slows brute force: after maxFailures within window the account is
// locked for lockout.
type Limiter struct {
	mu          sync.Mutex
	maxFailures int
	window      time.Duration
	lockout     time.Duration
	fails       map[string][]time.Time
	locked      map[string]time.Time
	now         func() time.Time
}

func NewLimiter(maxFailures int, window, lockout time.Duration) *Limiter {
	return &Limiter{maxFailures: maxFailures, window: window, lockout: lockout,
		fails: map[string][]time.Time{}, locked: map[string]time.Time{}, now: time.Now}
}

var ErrLocked = errors.New("too many failed logins; try again later")

// key folds case: usernames are compared case-insensitively, so "Admin" and
// "admin" must share one bucket.
func limiterKey(user string) string { return strings.ToLower(strings.TrimSpace(user)) }

// Allow reports whether a login attempt for user may proceed and, if so,
// counts it straight away. Counting before the (slow) password check means
// parallel requests cannot all slip in before the first failure is recorded;
// Success forgets the attempts of a correct login.
func (l *Limiter) Allow(user string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	key, now := limiterKey(user), l.now()
	if until, ok := l.locked[key]; ok {
		if now.Before(until) {
			return ErrLocked
		}
		delete(l.locked, key)
		delete(l.fails, key)
	}
	recent := l.recentLocked(key, now)
	if len(recent) >= l.maxFailures {
		l.locked[key] = now.Add(l.lockout)
		return ErrLocked
	}
	l.fails[key] = append(recent, now)
	l.pruneLocked(now)
	return nil
}

// Failure locks the account once maxFailures attempts fall inside the window.
// (The attempt itself was already counted by Allow.)
func (l *Limiter) Failure(user string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	key, now := limiterKey(user), l.now()
	if len(l.recentLocked(key, now)) >= l.maxFailures {
		l.locked[key] = now.Add(l.lockout)
	}
}

func (l *Limiter) Success(user string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	key := limiterKey(user)
	delete(l.fails, key)
	delete(l.locked, key)
}

func (l *Limiter) recentLocked(key string, now time.Time) []time.Time {
	var recent []time.Time
	for _, t := range l.fails[key] {
		if now.Sub(t) < l.window {
			recent = append(recent, t)
		}
	}
	return recent
}

// pruneLocked drops expired entries so random usernames cannot grow the maps forever.
func (l *Limiter) pruneLocked(now time.Time) {
	if len(l.fails)+len(l.locked) < 256 {
		return
	}
	for k := range l.fails {
		if len(l.recentLocked(k, now)) == 0 {
			delete(l.fails, k)
		}
	}
	for k, until := range l.locked {
		if !now.Before(until) {
			delete(l.locked, k)
		}
	}
}

// RevokeAllExcept ends every session but keep (e.g. after a password change).
func (s *Sessions) RevokeAllExcept(keep string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for tok := range s.toks {
		if tok != keep {
			delete(s.toks, tok)
		}
	}
}
