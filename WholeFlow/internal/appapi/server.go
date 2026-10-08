// Package appapi is the WholeFlow app API: the server side of the Owner and
// Staff apps (and a future web app). It serves every business from one
// process at /b/{slug}/api/v1/…, checks the same login tokens the business's
// GoTrue issues, and runs every query as the business data API's role with the
// caller's claims, so the database's row-level security decides what each
// user may see, exactly as through PostgREST. See docs/API_PLAN.md.
package appapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"wholeflow/internal/control"
)

// Server serves the app API for every business.
type Server struct {
	Control *pgxpool.Pool   // control_db: which businesses exist, their token secret
	Sealer  *control.Sealer // opens the sealed token secrets
	KitDir  string          // /opt/wholeflow: businesses/<slug>/env holds the data role's login
	PGHost  string          // host:port of PostgreSQL as seen from this process
	Log     *slog.Logger
	Now     func() time.Time

	// Resolve finds a business's token secret and database URL; nil means
	// control_db + businesses/<slug>/env (tests set their own).
	Resolve func(ctx context.Context, slug string) (secret, dbURL string, err error)

	mu      sync.Mutex
	tenants map[string]*tenant
}

// tenant is one business: its token secret and a small connection pool as
// its data API role (<slug>_api), refreshed every few minutes.
type tenant struct {
	slug     string
	secret   string
	pool     *pgxpool.Pool
	dbURL    string
	loadedAt time.Time
}

const tenantTTL = 5 * time.Minute

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("GET /b/{slug}/api/v1/payments", s.handle(s.paymentSummary))
	mux.HandleFunc("GET /b/{slug}/api/v1/payments/shops/{id}", s.handle(s.shopPayments))
	mux.HandleFunc("GET /b/{slug}/api/v1/shops/{id}/statement", s.handle(s.shopStatement))
	mux.HandleFunc("GET /b/{slug}/api/v1/dashboard", s.handle(s.dashboard))
	mux.HandleFunc("GET /b/{slug}/api/v1/shops", s.handle(s.shopsPage))
	mux.HandleFunc("GET /b/{slug}/api/v1/shops/{id}", s.handle(s.shopDetail))
	mux.HandleFunc("GET /b/{slug}/api/v1/reports/outstanding", s.handle(s.outstandingReport))
	mux.HandleFunc("GET /b/{slug}/api/v1/reports/overdue", s.handle(s.overdueReport))
	mux.HandleFunc("GET /b/{slug}/api/v1/stock", s.handle(s.stockList))
	mux.HandleFunc("GET /b/{slug}/api/v1/stock/{id}", s.handle(s.stockItem))
	mux.HandleFunc("GET /b/{slug}/api/v1/stock/{id}/purchases", s.handle(s.stockItemPurchases))
	mux.HandleFunc("PUT /b/{slug}/api/v1/stock/minimum", s.handleWrite(s.setStockMinimum))
	mux.HandleFunc("GET /b/{slug}/api/v1/purchases", s.handle(s.purchasesPage))
	mux.HandleFunc("GET /b/{slug}/api/v1/purchases/months", s.handle(s.purchaseMonths))
	mux.HandleFunc("GET /b/{slug}/api/v1/purchases/{id}", s.handle(s.purchaseDetail))
	mux.HandleFunc("GET /b/{slug}/api/v1/suppliers", s.handle(s.suppliersList))
	mux.HandleFunc("GET /b/{slug}/api/v1/suppliers/{id}", s.handle(s.supplierDetail))
	mux.HandleFunc("GET /b/{slug}/api/v1/me", s.handle(s.me))
	mux.HandleFunc("GET /b/{slug}/api/v1/me/access", s.handle(s.myAccess))
	mux.HandleFunc("GET /b/{slug}/api/v1/companies", s.handle(s.companies))
	mux.HandleFunc("GET /b/{slug}/api/v1/companies/{id}/areas", s.handle(s.companyAreas))
	mux.HandleFunc("GET /b/{slug}/api/v1/service-status", s.handle(s.serviceStatus))
	mux.HandleFunc("GET /b/{slug}/api/v1/sync/connections", s.handle(s.syncConnections))
	mux.HandleFunc("GET /b/{slug}/api/v1/sync/logs", s.handle(s.syncLogs))
	mux.HandleFunc("GET /b/{slug}/api/v1/sites", s.handle(s.sitesList))
	mux.HandleFunc("POST /b/{slug}/api/v1/sites", s.handleWrite(s.createSite))
	mux.HandleFunc("PATCH /b/{slug}/api/v1/sites/{id}", s.handleWrite(s.renameSite))
	mux.HandleFunc("DELETE /b/{slug}/api/v1/sites/{id}", s.handleWrite(s.deleteSite))
	mux.HandleFunc("GET /b/{slug}/api/v1/sites/{id}/shops", s.handle(s.siteShops))
	mux.HandleFunc("PUT /b/{slug}/api/v1/sites/{id}/shops", s.handleWrite(s.putSiteShops))
	mux.HandleFunc("GET /b/{slug}/api/v1/companies/{id}/site-shops", s.handle(s.companySiteShops))
	mux.HandleFunc("GET /b/{slug}/api/v1/reports/sites", s.handle(s.siteReport))
	mux.HandleFunc("GET /b/{slug}/api/v1/shops/{id}/location", s.handle(s.shopLocation))
	mux.HandleFunc("PUT /b/{slug}/api/v1/shops/{id}/location", s.handleWrite(s.setShopLocation))
	mux.HandleFunc("DELETE /b/{slug}/api/v1/shops/{id}/location", s.handleWrite(s.clearShopLocation))
	mux.HandleFunc("GET /b/{slug}/api/v1/location-suggestions", s.handle(s.locationSuggestions))
	mux.HandleFunc("POST /b/{slug}/api/v1/location-suggestions/{id}/review", s.handleWrite(s.reviewSuggestion))
	// Listing tasks first makes the days' tasks from the plans (idempotent), so it writes.
	mux.HandleFunc("GET /b/{slug}/api/v1/visits/tasks", s.handleWrite(s.visitTasks))
	mux.HandleFunc("GET /b/{slug}/api/v1/visits/tasks/{id}/failed-attempts", s.handle(s.failedAttempts))
	mux.HandleFunc("POST /b/{slug}/api/v1/visits/tasks/{id}/check-in", s.handleWrite(s.checkIn))
	mux.HandleFunc("GET /b/{slug}/api/v1/visits/plans", s.handle(s.visitPlans))
	mux.HandleFunc("POST /b/{slug}/api/v1/visits/plans", s.handleWrite(s.createPlans))
	mux.HandleFunc("PATCH /b/{slug}/api/v1/visits/plans/{id}", s.handleWrite(s.setPlanActive))
	mux.HandleFunc("DELETE /b/{slug}/api/v1/visits/plans/{id}", s.handleWrite(s.deletePlan))
	mux.HandleFunc("GET /b/{slug}/api/v1/visits/{id}", s.handle(s.visitDetail))
	mux.HandleFunc("POST /b/{slug}/api/v1/visits/{id}/note", s.handleWrite(s.addVisitNote))
	return mux
}

