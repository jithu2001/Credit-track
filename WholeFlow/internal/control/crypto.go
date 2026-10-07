package control

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Sealer encrypts secrets kept in control_db (business service keys and JWT
// secrets) with the server's master key, so a database dump alone reveals nothing.
type Sealer struct{ aead cipher.AEAD }

// NewSealer takes the master key as 64 hex characters (32 bytes).
func NewSealer(masterHex string) (*Sealer, error) {
	key, err := hex.DecodeString(strings.TrimSpace(masterHex))
	if err != nil || len(key) != 32 {
		return nil, errors.New("MASTER_KEY must be 64 hex characters")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &Sealer{aead: aead}, nil
}

// Seal returns "v1:" + base64(nonce|ciphertext).
func (s *Sealer) Seal(plain string) (string, error) {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	out := s.aead.Seal(nonce, nonce, []byte(plain), nil)
	return "v1:" + base64.RawStdEncoding.EncodeToString(out), nil
}

func (s *Sealer) Open(sealed string) (string, error) {
	raw, ok := strings.CutPrefix(sealed, "v1:")
	if !ok {
		return "", errors.New("unknown sealed format")
	}
	data, err := base64.RawStdEncoding.DecodeString(raw)
	if err != nil || len(data) < s.aead.NonceSize() {
		return "", errors.New("corrupt sealed value")
	}
	n := s.aead.NonceSize()
	plain, err := s.aead.Open(nil, data[:n], data[n:], nil)
	if err != nil {
		return "", errors.New("sealed value does not open with this master key")
	}
	return string(plain), nil
}

// ---------------------------------------------------------------- JWT (HS256)

var b64 = base64.RawURLEncoding

// SignJWT signs claims with a business's secret, the same way its login
// service signs user tokens, so its data API accepts the result.
func SignJWT(secret string, claims map[string]any) (string, error) {
	head := b64.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	body, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	unsigned := head + "." + b64.EncodeToString(body)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(unsigned))
	return unsigned + "." + b64.EncodeToString(mac.Sum(nil)), nil
}

// ParseJWTUnverified reads the claims without checking the signature; used
// only to find which business's secret to verify with.
func ParseJWTUnverified(token string) (map[string]any, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, errors.New("malformed token")
	}
	body, err := b64.DecodeString(parts[1])
	if err != nil {
		return nil, errors.New("malformed token")
	}
	var claims map[string]any
	if err := json.Unmarshal(body, &claims); err != nil {
		return nil, errors.New("malformed token")
	}
	return claims, nil
}

// VerifyJWT checks the HS256 signature and expiry and returns the claims.
func VerifyJWT(secret, token string, now time.Time) (map[string]any, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, errors.New("malformed token")
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(parts[0] + "." + parts[1]))
	sig, err := b64.DecodeString(parts[2])
	if err != nil || !hmac.Equal(sig, mac.Sum(nil)) {
		return nil, errors.New("bad signature")
	}
	claims, err := ParseJWTUnverified(token)
	if err != nil {
		return nil, err
	}
	if exp, ok := claims["exp"].(float64); ok && now.Unix() >= int64(exp) {
		return nil, errors.New("token expired")
	}
	return claims, nil
}

// DeviceKey is a Tally PC's own key: full write access to its business
// (role service_role) but refused once its device_id is revoked.
func DeviceKey(secret, slug, deviceID string, now time.Time) (string, error) {
	return SignJWT(secret, map[string]any{
		"iss": "wholeflow", "ref": slug, "role": "service_role", "device_id": deviceID,
		"iat": now.Unix(), "exp": now.AddDate(5, 0, 0).Unix(),
	})
}

// ---------------------------------------------------------------- keys and codes

// No 0/O/1/I/L: read out over the phone and typed by hand.
const keyAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

func randomFrom(alphabet string, n int) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	out := make([]byte, n)
	for i, b := range buf {
		// 256 % 31 bias is ~1%; acceptable for keys that are also rate-limited.
		out[i] = alphabet[int(b)%len(alphabet)]
	}
	return string(out), nil
}

// NewReferenceKey: "JMJ-7K4Q-92XD-PQ3M" (prefix from the slug, ~59 random bits).
func NewReferenceKey(slug string) (string, error) {
	prefix := strings.ToUpper(slug)
	if len(prefix) > 4 {
		prefix = prefix[:4]
	}
	r, err := randomFrom(keyAlphabet, 12)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s-%s-%s-%s", prefix, r[0:4], r[4:8], r[8:12]), nil
}

// NormalizeKey makes typed keys comparable: upper case, no spaces.
func NormalizeKey(k string) string {
	return strings.ToUpper(strings.Join(strings.Fields(k), ""))
}

// NewActivationCode: "K7Q2-M9XD" (~39 random bits, single use, 48 h).
func NewActivationCode() (string, error) {
	r, err := randomFrom(keyAlphabet, 8)
	if err != nil {
		return "", err
	}
	return r[:4] + "-" + r[4:], nil
}

// HashCode stores activation codes as SHA-256 of the normalized code.
func HashCode(code string) string {
	sum := sha256.Sum256([]byte(NormalizeKey(code)))
	return hex.EncodeToString(sum[:])
}

// RandomPassword for an owner's first login (must be changed at first sign-in).
func RandomPassword() (string, error) {
	r, err := randomFrom("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789", 12)
	if err != nil {
		return "", err
	}
	return r, nil
}
