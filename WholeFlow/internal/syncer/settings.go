// Package syncer is the background synchronisation engine: it reads selected
// Tally companies through internal/tally and writes them to a cloud.Provider.
// It knows nothing about Tally XML or about any particular cloud backend.
package syncer

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	gosync "sync"
	"time"

	"wholeflow/internal/secrets"
)

// Version of the sync service, reported to the cloud and the status page.
const Version = "0.4.1"

const (
	ProviderSupabase = "supabase"
	ProviderMemory   = "memory" // dry run: nothing leaves this PC
	// ProviderWholeFlow is the WholeFlow server, connected with a reference
	// key and activation code (see LinkSettings). It speaks the same API as
	// Supabase, with this PC's own key in place of the service key.
	ProviderWholeFlow = "wholeflow"
)

// DefaultControlURL is the WholeFlow control service (activation, heartbeat,
// logins for this app). CONTROL_URL or cloud.controlUrl in config.json override it.
const DefaultControlURL = "https://api.jitsuji.xyz"

// Messages shown when the server refuses this business or PC on purpose.
const (
	MsgSubscriptionEnded = "Subscription ended — sync paused"
	MsgDeviceRevoked     = "This PC's access was revoked. Connect again with a new activation code."
)

// Settings is the persisted configuration (config.json in the data directory).
// Secrets are stored encrypted (see internal/secrets) and never serialised in
// clear text; SupabaseKey is populated in memory only.
type Settings struct {
	Version   int              `json:"version"`
	Business  BusinessSettings `json:"business"`
	Cloud     CloudSettings    `json:"cloud"`
	Sync      SyncSettings     `json:"sync"`
	Companies []CompanySetting `json:"companies"`
}

type BusinessSettings struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type CloudSettings struct {
	Provider       string `json:"provider"`
	SupabaseURL    string `json:"supabaseUrl"`
	SupabaseKeyEnc string `json:"supabaseKeyEnc"`
	SupabaseKey    string `json:"-"`
	// KeyFromEnv is true when the key came from SUPABASE_SERVICE_ROLE_KEY and
	// is therefore not saved to the file.
	KeyFromEnv bool `json:"-"`
	// KeyError is set when the stored key could not be decrypted (moved machine).
	KeyError string `json:"-"`
	// ControlURL overrides DefaultControlURL (normally empty).
	ControlURL string `json:"controlUrl,omitempty"`
	// Link is the connection made with a reference key (Provider "wholeflow").
	Link LinkSettings `json:"link"`
}

// LinkSettings is what /control/activate returned for this PC. DeviceKey is
// stored encrypted like the Supabase key; the business id and name go to
// BusinessSettings.
type LinkSettings struct {
	ReferenceKey      string     `json:"referenceKey,omitempty"`
	BaseURL           string     `json:"baseUrl,omitempty"`
	DeviceID          string     `json:"deviceId,omitempty"`
	BusinessName      string     `json:"businessName,omitempty"`
	DeviceKeyEnc      string     `json:"deviceKeyEnc,omitempty"`
	DeviceKey         string     `json:"-"`
	KeyError          string     `json:"-"`
	MaxCompanies      int        `json:"maxCompanies,omitempty"`
	SubscriptionState string     `json:"subscriptionState,omitempty"`
	ConnectedAt       *time.Time `json:"connectedAt,omitempty"`
	// Revoked is set when the server said this PC's key was revoked; the
	// sync stops until the PC is connected again.
	Revoked bool `json:"revoked,omitempty"`
}

// Connected reports whether a reference-key connection is stored.
func (l LinkSettings) Connected() bool {
	return l.BaseURL != "" && (l.DeviceKey != "" || l.DeviceKeyEnc != "")
}

type SyncSettings struct {
	Enabled            bool `json:"enabled"`
	IntervalSeconds    int  `json:"intervalSeconds"`
	Transactions       bool `json:"transactions"`
	FullReconcileHours int  `json:"fullReconcileHours"`
	// Suppliers, Purchases and Inventory switch the purchasing sync steps.
	// They default to on, also for config files written before they existed.
	Suppliers bool `json:"suppliers"`
	Purchases bool `json:"purchases"`
	Inventory bool `json:"inventory"`
}

func (s SyncSettings) Interval() time.Duration { return time.Duration(s.IntervalSeconds) * time.Second }

type CompanySetting struct {
	TallyID string `json:"tallyId"` // Tally company GUID
	Name    string `json:"name"`
	Enabled bool   `json:"enabled"`
}

const (
	DefaultInterval      = 300
	MinInterval          = 60
	MaxInterval          = 86400
	DefaultReconcileHrs  = 24
	settingsFileVersion  = 1
	settingsFileName     = "config.json"
	stateFileName        = "state.json"
	controlTokenFileName = "control.token"
)

