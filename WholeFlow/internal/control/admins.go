package control

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"wholeflow/internal/auth"
)

// Admin accounts, their sessions and two-step sign-in.
//
//	POST /control/admin/login            {"email", "password", "code"?}
//	     → {"token", "name", "email", "enrol_required"}; 401 CODE_REQUIRED when two-step
//	       sign-in is set up and no code was sent (send the same request with "code":
//	       the 6-digit code or a backup code).
//	POST /control/admin/2fa/setup        → {"secret", "uri"} (otpauth://…; shown once)
//	POST /control/admin/2fa/confirm      {"code"} → {"backup_codes": [...]} (shown once)
//	POST /control/admin/admins           {"email", "name", "password", "role", "own_password"}
//	POST /control/admin/admins/{id}/disabled  {"disabled"}
//	POST /control/admin/admins/{id}/reset-2fa {"password"} (own password)
//	POST /control/admin/password         {"current", "new"}
//	POST /control/pc/login               {"email", "password"} (Tally PC page; admins and installers)
//
// Two-step sign-in is required: an admin without it gets a session that can
// only set it up (stage "enrol") until a code is confirmed. Installers sign in
// only on customers' Tally PCs, without a code (they type on the customer's
// PC); admins can still sign in there too, but should use installer accounts.

const (
	adminIdle   = 2 * time.Hour  // an admin session ends after this long unused
	adminMaxAge = 12 * time.Hour // and this long after sign-in at the latest

	stageFull  = "full"
	stageEnrol = "enrol"

	roleAdmin     = "admin"
	roleInstaller = "installer"

	backupCodeCount = 10
)

func hashToken(tok string) string {
	sum := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(sum[:])
}

func newToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func bearerToken(r *http.Request) string {
	tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	return strings.TrimSpace(tok)
}

// ---------------------------------------------------------------- sessions (control_db)

func (s *Server) createSession(ctx context.Context, adminID, stage, ip string) (string, error) {
	tok, err := newToken()
	if err != nil {
		return "", err
	}
	db := s.Svc.Store.DB
	_, _ = db.Exec(ctx, `delete from admin_sessions where created_at < now() - $1::interval or last_seen_at < now() - $2::interval`,
		adminMaxAge.String(), adminIdle.String())
	if _, err := db.Exec(ctx, `insert into admin_sessions (token_hash, admin_id, stage, ip) values ($1, $2, $3, $4)`,
		hashToken(tok), adminID, stage, ip); err != nil {
		return "", err
	}
	return tok, nil
}

// session finds the admin of a live session token (idle and absolute limits).
func (s *Server) session(ctx context.Context, tok string) (adminInfo, string, bool) {
	var a adminInfo
	var stage string
	if tok == "" {
		return a, "", false
	}
	var created, seen time.Time
	h := hashToken(tok)
	err := s.Svc.Store.DB.QueryRow(ctx, `select a.id, a.email, a.name, a.role, s.stage, s.created_at, s.last_seen_at
		from admin_sessions s join admins a on a.id = s.admin_id where s.token_hash = $1 and not a.disabled`, h).
		Scan(&a.ID, &a.Email, &a.Name, &a.Role, &stage, &created, &seen)
	if err != nil {
		return a, "", false
	}
	now := time.Now()
	if now.Sub(created) >= adminMaxAge || now.Sub(seen) >= adminIdle || a.Role != roleAdmin {
		_, _ = s.Svc.Store.DB.Exec(ctx, `delete from admin_sessions where token_hash = $1`, h)
		return a, "", false
	}
	if now.Sub(seen) > time.Minute {
		_, _ = s.Svc.Store.DB.Exec(ctx, `update admin_sessions set last_seen_at = now() where token_hash = $1`, h)
	}
	return a, stage, true
}

