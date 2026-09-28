// Package admin is the login and cloud-sync configuration API of the
// WholeFlow app, mounted under /api/sync/: the single admin account that
// unlocks the whole app, business/cloud/company configuration, connection
// tests, manual sync and log viewing. The business owner never uses this app;
// they use the mobile app against the cloud.
package admin

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"wholeflow/internal/auth"
	"wholeflow/internal/cloud"
	"wholeflow/internal/config"
	"wholeflow/internal/syncer"
	"wholeflow/internal/tally"
)

const (
	sessionCookie = "wfsync_session"
	csrfHeader    = "X-Requested-With"
	csrfValue     = "WholeFlowSync"
	syncWaitLimit = 45 * time.Minute
)

type Server struct {
	Settings     *syncer.SettingsStore
	Scheduler    *syncer.Scheduler
	Engine       *syncer.Engine
	Tally        *tally.Service
	Cfg          *config.Config
	Provider     syncer.ProviderFactory
	Sessions     *auth.Sessions
	Limiter      *auth.Limiter
	Log          *slog.Logger
	LogPath      string
	DataDir      string
	ControlToken string
	SecretScheme string
	// Quit, when set, is called by POST /api/sync/quit (control token only)
	// so that "wholeflow.exe stop" can end a background process gracefully.
	Quit func()
	// Mode tells the CLI how this instance runs: "service", "background" or
	// "foreground" (reported by GET /api/sync/status).
	Mode string
}

// Routes mounts the login and sync API under /api/sync/ on the application's
// mux. Only login and session are reachable without a session; everything
// else — including the web app's own endpoints, which main wraps with
// RequireLogin — needs the admin account.
func (s *Server) Routes(mux *http.ServeMux) {
	g := s.headers
	mux.HandleFunc("POST /api/sync/login", g(s.login))
	mux.HandleFunc("POST /api/sync/setup", g(s.setup))
	mux.HandleFunc("GET /api/sync/session", g(s.session))
	mux.HandleFunc("GET /api/sync/summary", g(s.auth(s.summary)))
	mux.HandleFunc("POST /api/sync/logout", g(s.auth(s.logout)))
	mux.HandleFunc("GET /api/sync/status", g(s.auth(s.status)))
	mux.HandleFunc("GET /api/sync/history", g(s.auth(s.history)))
	mux.HandleFunc("GET /api/sync/settings", g(s.auth(s.getSettings)))
	mux.HandleFunc("PUT /api/sync/settings", g(s.auth(s.putSettings)))
	mux.HandleFunc("POST /api/sync/tally/test", g(s.auth(s.tallyTest)))
	mux.HandleFunc("POST /api/sync/cloud/test", g(s.auth(s.cloudTest)))
	mux.HandleFunc("POST /api/sync/run", g(s.auth(s.sync)))
	mux.HandleFunc("GET /api/sync/logs", g(s.auth(s.logs)))
	mux.HandleFunc("POST /api/sync/password", g(s.auth(s.password)))
	mux.HandleFunc("GET /api/sync/users", g(s.auth(s.listUsers)))
	mux.HandleFunc("POST /api/sync/users", g(s.auth(s.createUser)))
	mux.HandleFunc("POST /api/sync/users/{id}/password", g(s.auth(s.userPassword)))
	mux.HandleFunc("POST /api/sync/users/{id}/active", g(s.auth(s.userActive)))
	mux.HandleFunc("POST /api/sync/quit", g(s.quit))
	mux.HandleFunc("/api/sync/", func(w http.ResponseWriter, r *http.Request) {
		writeErr(w, http.StatusNotFound, "NOT_FOUND", "Unknown endpoint.")
	})
}

// RequireLogin wraps any handler (the web app's API) with the same session /
// control-token check the sync API uses.
func (s *Server) RequireLogin(next http.Handler) http.Handler {
	return s.headers(s.auth(next.ServeHTTP))
}

// headers sets conservative response headers on API responses.
func (s *Server) headers(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Cache-Control", "no-store")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		next(w, r)
	}
}