func defaultSettings() Settings {
	return Settings{
		Version: settingsFileVersion,
		Cloud:   CloudSettings{Provider: ProviderSupabase},
		Sync: SyncSettings{Enabled: false, IntervalSeconds: DefaultInterval, Transactions: true, FullReconcileHours: DefaultReconcileHrs,
			Suppliers: true, Purchases: true, Inventory: true},
	}
}

// EnabledCompanies returns the companies selected for synchronisation.
func (s Settings) EnabledCompanies() []CompanySetting {
	var out []CompanySetting
	for _, c := range s.Companies {
		if c.Enabled && c.TallyID != "" {
			out = append(out, c)
		}
	}
	return out
}

// ControlURL is the control service address in effect.
func (s Settings) ControlURL() string {
	if u := strings.TrimSpace(s.Cloud.ControlURL); u != "" {
		return u
	}
	return DefaultControlURL
}

// Linked reports whether the sync uses the reference-key connection.
func (s Settings) Linked() bool { return s.Cloud.Provider == ProviderWholeFlow }

// CompanyLimit is the plan's company limit, or 0 when none applies (only the
// reference-key connection has one).
func (s Settings) CompanyLimit() int {
	if !s.Linked() || s.Cloud.Link.MaxCompanies <= 0 {
		return 0
	}
	return s.Cloud.Link.MaxCompanies
}

// SyncCompanies is EnabledCompanies cut to the plan's limit, in the same
// order; over is how many ticked companies were left out.
func (s Settings) SyncCompanies() (list []CompanySetting, over int) {
	list = s.EnabledCompanies()
	if n := s.CompanyLimit(); n > 0 && len(list) > n {
		return list[:n], len(list) - n
	}
	return list, 0
}

// CompanyLimitError is the refusal when more companies are ticked than the plan allows.
func CompanyLimitError(n int) error {
	if n == 1 {
		return errors.New("Your plan allows 1 company. Ask WholeFlow support to upgrade.")
	}
	return fmt.Errorf("Your plan allows %d companies. Ask WholeFlow support to upgrade.", n)
}

// CompanyLimitWarning explains which companies the sync leaves out.
func CompanyLimitWarning(limit, ticked int) string {
	return fmt.Sprintf("Your plan allows %d companies but %d are ticked: only the first %d are synced. Untick the others or ask WholeFlow support to upgrade.", limit, ticked, limit)
}

// Configured reports whether enough is set to attempt a sync. The admin
// login is not needed: the background sync runs without anyone logged in.
func (s Settings) Configured() (bool, string) {
	switch {
	case s.Linked() && s.Cloud.Link.Revoked:
		return false, MsgDeviceRevoked
	case s.Linked() && s.Cloud.Link.KeyError != "":
		return false, "the stored PC key cannot be read on this machine: connect again with a new activation code"
	case s.Linked() && (s.Cloud.Link.BaseURL == "" || s.Cloud.Link.DeviceKey == ""):
		return false, "not connected: enter the reference key and activation code"
	case s.Business.ID == "":
		return false, "business id not set"
	case s.Cloud.Provider == "":
		return false, "cloud provider not set"
	case s.Cloud.Provider == ProviderSupabase && (s.Cloud.SupabaseURL == "" || s.Cloud.SupabaseKey == ""):
		return false, "Supabase URL or key not set"
	case len(s.EnabledCompanies()) == 0:
		return false, "no company selected"
	}
	return true, ""
}

// Validate enforces ranges and required shapes.
func (s Settings) Validate() error {
	if s.Sync.IntervalSeconds < MinInterval || s.Sync.IntervalSeconds > MaxInterval {
		return fmt.Errorf("sync interval must be between %d and %d seconds", MinInterval, MaxInterval)
	}
	if s.Sync.FullReconcileHours < 1 || s.Sync.FullReconcileHours > 24*30 {
		return errors.New("full reconcile hours must be between 1 and 720")
	}
	switch s.Cloud.Provider {
	case ProviderSupabase, ProviderMemory, ProviderWholeFlow:
	default:
		return fmt.Errorf("unknown cloud provider %q", s.Cloud.Provider)
	}
	if s.Cloud.Provider == ProviderSupabase && s.Cloud.SupabaseURL != "" && !strings.HasPrefix(strings.ToLower(s.Cloud.SupabaseURL), "https://") &&
		!strings.HasPrefix(strings.ToLower(s.Cloud.SupabaseURL), "http://localhost") && !strings.HasPrefix(strings.ToLower(s.Cloud.SupabaseURL), "http://127.0.0.1") {
		return errors.New("Supabase URL must start with https://")
	}
	for _, u := range []struct{ name, url string }{{"WholeFlow server address", s.Cloud.ControlURL}, {"business address", s.Cloud.Link.BaseURL}} {
		if u.url != "" && !secureURL(u.url) {
			return errors.New(u.name + " must start with https://")
		}
	}
	seen := map[string]bool{}
	for _, c := range s.Companies {
		if c.TallyID == "" {
			return errors.New("company without Tally id")
		}
		if seen[c.TallyID] {
			return fmt.Errorf("company %s listed twice", c.TallyID)
		}
		seen[c.TallyID] = true
	}
	return nil
}

