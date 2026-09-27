package syncer

import (
	"os"
	"path/filepath"
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
		s.Cloud.SupabaseURL = "https://x.supabase.co"
		s.Cloud.SupabaseKey = "super-secret"
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
	if s.Cloud.SupabaseKey != "super-secret" || s.Business.ID != "b" || len(s.Companies) != 1 || s.Sync.IntervalSeconds != DefaultInterval {
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
	if err := st.Update(func(s *Settings) error { s.Cloud.SupabaseURL = "http://evil.example"; return nil }); err == nil {
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
	t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "env-key")
	t.Setenv("SYNC_INTERVAL_SECONDS", "600")
	t.Setenv("SYNC_COMPANIES", "g1, g2")
	t.Setenv("BUSINESS_ID", "biz")
	st, err := LoadSettings(t.TempDir(), secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	s := st.Get()
	if s.Cloud.SupabaseKey != "env-key" || !s.Cloud.KeyFromEnv || s.Sync.IntervalSeconds != 600 || s.Business.ID != "biz" || len(s.EnabledCompanies()) != 2 {
		t.Fatalf("%+v", s)
	}
	// Saving must not persist the env key.
	if err := st.Update(func(s *Settings) error { s.Business.Name = "n"; return nil }); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(st.Path())
	if containsStr(string(raw), "env-key") {
		t.Fatal("environment key was written to disk")
	}
}

func TestConfigured(t *testing.T) {
	s := defaultSettings()
	if ok, why := s.Configured(); ok || why == "" {
		t.Fatal("empty settings must not be configured")
	}
	s.Developer.PasswordHash, s.Business.ID = "h", "b"
	s.Cloud.SupabaseURL, s.Cloud.SupabaseKey = "https://x", "k"
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