// Close releases every business's connections.
func (s *Server) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, t := range s.tenants {
		t.pool.Close()
	}
	s.tenants = nil
}

// ---------------------------------------------------------------- errors

// apiError is sent as {"error": {"code", "message", "details", "hint"}}.
type apiError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
	Details string `json:"details,omitempty"`
	Hint    string `json:"hint,omitempty"`
}

func (e *apiError) Error() string { return e.Code + ": " + e.Message }

func fail(status int, code, message string) *apiError {
	return &apiError{Status: status, Code: code, Message: message}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// toAPIError maps database errors raised by the business's rules: check_request
// (PT402 subscription ended, PT403 PC revoked) and permission errors.
func toAPIError(err error) *apiError {
	var ae *apiError
	if errors.As(err, &ae) {
		return ae
	}
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		switch pg.Code {
		case "PT402":
			return &apiError{Status: http.StatusPaymentRequired, Code: "SUBSCRIPTION_ENDED", Message: pg.Message, Details: pg.Detail, Hint: pg.Hint}
		case "PT403":
			return &apiError{Status: http.StatusForbidden, Code: "FORBIDDEN", Message: pg.Message, Details: pg.Detail}
		case "42501":
			return fail(http.StatusForbidden, "FORBIDDEN", "You don't have access to this.")
		case "22P02":
			return fail(http.StatusBadRequest, "INVALID_INPUT", "Invalid id.")
		case "22023": // invalid input raised by our SQL functions: "fn_name: message"
			msg := pg.Message
			if _, after, ok := strings.Cut(msg, ": "); ok {
				msg = strings.ToUpper(after[:1]) + after[1:] + "."
			}
			return fail(http.StatusBadRequest, "INVALID_INPUT", msg)
		}
	}
	return nil
}

// ---------------------------------------------------------------- requests

// request is one authenticated call: the business, the caller's claims and
// a transaction that runs as them.
type request struct {
	*http.Request
	tenant *tenant
	claims map[string]any
	tx     pgx.Tx
	today  time.Time
}

// handle wraps a handler: finds the business, checks the token, and runs fn
// in a read-only transaction as the caller (role authenticated + their JWT
// claims), after public.check_request() — the same checks PostgREST makes.
func (s *Server) handle(fn func(*request) (any, error)) http.HandlerFunc {
	return s.handleTx(fn, pgx.ReadOnly)
}

// handleWrite is handle for requests that change data (read-write transaction,
// committed when fn succeeds). The database's own functions still decide who may.
func (s *Server) handleWrite(fn func(*request) (any, error)) http.HandlerFunc {
	return s.handleTx(fn, pgx.ReadWrite)
}