// secureURL accepts https, and http only to this PC (tests, development).
func secureURL(u string) bool {
	l := strings.ToLower(strings.TrimSpace(u))
	return strings.HasPrefix(l, "https://") || strings.HasPrefix(l, "http://localhost") || strings.HasPrefix(l, "http://127.0.0.1")
}

// ---------------------------------------------------------------- store

// SettingsStore is the thread-safe, persisted settings with environment overrides.
type SettingsStore struct {
	path    string
	secrets secrets.Store
	mu      gosync.RWMutex
	s       Settings
	// envOverrides lists which fields came from the environment, for the UI.
	envOverrides []string
	// hadStoredLogins: config.json still holds logins of versions before
	// 0.4.1 (local account, remembered offline logins); the next save drops
	// them (Settings has no such fields).
	hadStoredLogins bool
}

// LoadSettings reads config.json (creating defaults if absent) and applies
// environment overrides on top. Environment values are never written back.
func LoadSettings(dataDir string, sec secrets.Store) (*SettingsStore, error) {
	st := &SettingsStore{path: filepath.Join(dataDir, settingsFileName), secrets: sec, s: defaultSettings()}
	b, err := os.ReadFile(st.path)
	switch {
	case err == nil:
		var loaded Settings
		if err := json.Unmarshal(b, &loaded); err != nil {
			return nil, fmt.Errorf("%s: %w", st.path, err)
		}
		st.s = merge(defaultSettings(), loaded)
		var old struct {
			Developer *json.RawMessage  `json:"developer"`
			PCLogins  []json.RawMessage `json:"pcLogins"`
		}
		st.hadStoredLogins = json.Unmarshal(b, &old) == nil && (old.Developer != nil || len(old.PCLogins) > 0)
		defaultNewSyncOptions(b, &st.s)
	case errors.Is(err, os.ErrNotExist):
		// first run: keep defaults
	default:
		return nil, err
	}
	if st.s.Cloud.SupabaseKeyEnc != "" {
		key, err := sec.Decrypt(st.s.Cloud.SupabaseKeyEnc)
		if err != nil {
			st.s.Cloud.KeyError = err.Error()
		} else {
			st.s.Cloud.SupabaseKey = key
		}
	}
	if st.s.Cloud.Link.DeviceKeyEnc != "" {
		key, err := sec.Decrypt(st.s.Cloud.Link.DeviceKeyEnc)
		if err != nil {
			st.s.Cloud.Link.KeyError = err.Error()
		} else {
			st.s.Cloud.Link.DeviceKey = key
		}
	}
	st.applyEnv()
	return st, nil
}

func merge(def, loaded Settings) Settings {
	out := loaded
	if out.Sync.IntervalSeconds == 0 {
		out.Sync.IntervalSeconds = def.Sync.IntervalSeconds
	}
	if out.Sync.FullReconcileHours == 0 {
		out.Sync.FullReconcileHours = def.Sync.FullReconcileHours
	}
	if out.Cloud.Provider == "" {
		out.Cloud.Provider = def.Cloud.Provider
	}
	out.Version = settingsFileVersion
	return out
}

