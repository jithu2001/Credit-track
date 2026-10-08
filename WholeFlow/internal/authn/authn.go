// Package authn signs people in to a business, replacing its GoTrue
// container. It works directly on the business database's GoTrue tables
// (auth.users, auth.identities, auth.sessions, auth.refresh_tokens; see
// db/auth/auth_schema.sql), so existing logins, password hashes (bcrypt) and
// sessions keep working, and issues the same access tokens (HS256 with the
// business's JWT secret, GoTrue's claims). The app's login library talks to
// it unchanged through the HTTP handlers in internal/appapi (auth_http.go).
//
// Every function takes a transaction on the business database whose role may
// use the auth tables (the business's <slug>_auth role, or a superuser).
package authn

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

const (
	// TokenTTL is how long an access token is valid (as GoTrue's JWT_EXP).
	TokenTTL = time.Hour
	// MinPassword is the shortest password accepted anywhere (the apps ask for the same).
	MinPassword = 8
	// MaxPasswordBytes: bcrypt reads no further.
	MaxPasswordBytes = 72
	// SessionMaxAge: a session ends this long after sign-in, however much it is used.
	SessionMaxAge = 30 * 24 * time.Hour
	// SessionIdle: a session not refreshed for this long ends (a phone left
	// unused; an access token lives an hour, so an app in use refreshes hourly).
	SessionIdle = 14 * 24 * time.Hour
	// ReauthWindow: changing the password needs a sign-in this recent (the app
	// signs in again with the current password right before).
	ReauthWindow = 5 * time.Minute
	// reuseInterval: a refresh token used again this soon after it was
	// replaced (two requests racing) gets the newer token instead of ending
	// the session.
	reuseInterval = 10 * time.Second
	bcryptCost    = 10
)

var zeroInstance = "00000000-0000-0000-0000-000000000000"

// Error is an answer GoTrue would give: HTTP status, error code, message.
type Error struct {
	Status int
	Code   string
	Msg    string
	// Commit: the transaction must still be committed (the refusal ended a
	// session, which must stick).
	Commit bool
}

func (e *Error) Error() string { return e.Code + ": " + e.Msg }

// committed is e marked to keep the transaction's changes.
func committed(e *Error) *Error { c := *e; c.Commit = true; return &c }

// MustCommit reports whether a failed call's transaction must still be committed.
func MustCommit(err error) bool {
	var e *Error
	return errors.As(err, &e) && e.Commit
}

var (
	ErrInvalidCredentials = &Error{Status: http.StatusBadRequest, Code: "invalid_credentials", Msg: "Invalid login credentials"}
	ErrBanned             = &Error{Status: http.StatusBadRequest, Code: "user_banned", Msg: "User is banned"}
	ErrRefreshNotFound    = &Error{Status: http.StatusBadRequest, Code: "refresh_token_not_found", Msg: "Invalid Refresh Token: Refresh Token Not Found"}
	ErrRefreshReused      = &Error{Status: http.StatusBadRequest, Code: "refresh_token_already_used", Msg: "Invalid Refresh Token: Already Used"}
	ErrSessionNotFound    = &Error{Status: http.StatusForbidden, Code: "session_not_found", Msg: "Session from session_id claim in JWT does not exist"}
	ErrUserNotFound       = &Error{Status: http.StatusNotFound, Code: "user_not_found", Msg: "User not found"}
	ErrEmailExists        = &Error{Status: http.StatusUnprocessableEntity, Code: "email_exists", Msg: "A user with this email address has already been registered"}
	ErrSamePassword       = &Error{Status: http.StatusUnprocessableEntity, Code: "same_password", Msg: "New password should be different from the old password."}
	ErrWeakPassword       = &Error{Status: http.StatusUnprocessableEntity, Code: "weak_password", Msg: "Password should be at least 8 characters."}
	ErrLongPassword       = &Error{Status: http.StatusUnprocessableEntity, Code: "weak_password", Msg: "Password should be at most 72 characters."}
	// ErrReauthNeeded: 400, not 401 (the apps treat a 401 as a finished session).
	ErrReauthNeeded = &Error{Status: http.StatusBadRequest, Code: "reauthentication_needed", Msg: "Sign in again to change your password."}
	ErrInvalidEmail = &Error{Status: http.StatusBadRequest, Code: "validation_failed", Msg: "Unable to validate email address: invalid format"}
)

