// Package secrets encrypts configuration secrets (the cloud service-role key)
// at rest. On Windows it uses DPAPI in machine scope so both the Windows
// service (LocalSystem) and the developer's console session can decrypt.
// Elsewhere it falls back to an obfuscated-but-not-secret encoding, clearly
// prefixed so nobody mistakes it for encryption.
package secrets

import (
	"encoding/base64"
	"errors"
	"strings"
)

// Store encrypts and decrypts short strings. Encrypted values are prefixed
// with the scheme ("dpapi:" or "plain:") so a file can be moved between
// platforms and fail loudly rather than silently.
type Store interface {
	Encrypt(plain string) (string, error)
	Decrypt(enc string) (string, error)
	// Scheme names the mechanism, for the status page.
	Scheme() string
}

var ErrWrongMachine = errors.New("secret was encrypted on another machine or by another mechanism; re-enter it")

// Plain is the non-Windows fallback. It is NOT encryption.
type Plain struct{}

func (Plain) Scheme() string { return "plain" }

func (Plain) Encrypt(plain string) (string, error) {
	return "plain:" + base64.StdEncoding.EncodeToString([]byte(plain)), nil
}

func (Plain) Decrypt(enc string) (string, error) {
	if enc == "" {
		return "", nil
	}
	if !strings.HasPrefix(enc, "plain:") {
		return "", ErrWrongMachine
	}
	b, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(enc, "plain:"))
	if err != nil {
		return "", err
	}
	return string(b), nil
}
