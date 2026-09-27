package secrets

import (
	"strings"
	"testing"
)

func TestDefaultRoundTrip(t *testing.T) {
	s := Default()
	enc, err := s.Encrypt("service-role-key-value")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(enc, "service-role-key-value") || !strings.HasPrefix(enc, s.Scheme()+":") {
		t.Fatalf("encoded value leaks or lacks prefix: %s", enc)
	}
	dec, err := s.Decrypt(enc)
	if err != nil || dec != "service-role-key-value" {
		t.Fatalf("decrypt: %q %v", dec, err)
	}
	if v, err := s.Decrypt(""); err != nil || v != "" {
		t.Fatal("empty must round-trip")
	}
	if _, err := s.Decrypt("other:AAAA"); err == nil {
		t.Fatal("foreign scheme must be rejected")
	}
}

func TestPlainIsMarkedAsSuch(t *testing.T) {
	enc, _ := Plain{}.Encrypt("x")
	if !strings.HasPrefix(enc, "plain:") {
		t.Fatal(enc)
	}
}