// User is a login as GoTrue returns it.
type User struct {
	ID               string         `json:"id"`
	Aud              string         `json:"aud"`
	Role             string         `json:"role"`
	Email            string         `json:"email"`
	EmailConfirmedAt *time.Time     `json:"email_confirmed_at,omitempty"`
	Phone            string         `json:"phone"`
	ConfirmedAt      *time.Time     `json:"confirmed_at,omitempty"`
	LastSignInAt     *time.Time     `json:"last_sign_in_at,omitempty"`
	AppMetadata      map[string]any `json:"app_metadata"`
	UserMetadata     map[string]any `json:"user_metadata"`
	Identities       []any          `json:"identities"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	IsAnonymous      bool           `json:"is_anonymous"`

	bannedUntil *time.Time
	hash        string
}

// Session is GoTrue's answer to a sign-in or refresh.
type Session struct {
	AccessToken  string `json:"access_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	ExpiresAt    int64  `json:"expires_at"`
	RefreshToken string `json:"refresh_token"`
	User         *User  `json:"user"`
}

// Issuer signs access tokens for one business.
type Issuer struct {
	Secret string // the business's JWT secret
	URL    string // iss claim, e.g. https://api.example/b/demo/auth/v1
	Now    func() time.Time
}

func (is Issuer) now() time.Time {
	if is.Now != nil {
		return is.Now()
	}
	return time.Now()
}

// Meta is where a sign-in came from (kept on the session).
type Meta struct {
	UserAgent string
	IP        string
}

const userColumns = `id::text, coalesce(aud, ''), coalesce(role, ''), coalesce(email, ''), email_confirmed_at, coalesce(phone, ''),
	confirmed_at, last_sign_in_at, coalesce(raw_app_meta_data, '{}'::jsonb), coalesce(raw_user_meta_data, '{}'::jsonb),
	coalesce(created_at, now()), coalesce(updated_at, now()), coalesce(is_anonymous, false), banned_until, coalesce(encrypted_password, '')`

func scanUser(row pgx.Row) (*User, error) {
	var u User
	var app, meta []byte
	err := row.Scan(&u.ID, &u.Aud, &u.Role, &u.Email, &u.EmailConfirmedAt, &u.Phone, &u.ConfirmedAt, &u.LastSignInAt,
		&app, &meta, &u.CreatedAt, &u.UpdatedAt, &u.IsAnonymous, &u.bannedUntil, &u.hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	} else if err != nil {
		return nil, err
	}
	_ = json.Unmarshal(app, &u.AppMetadata)
	_ = json.Unmarshal(meta, &u.UserMetadata)
	if u.AppMetadata == nil {
		u.AppMetadata = map[string]any{}
	}
	if u.UserMetadata == nil {
		u.UserMetadata = map[string]any{}
	}
	u.Identities = []any{}
	return &u, nil
}

// GetUser reads one login.
func GetUser(ctx context.Context, tx pgx.Tx, id string) (*User, error) {
	return scanUser(tx.QueryRow(ctx, `select `+userColumns+` from auth.users where id::text = $1 and deleted_at is null`, id))
}

func (u *User) banned(now time.Time) bool { return u.bannedUntil != nil && u.bannedUntil.After(now) }

// dummyHash keeps a sign-in for an unknown email as slow as for a known one.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("wholeflow-not-a-password"), bcryptCost)

func randomToken() string {
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	h := make([]byte, 32)
	const hexd = "0123456789abcdef"
	for i, c := range b {
		h[i*2], h[i*2+1] = hexd[c>>4], hexd[c&15]
	}
	s := string(h)
	return s[0:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:]
}

// ---------------------------------------------------------------- tokens

func b64(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }

// accessToken issues GoTrue's access token for u in session sessionID.
func (is Issuer) accessToken(u *User, sessionID string, now time.Time) (string, int64) {
	exp := now.Add(TokenTTL).Unix()
	claims := map[string]any{
		"aud": "authenticated", "exp": exp, "iat": now.Unix(), "iss": is.URL, "sub": u.ID,
		"email": u.Email, "phone": u.Phone, "app_metadata": u.AppMetadata, "user_metadata": u.UserMetadata,
		"role": "authenticated", "aal": "aal1",
		"amr":        []map[string]any{{"method": "password", "timestamp": now.Unix()}},
		"session_id": sessionID, "is_anonymous": false,
	}
	header, _ := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	payload, _ := json.Marshal(claims)
	unsigned := b64(header) + "." + b64(payload)
	mac := hmac.New(sha256.New, []byte(is.Secret))
	mac.Write([]byte(unsigned))
	return unsigned + "." + b64(mac.Sum(nil)), exp
}

func (is Issuer) session(u *User, sessionID, refresh string, now time.Time) *Session {
	at, exp := is.accessToken(u, sessionID, now)
	return &Session{AccessToken: at, TokenType: "bearer", ExpiresIn: int(TokenTTL.Seconds()), ExpiresAt: exp,
		RefreshToken: refresh, User: u}
}

// Refresh tokens are stored as "h1:" + hex(SHA-256(token)), so the login
// tables alone (a backup, a leak) give nobody a working token. Rows GoTrue
// wrote hold the token itself and are still found.
const hashedPrefix = "h1:"

func hashRefresh(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hashedPrefix + hex.EncodeToString(sum[:])
}

// insertRefresh adds a refresh token to a session and returns it; parent is
// the stored value of the token it replaces.
func insertRefresh(ctx context.Context, tx pgx.Tx, userID, sessionID string, parent *string, now time.Time) (string, error) {
	token := randomToken()
	_, err := tx.Exec(ctx, `insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at, parent, session_id)
		values ($1::uuid, $2, $3, false, $4, $4, $5, $6::uuid)`, zeroInstance, hashRefresh(token), userID, now, parent, sessionID)
	return token, err
}

type refreshRow struct {
	id                        int64
	stored, userID, sessionID string
	revoked                   bool
	updated                   time.Time
}

// findRefresh finds (and locks) a refresh token's row: by its hash, or as
// GoTrue stored it. A value that looks like a stored hash is never matched
// as a token (a copy of the table must not work as tokens).
func findRefresh(ctx context.Context, tx pgx.Tx, token string) (*refreshRow, error) {
	if token == "" || strings.HasPrefix(token, hashedPrefix) {
		return nil, ErrRefreshNotFound
	}
	for _, key := range []string{hashRefresh(token), token} {
		var r refreshRow
		err := tx.QueryRow(ctx, `select id, token, coalesce(user_id, ''), coalesce(revoked, false), coalesce(session_id::text, ''),
				coalesce(updated_at, created_at, now())
			from auth.refresh_tokens where token = $1 for update`, key).Scan(&r.id, &r.stored, &r.userID, &r.revoked, &r.sessionID, &r.updated)
		if errors.Is(err, pgx.ErrNoRows) {
			continue
		} else if err != nil {
			return nil, err
		}
		if r.sessionID == "" {
			return nil, ErrRefreshNotFound
		}
		return &r, nil
	}
	return nil, ErrRefreshNotFound
}

// ---------------------------------------------------------------- sign in, refresh, sign out

// SignIn checks email and password and starts a session.
func (is Issuer) SignIn(ctx context.Context, tx pgx.Tx, email, password string, m Meta) (*Session, error) {
	now := is.now()
	u, err := scanUser(tx.QueryRow(ctx, `select `+userColumns+` from auth.users
		where email = lower($1) and is_sso_user = false and deleted_at is null`, strings.TrimSpace(email)))
	if errors.Is(err, ErrUserNotFound) {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return nil, ErrInvalidCredentials
	} else if err != nil {
		return nil, err
	}
	if u.hash == "" || bcrypt.CompareHashAndPassword([]byte(u.hash), []byte(password)) != nil {
		return nil, ErrInvalidCredentials
	}
	if u.banned(now) {
		return nil, ErrBanned
	}
	sessionID := newUUID()
	var ip any
	if m.IP != "" {
		ip = m.IP
	}
	if _, err := tx.Exec(ctx, `insert into auth.sessions (id, user_id, created_at, updated_at, aal, user_agent, ip, not_after)
		values ($1::uuid, $2::uuid, $3, $3, 'aal1', $4, $5::inet, $6)`, sessionID, u.ID, now, m.UserAgent, ip, now.Add(SessionMaxAge)); err != nil {
		return nil, err
	}
	refresh, err := insertRefresh(ctx, tx, u.ID, sessionID, nil, now)
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `update auth.users set last_sign_in_at = $2, updated_at = $2 where id::text = $1`, u.ID, now); err != nil {
		return nil, err
	}
	u.LastSignInAt = &now
	return is.session(u, sessionID, refresh, now), nil
}