// endSessions signs an admin out everywhere except the session keepToken ("" = everywhere).
func (s *Server) endSessions(ctx context.Context, adminID, keepToken string) error {
	keep := ""
	if keepToken != "" {
		keep = hashToken(keepToken)
	}
	_, err := s.Svc.Store.DB.Exec(ctx, `delete from admin_sessions where admin_id = $1 and token_hash <> $2`, adminID, keep)
	return err
}

func (s *Server) withSession(h http.HandlerFunc, stages ...string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		a, stage, ok := s.session(r.Context(), bearerToken(r))
		if !ok {
			writeErr(w, userErr(401, "UNAUTHENTICATED", "Sign in again."))
			return
		}
		allowed := false
		for _, st := range stages {
			allowed = allowed || st == stage
		}
		if !allowed {
			writeErr(w, userErr(403, "ENROL_2FA", "Set up two-step sign-in first."))
			return
		}
		a.Stage = stage
		h(w, r.WithContext(context.WithValue(r.Context(), adminKey{}, a)))
	}
}

// admin: a signed-in admin with two-step sign-in done.
func (s *Server) admin(h http.HandlerFunc) http.HandlerFunc { return s.withSession(h, stageFull) }

// adminOrEnrol: also a session that still has to set up two-step sign-in.
func (s *Server) adminOrEnrol(h http.HandlerFunc) http.HandlerFunc {
	return s.withSession(h, stageFull, stageEnrol)
}

// ---------------------------------------------------------------- sign-in limits

// Wrong passwords and codes: 8 per email from one address within 15 minutes
// lock that pair for 15 minutes; 30 per email from anywhere within 15
// minutes lock the email (stops guessing spread over many addresses without
// letting one stranger lock an admin out for long); 30 requests per minute
// per address.
func (s *Server) limitKeys(email string, r *http.Request) (pair, mail string) {
	email = strings.ToLower(strings.TrimSpace(email))
	return email + "|" + auth.IPKey(auth.ClientIP(r)), email
}

func (s *Server) allowAttempt(email string, r *http.Request) error {
	pair, mail := s.limitKeys(email, r)
	if s.limiter.Allow(pair) != nil || s.emailLimiter.Allow(mail) != nil {
		return userErr(429, "LOCKED", "Too many failed attempts. Try again in 15 minutes.")
	}
	return nil
}

func (s *Server) attemptFailed(email string, r *http.Request) {
	pair, mail := s.limitKeys(email, r)
	s.limiter.Failure(pair)
	s.emailLimiter.Failure(mail)
}

func (s *Server) attemptOK(email string, r *http.Request) {
	pair, _ := s.limitKeys(email, r)
	s.limiter.Success(pair) // the per-email count is left to expire: it only stops mass guessing
}

// ---------------------------------------------------------------- sign in

type adminLogin struct {
	adminInfo
	totpSealed string
	lastStep   int64
}

// checkPassword checks an email and password (rate limited).
func (s *Server) checkPassword(r *http.Request, email, password string) (*adminLogin, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if !s.allowIP(auth.ClientIP(r), 30) {
		return nil, userErr(429, "TOO_MANY", "Too many attempts. Try again in a minute.")
	}
	if err := s.allowAttempt(email, r); err != nil {
		return nil, err
	}
	var a adminLogin
	var hash string
	var sealed *string
	err := s.Svc.Store.DB.QueryRow(r.Context(), `select id, email, name, role, password_hash, totp_secret_sealed, totp_last_step
		from admins where email = $1 and not disabled`, email).
		Scan(&a.ID, &a.Email, &a.Name, &a.Role, &hash, &sealed, &a.lastStep)
	if err != nil {
		hash = dummyAdminHash() // as slow as a real check
	}
	if !auth.VerifyPassword(hash, password) || err != nil {
		s.attemptFailed(email, r)
		return nil, userErr(401, "BAD_LOGIN", "Wrong email or password.")
	}
	if sealed != nil {
		a.totpSealed = *sealed
	}
	return &a, nil
}

var dummyAdminHash = sync.OnceValue(func() string { h, _ := auth.HashSecret("wholeflow-not-a-password"); return h })

