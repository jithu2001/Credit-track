package admin

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"wholeflow/internal/auth"
	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/memory"
	"wholeflow/internal/config"
	"wholeflow/internal/secrets"
	"wholeflow/internal/syncer"
	"wholeflow/internal/tally"
)

func newTestServer(t *testing.T, withPassword bool) (*httptest.Server, *Server) {
	t.Helper()
	dir := t.TempDir()
	set, err := syncer.LoadSettings(dir, secrets.Plain{})
	if err != nil {
		t.Fatal(err)
	}
	if withPassword {
		hash, _ := auth.HashPassword("admin-secret-1")
		set.Update(func(s *syncer.Settings) error {
			s.Developer = syncer.DeveloperSettings{Username: "admin", PasswordHash: hash}
			s.Business.ID = "biz"
			s.Cloud.Provider = syncer.ProviderMemory
			return nil
		})
	}
	state, _ := syncer.LoadState(dir)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	client := tally.NewClient("127.0.0.1", 1, time.Second, log, dir, false)
	svc := tally.NewService(client, log, "127.0.0.1", 1, []string{"Sundry Debtors"})
	store := memory.New("biz")
	engine := &syncer.Engine{Tally: svc, Provider: func(syncer.Settings) (cloud.Provider, error) { return store, nil },
		Settings: set, State: state, Log: log}
	s := &Server{Settings: set, Scheduler: syncer.NewScheduler(engine, set, log), Engine: engine, Tally: svc,
		Cfg: &config.Config{PortSource: "test", ShopGroups: []string{"Sundry Debtors"}}, Provider: engine.Provider,
		Sessions: auth.NewSessions(time.Hour), Limiter: auth.NewLimiter(3, time.Minute, time.Minute), Log: log,
		LogPath: dir + "/app.log", DataDir: dir, ControlToken: "ctl-token", SecretScheme: "plain"}
	mux := http.NewServeMux()
	s.Routes(mux)
	// The web app's API is mounted the same way main does it.
	webAPI := http.NewServeMux()
	webAPI.HandleFunc("GET /api/dashboard", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "dashboard") })
	webAPI.HandleFunc("POST /api/tally/refresh", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "refreshed") })
	mux.Handle("/api/", s.RequireLogin(webAPI))
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts, s
}

type client struct {
	t      *testing.T
	base   string
	cookie *http.Cookie
	bearer string
}

