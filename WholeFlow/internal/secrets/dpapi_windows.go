//go:build windows

package secrets

import (
	"encoding/base64"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

// cryptProtectLocalMachine lets any process on this machine decrypt: the
// service runs as LocalSystem while the developer configures it as a user.
const cryptProtectLocalMachine = 0x4

// DPAPI uses Windows Data Protection API in machine scope.
type DPAPI struct{}

// Default returns the platform's best store.
func Default() Store { return DPAPI{} }

func (DPAPI) Scheme() string { return "dpapi" }

func (DPAPI) Encrypt(plain string) (string, error) {
	if plain == "" {
		return "", nil
	}
	in := windows.DataBlob{Size: uint32(len(plain)), Data: &[]byte(plain)[0]}
	var out windows.DataBlob
	err := windows.CryptProtectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN|cryptProtectLocalMachine, &out)
	if err != nil {
		return "", err
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	enc := unsafe.Slice(out.Data, out.Size)
	return "dpapi:" + base64.StdEncoding.EncodeToString(enc), nil
}

func (DPAPI) Decrypt(enc string) (string, error) {
	if enc == "" {
		return "", nil
	}
	if !strings.HasPrefix(enc, "dpapi:") {
		return "", ErrWrongMachine
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(enc, "dpapi:"))
	if err != nil || len(raw) == 0 {
		return "", ErrWrongMachine
	}
	in := windows.DataBlob{Size: uint32(len(raw)), Data: &raw[0]}
	var out windows.DataBlob
	if err := windows.CryptUnprotectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out); err != nil {
		return "", ErrWrongMachine
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	return string(unsafe.Slice(out.Data, out.Size)), nil
}