// checkCode checks a two-step code (authenticator or unused backup code) and
// uses it up. Failures count toward the sign-in limits.
func (s *Server) checkCode(r *http.Request, a *adminLogin, code string) error {
	ctx := r.Context()
	code = strings.TrimSpace(code)
	if secret, err := s.Svc.Sealer.Open(a.totpSealed); err == nil {
		if step, ok := CheckTOTP(secret, code, time.Now(), a.lastStep); ok {
			tag, err := s.Svc.Store.DB.Exec(ctx, `update admins set totp_last_step = $2 where id = $1 and totp_last_step < $2`, a.ID, step)
			if err == nil && tag.RowsAffected() == 1 {
				return nil
			}
		}
	} else {
		return err
	}
	if len(NormalizeKey(code)) >= 10 {
		tag, err := s.Svc.Store.DB.Exec(ctx, `update admin_backup_codes set used_at = now()
			where admin_id = $1 and code_hash = $2 and used_at is null`, a.ID, HashCode(strings.ReplaceAll(code, "-", "")))
		if err == nil && tag.RowsAffected() == 1 {
			s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.backup_code_used", nil)
			return nil
		}
	}
	s.attemptFailed(a.Email, r)
	return userErr(401, "BAD_CODE", "That code is wrong or already used. Enter the current code from your authenticator app.")
}

func (s *Server) adminLogin(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Password, Code string }
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	a, err := s.checkPassword(r, in.Email, in.Password)
	if err != nil {
		writeErr(w, err)
		return
	}
	if a.Role != roleAdmin {
		s.attemptOK(a.Email, r)
		writeErr(w, userErr(403, "INSTALLER", "This is an installer account: it signs in only on customers' Tally PCs."))
		return
	}
	stage := stageEnrol
	if a.totpSealed != "" {
		if strings.TrimSpace(in.Code) == "" {
			writeErr(w, userErr(401, "CODE_REQUIRED", "Enter the 6-digit code from your authenticator app."))
			return
		}
		if err := s.checkCode(r, a, in.Code); err != nil {
			s.fail(w, r, err)
			return
		}
		stage = stageFull
	}
	s.attemptOK(a.Email, r)
	tok, err := s.createSession(r.Context(), a.ID, stage, auth.ClientIP(r))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	_, _ = s.Svc.Store.DB.Exec(r.Context(), `update admins set last_login_at = now() where id = $1`, a.ID)
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "admin.login", map[string]any{"ip": auth.ClientIP(r), "two_step": stage == stageFull})
	writeJSON(w, 200, map[string]any{"token": tok, "name": a.Name, "email": a.Email, "enrol_required": stage == stageEnrol})
}

func (s *Server) adminLogout(w http.ResponseWriter, r *http.Request) {
	_, _ = s.Svc.Store.DB.Exec(r.Context(), `delete from admin_sessions where token_hash = $1`, hashToken(bearerToken(r)))
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (s *Server) adminMe(w http.ResponseWriter, r *http.Request) {
	a := adminOf(r)
	writeJSON(w, 200, map[string]any{"id": a.ID, "email": a.Email, "name": a.Name, "role": a.Role,
		"enrol_required": a.Stage == stageEnrol})
}

// pcLogin: the Tally PC's local page signs in with an installer (or admin)
// account. No two-step code: it is typed on a customer's PC, and gives no
// admin session, only the PC page's own sign-in.
func (s *Server) pcLogin(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Password string }
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	a, err := s.checkPassword(r, in.Email, in.Password)
	if err != nil {
		writeErr(w, err)
		return
	}
	s.attemptOK(a.Email, r)
	_, _ = s.Svc.Store.DB.Exec(r.Context(), `update admins set last_login_at = now() where id = $1`, a.ID)
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "admin.pc_login", map[string]any{"ip": auth.ClientIP(r), "role": a.Role})
	writeJSON(w, 200, map[string]any{"ok": true, "name": a.Name, "email": a.Email, "role": a.Role,
		"offline_until": time.Now().Add(7 * 24 * time.Hour).UTC().Format(time.RFC3339)})
}