// Refresh exchanges a refresh token for a new access token and a new refresh
// token (the old one is revoked). A revoked token used again ends the session,
// unless it was replaced only moments ago (two requests racing). A session
// ends SessionMaxAge after sign-in, or after SessionIdle without a refresh.
func (is Issuer) Refresh(ctx context.Context, tx pgx.Tx, token string) (*Session, error) {
	now := is.now()
	rt, err := findRefresh(ctx, tx, token)
	if err != nil {
		return nil, err
	}
	sessionID, userID := rt.sessionID, rt.userID
	if err := checkSessionAge(ctx, tx, sessionID, now); err != nil {
		return nil, err
	}
	u, err := GetUser(ctx, tx, userID)
	if errors.Is(err, ErrUserNotFound) || (err == nil && u.banned(now)) {
		if _, derr := tx.Exec(ctx, `delete from auth.sessions where id = $1::uuid`, sessionID); derr != nil {
			return nil, derr
		}
		if err != nil {
			return nil, committed(ErrRefreshNotFound)
		}
		return nil, committed(ErrBanned)
	} else if err != nil {
		return nil, err
	}
	if rt.revoked {
		// Replaced moments ago (two requests racing): this request gets a
		// token of its own on the same session (the newer token is stored
		// only as a hash, so it can't be handed out again).
		var newer bool
		if err := tx.QueryRow(ctx, `select exists(select 1 from auth.refresh_tokens where parent = $1 and not coalesce(revoked, false))`,
			rt.stored).Scan(&newer); err != nil {
			return nil, err
		}
		if newer && now.Sub(rt.updated) <= reuseInterval {
			sibling, err := insertRefresh(ctx, tx, userID, sessionID, &rt.stored, now)
			if err != nil {
				return nil, err
			}
			return is.session(u, sessionID, sibling, now), nil
		}
		// Reuse of an old token: someone may have copied it. End the session.
		if _, err := tx.Exec(ctx, `delete from auth.sessions where id = $1::uuid`, sessionID); err != nil {
			return nil, err
		}
		return nil, committed(ErrRefreshReused)
	}
	if _, err := tx.Exec(ctx, `update auth.refresh_tokens set revoked = true, updated_at = $2 where id = $1`, rt.id, now); err != nil {
		return nil, err
	}
	next, err := insertRefresh(ctx, tx, userID, sessionID, &rt.stored, now)
	if err != nil {
		return nil, err
	}
	// Sessions from before these limits (GoTrue's) get their 30 days from now.
	if _, err := tx.Exec(ctx, `update auth.sessions set refreshed_at = $2::timestamp, updated_at = $3,
			not_after = coalesce(not_after, $4) where id = $1::uuid`,
		sessionID, now.UTC(), now, now.Add(SessionMaxAge)); err != nil {
		return nil, err
	}
	return is.session(u, sessionID, next, now), nil
}

