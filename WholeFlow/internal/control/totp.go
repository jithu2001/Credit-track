package control

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Two-step sign-in for admins: time-based one-time codes (RFC 6238 TOTP:
// HMAC-SHA1, 30-second steps, 6 digits), as any authenticator app makes them.

const (
	totpStep   = 30 // seconds
	totpDigits = 6
	totpSkew   = 1 // steps accepted either side of now (clock drift)
	totpIssuer = "WholeFlow Admin"
)

var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewTOTPSecret is 20 random bytes in base32 (what authenticator apps take).
func NewTOTPSecret() (string, error) {
	b := make([]byte, 20)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return b32.EncodeToString(b), nil
}

// TOTPURI is the otpauth:// address an authenticator app adds (as a QR code or typed).
func TOTPURI(secret, account string) string {
	label := url.PathEscape(totpIssuer + ":" + account)
	q := url.Values{"secret": {secret}, "issuer": {totpIssuer}, "algorithm": {"SHA1"}, "digits": {"6"}, "period": {"30"}}
	return "otpauth://totp/" + label + "?" + q.Encode()
}

// totpCode is the code of one time step (RFC 4226 HOTP with counter = step).
func totpCode(key []byte, step int64) string {
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], uint64(step))
	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	v := binary.BigEndian.Uint32(sum[off:off+4]) & 0x7fffffff
	return fmt.Sprintf("%0*d", totpDigits, v%1_000_000)
}

func decodeTOTPSecret(secret string) ([]byte, error) {
	return b32.DecodeString(strings.ToUpper(strings.TrimRight(strings.ReplaceAll(secret, " ", ""), "=")))
}

// CheckTOTP finds the time step whose code is code (now ± totpSkew steps)
// and returns it; ok is false when none matches or the step is not after
// lastStep (a code is used once: replaying it, or an older one, fails).
func CheckTOTP(secret, code string, now time.Time, lastStep int64) (step int64, ok bool) {
	code = strings.ReplaceAll(strings.TrimSpace(code), " ", "")
	if len(code) != totpDigits {
		return 0, false
	}
	key, err := decodeTOTPSecret(secret)
	if err != nil || len(key) == 0 {
		return 0, false
	}
	cur := now.Unix() / totpStep
	for d := int64(-totpSkew); d <= totpSkew; d++ {
		st := cur + d
		if st > lastStep && subtle.ConstantTimeCompare([]byte(totpCode(key, st)), []byte(code)) == 1 {
			return st, true
		}
	}
	return 0, false
}

// NewBackupCodes are one-time codes for when the phone with the
// authenticator app is lost ("ABCD-EFGH"); only their hashes are stored.
func NewBackupCodes(n int) ([]string, error) {
	out := make([]string, n)
	for i := range out {
		r, err := randomFrom(keyAlphabet, 10)
		if err != nil {
			return nil, err
		}
		out[i] = r[:5] + "-" + r[5:]
	}
	return out, nil
}