// summary is the compact sync state shown in the app header: no identifiers,
// no credentials, no error text.
func (s *Server) summary(w http.ResponseWriter, r *http.Request) {
	st := s.Scheduler.Status()
	type cs struct {
		Name          string     `json:"name"`
		Status        string     `json:"status"`
		LastSuccessAt *time.Time `json:"lastSuccessAt,omitempty"`
	}
	companies := make([]cs, 0, len(st.Companies))
	for _, c := range st.Companies {
		companies = append(companies, cs{Name: c.Name, Status: c.Status, LastSuccessAt: c.LastSuccessAt})
	}
	writeJSON(w, http.StatusOK, map[string]any{"state": st.State, "enabled": st.Enabled, "running": st.Running,
		"configured": st.Configured, "nextRunAt": st.NextRunAt, "companies": companies, "version": syncer.Version})
}

// auth accepts a session cookie (browser) or the control token (CLI).
func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if bearer := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "); bearer != "" && s.ControlToken != "" {
			if tokenEqual(bearer, s.ControlToken) {
				next(w, r)
				return
			}
			writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid control token.")
			return
		}
		c, err := r.Cookie(sessionCookie)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Please log in.")
			return
		}
		if _, ok := s.Sessions.Validate(c.Value); !ok {
			writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Session expired. Please log in again.")
			return
		}
		if r.Method != http.MethodGet && r.Header.Get(csrfHeader) != csrfValue {
			writeErr(w, http.StatusForbidden, "FORBIDDEN", "Missing request header.")
			return
		}
		next(w, r)
	}
}

// ---------------------------------------------------------------- session

func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	set := s.Settings.Get()
	resp := map[string]any{"loggedIn": false, "setupRequired": set.Developer.PasswordHash == "", "version": syncer.Version}
	if c, err := r.Cookie(sessionCookie); err == nil {
		if user, ok := s.Sessions.Validate(c.Value); ok {
			resp["loggedIn"], resp["username"] = true, user
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get(csrfHeader) != csrfValue {
		writeErr(w, http.StatusForbidden, "FORBIDDEN", "Missing request header.")
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	set := s.Settings.Get()
	if set.Developer.PasswordHash == "" {
		writeErr(w, http.StatusConflict, "SETUP_REQUIRED", "No admin account exists yet. Open the app to create it.")
		return
	}
	user := strings.TrimSpace(body.Username)
	if err := s.Limiter.Allow(user); err != nil {
		writeErr(w, http.StatusTooManyRequests, "LOCKED", err.Error())
		return
	}
	if !strings.EqualFold(user, set.Developer.Username) || !auth.VerifyPassword(set.Developer.PasswordHash, body.Password) {
		s.Limiter.Failure(user)
		s.Log.Warn("developer login failed", "username", user, "remote", r.RemoteAddr)
		time.Sleep(700 * time.Millisecond)
		writeErr(w, http.StatusUnauthorized, "BAD_CREDENTIALS", "Incorrect username or password.")
		return
	}
	s.Limiter.Success(user)
	tok, err := s.Sessions.Create(set.Developer.Username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "INTERNAL", "Could not create session.")
		return
	}
	http.SetCookie(w, &http.Cookie{Name: sessionCookie, Value: tok, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
	s.Log.Info("developer logged in", "username", set.Developer.Username)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": set.Developer.Username})
}

// setup creates the admin account on first run, from the browser, and logs
// the caller in. It only works while no password is set; afterwards the
// password can be changed on the Cloud Sync page or reset with set-password.
func (s *Server) setup(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get(csrfHeader) != csrfValue {
		writeErr(w, http.StatusForbidden, "FORBIDDEN", "Missing request header.")
		return
	}
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
		Confirm  string `json:"confirm"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	if s.Settings.Get().Developer.PasswordHash != "" {
		writeErr(w, http.StatusConflict, "ALREADY_SET", "An admin account already exists. Log in.")
		return
	}
	user := strings.TrimSpace(body.Username)
	if user == "" {
		user = "admin"
	}
	if body.Password != body.Confirm {
		writeErr(w, http.StatusBadRequest, "MISMATCH", "The two passwords do not match.")
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "WEAK_PASSWORD", err.Error())
		return
	}
	err = s.Settings.Update(func(st *syncer.Settings) error {
		if st.Developer.PasswordHash != "" { // lost a race with another tab or the CLI
			return errors.New("an admin account already exists")
		}
		st.Developer.Username, st.Developer.PasswordHash = user, hash
		return nil
	})
	if err != nil {
		writeErr(w, http.StatusConflict, "ALREADY_SET", err.Error())
		return
	}
	tok, err := s.Sessions.Create(user)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "INTERNAL", "Could not create session.")
		return
	}
	http.SetCookie(w, &http.Cookie{Name: sessionCookie, Value: tok, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
	s.Log.Info("admin account created from the browser", "username", user, "remote", r.RemoteAddr)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "username": user})
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(sessionCookie); err == nil {
		s.Sessions.Revoke(c.Value)
	}
	http.SetCookie(w, &http.Cookie{Name: sessionCookie, Value: "", Path: "/", HttpOnly: true, MaxAge: -1})
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) password(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Current  string `json:"current"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	set := s.Settings.Get()
	if err := s.Limiter.Allow(set.Developer.Username); err != nil {
		writeErr(w, http.StatusTooManyRequests, "LOCKED", err.Error())
		return
	}
	if !auth.VerifyPassword(set.Developer.PasswordHash, body.Current) {
		s.Limiter.Failure(set.Developer.Username)
		writeErr(w, http.StatusUnauthorized, "BAD_CREDENTIALS", "Current password is incorrect.")
		return
	}
	s.Limiter.Success(set.Developer.Username)
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "WEAK_PASSWORD", err.Error())
		return
	}
	user := strings.TrimSpace(body.Username)
	if user == "" {
		user = set.Developer.Username
	}
	if err := s.Settings.Update(func(st *syncer.Settings) error {
		st.Developer.Username, st.Developer.PasswordHash = user, hash
		return nil
	}); err != nil {
		writeErr(w, http.StatusBadRequest, "INVALID", err.Error())
		return
	}
	// Sign out every other browser; this one keeps its session.
	if c, err := r.Cookie(sessionCookie); err == nil {
		s.Sessions.RevokeAllExcept(c.Value)
	} else {
		s.Sessions.RevokeAllExcept("")
	}
	s.Log.Info("developer password changed", "username", user)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// ---------------------------------------------------------------- status & settings

func (s *Server) status(w http.ResponseWriter, r *http.Request) {
	st := s.Scheduler.Status()
	writeJSON(w, http.StatusOK, map[string]any{
		"sync":          st,
		"tallyEndpoint": s.Tally.Endpoint(), "portSource": s.Cfg.PortSource, "shopGroups": s.Cfg.ShopGroups,
		"dataDir": s.DataDir, "logPath": s.LogPath, "secretScheme": s.SecretScheme, "now": time.Now(),
		"mode": s.Mode, "pid": os.Getpid(),
	})
}

func (s *Server) history(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"runs": s.Scheduler.History()})
}

