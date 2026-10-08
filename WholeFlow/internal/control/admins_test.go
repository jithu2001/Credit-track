package control

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// Admin sign-in, two-step codes, installers and sessions against a real
// control_db (a throwaway database wf_go_control next to WF_TEST_PG's):
//
//	WF_TEST_PG=postgres://postgres:pw@127.0.0.1:55432/wf go test ./internal/control -run Admin
func TestAdminSecurity(t *testing.T) {
	dsn := os.Getenv("WF_TEST_PG")
	if dsn == "" {
		t.Skip("set WF_TEST_PG")
	}
	ctx := context.Background()
	u, _ := url.Parse(dsn)
	admin, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	const dbName = "wf_go_control"
	if _, err := admin.Exec(ctx, `drop database if exists `+dbName+` with (force)`); err != nil {
		t.Fatal(err)
	}
	if _, err := admin.Exec(ctx, `create database `+dbName); err != nil {
		t.Fatal(err)
	}
	admin.Close(ctx)
	u.Path = "/" + dbName
	store, err := OpenStore(ctx, u.String(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	if _, err := store.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	sealer, _ := NewSealer(strings.Repeat("cd", 32))
	svc := &Service{Store: store, Sealer: sealer, Now: time.Now}
	srv := NewServer(svc, slog.New(slog.NewTextHandler(io.Discard, nil)))
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	call := func(method, path, tok string, body any) (int, map[string]any) {
		t.Helper()
		var rd io.Reader
		if body != nil {
			raw, _ := json.Marshal(body)
			rd = strings.NewReader(string(raw))
		}
		req, _ := http.NewRequest(method, ts.URL+path, rd)
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]any
		raw, _ := io.ReadAll(res.Body)
		_ = json.Unmarshal(raw, &out)
		return res.StatusCode, out
	}
	errCode := func(out map[string]any) string {
		e, _ := out["error"].(map[string]any)
		c, _ := e["code"].(string)
		return c
	}
	want := func(got, want any, what string) {
		t.Helper()
		if got != want {
			t.Fatalf("%s: got %v, want %v", what, got, want)
		}
	}

	if _, err := CreateAdmin(ctx, store, "boss@wf.test", "Boss", "boss-password-1"); err != nil {
		t.Fatal(err)
	}
	login := func(email, pw, code string) (int, map[string]any) {
		return call("POST", "/control/admin/login", "", map[string]string{"email": email, "password": pw, "code": code})
	}

	// First sign-in: only two-step set-up is allowed.
	code, out := login("boss@wf.test", "boss-password-1", "")
	want(code, 200, "first sign-in")
	want(out["enrol_required"], true, "enrol required")
	enrolTok := out["token"].(string)
	code, out = call("GET", "/control/admin/businesses", enrolTok, nil)
	want(code, 403, "enrol session can't list businesses")
	want(errCode(out), "ENROL_2FA", "enrol code")
	code, _ = call("GET", "/control/admin/me", enrolTok, nil)
	want(code, 200, "me while enrolling")

	code, out = call("POST", "/control/admin/2fa/setup", enrolTok, map[string]any{})
	want(code, 200, "setup")
	secret := out["secret"].(string)
	if !strings.HasPrefix(out["uri"].(string), "otpauth://totp/") {
		t.Fatalf("uri %v", out["uri"])
	}
	key, _ := decodeTOTPSecret(secret)
	step := time.Now().Unix() / totpStep
	code, _ = call("POST", "/control/admin/2fa/confirm", enrolTok, map[string]string{"code": "000000"})
	want(code, 400, "wrong confirm code")
	code, out = call("POST", "/control/admin/2fa/confirm", enrolTok, map[string]string{"code": totpCode(key, step-1)})
	want(code, 200, "confirm")
	backups := out["backup_codes"].([]any)
	want(len(backups), backupCodeCount, "backup codes")
	code, _ = call("GET", "/control/admin/businesses", enrolTok, nil)
	want(code, 200, "session is full after confirming")

	// Next sign-ins need a code; a code works once.
	code, out = login("boss@wf.test", "boss-password-1", "")
	want(code, 401, "code required")
	want(errCode(out), "CODE_REQUIRED", "code required code")
	code, out = login("boss@wf.test", "boss-password-1", totpCode(key, step-1))
	want(code, 401, "step already used")
	want(errCode(out), "BAD_CODE", "reused code")
	code, out = login("boss@wf.test", "boss-password-1", totpCode(key, step))
	want(code, 200, "sign-in with code")
	want(out["enrol_required"], false, "no enrolment")
	boss := out["token"].(string)
	code, _ = login("boss@wf.test", "boss-password-1", backups[0].(string))
	want(code, 200, "backup code")
	code, _ = login("boss@wf.test", "boss-password-1", backups[0].(string))
	want(code, 401, "backup code used up")

	// Adding admins: own password needed; an existing email is refused.
	code, out = call("POST", "/control/admin/admins", boss, map[string]string{"email": "fitter@wf.test", "name": "Fitter",
		"password": "fitter-password", "role": "installer", "own_password": "wrong-password"})
	want(code, 403, "own password checked")
	code, _ = call("POST", "/control/admin/admins", boss, map[string]string{"email": "fitter@wf.test", "name": "Fitter",
		"password": "fitter-password", "role": "installer", "own_password": "boss-password-1"})
	want(code, 201, "installer added")
	code, out = call("POST", "/control/admin/admins", boss, map[string]string{"email": "BOSS@wf.test", "name": "Evil",
		"password": "taken-over-pw", "own_password": "boss-password-1"})
	want(code, 409, "existing email")
	code, _ = login("boss@wf.test", "taken-over-pw", "")
	want(code, 401, "password not overwritten")

	// Installers: Tally PC page only.
	code, out = login("fitter@wf.test", "fitter-password", "")
	want(code, 403, "installer in the admin app")
	want(errCode(out), "INSTALLER", "installer code")
	code, out = call("POST", "/control/pc/login", "", map[string]string{"email": "fitter@wf.test", "password": "fitter-password"})
	want(code, 200, "installer on a PC")
	want(out["role"], "installer", "role")
	code, _ = call("POST", "/control/pc/login", "", map[string]string{"email": "boss@wf.test", "password": "boss-password-1"})
	want(code, 200, "admin on a PC (allowed, installers recommended)")

	// A second admin; disabling them, or resetting their two-step sign-in, signs them out.
	code, _ = call("POST", "/control/admin/admins", boss, map[string]string{"email": "two@wf.test", "name": "Two",
		"password": "second-password", "own_password": "boss-password-1"})
	want(code, 201, "second admin")
	_, out = login("two@wf.test", "second-password", "")
	two := out["token"].(string)
	var twoID string
	_ = store.DB.QueryRow(ctx, `select id::text from admins where email = 'two@wf.test'`).Scan(&twoID)
	code, _ = call("POST", "/control/admin/admins/"+twoID+"/disabled", boss, map[string]bool{"disabled": true})
	want(code, 200, "disable")
	code, _ = call("GET", "/control/admin/me", two, nil)
	want(code, 401, "disabled admin signed out")
	code, _ = call("POST", "/control/admin/admins/"+twoID+"/disabled", boss, map[string]bool{"disabled": false})
	want(code, 200, "enable")
	_, out = login("two@wf.test", "second-password", "")
	two = out["token"].(string)
	code, _ = call("POST", "/control/admin/admins/"+twoID+"/reset-2fa", boss, map[string]string{"password": "nope-nope-nope"})
	want(code, 403, "reset-2fa needs own password")
	code, _ = call("POST", "/control/admin/admins/"+twoID+"/reset-2fa", boss, map[string]string{"password": "boss-password-1"})
	want(code, 200, "reset-2fa")
	code, _ = call("GET", "/control/admin/me", two, nil)
	want(code, 401, "reset signs out")

	// Password change ends the admin's other sessions.
	code, out = login("boss@wf.test", "boss-password-1", backups[1].(string))
	want(code, 200, "second session")
	other := out["token"].(string)
	code, _ = call("POST", "/control/admin/password", boss, map[string]string{"current": "boss-password-1", "new": "boss-password-2"})
	want(code, 200, "password change")
	code, _ = call("GET", "/control/admin/me", other, nil)
	want(code, 401, "other session ended")
	code, _ = call("GET", "/control/admin/me", boss, nil)
	want(code, 200, "this session kept")

	// Sessions survive a restart (they live in control_db) but not their age.
	srv2 := NewServer(svc, srv.Log)
	if _, _, ok := srv2.session(ctx, boss); !ok {
		t.Fatal("session lost on restart")
	}
	_, _ = store.DB.Exec(ctx, `update admin_sessions set created_at = now() - interval '13 hours'`)
	code, _ = call("GET", "/control/admin/me", boss, nil)
	want(code, 401, "12-hour cap")

	// Settings: minimum app build and latest PC version.
	_, out = login("boss@wf.test", "boss-password-2", backups[2].(string))
	boss = out["token"].(string)
	code, out = call("PUT", "/control/admin/settings", boss, map[string]any{"min_app_build": 7, "latest_pc_version": "0.6.1"})
	want(code, 200, "settings")
	want(out["min_app_build"], 7.0, "min build saved")
	code, _ = call("PUT", "/control/admin/settings", boss, map[string]any{"latest_pc_version": "new!"})
	want(code, 400, "bad version")
	req, _ := http.NewRequest("GET", ts.URL+"/control/connect?key=NOPE-AAAA-BBBB-CCCC", nil)
	req.Header.Set("X-App-Version", "1.0.0+6")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	want(res.StatusCode, 426, "outdated app at /control/connect")

	// The command-line reset for a lost phone.
	bossID, _ := AdminIDByEmail(ctx, store, "BOSS@wf.test")
	if err := ResetTOTP(ctx, store, bossID); err != nil {
		t.Fatal(err)
	}
	code, out = login("boss@wf.test", "boss-password-2", "")
	want(code, 200, "after reset-2fa")
	want(out["enrol_required"], true, "enrol again")
}
