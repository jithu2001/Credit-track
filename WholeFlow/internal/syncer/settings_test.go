package syncer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"wholeflow/internal/secrets"
)

func TestSettingsRoundTripEncryptsKey(t *testing.T) {
	dir := t.TempDir()
	st, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if err := st.Update(func(s *Settings) error {
		s.Business.ID = "b"
		s.Cloud.Link = LinkSettings{BaseURL: "https://api.example/b/demo", DeviceKey: "super-secret"}
		s.Companies = []CompanySetting{{TallyID: "g1", Name: "Co", Enabled: true}}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, settingsFileName))
	if string(raw) == "" || containsStr(string(raw), "super-secret") {
		t.Fatalf("key must not be stored in clear text: %s", raw)
	}
	again, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	s := again.Get()
	if s.Cloud.Link.DeviceKey != "super-secret" || s.Business.ID != "b" || len(s.Companies) != 1 || s.Sync.IntervalSeconds != DefaultInterval {
		t.Fatalf("reloaded: %+v", s)
	}
}

func TestSettingsValidation(t *testing.T) {
	dir := t.TempDir()
	st, _ := LoadSettings(dir, secrets.Plain{})
	if err := st.Update(func(s *Settings) error { s.Sync.IntervalSeconds = 10; return nil }); err == nil {
		t.Error("interval below minimum accepted")
	}
	if err := st.Update(func(s *Settings) error { s.Cloud.Provider = "firebase"; return nil }); err == nil {
		t.Error("unknown provider accepted")
	}
	if err := st.Update(func(s *Settings) error { s.Cloud.Link.BaseURL = "http://evil.example"; return nil }); err == nil {
		t.Error("non-https URL accepted")
	}
	if err := st.Update(func(s *Settings) error { s.Companies = []CompanySetting{{TallyID: "a"}, {TallyID: "a"}}; return nil }); err == nil {
		t.Error("duplicate company accepted")
	}
	if st.Get().Sync.IntervalSeconds != DefaultInterval {
		t.Error("failed update must not change settings")
	}
}

func TestEnvOverrides(t *testing.T) {
	t.Setenv("SYNC_INTERVAL_SECONDS", "600")
	t.Setenv("SYNC_COMPANIES", "g1, g2")
	t.Setenv("CLOUD_PROVIDER", "memory")
	st, err := LoadSettings(t.TempDir(), secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	s := st.Get()
	if s.Cloud.Provider != ProviderMemory || s.Business.ID != DryRunBusinessID || s.Sync.IntervalSeconds != 600 || len(s.EnabledCompanies()) != 2 {
		t.Fatalf("%+v", s)
	}
	if ok, why := s.Configured(); !ok {
		t.Fatalf("dry run not configured: %s", why)
	}
}

// An old .env may still say CLOUD_PROVIDER=supabase and hold the old URL and
// key: they are ignored and the PC can still save its settings.
func TestOldEnvIsIgnored(t *testing.T) {
	t.Setenv("CLOUD_PROVIDER", "supabase")
	t.Setenv("SUPABASE_URL", "https://x.example")
	t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "env-key")
	t.Setenv("BUSINESS_ID", "biz")
	st, err := LoadSettings(t.TempDir(), secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	s := st.Get()
	if s.Cloud.Provider != ProviderWholeFlow || s.Business.ID != "" || len(st.EnvOverrides()) != 0 {
		t.Fatalf("%+v %v", s, st.EnvOverrides())
	}
	if err := st.Update(func(s *Settings) error { s.Sync.Enabled = true; return nil }); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(st.Path())
	if containsStr(string(raw), "env-key") || containsStr(string(raw), "x.example") {
		t.Fatal("old environment values were written to disk")
	}
}

func TestConfigured(t *testing.T) {
	s := defaultSettings()
	if ok, why := s.Configured(); ok || why == "" {
		t.Fatal("empty settings must not be configured")
	}
	if ok, why := s.Configured(); ok || !strings.Contains(why, "not connected") {
		t.Fatalf("not connected: %q", why)
	}
	s.Business.ID = "b"
	s.Cloud.Link = LinkSettings{BaseURL: "https://api.example/b/demo", DeviceKey: "k"}
	if ok, why := s.Configured(); ok || why != "no company selected" {
		t.Fatal(why)
	}
	s.Companies = []CompanySetting{{TallyID: "g", Enabled: true}}
	if ok, _ := s.Configured(); !ok {
		t.Fatal("should be configured")
	}
}

func TestStateSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	st, _ := LoadState(dir)
	st.UpdateCompany("g1", func(c *CompanyState) { c.VoucherCursor = 42; c.Status = StatusSynced })
	again, err := LoadState(dir)
	if err != nil {
		t.Fatal(err)
	}
	if c := again.Company("g1"); c.VoucherCursor != 42 || c.Status != StatusSynced {
		t.Fatalf("%+v", c)
	}
	os.WriteFile(filepath.Join(dir, stateFileName), []byte("{corrupt"), 0o600)
	fresh, err := LoadState(dir)
	if err != nil || fresh.Company("g1").VoucherCursor != 0 {
		t.Fatal("corrupt state must reset to a full sync, not fail")
	}
}