// checkSessionAge: the session exists and is within its limits; an
// expired one is removed (and that removal kept).
func checkSessionAge(ctx context.Context, tx pgx.Tx, sessionID string, now time.Time) error {
	var created time.Time
	var notAfter, refreshed *time.Time
	err := tx.QueryRow(ctx, `select coalesce(created_at, now()), not_after, refreshed_at from auth.sessions where id = $1::uuid`, sessionID).
		Scan(&created, &notAfter, &refreshed)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrRefreshNotFound
	} else if err != nil {
		return err
	}
	last := created
	if refreshed != nil {
		// refreshed_at is a timestamp without time zone, written in UTC.
		r := *refreshed
		last = time.Date(r.Year(), r.Month(), r.Day(), r.Hour(), r.Minute(), r.Second(), r.Nanosecond(), time.UTC)
	}
	if (notAfter != nil && !now.Before(*notAfter)) || now.Sub(last) > SessionIdle {
		if _, err := tx.Exec(ctx, `delete from auth.sessions where id = $1::uuid`, sessionID); err != nil {
			return err
		}
		return committed(ErrRefreshNotFound)
	}
	return nil
}

// SignOut ends sessions: "local" (this one, the default), "global" (all of
// the user's) or "others" (all but this one).
func SignOut(ctx context.Context, tx pgx.Tx, userID, sessionID, scope string) error {
	var err error
	switch scope {
	case "global":
		_, err = tx.Exec(ctx, `delete from auth.sessions where user_id::text = $1`, userID)
	case "others":
		_, err = tx.Exec(ctx, `delete from auth.sessions where user_id::text = $1 and id::text <> $2`, userID, sessionID)
	default:
		_, err = tx.Exec(ctx, `delete from auth.sessions where id::text = $1 and user_id::text = $2`, sessionID, userID)
	}
	return err
}

// SessionExists reports whether the session of an access token is still
// open (not signed out, reset, banned or past its end) at now.
func SessionExists(ctx context.Context, q Querier, sessionID string, now time.Time) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `select exists(select 1 from auth.sessions where id::text = $1 and (not_after is null or not_after > $2))`,
		sessionID, now).Scan(&ok)
	return ok, err
}

// Querier is a transaction, connection or pool.
type Querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ---------------------------------------------------------------- the signed-in user's own changes

// protectedMetadata are user metadata keys the user can't set or remove
// themselves (PUT /user "data"): the server keeps them.
var protectedMetadata = []string{"must_change_password", "role", "business_id"}

func checkPassword(password string) error {
	if utf8.RuneCountInString(password) < MinPassword {
		return ErrWeakPassword
	}
	if len(password) > MaxPasswordBytes {
		return ErrLongPassword
	}
	return nil
}

// UpdateUser changes the user's own password and/or merges data into their
// user metadata (a null value removes a key), as GoTrue's PUT /user, in the
// session sessionID. A new password needs a sign-in within ReauthWindow
// (ErrReauthNeeded otherwise), clears must_change_password and ends the
// user's other sessions.
func (is Issuer) UpdateUser(ctx context.Context, tx pgx.Tx, id, sessionID string, password *string, data map[string]any) (*User, error) {
	u, err := GetUser(ctx, tx, id)
	if err != nil {
		return nil, err
	}
	now := is.now()
	for _, k := range protectedMetadata {
		delete(data, k)
	}
	if password != nil {
		var created time.Time
		err := tx.QueryRow(ctx, `select coalesce(created_at, 'epoch') from auth.sessions where id::text = $1 and user_id::text = $2`,
			sessionID, id).Scan(&created)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSessionNotFound
		} else if err != nil {
			return nil, err
		}
		if now.Sub(created) > ReauthWindow {
			return nil, ErrReauthNeeded
		}
		if err := checkPassword(*password); err != nil {
			return nil, err
		}
		if u.hash != "" && bcrypt.CompareHashAndPassword([]byte(u.hash), []byte(*password)) == nil {
			return nil, ErrSamePassword
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(*password), bcryptCost)
		if err != nil {
			return nil, err
		}
		if _, err := tx.Exec(ctx, `update auth.users set encrypted_password = $2, updated_at = $3 where id::text = $1`, id, string(hash), now); err != nil {
			return nil, err
		}
		if data == nil {
			data = map[string]any{}
		}
		data["must_change_password"] = false
		if err := SignOut(ctx, tx, id, sessionID, "others"); err != nil {
			return nil, err
		}
	}
	if len(data) > 0 {
		if err := mergeMetadata(ctx, tx, id, data, now); err != nil {
			return nil, err
		}
	}
	return GetUser(ctx, tx, id)
}