// ---------------------------------------------------------------- two-step sign-in

func (s *Server) totpSetup(w http.ResponseWriter, r *http.Request) {
	ctx, a := r.Context(), adminOf(r)
	var enabled bool
	if err := s.Svc.Store.DB.QueryRow(ctx, `select totp_secret_sealed is not null from admins where id = $1`, a.ID).Scan(&enabled); err != nil {
		s.fail(w, r, err)
		return
	}
	if enabled {
		writeErr(w, userErr(409, "ALREADY_SET_UP", "Two-step sign-in is already set up. Another admin can reset it."))
		return
	}
	secret, err := NewTOTPSecret()
	if err != nil {
		s.fail(w, r, err)
		return
	}
	sealed, err := s.Svc.Sealer.Seal(secret)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if _, err := s.Svc.Store.DB.Exec(ctx, `update admins set totp_pending_sealed = $2 where id = $1`, a.ID, sealed); err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, map[string]string{"secret": secret, "uri": TOTPURI(secret, a.Email)})
}

func (s *Server) totpConfirm(w http.ResponseWriter, r *http.Request) {
	var in struct{ Code string }
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, a := r.Context(), adminOf(r)
	if err := s.allowAttempt(a.Email, r); err != nil {
		writeErr(w, err)
		return
	}
	var pending *string
	var lastStep int64
	if err := s.Svc.Store.DB.QueryRow(ctx, `select totp_pending_sealed, totp_last_step from admins where id = $1 and totp_secret_sealed is null`, a.ID).
		Scan(&pending, &lastStep); err != nil || pending == nil {
		writeErr(w, userErr(409, "NO_SETUP", "Start the set-up again."))
		return
	}
	secret, err := s.Svc.Sealer.Open(*pending)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	step, ok := CheckTOTP(secret, in.Code, time.Now(), lastStep)
	if !ok {
		s.attemptFailed(a.Email, r)
		writeErr(w, userErr(400, "BAD_CODE", "That code is wrong. Check the phone's clock and enter the current code."))
		return
	}
	codes, err := NewBackupCodes(backupCodeCount)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	err = pgx.BeginFunc(ctx, s.Svc.Store.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `update admins set totp_secret_sealed = totp_pending_sealed, totp_pending_sealed = null,
			totp_enabled_at = now(), totp_last_step = $2 where id = $1 and totp_secret_sealed is null and totp_pending_sealed = $3`, a.ID, step, *pending)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return userErr(409, "NO_SETUP", "Start the set-up again.")
		}
		if _, err := tx.Exec(ctx, `delete from admin_backup_codes where admin_id = $1`, a.ID); err != nil {
			return err
		}
		for _, c := range codes {
			if _, err := tx.Exec(ctx, `insert into admin_backup_codes (admin_id, code_hash) values ($1, $2)`,
				a.ID, HashCode(strings.ReplaceAll(c, "-", ""))); err != nil {
				return err
			}
		}
		// This session may now do everything; any other is ended.
		if _, err := tx.Exec(ctx, `update admin_sessions set stage = 'full' where token_hash = $1`, hashToken(bearerToken(r))); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `delete from admin_sessions where admin_id = $1 and token_hash <> $2`, a.ID, hashToken(bearerToken(r)))
		return err
	})
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.attemptOK(a.Email, r)
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.2fa_enabled", nil)
	writeJSON(w, 200, map[string]any{"backup_codes": codes})
}

// ResetTOTP turns off an admin's two-step sign-in (they set it up again at
// the next sign-in) and signs them out. For `wholeflow-control reset-2fa`
// and the admin app.
func ResetTOTP(ctx context.Context, store *Store, adminID string) error {
	return pgx.BeginFunc(ctx, store.DB, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `update admins set totp_secret_sealed = null, totp_pending_sealed = null, totp_enabled_at = null,
			totp_last_step = 0 where id::text = $1`, adminID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return userErr(404, "NOT_FOUND", "No such admin.")
		}
		if _, err := tx.Exec(ctx, `delete from admin_backup_codes where admin_id::text = $1`, adminID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `delete from admin_sessions where admin_id::text = $1`, adminID)
		return err
	})
}

