package control

import (
	"encoding/base32"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestTOTP(t *testing.T) {
	// RFC 6238 appendix B (SHA-1 seed), last 6 digits.
	secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString([]byte("12345678901234567890"))
	for at, want := range map[int64]string{59: "287082", 1111111109: "081804", 1234567890: "005924", 2000000000: "279037"} {
		step, ok := CheckTOTP(secret, want, time.Unix(at, 0), 0)
		if !ok || step != at/30 {
			t.Fatalf("T=%d: code %s not accepted (step %d)", at, want, step)
		}
	}
	now := time.Unix(1111111109, 0)
	step, ok := CheckTOTP(secret, "081804", now.Add(30*time.Second), 0)
	if !ok || step != 1111111109/30 {
		t.Fatal("one step of drift refused")
	}
	if _, ok := CheckTOTP(secret, "081804", now.Add(90*time.Second), 0); ok {
		t.Fatal("three steps old code accepted")
	}
	if _, ok := CheckTOTP(secret, "081804", now, step); ok {
		t.Fatal("same step used twice")
	}
	if _, ok := CheckTOTP(secret, "000000", now, 0); ok {
		t.Fatal("wrong code accepted")
	}
	if _, ok := CheckTOTP(secret, "", now, 0); ok {
		t.Fatal("empty code accepted")
	}
	s, _ := NewTOTPSecret()
	uri := TOTPURI(s, "a@b.test")
	if !strings.HasPrefix(uri, "otpauth://totp/WholeFlow%20Admin:a@b.test?") || !strings.Contains(uri, "secret="+s) {
		t.Fatalf("uri %s", uri)
	}
	codes, _ := NewBackupCodes(10)
	if len(codes) != 10 || len(codes[0]) != 11 || HashCode(codes[0]) == HashCode(codes[1]) {
		t.Fatalf("backup codes %v", codes)
	}
}

func TestVersions(t *testing.T) {
	if !VersionLess("0.5.1", "0.6.0") || VersionLess("0.6.0", "0.6.0") || VersionLess("0.10", "0.9") || VersionLess("", "0.6.0") {
		t.Fatal("VersionLess")
	}
	r := httptest.NewRequest("GET", "/", nil)
	if TooOld(r, 5) {
		t.Fatal("no header: never too old")
	}
	r.Header.Set("X-App-Version", "1.0.0+3")
	if !TooOld(r, 5) || TooOld(r, 3) || TooOld(r, 0) {
		t.Fatal("build 3")
	}
	r.Header.Set("X-App-Version", "1.0.0")
	if TooOld(r, 5) {
		t.Fatal("no build number: let through")
	}
}