func mergeMetadata(ctx context.Context, tx pgx.Tx, id string, data map[string]any, now time.Time) error {
	set, unset := map[string]any{}, []string{}
	for k, v := range data {
		if v == nil {
			unset = append(unset, k)
		} else {
			set[k] = v
		}
	}
	raw, _ := json.Marshal(set)
	_, err := tx.Exec(ctx, `update auth.users set raw_user_meta_data = (coalesce(raw_user_meta_data, '{}'::jsonb) || $2::jsonb) - $3::text[],
		updated_at = $4 where id::text = $1`, id, string(raw), unset, now)
	return err
}

// ---------------------------------------------------------------- admin (staff management, admin app)

// CreateUser makes a confirmed email login; ErrEmailExists when the address is taken.
func CreateUser(ctx context.Context, tx pgx.Tx, email, password string, meta map[string]any, now time.Time) (string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if !strings.Contains(email, "@") || len(email) > 255 {
		return "", ErrInvalidEmail
	}
	if err := checkPassword(password); err != nil {
		return "", err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return "", err
	}
	if meta == nil {
		meta = map[string]any{}
	}
	metaJSON, _ := json.Marshal(meta)
	id := newUUID()
	if _, err := tx.Exec(ctx, `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
			raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
		values ($1::uuid, $2::uuid, 'authenticated', 'authenticated', $3, $4, $5, '{"provider": "email", "providers": ["email"]}'::jsonb,
			$6::jsonb, $5, $5, false, false)`, zeroInstance, id, email, string(hash), now, string(metaJSON)); err != nil {
		var pg *pgconn.PgError
		if errors.As(err, &pg) && pg.Code == "23505" {
			return "", ErrEmailExists
		}
		return "", err
	}
	identity, _ := json.Marshal(map[string]any{"sub": id, "email": email, "email_verified": false, "phone_verified": false})
	if _, err := tx.Exec(ctx, `insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
		values ($1, $2::uuid, $3::jsonb, 'email', $4, $4)`, id, id, string(identity), now); err != nil {
		return "", err
	}
	return id, nil
}

// Update is an admin change to a login; nil fields are left as they are.
type Update struct {
	Password *string
	Metadata map[string]any // merged into the user metadata
	Ban      *time.Duration // 0 lifts a ban; a ban also ends the user's sessions
}

// AdminUpdate changes a login. A new password also ends all of the user's
// sessions (whoever knew the old one is signed out).
func AdminUpdate(ctx context.Context, tx pgx.Tx, id string, up Update, now time.Time) error {
	if _, err := GetUser(ctx, tx, id); err != nil {
		return err
	}
	if up.Password != nil {
		if err := checkPassword(*up.Password); err != nil {
			return err
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(*up.Password), bcryptCost)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `update auth.users set encrypted_password = $2, updated_at = $3 where id::text = $1`, id, string(hash), now); err != nil {
			return err
		}
		if err := EndSessions(ctx, tx, id); err != nil {
			return err
		}
	}
	if up.Metadata != nil {
		if err := mergeMetadata(ctx, tx, id, up.Metadata, now); err != nil {
			return err
		}
	}
	if up.Ban != nil {
		var until any
		if *up.Ban > 0 {
			until = now.Add(*up.Ban)
		}
		if _, err := tx.Exec(ctx, `update auth.users set banned_until = $2, updated_at = $3 where id::text = $1`, id, until, now); err != nil {
			return err
		}
		if *up.Ban > 0 {
			if _, err := tx.Exec(ctx, `delete from auth.sessions where user_id::text = $1`, id); err != nil {
				return err
			}
		}
	}
	return nil
}

// EndSessions signs a user out everywhere.
func EndSessions(ctx context.Context, tx pgx.Tx, id string) error {
	_, err := tx.Exec(ctx, `delete from auth.sessions where user_id::text = $1`, id)
	return err
}

// DeleteUser removes a login (its sessions and identities go with it).
func DeleteUser(ctx context.Context, tx pgx.Tx, id string) error {
	_, err := tx.Exec(ctx, `delete from auth.users where id::text = $1`, id)
	return err
}