type settingsDTO struct {
	Business  syncer.BusinessSettings   `json:"business"`
	Cloud     cloudDTO                  `json:"cloud"`
	Sync      syncer.SyncSettings       `json:"sync"`
	Companies []syncer.CompanySetting   `json:"companies"`
	Developer struct{ Username string } `json:"developer"`
	Env       []string                  `json:"envOverrides"`
	Path      string                    `json:"path"`
}

type cloudDTO struct {
	Provider    string `json:"provider"`
	SupabaseURL string `json:"supabaseUrl"`
	SupabaseKey string `json:"supabaseKey,omitempty"` // request only; never echoed
	HasKey      bool   `json:"hasKey"`
	KeyFromEnv  bool   `json:"keyFromEnv"`
	KeyError    string `json:"keyError,omitempty"`
}

func (s *Server) getSettings(w http.ResponseWriter, r *http.Request) {
	set := s.Settings.Get()
	dto := settingsDTO{Business: set.Business, Sync: set.Sync, Companies: set.Companies,
		Env: s.Settings.EnvOverrides(), Path: s.Settings.Path()}
	dto.Cloud = cloudDTO{Provider: set.Cloud.Provider, SupabaseURL: set.Cloud.SupabaseURL, HasKey: set.Cloud.SupabaseKey != "",
		KeyFromEnv: set.Cloud.KeyFromEnv, KeyError: set.Cloud.KeyError}
	dto.Developer.Username = set.Developer.Username
	if dto.Companies == nil {
		dto.Companies = []syncer.CompanySetting{}
	}
	if dto.Env == nil {
		dto.Env = []string{}
	}
	writeJSON(w, http.StatusOK, dto)
}