// AdminIDByEmail finds an admin (for the command line).
func AdminIDByEmail(ctx context.Context, store *Store, email string) (string, error) {
	var id string
	err := store.DB.QueryRow(ctx, `select id::text from admins where email = $1`, strings.ToLower(strings.TrimSpace(email))).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", userErr(404, "NOT_FOUND", "No admin has this email.")
	}
	return id, err
}

func (s *Server) resetAdminTOTP(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string `json:"password"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, id, a := r.Context(), r.PathValue("id"), adminOf(r)
	if id == a.ID {
		writeErr(w, userErr(400, "INVALID_INPUT", "Ask another admin to reset your two-step sign-in (or use reset-2fa on the server)."))
		return
	}
	if err := s.checkOwnPassword(r, in.Password); err != nil {
		writeErr(w, err)
		return
	}
	if err := ResetTOTP(ctx, s.Svc.Store, id); err != nil {
		s.fail(w, r, err)
		return
	}
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.2fa_reset", map[string]any{"admin": id})
	s.Log.Warn("admin two-step sign-in reset", "admin", id, "by", a.Email)
	s.listAdmins(w, r)
}

// ---------------------------------------------------------------- admin accounts

func (s *Server) listAdmins(w http.ResponseWriter, r *http.Request) {
	type admin struct {
		ID          string     `json:"id"`
		Email       string     `json:"email"`
		Name        string     `json:"name"`
		Role        string     `json:"role"`
		Disabled    bool       `json:"disabled"`
		TwoStep     bool       `json:"two_step"`
		LastLoginAt *time.Time `json:"last_login_at"`
	}
	rows, err := s.Svc.Store.DB.Query(r.Context(), `select id, email, name, role, disabled, totp_secret_sealed is not null, last_login_at
		from admins order by role, email`)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []admin{}
	for rows.Next() {
		var a admin
		if rows.Scan(&a.ID, &a.Email, &a.Name, &a.Role, &a.Disabled, &a.TwoStep, &a.LastLoginAt) == nil {
			out = append(out, a)
		}
	}
	writeJSON(w, 200, out)
}

// createAdmin adds an admin or installer; the signed-in admin's own password
// is needed again. An email already in use is refused (never overwritten).
func (s *Server) createAdmin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email       string `json:"email"`
		Name        string `json:"name"`
		Password    string `json:"password"`
		Role        string `json:"role"`
		OwnPassword string `json:"own_password"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if in.Role == "" {
		in.Role = roleAdmin
	}
	if in.Role != roleAdmin && in.Role != roleInstaller {
		writeErr(w, userErr(400, "INVALID_INPUT", "Role must be admin or installer."))
		return
	}
	if err := s.checkOwnPassword(r, in.OwnPassword); err != nil {
		writeErr(w, err)
		return
	}
	id, err := NewAdmin(r.Context(), s.Svc.Store, in.Email, in.Name, in.Password, in.Role)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	a := adminOf(r)
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "admin.create", map[string]any{"email": in.Email, "role": in.Role})
	writeJSON(w, 201, map[string]string{"id": id})
}

func adminFields(email, password string) (string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if !strings.Contains(email, "@") {
		return "", "", userErr(400, "INVALID_INPUT", "Enter a valid email.")
	}
	hash, err := auth.HashPassword(password)
	if err != nil {
		return "", "", userErr(400, "INVALID_INPUT", err.Error())
	}
	return email, hash, nil
}

