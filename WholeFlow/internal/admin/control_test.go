package admin

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"wholeflow/internal/syncer"
)

// fakeControl answers like the WholeFlow control service. down makes it
// answer 503 (as when it cannot be reached); offlineUntil is what a good
// login returns.
type fakeControl struct {
	mu           sync.Mutex
	srv          *httptest.Server
	down         bool
	offlineUntil time.Time
	logins       int
	activations  []map[string]string
}

func newFakeControl(t *testing.T, s *Server) *fakeControl {
	t.Helper()
	f := &fakeControl{offlineUntil: time.Now().Add(7 * 24 * time.Hour)}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.srv.Close)
	s.Settings.Update(func(st *syncer.Settings) error { st.Cloud.ControlURL = f.srv.URL; return nil })
	return f
}

func (f *fakeControl) handle(w http.ResponseWriter, r *http.Request) {
	var body map[string]string
	json.NewDecoder(r.Body).Decode(&body)
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.down {
		w.WriteHeader(http.StatusServiceUnavailable)
		return
	}
	fail := func(status int, code, msg string) {
		w.WriteHeader(status)
		fmt.Fprintf(w, `{"error":{"code":%q,"message":%q}}`, code, msg)
	}
	switch r.URL.Path {
	case "/control/pc/login":
		f.logins++
		if body["email"] != "jithu@example.com" || body["password"] != "pw-online" {
			fail(http.StatusUnauthorized, "BAD_LOGIN", "Wrong email or password.")
			return
		}
		fmt.Fprintf(w, `{"ok":true,"name":"Jithu","email":"jithu@example.com","offline_until":%q}`, f.offlineUntil.Format(time.RFC3339))
	case "/control/activate":
		f.activations = append(f.activations, body)
		switch body["activation_code"] {
		case "GOOD-CODE":
			io.WriteString(w, `{"device_id":"dev-1","business_id":"biz-demo","business_name":"Demo Traders","base_url":"https://api.example/b/demo/",
				"device_key":"pc-secret-key","max_companies":1,"subscription_state":"active"}`)
		case "USED-CODE":
			fail(http.StatusGone, "CODE_USED", "This activation code has already been used. Ask WholeFlow support for a new one.")
		default:
			fail(http.StatusBadRequest, "BAD_CODE", "The activation code is not correct.")
		}
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (c *client) loginEmail(email, password string) (*http.Response, string) {
	return c.do("POST", "/api/sync/login", `{"email":"`+email+`","password":"`+password+`"}`, true)
}

// Every login is checked by the WholeFlow server. Nothing is remembered on
// the PC, so with the server unreachable nobody can sign in, not even right
// after a successful online login.
func TestPCLoginAlwaysNeedsTheServer(t *testing.T) {
	ts, s := newTestServer(t, false)
	ctl := newFakeControl(t, s)
	c := &client{t: t, base: ts.URL}
	resp, body := c.loginEmail("Jithu@Example.com", "pw-online")
	if resp.StatusCode != http.StatusOK || c.cookie == nil || !c.cookie.HttpOnly || c.cookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("login = %d %s", resp.StatusCode, body)
	}
	if resp, _ := c.do("GET", "/api/dashboard", "", false); resp.StatusCode != http.StatusOK {
		t.Fatalf("not logged in: %d", resp.StatusCode)
	}
	if b, _ := os.ReadFile(s.Settings.Path()); strings.Contains(string(b), "pcLogins") || strings.Contains(string(b), "jithu@example.com") {
		t.Fatalf("a login was stored on the PC: %s", b)
	}

	ctl.mu.Lock()
	ctl.down = true
	ctl.mu.Unlock()
	off := &client{t: t, base: ts.URL}
	resp, body = off.loginEmail("jithu@example.com", "pw-online")
	if resp.StatusCode != http.StatusServiceUnavailable || off.cookie != nil || !strings.Contains(body, "Cannot reach the WholeFlow server") {
		t.Fatalf("login with the server down = %d %s", resp.StatusCode, body)
	}
}

func TestPCLoginWrongPassword(t *testing.T) {
	ts, s := newTestServer(t, false)
	newFakeControl(t, s)
	c := &client{t: t, base: ts.URL}
	resp, body := c.loginEmail("jithu@example.com", "pw-old")
	if resp.StatusCode != http.StatusUnauthorized || c.cookie != nil || !strings.Contains(body, "Wrong email or password.") {
		t.Fatalf("401 = %d %s", resp.StatusCode, body)
	}
}

// There is no local account: the login of an older version left in
// config.json does not open the app, with or without the server.
func TestOldLocalAccountDoesNotOpenTheApp(t *testing.T) {
	ts, s := newTestServer(t, false)
	ctl := newFakeControl(t, s)
	c := &client{t: t, base: ts.URL}
	if resp, _ := c.loginEmail("admin", "admin-secret-1"); resp.StatusCode != http.StatusUnauthorized || c.cookie != nil {
		t.Fatalf("old local login with the server up = %d", resp.StatusCode)
	}
	ctl.down = true
	if resp, _ := c.loginEmail("admin", "admin-secret-1"); resp.StatusCode == http.StatusOK || c.cookie != nil {
		t.Fatalf("old local login with the server down = %d", resp.StatusCode)
	}
	if _, body := c.do("GET", "/api/sync/settings", "", false); strings.Contains(body, "hasLocalAccount") {
		t.Fatal(body)
	}
}

func TestPCLoginLockout(t *testing.T) {
	ts, s := newTestServer(t, false)
	ctl := newFakeControl(t, s)
	c := &client{t: t, base: ts.URL}
	for i := 0; i < 3; i++ {
		if resp, _ := c.loginEmail("jithu@example.com", "nope"); resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("bad password = %d", resp.StatusCode)
		}
	}
	if resp, _ := c.loginEmail("jithu@example.com", "pw-online"); resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("expected lockout, got %d", resp.StatusCode)
	}
	if ctl.logins != 3 {
		t.Fatalf("locked login still asked the server (%d calls)", ctl.logins)
	}
}