func (s *Server) putSettings(w http.ResponseWriter, r *http.Request) {
	var in settingsDTO
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request: "+err.Error())
		return
	}
	cur := s.Settings.Get()
	wasEnabled := cur.Sync.Enabled
	if keyNeededFor(cur.Cloud.SupabaseURL, in.Cloud.SupabaseURL, in.Cloud.SupabaseKey, cur.Cloud.KeyFromEnv) {
		writeErr(w, http.StatusBadRequest, "KEY_REQUIRED", "The project URL changed: enter the service-role key for the new project too.")
		return
	}
	err := s.Settings.Update(func(st *syncer.Settings) error {
		st.Business = syncer.BusinessSettings{ID: strings.TrimSpace(in.Business.ID), Name: strings.TrimSpace(in.Business.Name)}
		st.Cloud.Provider = strings.ToLower(strings.TrimSpace(in.Cloud.Provider))
		st.Cloud.SupabaseURL = strings.TrimSpace(in.Cloud.SupabaseURL)
		if k := strings.TrimSpace(in.Cloud.SupabaseKey); k != "" && !st.Cloud.KeyFromEnv {
			st.Cloud.SupabaseKey, st.Cloud.KeyError = k, ""
		}
		st.Sync = in.Sync
		st.Companies = nil
		for _, c := range in.Companies {
			c.TallyID, c.Name = strings.TrimSpace(c.TallyID), strings.TrimSpace(c.Name)
			if c.TallyID != "" {
				st.Companies = append(st.Companies, c)
			}
		}
		return nil
	})
	if err != nil {
		writeErr(w, http.StatusBadRequest, "INVALID", err.Error())
		return
	}
	set := s.Settings.Get()
	s.Log.Info("settings saved", "business", set.Business.ID, "provider", set.Cloud.Provider,
		"interval_s", set.Sync.IntervalSeconds, "enabled", set.Sync.Enabled, "companies", len(set.EnabledCompanies()))
	if set.Sync.Enabled && !wasEnabled {
		s.Scheduler.TriggerNow()
	}
	s.getSettings(w, r)
}

// ---------------------------------------------------------------- tests & actions

func (s *Server) tallyTest(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	st := s.Tally.TestConnection(ctx)
	resp := map[string]any{"connected": st.Connected, "state": st.State, "host": st.Host, "port": st.Port,
		"endpoint": st.Endpoint, "portSource": s.Cfg.PortSource, "processRunning": st.ProcessRunning,
		"responseMs": st.ResponseMs, "companies": st.Companies, "checkedAt": st.CheckedAt, "warnings": s.Cfg.Warnings}
	if st.Error != nil {
		resp["error"] = map[string]string{"code": string(st.Error.Kind), "message": tallyMessage(st.Error)}
	}
	writeJSON(w, http.StatusOK, resp)
}

func tallyMessage(e *tally.Error) string {
	switch e.Kind {
	case tally.KindUnreachable:
		return "Unable to connect to TallyPrime. Make sure it is running and acting as Server (Help > Settings > Connectivity)."
	case tally.KindTimeout:
		return "TallyPrime did not respond in time."
	}
	return "TallyPrime returned an unexpected response: " + e.Msg
}