// NewAdmin adds an account; 409 when the email is taken.
func NewAdmin(ctx context.Context, store *Store, email, name, password, role string) (string, error) {
	email, hash, err := adminFields(email, password)
	if err != nil {
		return "", err
	}
	var id string
	err = store.DB.QueryRow(ctx, `insert into admins (email, name, password_hash, role) values ($1, $2, $3, $4) returning id`,
		email, strings.TrimSpace(name), hash, role).Scan(&id)
	var pg *pgconn.PgError
	if errors.As(err, &pg) && pg.Code == "23505" {
		return "", userErr(409, "EMAIL_TAKEN", "An admin or installer with this email already exists.")
	}
	return id, err
}

// CreateAdmin creates an admin or, for an existing email, sets a new
// password and enables it again (and signs it out everywhere). Only for the
// server's command line (`wholeflow-control create-admin`), never the API.
func CreateAdmin(ctx context.Context, store *Store, email, name, password string) (string, error) {
	email, hash, err := adminFields(email, password)
	if err != nil {
		return "", err
	}
	var id string
	err = pgx.BeginFunc(ctx, store.DB, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `insert into admins (email, name, password_hash) values ($1, $2, $3)
			on conflict (email) do update set password_hash = excluded.password_hash, name = excluded.name, disabled = false
			returning id`, email, strings.TrimSpace(name), hash).Scan(&id); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `delete from admin_sessions where admin_id = $1`, id)
		return err
	})
	return id, err
}

func (s *Server) setAdminDisabled(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Disabled bool `json:"disabled"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, id, a := r.Context(), r.PathValue("id"), adminOf(r)
	if id == a.ID && in.Disabled {
		writeErr(w, userErr(400, "INVALID_INPUT", "You cannot disable your own account."))
		return
	}
	tag, err := s.Svc.Store.DB.Exec(ctx, `update admins set disabled = $2 where id::text = $1`, id, in.Disabled)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, userErr(404, "NOT_FOUND", "No such admin."))
		return
	}
	if in.Disabled {
		if err := s.endSessions(ctx, id, ""); err != nil {
			s.fail(w, r, err)
			return
		}
	}
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.disabled", map[string]any{"admin": id, "disabled": in.Disabled})
	s.listAdmins(w, r)
}

// changePassword: the admin's own password; every other session of theirs ends.
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Current string `json:"current"`
		New     string `json:"new"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, a := r.Context(), adminOf(r)
	if err := s.checkOwnPassword(r, in.Current); err != nil {
		var ue *UserError
		if errors.As(err, &ue) && ue.Code == "BAD_PASSWORD" {
			err = userErr(400, "BAD_PASSWORD", "The current password is wrong.")
		}
		writeErr(w, err)
		return
	}
	newHash, err := auth.HashPassword(in.New)
	if err != nil {
		writeErr(w, userErr(400, "INVALID_INPUT", err.Error()))
		return
	}
	if _, err := s.Svc.Store.DB.Exec(ctx, `update admins set password_hash = $2 where id = $1`, a.ID, newHash); err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.endSessions(ctx, a.ID, bearerToken(r)); err != nil {
		s.fail(w, r, err)
		return
	}
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.password", nil)
	writeJSON(w, 200, map[string]any{"ok": true})
}

// checkOwnPassword: deleting data, resetting a login and adding admins need
// the signed-in admin's password again. Failures count towards the same
// lockout as signing in.
func (s *Server) checkOwnPassword(r *http.Request, password string) error {
	a := adminOf(r)
	if err := s.allowAttempt(a.Email, r); err != nil {
		return userErr(http.StatusTooManyRequests, "LOCKED", "Too many wrong passwords. Try again in 15 minutes.")
	}
	var hash string
	if err := s.Svc.Store.DB.QueryRow(r.Context(), `select password_hash from admins where id = $1`, a.ID).Scan(&hash); err != nil ||
		!auth.VerifyPassword(hash, password) {
		s.attemptFailed(a.Email, r)
		return userErr(http.StatusForbidden, "BAD_PASSWORD", "Your password is wrong. Nothing was changed.")
	}
	s.attemptOK(a.Email, r)
	return nil
}