func (c *client) do(method, path string, body string, csrf bool) (*http.Response, string) {
	c.t.Helper()
	req, _ := http.NewRequest(method, c.base+path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if csrf {
		req.Header.Set("X-Requested-With", "WholeFlowSync")
	}
	if c.cookie != nil {
		req.AddCookie(c.cookie)
	}
	if c.bearer != "" {
		req.Header.Set("Authorization", "Bearer "+c.bearer)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	for _, ck := range resp.Cookies() {
		if ck.Name == sessionCookie {
			if ck.MaxAge < 0 {
				c.cookie = nil
			} else {
				c.cookie = ck
			}
		}
	}
	return resp, string(b)
}

func (c *client) login(password string) *http.Response {
	resp, _ := c.do("POST", "/api/sync/login", `{"username":"admin","password":"`+password+`"}`, true)
	return resp
}

func TestSetupRequiredWithoutPassword(t *testing.T) {
	ts, _ := newTestServer(t, false)
	c := &client{t: t, base: ts.URL}
	_, body := c.do("GET", "/api/sync/session", "", false)
	if !strings.Contains(body, `"setupRequired":true`) {
		t.Fatal(body)
	}
	resp, _ := c.do("POST", "/api/sync/login", `{"username":"admin","password":"anything-at-all"}`, true)
	if resp.StatusCode != http.StatusConflict {
		t.Fatalf("login without a configured password must be refused, got %d", resp.StatusCode)
	}
	if resp, _ := c.do("GET", "/api/dashboard", "", false); resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("web app reachable without any account: %d", resp.StatusCode)
	}
}

func TestFirstRunSetupFromBrowser(t *testing.T) {
	ts, s := newTestServer(t, false)
	c := &client{t: t, base: ts.URL}
	if resp, _ := c.do("POST", "/api/sync/setup", `{"username":"admin","password":"first-password-1","confirm":"first-password-1"}`, false); resp.StatusCode != http.StatusForbidden {
		t.Fatalf("setup without CSRF header = %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/setup", `{"username":"admin","password":"short","confirm":"short"}`, true); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("weak password accepted: %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/setup", `{"username":"admin","password":"first-password-1","confirm":"other-password-1"}`, true); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("mismatch accepted: %d", resp.StatusCode)
	}
	resp, body := c.do("POST", "/api/sync/setup", `{"username":"","password":"first-password-1","confirm":"first-password-1"}`, true)
	if resp.StatusCode != http.StatusOK || !strings.Contains(body, `"username":"admin"`) || c.cookie == nil {
		t.Fatalf("setup = %d %s cookie=%v", resp.StatusCode, body, c.cookie)
	}
	if got := s.Settings.Get().Developer; got.Username != "admin" || !auth.VerifyPassword(got.PasswordHash, "first-password-1") {
		t.Fatalf("account not stored: %+v", got)
	}
	// Logged in straight away, and setup can never run again.
	if resp, _ := c.do("GET", "/api/dashboard", "", false); resp.StatusCode != http.StatusOK {
		t.Fatalf("not logged in after setup: %d", resp.StatusCode)
	}
	other := &client{t: t, base: ts.URL}
	if resp, _ := other.do("POST", "/api/sync/setup", `{"username":"x","password":"another-password-1","confirm":"another-password-1"}`, true); resp.StatusCode != http.StatusConflict {
		t.Fatalf("second setup accepted: %d", resp.StatusCode)
	}
	if _, body := other.do("GET", "/api/sync/session", "", false); !strings.Contains(body, `"setupRequired":false`) {
		t.Fatal(body)
	}
}

func TestWholeAppRequiresLogin(t *testing.T) {
	ts, _ := newTestServer(t, true)
	c := &client{t: t, base: ts.URL}
	for _, p := range []string{"/api/dashboard", "/api/sync/status", "/api/sync/summary", "/api/sync/settings"} {
		if resp, _ := c.do("GET", p, "", false); resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("%s served without login: %d", p, resp.StatusCode)
		}
	}
	if resp := c.login("admin-secret-1"); resp.StatusCode != http.StatusOK || c.cookie == nil || !c.cookie.HttpOnly || c.cookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("login = %d cookie=%+v", resp.StatusCode, c.cookie)
	}
	if resp, body := c.do("GET", "/api/dashboard", "", false); resp.StatusCode != http.StatusOK || body != "dashboard" {
		t.Fatalf("dashboard after login = %d %s", resp.StatusCode, body)
	}
	if resp, body := c.do("GET", "/api/sync/summary", "", false); resp.StatusCode != http.StatusOK || !strings.Contains(body, `"state":`) || strings.Contains(body, "tallyId") {
		t.Fatalf("summary = %d %s", resp.StatusCode, body)
	}
	// Mutations need the CSRF header even with a valid cookie — web app and sync API alike.
	if resp, _ := c.do("POST", "/api/tally/refresh", "", false); resp.StatusCode != http.StatusForbidden {
		t.Fatalf("refresh without CSRF header = %d", resp.StatusCode)
	}
	if resp, body := c.do("POST", "/api/tally/refresh", "", true); resp.StatusCode != http.StatusOK || body != "refreshed" {
		t.Fatalf("refresh = %d %s", resp.StatusCode, body)
	}
	if resp, _ := c.do("PUT", "/api/sync/settings", `{}`, false); resp.StatusCode != http.StatusForbidden {
		t.Fatalf("PUT without CSRF header = %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/logout", "", true); resp.StatusCode != http.StatusOK || c.cookie != nil {
		t.Fatalf("logout = %d", resp.StatusCode)
	}
	if resp, _ := c.do("GET", "/api/dashboard", "", false); resp.StatusCode != http.StatusUnauthorized {
		t.Fatal("session should be gone after logout")
	}
}

func TestLoginRejectsBadCredentialsAndLocksOut(t *testing.T) {
	ts, _ := newTestServer(t, true)
	c := &client{t: t, base: ts.URL}
	if resp, _ := c.do("POST", "/api/sync/login", `{"username":"admin","password":"admin-secret-1"}`, false); resp.StatusCode != http.StatusForbidden {
		t.Fatalf("login without CSRF header = %d", resp.StatusCode)
	}
	for i := 0; i < 3; i++ {
		if resp := c.login("wrong-password"); resp.StatusCode != http.StatusUnauthorized || c.cookie != nil {
			t.Fatalf("bad password = %d", resp.StatusCode)
		}
	}
	if resp := c.login("admin-secret-1"); resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("expected lockout, got %d", resp.StatusCode)
	}
}

func TestControlToken(t *testing.T) {
	ts, _ := newTestServer(t, true)
	cli := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	if resp, _ := cli.do("GET", "/api/sync/status", "", false); resp.StatusCode != http.StatusOK {
		t.Fatalf("control token rejected: %d", resp.StatusCode)
	}
	bad := &client{t: t, base: ts.URL, bearer: "nope"}
	if resp, _ := bad.do("GET", "/api/sync/status", "", false); resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("wrong token accepted: %d", resp.StatusCode)
	}
}