func containsStr(s, sub string) bool { return len(sub) > 0 && len(s) >= len(sub) && index(s, sub) >= 0 }

func index(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

// Versions before 0.4.1 kept a local login and remembered offline logins in
// config.json. They are no longer read, and the first save drops them.
func TestOldLocalAccountIsDropped(t *testing.T) {
	dir := t.TempDir()
	old := `{"version":1,"business":{"id":"b"},"developer":{"username":"admin","passwordHash":"pbkdf2-sha256$1$x$y"},` +
		`"pcLogins":[{"email":"a@b.c","passwordHash":"pbkdf2-sha256$1$p$q","offlineUntil":"2099-01-01T00:00:00Z"}]}`
	if err := os.WriteFile(filepath.Join(dir, settingsFileName), []byte(old), 0o600); err != nil {
		t.Fatal(err)
	}
	st, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if !st.HadStoredLogins() {
		t.Fatal("old stored logins not noticed")
	}
	if err := st.Update(func(*Settings) error { return nil }); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, settingsFileName))
	if strings.Contains(string(b), "developer") || strings.Contains(string(b), "pcLogins") || strings.Contains(string(b), "pbkdf2") || st.HadStoredLogins() {
		t.Fatalf("logins still in config.json: %s", b)
	}
	if st.Get().Business.ID != "b" {
		t.Fatal("other settings lost")
	}
}

// Versions before 0.5.0 could connect straight to a cloud project with its URL
// and service key. Such a PC loads as not connected (it must connect with a
// reference key) and the first save drops the old fields.
func TestOldDirectCloudIsDropped(t *testing.T) {
	dir := t.TempDir()
	old := `{"version":1,"business":{"id":"11111111-1111-1111-1111-111111111111","name":"JMJ"},` +
		`"cloud":{"provider":"supabase","supabaseUrl":"https://x.example","supabaseKeyEnc":"plain:service-key","link":{}},` +
		`"sync":{"enabled":true,"intervalSeconds":600,"transactions":true,"fullReconcileHours":24},` +
		`"companies":[{"tallyId":"g1","name":"Co","enabled":true}]}`
	if err := os.WriteFile(filepath.Join(dir, settingsFileName), []byte(old), 0o600); err != nil {
		t.Fatal(err)
	}
	st, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if !st.HadOldCloud() {
		t.Fatal("old direct connection not noticed")
	}
	s := st.Get()
	if ok, why := s.Configured(); ok || !strings.Contains(why, "not connected") {
		t.Fatalf("old PC must count as not connected: %v %q", ok, why)
	}
	if s.Cloud.Provider != ProviderWholeFlow || s.Business.ID != "" || s.Cloud.Link.Connected() {
		t.Fatalf("loaded: %+v %+v", s.Business, s.Cloud)
	}
	if err := st.Update(func(*Settings) error { return nil }); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, settingsFileName))
	for _, gone := range []string{"supabase", "x.example", "service-key", "11111111"} {
		if strings.Contains(string(b), gone) {
			t.Fatalf("%q still in config.json: %s", gone, b)
		}
	}
	if st.HadOldCloud() {
		t.Fatal("still flagged after the save")
	}
	again, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if s := again.Get(); again.HadOldCloud() || s.Sync.IntervalSeconds != 600 || !s.Sync.Enabled || len(s.EnabledCompanies()) != 1 {
		t.Fatalf("other settings lost: %+v", s)
	}
}

// A PC that used the direct connection and was later connected by reference
// key keeps that connection; only the old fields go.
func TestOldFieldsDroppedFromConnectedPC(t *testing.T) {
	dir := t.TempDir()
	old := `{"version":1,"business":{"id":"biz-demo","name":"Demo"},` +
		`"cloud":{"provider":"wholeflow","supabaseUrl":"https://x.example","supabaseKeyEnc":"plain:service-key",` +
		`"link":{"baseUrl":"https://api.example/b/demo","deviceKeyEnc":"plain:cGMta2V5"}},"companies":[{"tallyId":"g1","enabled":true}]}`
	if err := os.WriteFile(filepath.Join(dir, settingsFileName), []byte(old), 0o600); err != nil {
		t.Fatal(err)
	}
	st, err := LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if !st.HadOldCloud() {
		t.Fatal("old fields not noticed")
	}
	if ok, why := st.Get().Configured(); !ok || st.Get().Business.ID != "biz-demo" {
		t.Fatalf("connection lost: %q", why)
	}
	if err := st.Update(func(*Settings) error { return nil }); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, settingsFileName)); strings.Contains(string(b), "supabase") || strings.Contains(string(b), "service-key") {
		t.Fatalf("old fields still in config.json: %s", b)
	}
}