func TestConnectWithReferenceKey(t *testing.T) {
	ts, s := newTestServer(t, true)
	ctl := newFakeControl(t, s)
	s.Hostname, s.WindowsUser = "TALLY-PC", `TALLY-PC\owner`
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}

	resp, body := c.do("POST", "/api/sync/connect", `{"referenceKey":"demo-65yc 47x7-qmez","activationCode":"USED-CODE"}`, true)
	if resp.StatusCode != http.StatusGone || !strings.Contains(body, "already been used") {
		t.Fatalf("used code = %d %s", resp.StatusCode, body)
	}
	if s.Settings.Get().Linked() {
		t.Fatal("connected with a refused code")
	}

	resp, body = c.do("POST", "/api/sync/connect", `{"referenceKey":"demo-65yc 47x7-qmez","activationCode":"good-code"}`, true)
	if resp.StatusCode != http.StatusOK || !strings.Contains(body, `"businessName":"Demo Traders"`) {
		t.Fatalf("connect = %d %s", resp.StatusCode, body)
	}
	a := ctl.activations[1]
	if a["reference_key"] != "DEMO-65YC47X7-QMEZ" || a["machine"] != "TALLY-PC" || a["windows_user"] != `TALLY-PC\owner` || a["app_version"] != syncer.Version {
		t.Fatalf("activation request: %v", a)
	}
	set := s.Settings.Get()
	if !set.Linked() || set.Business.ID != "biz-demo" || set.Business.Name != "Demo Traders" || set.Cloud.Link.BaseURL != "https://api.example/b/demo" ||
		set.Cloud.Link.DeviceKey != "pc-secret-key" || set.Cloud.Link.MaxCompanies != 1 || set.Cloud.Link.DeviceID != "dev-1" {
		t.Fatalf("stored: %+v %+v", set.Business, set.Cloud.Link)
	}
	_, out := c.do("GET", "/api/sync/settings", "", false)
	if strings.Contains(out, "pc-secret-key") || !strings.Contains(out, `"connected":true`) || !strings.Contains(out, `"businessName":"Demo Traders"`) {
		t.Fatalf("settings: %s", out)
	}
	// Saving the page does not overwrite the business that came with the activation.
	c.do("PUT", "/api/sync/settings", `{"business":{"id":"other"},"cloud":{"provider":"memory"},
	  "sync":{"enabled":false,"intervalSeconds":300,"transactions":true,"fullReconcileHours":24},"companies":[{"tallyId":"g1","name":"Co","enabled":true}]}`, true)
	if set := s.Settings.Get(); set.Business.ID != "biz-demo" || !set.Linked() || len(set.EnabledCompanies()) != 1 {
		t.Fatalf("connection changed by save: %+v", set.Business)
	}

	if resp, _ := c.do("POST", "/api/sync/disconnect", "", true); resp.StatusCode != http.StatusOK {
		t.Fatalf("disconnect = %d", resp.StatusCode)
	}
	set = s.Settings.Get()
	if set.Cloud.Link.Connected() || set.Cloud.Link.DeviceKey != "" || set.Cloud.Link.DeviceKeyEnc != "" || set.Business.ID != "" {
		t.Fatalf("not disconnected: %+v", set.Cloud.Link)
	}
	// No other connection takes over: the sync waits until connected again.
	if ok, why := set.Configured(); ok || set.Cloud.Provider != syncer.ProviderWholeFlow || !strings.Contains(why, "not connected") {
		t.Fatalf("after disconnect: provider %q, configured %v %q", set.Cloud.Provider, ok, why)
	}
}