func (s *Server) cloudTest(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Business syncer.BusinessSettings `json:"business"`
		Cloud    cloudDTO                `json:"cloud"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&in); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	set := s.Settings.Get()
	if keyNeededFor(set.Cloud.SupabaseURL, in.Cloud.SupabaseURL, in.Cloud.SupabaseKey, set.Cloud.KeyFromEnv) {
		writeErr(w, http.StatusBadRequest, "KEY_REQUIRED", "The project URL differs from the saved one: enter the service-role key for that project too.")
		return
	}
	if in.Business.ID != "" {
		set.Business.ID = strings.TrimSpace(in.Business.ID)
	}
	if in.Cloud.Provider != "" {
		set.Cloud.Provider = strings.ToLower(strings.TrimSpace(in.Cloud.Provider))
	}
	if in.Cloud.SupabaseURL != "" {
		set.Cloud.SupabaseURL = strings.TrimSpace(in.Cloud.SupabaseURL)
	}
	if k := strings.TrimSpace(in.Cloud.SupabaseKey); k != "" && !set.Cloud.KeyFromEnv {
		set.Cloud.SupabaseKey, set.Cloud.KeyError = k, ""
	}
	start := time.Now()
	prov, err := s.Provider(set)
	if err == nil {
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		err = prov.Authenticate(ctx)
	}
	resp := map[string]any{"ok": err == nil, "provider": set.Cloud.Provider, "businessId": set.Business.ID, "responseMs": time.Since(start).Milliseconds()}
	if err != nil {
		code, msg := classifyForUI(err)
		resp["error"] = map[string]string{"code": code, "message": msg}
	}
	writeJSON(w, http.StatusOK, resp)
}

func classifyForUI(err error) (string, string) {
	msg := err.Error()
	code := "CLOUD_ERROR"
	if i := strings.Index(msg, "CLOUD_"); i >= 0 {
		rest := msg[i:]
		if j := strings.Index(rest, ":"); j > 0 {
			code = rest[:j]
			msg = strings.TrimSpace(rest[j+1:])
		}
	}
	return code, msg
}

// ---------------------------------------------------------------- owner / staff accounts

const minUserPassword = 8

// userManager builds the provider from the saved settings and requires the
// optional UserManager capability.
func (s *Server) userManager(w http.ResponseWriter) (cloud.UserManager, bool) {
	set := s.Settings.Get()
	if set.Business.ID == "" {
		writeErr(w, http.StatusBadRequest, "NOT_CONFIGURED", "Save the business and cloud settings first.")
		return nil, false
	}
	prov, err := s.Provider(set)
	if err != nil {
		code, msg := classifyForUI(err)
		writeErr(w, http.StatusBadRequest, code, msg)
		return nil, false
	}
	um, ok := prov.(cloud.UserManager)
	if !ok {
		writeErr(w, http.StatusBadRequest, "NOT_SUPPORTED", "This cloud provider cannot manage accounts.")
		return nil, false
	}
	return um, true
}

func (s *Server) cloudFail(w http.ResponseWriter, err error) {
	code, msg := classifyForUI(err)
	status := http.StatusBadGateway
	switch cloud.KindOf(err) {
	case cloud.KindError, cloud.KindConfig:
		status = http.StatusBadRequest
	case cloud.KindNotFound:
		status = http.StatusNotFound
	case cloud.KindAuth:
		status = http.StatusBadRequest
	}
	writeErr(w, status, code, msg)
}

type userDTO struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Name      string    `json:"name"`
	Role      string    `json:"role"`
	IsActive  bool      `json:"isActive"`
	CreatedAt time.Time `json:"createdAt"`
}

func toUserDTO(u cloud.User) userDTO {
	return userDTO{ID: u.ID, Email: u.Email, Name: u.Name, Role: u.Role, IsActive: u.IsActive, CreatedAt: u.CreatedAt}
}

func (s *Server) listUsers(w http.ResponseWriter, r *http.Request) {
	um, ok := s.userManager(w)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	users, err := um.ListUsers(ctx)
	if err != nil {
		s.cloudFail(w, err)
		return
	}
	out := make([]userDTO, 0, len(users))
	for _, u := range users {
		out = append(out, toUserDTO(u))
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": out, "businessId": s.Settings.Get().Business.ID})
}

func (s *Server) createUser(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email    string `json:"email"`
		Name     string `json:"name"`
		Password string `json:"password"`
		Role     string `json:"role"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	email := strings.ToLower(strings.TrimSpace(body.Email))
	if !strings.Contains(email, "@") || strings.ContainsAny(email, " \t") {
		writeErr(w, http.StatusBadRequest, "BAD_EMAIL", "Enter a valid email address.")
		return
	}
	if len(body.Password) < minUserPassword {
		writeErr(w, http.StatusBadRequest, "WEAK_PASSWORD", fmt.Sprintf("Password must be at least %d characters.", minUserPassword))
		return
	}
	role := strings.ToUpper(strings.TrimSpace(body.Role))
	if role == "" {
		role = cloud.RoleOwner
	}
	if role != cloud.RoleOwner && role != cloud.RoleStaff {
		writeErr(w, http.StatusBadRequest, "BAD_ROLE", "Role must be OWNER or STAFF.")
		return
	}
	um, ok := s.userManager(w)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	u, err := um.CreateUser(ctx, cloud.NewUser{Email: email, Password: body.Password, Name: strings.TrimSpace(body.Name), Role: role})
	if err != nil {
		s.cloudFail(w, err)
		return
	}
	s.Log.Info("cloud user created", "email", email, "role", role, "id", u.ID)
	writeJSON(w, http.StatusOK, map[string]any{"user": toUserDTO(u)})
}