func TestSettingsNeverEchoKey(t *testing.T) {
	ts, s := newTestServer(t, true)
	c := &client{t: t, base: ts.URL}
	c.login("admin-secret-1")
	body := `{"business":{"id":"biz","name":"JMJ"},"cloud":{"provider":"supabase","supabaseUrl":"https://x.supabase.co","supabaseKey":"sk-very-secret"},
	          "sync":{"enabled":false,"intervalSeconds":600,"transactions":true,"fullReconcileHours":24},"companies":[{"tallyId":"g1","name":"Co","enabled":true}]}`
	resp, out := c.do("PUT", "/api/sync/settings", body, true)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("save = %d %s", resp.StatusCode, out)
	}
	if strings.Contains(out, "sk-very-secret") || !strings.Contains(out, `"hasKey":true`) {
		t.Fatalf("key leaked or not stored: %s", out)
	}
	if got := s.Settings.Get(); got.Cloud.SupabaseKey != "sk-very-secret" || got.Sync.IntervalSeconds != 600 || len(got.EnabledCompanies()) != 1 {
		t.Fatalf("settings not applied: %+v", got)
	}
	c.do("PUT", "/api/sync/settings", strings.Replace(body, `"supabaseKey":"sk-very-secret"`, `"supabaseKey":""`, 1), true)
	if got := s.Settings.Get(); got.Cloud.SupabaseKey != "sk-very-secret" {
		t.Fatal("blank key must keep the stored key")
	}
	resp, _ = c.do("PUT", "/api/sync/settings", strings.Replace(body, `"intervalSeconds":600`, `"intervalSeconds":5`, 1), true)
	if resp.StatusCode != http.StatusBadRequest || s.Settings.Get().Sync.IntervalSeconds != 600 {
		t.Fatalf("invalid interval accepted: %d", resp.StatusCode)
	}
}

func TestTallyTestReportsOffline(t *testing.T) {
	ts, _ := newTestServer(t, true)
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	resp, body := c.do("POST", "/api/sync/tally/test", "{}", true)
	var out struct {
		Connected bool `json:"connected"`
		Error     struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	json.Unmarshal([]byte(body), &out)
	if resp.StatusCode != http.StatusOK || out.Connected || out.Error.Code != string(tally.KindUnreachable) {
		t.Fatalf("%d %s", resp.StatusCode, body)
	}
}

func TestOwnerAccounts(t *testing.T) {
	ts, _ := newTestServer(t, true)
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	if resp, body := c.do("GET", "/api/sync/users", "", false); resp.StatusCode != http.StatusOK || !strings.Contains(body, `"users":[]`) {
		t.Fatalf("list = %d %s", resp.StatusCode, body)
	}
	if resp, _ := c.do("POST", "/api/sync/users", `{"email":"not-an-email","password":"owner-pass-1"}`, true); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("bad email accepted: %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/users", `{"email":"o@x.com","password":"short"}`, true); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("weak password accepted: %d", resp.StatusCode)
	}
	resp, body := c.do("POST", "/api/sync/users", `{"email":"Owner@Example.com","name":"Owner","password":"owner-pass-1"}`, true)
	if resp.StatusCode != http.StatusOK || !strings.Contains(body, `"email":"owner@example.com"`) || !strings.Contains(body, `"role":"OWNER"`) {
		t.Fatalf("create = %d %s", resp.StatusCode, body)
	}
	var created struct {
		User userDTO `json:"user"`
	}
	json.Unmarshal([]byte(body), &created)
	if resp, _ := c.do("POST", "/api/sync/users", `{"email":"owner@example.com","password":"owner-pass-2"}`, true); resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("duplicate email accepted: %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/users/"+created.User.ID+"/password", `{"password":"new-owner-pass"}`, true); resp.StatusCode != http.StatusOK {
		t.Fatalf("reset = %d", resp.StatusCode)
	}
	if resp, _ := c.do("POST", "/api/sync/users/"+created.User.ID+"/active", `{"active":false}`, true); resp.StatusCode != http.StatusOK {
		t.Fatalf("disable = %d", resp.StatusCode)
	}
	if _, body := c.do("GET", "/api/sync/users", "", false); !strings.Contains(body, `"isActive":false`) {
		t.Fatalf("not disabled: %s", body)
	}
	if resp, _ := c.do("POST", "/api/sync/users/nope/password", `{"password":"new-owner-pass"}`, true); resp.StatusCode != http.StatusNotFound {
		t.Fatalf("unknown user = %d", resp.StatusCode)
	}
}

func TestManualSyncRunsAndReportsResult(t *testing.T) {
	ts, _ := newTestServer(t, true)
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	resp, body := c.do("POST", "/api/sync/run?wait=1", "", true)
	if resp.StatusCode != http.StatusOK || !strings.Contains(body, `"status":"skipped"`) {
		t.Fatalf("%d %s", resp.StatusCode, body)
	}
	if resp, _ := c.do("POST", "/api/sync/run", "", true); resp.StatusCode != http.StatusAccepted {
		t.Fatalf("trigger = %d", resp.StatusCode)
	}
}
