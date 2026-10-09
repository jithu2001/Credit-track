package appapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/auth"
	"wholeflow/internal/authn"
	"wholeflow/internal/control"
)

// Signing in, at the address the apps' login library already uses
// (https://api.<domain>/b/<slug>/auth/v1/…), in GoTrue's format, so the apps
// work unchanged. Replaces each business's GoTrue container.
//
//	POST /b/{slug}/auth/v1/token?grant_type=password        {"email", "password"} → session
//	POST /b/{slug}/auth/v1/token?grant_type=refresh_token   {"refresh_token"}     → session
//	GET  /b/{slug}/auth/v1/user                             the signed-in user
//	PUT  /b/{slug}/auth/v1/user                             {"password", "data"}  (own password, metadata)
//	     A new password needs a sign-in within the last 5 minutes (else 400
//	     reauthentication_needed: the app signs in with the current password
//	     first), ends the user's other sessions and clears must_change_password;
//	     "data" can't set must_change_password, role or business_id.
//	POST /b/{slug}/auth/v1/logout?scope=local|global|others
//	GET  /b/{slug}/auth/v1/health

// Sign-in attempts (counted before the password check; a correct password
// clears the first):
//   - 10 per email of a business from one address (IPv6: its /64) within 15
//     minutes lock that pair for 15 minutes — a stranger can't lock the owner
//     out of their own phone this way;
//   - 50 per email from anywhere within 15 minutes lock the email for 15
//     minutes (stops guessing spread over many addresses);
//   - 60 per address within 15 minutes, across every business.
var (
	loginLimiterOnce sync.Once
	pairLimiter      *auth.Limiter
	emailLimiter     *auth.Limiter
	ipLimiter        *auth.Limiter
)

func limiters() (pair, email, ip *auth.Limiter) {
	loginLimiterOnce.Do(func() {
		pairLimiter = auth.NewLimiter(10, 15*time.Minute, 15*time.Minute)
		emailLimiter = auth.NewLimiter(50, 15*time.Minute, 15*time.Minute)
		ipLimiter = auth.NewLimiter(60, 15*time.Minute, 15*time.Minute)
	})
	return pairLimiter, emailLimiter, ipLimiter
}

// authError answers like GoTrue (API version 2024-01-01): {"code", "msg"}.
func authError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("X-Supabase-Api-Version", "2024-01-01")
	writeJSON(w, status, map[string]any{"code": code, "error_code": code, "msg": msg})
}

func (s *Server) issuer(t *tenant) authn.Issuer {
	return authn.Issuer{Secret: t.Secret, URL: strings.TrimRight(t.BaseURL, "/") + "/auth/v1", Now: s.Now}
}

// inAuthTx runs fn in a transaction on the business's login tables. A
// refusal that must stick (authn.MustCommit) is still committed.
func inAuthTx(ctx context.Context, t *tenant, fn func(pgx.Tx) error) error {
	if t.authPool == nil {
		return errors.New("no login database configured for " + t.slug)
	}
	tx, err := t.authPool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.WithoutCancel(ctx))
	if err := fn(tx); err != nil {
		if authn.MustCommit(err) {
			if cerr := tx.Commit(ctx); cerr != nil {
				return cerr
			}
		}
		return err
	}
	return tx.Commit(ctx)
}

// authFail writes an authn.Error as GoTrue would, anything else as a server error.
func (s *Server) authFail(w http.ResponseWriter, r *http.Request, err error) {
	var e *authn.Error
	if errors.As(err, &e) {
		authError(w, e.Status, e.Code, e.Msg)
		return
	}
	var ae *apiError
	if errors.As(err, &ae) {
		authError(w, ae.Status, strings.ToLower(ae.Code), ae.Message)
		return
	}
	s.Log.Error("auth request failed", "path", r.URL.Path, "error", err.Error())
	authError(w, http.StatusInternalServerError, "unexpected_failure", "The server had a problem. Please try again in a moment.")
}

func (s *Server) authRoutes(mux *http.ServeMux) {
	const p = "/b/{slug}/auth/v1/"
	mux.HandleFunc("POST "+p+"token", s.authToken)
	mux.HandleFunc("GET "+p+"user", s.authUser)
	mux.HandleFunc("PUT "+p+"user", s.authUpdateUser)
	mux.HandleFunc("POST "+p+"logout", s.authLogout)
	mux.HandleFunc("GET "+p+"health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"name": "WholeFlow", "description": "WholeFlow sign-in"})
	})
}