func (st *SettingsStore) applyEnv() {
	set := func(name string, apply func(string)) {
		if v := strings.TrimSpace(os.Getenv(name)); v != "" {
			apply(v)
			st.envOverrides = append(st.envOverrides, name)
		}
	}
	set("CLOUD_PROVIDER", func(v string) { st.s.Cloud.Provider = strings.ToLower(v) })
	set("CONTROL_URL", func(v string) { st.s.Cloud.ControlURL = v })
	set("SUPABASE_URL", func(v string) { st.s.Cloud.SupabaseURL = v })
	set("SUPABASE_SERVICE_ROLE_KEY", func(v string) { st.s.Cloud.SupabaseKey, st.s.Cloud.KeyFromEnv, st.s.Cloud.KeyError = v, true, "" })
	set("BUSINESS_ID", func(v string) { st.s.Business.ID = v })
	set("BUSINESS_NAME", func(v string) { st.s.Business.Name = v })
	set("SYNC_INTERVAL_SECONDS", func(v string) {
		if n, err := strconv.Atoi(v); err == nil {
			n = min(max(n, MinInterval), MaxInterval) // Validate does not run on env values
			st.s.Sync.IntervalSeconds = n
		}
	})
	set("SYNC_TRANSACTIONS", func(v string) { st.s.Sync.Transactions = isTrue(v) })
	set("SYNC_ENABLED", func(v string) { st.s.Sync.Enabled = isTrue(v) })
	set("SYNC_SUPPLIERS", func(v string) { st.s.Sync.Suppliers = isTrue(v) })
	set("SYNC_PURCHASES", func(v string) { st.s.Sync.Purchases = isTrue(v) })
	set("SYNC_INVENTORY", func(v string) { st.s.Sync.Inventory = isTrue(v) })
	set("SYNC_COMPANIES", func(v string) {
		// Comma-separated Tally company GUIDs to enable (headless setups).
		for _, id := range strings.Split(v, ",") {
			id = strings.TrimSpace(id)
			if id == "" {
				continue
			}
			found := false
			for i := range st.s.Companies {
				if st.s.Companies[i].TallyID == id {
					st.s.Companies[i].Enabled, found = true, true
				}
			}
			if !found {
				st.s.Companies = append(st.s.Companies, CompanySetting{TallyID: id, Enabled: true})
			}
		}
	})
}

func isTrue(v string) bool {
	switch strings.ToLower(v) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

// Get returns a copy of the current settings.
func (st *SettingsStore) Get() Settings {
	st.mu.RLock()
	defer st.mu.RUnlock()
	s := st.s
	s.Companies = append([]CompanySetting(nil), s.Companies...)
	return s
}

// HadStoredLogins reports whether config.json still holds logins of older
// versions (local account, offline logins); any Update rewrites it without them.
func (st *SettingsStore) HadStoredLogins() bool {
	st.mu.RLock()
	defer st.mu.RUnlock()
	return st.hadStoredLogins
}

// EnvOverrides lists environment variables that override the file.
func (st *SettingsStore) EnvOverrides() []string { return append([]string(nil), st.envOverrides...) }

// Path is the settings file location.
func (st *SettingsStore) Path() string { return st.path }

// Update applies fn under the lock, validates, encrypts secrets and saves.
func (st *SettingsStore) Update(fn func(*Settings) error) error {
	st.mu.Lock()
	defer st.mu.Unlock()
	next := st.s
	next.Companies = append([]CompanySetting(nil), next.Companies...)
	if err := fn(&next); err != nil {
		return err
	}
	if err := next.Validate(); err != nil {
		return err
	}
	if !next.Cloud.KeyFromEnv {
		if next.Cloud.SupabaseKey != "" {
			enc, err := st.secrets.Encrypt(next.Cloud.SupabaseKey)
			if err != nil {
				return fmt.Errorf("encrypt key: %w", err)
			}
			next.Cloud.SupabaseKeyEnc, next.Cloud.KeyError = enc, ""
		} else if next.Cloud.KeyError == "" {
			next.Cloud.SupabaseKeyEnc = ""
		}
	}
	if next.Cloud.Link.DeviceKey != "" {
		enc, err := st.secrets.Encrypt(next.Cloud.Link.DeviceKey)
		if err != nil {
			return fmt.Errorf("encrypt key: %w", err)
		}
		next.Cloud.Link.DeviceKeyEnc, next.Cloud.Link.KeyError = enc, ""
	} else if next.Cloud.Link.KeyError == "" {
		next.Cloud.Link.DeviceKeyEnc = ""
	}
	if err := writeJSONAtomic(st.path, next); err != nil {
		return err
	}
	st.s = next
	st.hadStoredLogins = false
	return nil
}

// writeJSONAtomic writes via a temp file and rename so a crash never leaves a
// half-written config or state file.
func writeJSONAtomic(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		// Windows refuses to rename over an open file; fall back to replace.
		os.Remove(path)
		if err2 := os.Rename(tmp, path); err2 != nil {
			return err
		}
	}
	return nil
}

// defaultNewSyncOptions turns on sync options that a config file written by an
// older version does not mention (absent keys unmarshal as false).
func defaultNewSyncOptions(raw []byte, s *Settings) {
	var probe struct {
		Sync map[string]json.RawMessage `json:"sync"`
	}
	if json.Unmarshal(raw, &probe) != nil {
		return
	}
	for key, field := range map[string]*bool{"suppliers": &s.Sync.Suppliers, "purchases": &s.Sync.Purchases, "inventory": &s.Sync.Inventory} {
		if _, present := probe.Sync[key]; !present {
			*field = true
		}
	}
}
