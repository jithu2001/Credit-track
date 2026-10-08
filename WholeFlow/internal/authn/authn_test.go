package authn_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/authn"
	"wholeflow/internal/control"
)

// Runs against the local test database with the real login tables:
//
//	db/tests/run_local.sh
//	WF_TEST_PG=postgres://postgres:pw@127.0.0.1:55432/wf go test ./internal/authn
func TestAuthn(t *testing.T) {
	dsn := os.Getenv("WF_TEST_PG")
	if dsn == "" {
		t.Skip("set WF_TEST_PG (see the comment above)")
	}
	ctx := context.Background()
	db, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close(ctx)
	clock := time.Date(2026, 10, 8, 10, 0, 0, 0, time.UTC)
	is := authn.Issuer{Secret: "authn-test-secret-authn-test-secret-32", URL: "https://api.example/b/t/auth/v1",
		Now: func() time.Time { return clock }}

	// Each step in its own committed transaction, as the HTTP handlers do.
	run := func(fn func(pgx.Tx) error) error {
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		if err := fn(tx); err != nil {
			if authn.MustCommit(err) {
				if cerr := tx.Commit(ctx); cerr != nil {
					t.Fatal(cerr)
				}
			}
			return err
		}
		return tx.Commit(ctx)
	}
	is400 := func(err error, want *authn.Error, what string) {
		t.Helper()
		var e *authn.Error
		if !errors.As(err, &e) || e.Code != want.Code {
			t.Fatalf("%s: got %v, want %s", what, err, want.Code)
		}
	}
	var id string
	t.Cleanup(func() { _, _ = db.Exec(ctx, `delete from auth.users where email like '%@authn.test'`) })
	_, _ = db.Exec(ctx, `delete from auth.users where email like '%@authn.test'`)

	if err := run(func(tx pgx.Tx) (err error) {
		id, err = authn.CreateUser(ctx, tx, " Owner@Authn.Test ", "first-pass-1", map[string]any{"name": "Owner", "must_change_password": true}, clock)
		return err
	}); err != nil {
		t.Fatal(err)
	}
	is400(run(func(tx pgx.Tx) error {
		_, err := authn.CreateUser(ctx, tx, "owner@authn.test", "another-pass", nil, clock)
		return err
	}), authn.ErrEmailExists, "same email")
	is400(run(func(tx pgx.Tx) error {
		_, err := authn.CreateUser(ctx, tx, "short@authn.test", "12345", nil, clock)
		return err
	}),
		authn.ErrWeakPassword, "weak password")

	// Sign in.
	is400(run(func(tx pgx.Tx) error {
		_, err := is.SignIn(ctx, tx, "owner@authn.test", "wrong-pass", authn.Meta{})
		return err
	}),
		authn.ErrInvalidCredentials, "wrong password")
	is400(run(func(tx pgx.Tx) error {
		_, err := is.SignIn(ctx, tx, "nobody@authn.test", "first-pass-1", authn.Meta{})
		return err
	}),
		authn.ErrInvalidCredentials, "unknown email")
	var s *authn.Session
	if err := run(func(tx pgx.Tx) (err error) {
		s, err = is.SignIn(ctx, tx, "OWNER@authn.test", "first-pass-1", authn.Meta{UserAgent: "test", IP: "127.0.0.1"})
		return err
	}); err != nil {
		t.Fatal(err)
	}
	claims, err := control.VerifyJWT(is.Secret, s.AccessToken, clock)
	if err != nil {
		t.Fatalf("token does not verify: %v", err)
	}
	if claims["sub"] != id || claims["role"] != "authenticated" || claims["session_id"] == "" ||
		claims["user_metadata"].(map[string]any)["must_change_password"] != true {
		t.Fatalf("claims: %v", claims)
	}
	if s.User.Email != "owner@authn.test" || s.ExpiresIn != 3600 || s.RefreshToken == "" {
		t.Fatalf("session: %+v", s)
	}
	sessionID := claims["session_id"].(string)

	// Refresh rotates; an old token used moments later gets the newest one;
	// used later still, it ends the session.
	var s2 *authn.Session
	if err := run(func(tx pgx.Tx) (err error) { s2, err = is.Refresh(ctx, tx, s.RefreshToken); return err }); err != nil {
		t.Fatal(err)
	}
	if s2.RefreshToken == s.RefreshToken {
		t.Fatal("refresh token not rotated")
	}
	var raced *authn.Session
	if err := run(func(tx pgx.Tx) (err error) { raced, err = is.Refresh(ctx, tx, s.RefreshToken); return err }); err != nil {
		t.Fatalf("race: %v", err)
	}
	if raced.RefreshToken != s2.RefreshToken {
		t.Fatal("racing refresh should get the newest token")
	}
	clock = clock.Add(time.Minute)
	is400(run(func(tx pgx.Tx) error { _, err := is.Refresh(ctx, tx, s.RefreshToken); return err }), authn.ErrRefreshReused, "reuse")
	is400(run(func(tx pgx.Tx) error { _, err := is.Refresh(ctx, tx, s2.RefreshToken); return err }), authn.ErrRefreshNotFound,
		"session ended after reuse")
	is400(run(func(tx pgx.Tx) error { _, err := is.Refresh(ctx, tx, "not-a-token"); return err }), authn.ErrRefreshNotFound, "unknown token")
	var open bool
	_ = run(func(tx pgx.Tx) (err error) { open, err = authn.SessionExists(ctx, tx, sessionID); return err })
	if open {
		t.Fatal("session should be gone")
	}

	// Change password and metadata (as the app's "change password" does).
	if err := run(func(tx pgx.Tx) (err error) {
		s, err = is.SignIn(ctx, tx, "owner@authn.test", "first-pass-1", authn.Meta{})
		return err
	}); err != nil {
		t.Fatal(err)
	}
	pw := "first-pass-1"
	is400(run(func(tx pgx.Tx) error { _, err := is.UpdateUser(ctx, tx, id, &pw, nil); return err }), authn.ErrSamePassword, "same password")
	pw = "new-pass-22"
	var u *authn.User
	if err := run(func(tx pgx.Tx) (err error) {
		u, err = is.UpdateUser(ctx, tx, id, &pw, map[string]any{"must_change_password": false, "name": nil})
		return err
	}); err != nil {
		t.Fatal(err)
	}
	if u.UserMetadata["must_change_password"] != false {
		t.Fatalf("metadata: %v", u.UserMetadata)
	}
	if _, kept := u.UserMetadata["name"]; kept {
		t.Fatal("null should remove the key")
	}
	is400(run(func(tx pgx.Tx) error {
		_, err := is.SignIn(ctx, tx, "owner@authn.test", "first-pass-1", authn.Meta{})
		return err
	}),
		authn.ErrInvalidCredentials, "old password")
	if err := run(func(tx pgx.Tx) (err error) {
		_, err = is.SignIn(ctx, tx, "owner@authn.test", "new-pass-22", authn.Meta{})
		return err
	}); err != nil {
		t.Fatal(err)
	}

	// Ban: sessions end, sign-in and refresh refused; lifting it lets them in.
	ban := 100 * 365 * 24 * time.Hour
	if err := run(func(tx pgx.Tx) error { return authn.AdminUpdate(ctx, tx, id, authn.Update{Ban: &ban}, clock) }); err != nil {
		t.Fatal(err)
	}
	is400(run(func(tx pgx.Tx) error {
		_, err := is.SignIn(ctx, tx, "owner@authn.test", "new-pass-22", authn.Meta{})
		return err
	}),
		authn.ErrBanned, "banned sign-in")
	is400(run(func(tx pgx.Tx) error { _, err := is.Refresh(ctx, tx, s.RefreshToken); return err }), authn.ErrRefreshNotFound,
		"banned user's sessions ended")
	none := time.Duration(0)
	reset := "reset-pass-33"
	if err := run(func(tx pgx.Tx) error {
		return authn.AdminUpdate(ctx, tx, id, authn.Update{Ban: &none, Password: &reset, Metadata: map[string]any{"must_change_password": true}}, clock)
	}); err != nil {
		t.Fatal(err)
	}
	if err := run(func(tx pgx.Tx) (err error) {
		s, err = is.SignIn(ctx, tx, "owner@authn.test", "reset-pass-33", authn.Meta{})
		return err
	}); err != nil {
		t.Fatalf("after unban and reset: %v", err)
	}
	if s.User.UserMetadata["must_change_password"] != true {
		t.Fatal("reset should ask for a new password")
	}

	// Sign out ends this session; delete removes the login.
	claims, _ = control.VerifyJWT(is.Secret, s.AccessToken, clock)
	if err := run(func(tx pgx.Tx) error { return authn.SignOut(ctx, tx, id, claims["session_id"].(string), "local") }); err != nil {
		t.Fatal(err)
	}
	is400(run(func(tx pgx.Tx) error { _, err := is.Refresh(ctx, tx, s.RefreshToken); return err }), authn.ErrRefreshNotFound, "signed out")
	if err := run(func(tx pgx.Tx) error { return authn.DeleteUser(ctx, tx, id) }); err != nil {
		t.Fatal(err)
	}
	is400(run(func(tx pgx.Tx) error { _, err := authn.GetUser(ctx, tx, id); return err }), authn.ErrUserNotFound, "deleted")
}