func (s *Server) authToken(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	var in struct {
		Email        string `json:"email"`
		Password     string `json:"password"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		authError(w, http.StatusBadRequest, "validation_failed", "Could not read the request.")
		return
	}
	is := s.issuer(t)
	var session *authn.Session
	switch r.URL.Query().Get("grant_type") {
	case "password":
		byPair, byEmail, byIP := limiters()
		ip := auth.ClientIP(r)
		emailKey := t.slug + "|" + strings.ToLower(strings.TrimSpace(in.Email))
		pairKey, ipKey := emailKey+"|"+auth.IPKey(ip), auth.IPKey(ip)
		if byIP.Allow(ipKey) != nil || byPair.Allow(pairKey) != nil || byEmail.Allow(emailKey) != nil {
			authError(w, http.StatusTooManyRequests, "over_request_rate_limit", "Too many sign-in attempts. Try again in 15 minutes.")
			return
		}
		err = inAuthTx(ctx, t, func(tx pgx.Tx) (err error) {
			session, err = is.SignIn(ctx, tx, in.Email, in.Password, authn.Meta{UserAgent: r.UserAgent(), IP: ip})
			return err
		})
		if errors.Is(err, authn.ErrInvalidCredentials) {
			byPair.Failure(pairKey)
			byEmail.Failure(emailKey)
			byIP.Failure(ipKey)
		} else if err == nil {
			byPair.Success(pairKey)
		}
	case "refresh_token":
		if in.RefreshToken == "" {
			authError(w, http.StatusBadRequest, "validation_failed", "refresh_token is required")
			return
		}
		err = inAuthTx(ctx, t, func(tx pgx.Tx) (err error) {
			session, err = is.Refresh(ctx, tx, in.RefreshToken)
			return err
		})
	default:
		authError(w, http.StatusBadRequest, "validation_failed", "unsupported grant_type")
		return
	}
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	w.Header().Set("X-Supabase-Api-Version", "2024-01-01")
	writeJSON(w, http.StatusOK, session)
}

// bearer checks the access token: the user id and session it names.
func (s *Server) bearer(r *http.Request, t *tenant) (userID, sessionID string, err error) {
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		return "", "", &authn.Error{Status: http.StatusUnauthorized, Code: "no_authorization", Msg: "This endpoint requires a Bearer token"}
	}
	claims, err := control.VerifyJWT(t.Secret, token, s.Now())
	if err != nil {
		return "", "", &authn.Error{Status: http.StatusForbidden, Code: "bad_jwt", Msg: "invalid JWT"}
	}
	userID, _ = claims["sub"].(string)
	sessionID, _ = claims["session_id"].(string)
	if userID == "" || claims["role"] != "authenticated" {
		return "", "", &authn.Error{Status: http.StatusForbidden, Code: "bad_jwt", Msg: "invalid JWT: not a user"}
	}
	return userID, sessionID, nil
}

// requireSession: the token's session must still be open (not signed out or banned).
func (s *Server) requireSession(ctx context.Context, tx pgx.Tx, sessionID string) error {
	if sessionID == "" {
		return authn.ErrSessionNotFound
	}
	ok, err := authn.SessionExists(ctx, tx, sessionID, s.Now())
	if err == nil && !ok {
		err = authn.ErrSessionNotFound
	}
	return err
}

func (s *Server) authUser(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	userID, sessionID, err := s.bearer(r, t)
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	var u *authn.User
	err = inAuthTx(ctx, t, func(tx pgx.Tx) (err error) {
		if err := s.requireSession(ctx, tx, sessionID); err != nil {
			return err
		}
		u, err = authn.GetUser(ctx, tx, userID)
		return err
	})
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) authUpdateUser(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	userID, sessionID, err := s.bearer(r, t)
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	var in struct {
		Password *string        `json:"password"`
		Data     map[string]any `json:"data"`
		Email    *string        `json:"email"`
		Phone    *string        `json:"phone"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		authError(w, http.StatusBadRequest, "validation_failed", "Could not read the request.")
		return
	}
	if in.Email != nil || in.Phone != nil {
		authError(w, http.StatusUnprocessableEntity, "email_change_not_allowed", "Email and phone can't be changed here.")
		return
	}
	var u *authn.User
	err = inAuthTx(ctx, t, func(tx pgx.Tx) (err error) {
		if err := s.requireSession(ctx, tx, sessionID); err != nil {
			return err
		}
		u, err = s.issuer(t).UpdateUser(ctx, tx, userID, sessionID, in.Password, in.Data)
		return err
	})
	if in.Password != nil {
		t.forgetSessions() // the user's other sessions just ended
	}
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) authLogout(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	userID, sessionID, err := s.bearer(r, t)
	if err != nil {
		s.authFail(w, r, err)
		return
	}
	if err := inAuthTx(ctx, t, func(tx pgx.Tx) error {
		return authn.SignOut(ctx, tx, userID, sessionID, r.URL.Query().Get("scope"))
	}); err != nil {
		s.authFail(w, r, err)
		return
	}
	t.forgetSessions()
	w.WriteHeader(http.StatusNoContent)
}