func (s *Server) handleTx(fn func(*request) (any, error), mode pgx.TxAccessMode) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := s.serve(r, fn, mode)
		if err != nil {
			ae := toAPIError(err)
			if ae == nil {
				s.Log.Error("request failed", "path", r.URL.Path, "error", err.Error())
				ae = fail(http.StatusInternalServerError, "SERVER_ERROR", "The server had a problem. Please try again in a moment.")
			}
			writeJSON(w, ae.Status, map[string]any{"error": ae})
			return
		}
		writeJSON(w, http.StatusOK, out)
	}
}

func (s *Server) serve(r *http.Request, fn func(*request) (any, error), mode pgx.TxAccessMode) (any, error) {
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		return nil, err
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		return nil, fail(http.StatusUnauthorized, "UNAUTHENTICATED", "Sign in again.")
	}
	claims, err := control.VerifyJWT(t.secret, token, s.Now())
	if err != nil {
		return nil, fail(http.StatusUnauthorized, "UNAUTHENTICATED", "Sign in again.")
	}
	// Only signed-in people: not the public key, not a Tally PC's key.
	if claims["role"] != "authenticated" {
		return nil, fail(http.StatusForbidden, "FORBIDDEN", "This key can't use the app API.")
	}
	claimsJSON, _ := json.Marshal(claims)

	tx, err := t.pool.BeginTx(ctx, pgx.TxOptions{AccessMode: mode})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(context.WithoutCancel(ctx))
	if _, err := tx.Exec(ctx, `set local role authenticated`); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `select set_config('request.jwt.claims', $1, true)`, string(claimsJSON)); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `select public.check_request()`); err != nil {
		return nil, err
	}
	out, err := fn(&request{Request: r, tenant: t, claims: claims, tx: tx, today: control.Today(s.Now())})
	if err != nil {
		return nil, err
	}
	if mode == pgx.ReadWrite {
		if err := tx.Commit(ctx); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// readBody decodes a JSON request body (at most 1 MB) into v.
func readBody(r *request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return fail(http.StatusBadRequest, "INVALID_INPUT", "The request body is not valid JSON.")
	}
	return nil
}

// tenant finds a business by slug (cached for a few minutes).
func (s *Server) tenant(ctx context.Context, slug string) (*tenant, error) {
	if slug == "" || strings.ContainsAny(slug, "/.\\") {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "No such business.")
	}
	s.mu.Lock()
	if s.tenants == nil {
		s.tenants = map[string]*tenant{}
	}
	cached := s.tenants[slug]
	s.mu.Unlock()
	if cached != nil && s.Now().Sub(cached.loadedAt) < tenantTTL {
		return cached, nil
	}

	resolve := s.Resolve
	if resolve == nil {
		resolve = s.fromControl
	}
	secret, dbURL, err := resolve(ctx, slug)
	if err != nil {
		var ae *apiError
		if errors.As(err, &ae) && ae.Status == http.StatusNotFound {
			s.drop(slug)
		}
		return nil, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if cur := s.tenants[slug]; cur != nil && cur.dbURL == dbURL {
		cur.secret, cur.loadedAt = secret, s.Now()
		return cur, nil
	}
	cfg, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 4
	cfg.MaxConnIdleTime = 5 * time.Minute
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if old := s.tenants[slug]; old != nil {
		old.pool.Close()
	}
	t := &tenant{slug: slug, secret: secret, pool: pool, dbURL: dbURL, loadedAt: s.Now()}
	s.tenants[slug] = t
	return t, nil
}

// fromControl looks a business up in control_db (closed ones don't exist
// here) and reads its data role's login from businesses/<slug>/env.
func (s *Server) fromControl(ctx context.Context, slug string) (string, string, error) {
	var sealed, status string
	err := s.Control.QueryRow(ctx, `select jwt_secret_sealed, status from businesses where slug = $1`, slug).Scan(&sealed, &status)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && status == "closed") {
		return "", "", fail(http.StatusNotFound, "NOT_FOUND", "No such business.")
	} else if err != nil {
		return "", "", err
	}
	secret, err := s.Sealer.Open(sealed)
	if err != nil {
		return "", "", err
	}
	env, err := control.ReadEnvFile(filepath.Join(s.KitDir, "businesses", slug, "env"))
	if err != nil {
		return "", "", fmt.Errorf("business %s env: %w", slug, err)
	}
	dbURL, err := s.localURL(env["API_DB_URL"])
	if err != nil {
		return "", "", fmt.Errorf("business %s API_DB_URL: %w", slug, err)
	}
	return secret, dbURL, nil
}

func (s *Server) drop(slug string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if t := s.tenants[slug]; t != nil {
		t.pool.Close()
		delete(s.tenants, slug)
	}
}

// localURL points a business's database URL (written for the containers,
// host "db") at PostgreSQL as this process reaches it.
func (s *Server) localURL(raw string) (string, error) {
	if raw == "" {
		return "", errors.New("missing")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if s.PGHost != "" {
		u.Host = s.PGHost
	}
	q := u.Query()
	if q.Get("sslmode") == "" {
		q.Set("sslmode", "disable")
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}