func (s *Server) userPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil || len(body.Password) < minUserPassword {
		writeErr(w, http.StatusBadRequest, "WEAK_PASSWORD", fmt.Sprintf("Password must be at least %d characters.", minUserPassword))
		return
	}
	um, ok := s.userManager(w)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	if err := um.SetUserPassword(ctx, r.PathValue("id"), body.Password); err != nil {
		s.cloudFail(w, err)
		return
	}
	s.Log.Info("cloud user password reset", "id", r.PathValue("id"))
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) userActive(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Active bool `json:"active"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "BAD_REQUEST", "Invalid request.")
		return
	}
	um, ok := s.userManager(w)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	if err := um.SetUserActive(ctx, r.PathValue("id"), body.Active); err != nil {
		s.cloudFail(w, err)
		return
	}
	s.Log.Info("cloud user active flag changed", "id", r.PathValue("id"), "active", body.Active)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// sync triggers a run. With ?wait=1 it runs synchronously (used by the CLI)
// and returns the result; otherwise it kicks the scheduler and returns.
func (s *Server) sync(w http.ResponseWriter, r *http.Request) {
	if r.URL.Query().Get("wait") == "1" {
		ctx, cancel := context.WithTimeout(context.Background(), syncWaitLimit)
		defer cancel()
		res := s.Engine.Run(ctx)
		writeJSON(w, http.StatusOK, map[string]any{"run": res})
		return
	}
	s.Scheduler.TriggerNow()
	writeJSON(w, http.StatusAccepted, map[string]any{"triggered": true})
}

// quit asks the process to shut down. Only the CLI (control token) may call
// it; a browser session cannot stop the app.
func (s *Server) quit(w http.ResponseWriter, r *http.Request) {
	bearer := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if s.ControlToken == "" || !tokenEqual(bearer, s.ControlToken) {
		writeErr(w, http.StatusUnauthorized, "UNAUTHORIZED", "Invalid control token.")
		return
	}
	if s.Quit == nil {
		writeErr(w, http.StatusConflict, "NOT_SUPPORTED", "This instance cannot be stopped over the API.")
		return
	}
	s.Log.Info("shutdown requested over the control API")
	writeJSON(w, http.StatusOK, map[string]any{"stopping": true})
	go s.Quit()
}

func (s *Server) logs(w http.ResponseWriter, r *http.Request) {
	n, _ := strconv.Atoi(r.URL.Query().Get("lines"))
	if n <= 0 || n > 2000 {
		n = 200
	}
	lines, err := tailLines(s.LogPath, n)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		writeErr(w, http.StatusInternalServerError, "INTERNAL", "Could not read log: "+err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": s.LogPath, "lines": lines})
}

func tailLines(path string, n int) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	const window = 512 * 1024
	off := st.Size() - window
	if off < 0 {
		off = 0
	}
	buf := make([]byte, st.Size()-off)
	if _, err := f.ReadAt(buf, off); err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return nil, err
	}
	lines := strings.Split(strings.TrimRight(string(buf), "\r\n"), "\n")
	if off > 0 && len(lines) > 0 {
		lines = lines[1:] // first line is probably partial
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	for i := range lines {
		lines[i] = strings.TrimRight(lines[i], "\r")
	}
	return lines, nil
}

// ---------------------------------------------------------------- helpers

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	enc.Encode(v)
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": msg}})
}

// tokenEqual compares secrets in constant time.
func tokenEqual(a, b string) bool {
	return len(a) == len(b) && subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

// keyNeededFor reports whether switching to newURL requires the caller to
// supply the service-role key again: the stored key is only ever sent to the
// Supabase project it was saved for.
func keyNeededFor(saved, newURL, suppliedKey string, keyFromEnv bool) bool {
	norm := func(u string) string { return strings.ToLower(strings.TrimRight(strings.TrimSpace(u), "/")) }
	return !keyFromEnv && strings.TrimSpace(suppliedKey) == "" && saved != "" && norm(newURL) != "" && norm(newURL) != norm(saved)
}