func TestConnectServerUnreachable(t *testing.T) {
	ts, s := newTestServer(t, true)
	s.Settings.Update(func(st *syncer.Settings) error { st.Cloud.ControlURL = "http://127.0.0.1:1"; return nil }) // closed port
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	resp, body := c.do("POST", "/api/sync/connect", `{"referenceKey":"DEMO-1","activationCode":"GOOD-CODE"}`, true)
	if resp.StatusCode != http.StatusBadGateway || !strings.Contains(body, "Cannot reach the WholeFlow server") {
		t.Fatalf("%d %s", resp.StatusCode, body)
	}
}

func TestCompanyLimitWhenTicking(t *testing.T) {
	ts, s := newTestServer(t, true)
	newFakeControl(t, s)
	c := &client{t: t, base: ts.URL, bearer: "ctl-token"}
	if resp, _ := c.do("POST", "/api/sync/connect", `{"referenceKey":"DEMO-1","activationCode":"GOOD-CODE"}`, true); resp.StatusCode != http.StatusOK {
		t.Fatal("connect failed")
	}
	two := `{"sync":{"enabled":false,"intervalSeconds":300,"transactions":true,"fullReconcileHours":24},
	  "companies":[{"tallyId":"g1","name":"Co 1","enabled":true},{"tallyId":"g2","name":"Co 2","enabled":true}]}`
	resp, body := c.do("PUT", "/api/sync/settings", two, true)
	if resp.StatusCode != http.StatusBadRequest || !strings.Contains(body, "Your plan allows 1 company. Ask WholeFlow support to upgrade.") {
		t.Fatalf("over the limit = %d %s", resp.StatusCode, body)
	}
	if n := len(s.Settings.Get().EnabledCompanies()); n != 0 {
		t.Fatalf("refused selection saved: %d", n)
	}
	one := strings.Replace(two, `"name":"Co 2","enabled":true`, `"name":"Co 2","enabled":false`, 1)
	if resp, body := c.do("PUT", "/api/sync/settings", one, true); resp.StatusCode != http.StatusOK {
		t.Fatalf("within the limit = %d %s", resp.StatusCode, body)
	}
}
