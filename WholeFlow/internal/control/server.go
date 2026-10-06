package control

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/auth"
)

// Server is the control service's HTTP API. nginx forwards /control/ to it
// on 127.0.0.1; it never listens on a public address.
type Server struct {
	Svc           *Service
	Log           *slog.Logger
	InternalToken string // shared with the staff service on this machine

	sessions *auth.Sessions
	limiter  *auth.Limiter
	ipMu     sync.Mutex
	ipHits   map[string][]time.Time
}

func NewServer(svc *Service, log *slog.Logger, internalToken string) *Server {
	return &Server{Svc: svc, Log: log, InternalToken: internalToken,
		sessions: auth.NewSessions(12 * time.Hour),
		limiter:  auth.NewLimiter(5, 15*time.Minute, 15*time.Minute),
		ipHits:   map[string][]time.Time{}}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /control/health", func(w http.ResponseWriter, r *http.Request) {
		if err := s.Svc.Store.DB.Ping(r.Context()); err != nil {
			writeJSON(w, 503, map[string]any{"ok": false})
			return
		}
		writeJSON(w, 200, map[string]any{"ok": true})
	})

	// Phones and Tally PCs.
	mux.HandleFunc("GET /control/connect", s.connect)
	mux.HandleFunc("POST /control/activate", s.activate)
	mux.HandleFunc("POST /control/heartbeat", s.heartbeat)
	mux.HandleFunc("POST /control/pc/login", s.pcLogin)

	// Staff service (same machine, shared token).
	mux.HandleFunc("GET /control/internal/tenant/{slug}", s.internalTenant)

	// Admin app.
	mux.HandleFunc("POST /control/admin/login", s.adminLogin)
	mux.HandleFunc("POST /control/admin/logout", s.admin(s.adminLogout))
	mux.HandleFunc("GET /control/admin/me", s.admin(s.adminMe))
	mux.HandleFunc("GET /control/admin/businesses", s.admin(s.listBusinesses))
	mux.HandleFunc("POST /control/admin/businesses", s.admin(s.createBusiness))
	mux.HandleFunc("GET /control/admin/businesses/{id}", s.admin(s.getBusiness))
	mux.HandleFunc("PATCH /control/admin/businesses/{id}", s.admin(s.updateBusiness))
	mux.HandleFunc("POST /control/admin/businesses/{id}/payments", s.admin(s.recordPayment))
	mux.HandleFunc("POST /control/admin/businesses/{id}/status", s.admin(s.setStatus))
	mux.HandleFunc("POST /control/admin/businesses/{id}/activation-codes", s.admin(s.newActivationCode))
	mux.HandleFunc("POST /control/admin/businesses/{id}/reference-key", s.admin(s.rotateReferenceKey))
	mux.HandleFunc("POST /control/admin/devices/{id}/revoke", s.admin(s.revokeDevice))
	mux.HandleFunc("GET /control/admin/plans", s.admin(s.listPlans))
	mux.HandleFunc("PUT /control/admin/plans/{code}", s.admin(s.putPlan))
	mux.HandleFunc("GET /control/admin/settings", s.admin(s.getSettings))
	mux.HandleFunc("PUT /control/admin/settings", s.admin(s.putSettings))
	mux.HandleFunc("POST /control/admin/migrate-all", s.admin(s.migrateAll))
	mux.HandleFunc("GET /control/admin/admins", s.admin(s.listAdmins))
	mux.HandleFunc("POST /control/admin/admins", s.admin(s.createAdmin))
	s.webRoutes(mux)
	s.deleteRoutes(mux)
	s.leadRoutes(mux)
	return s.recoverer(mux)
}

// ---------------------------------------------------------------- plumbing

type adminKey struct{}

type adminInfo struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
}

func (s *Server) admin(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		id, ok := s.sessions.Validate(strings.TrimSpace(tok))
		if !ok {
			writeErr(w, userErr(401, "UNAUTHENTICATED", "Sign in again."))
			return
		}
		var a adminInfo
		err := s.Svc.Store.DB.QueryRow(r.Context(), `select id, email, name from admins where id = $1 and not disabled`, id).Scan(&a.ID, &a.Email, &a.Name)
		if err != nil {
			s.sessions.Revoke(tok)
			writeErr(w, userErr(401, "UNAUTHENTICATED", "Sign in again."))
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), adminKey{}, a)))
	}
}

func adminOf(r *http.Request) adminInfo { a, _ := r.Context().Value(adminKey{}).(adminInfo); return a }

func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				s.Log.Error("panic", "path", r.URL.Path, "error", v)
				writeJSON(w, 500, errBody("INTERNAL", "Something went wrong."))
			}
		}()
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

// clientIP: nginx sets X-Real-IP; the service only listens on localhost.
func clientIP(r *http.Request) string {
	if ip := strings.TrimSpace(r.Header.Get("X-Real-IP")); ip != "" {
		return ip
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	return host
}

// allowIP: at most n requests per IP per minute for a public endpoint.
func (s *Server) allowIP(ip string, n int) bool {
	s.ipMu.Lock()
	defer s.ipMu.Unlock()
	now := time.Now()
	hits := s.ipHits[ip][:0]
	for _, t := range s.ipHits[ip] {
		if now.Sub(t) < time.Minute {
			hits = append(hits, t)
		}
	}
	if len(hits) >= n {
		s.ipHits[ip] = hits
		return false
	}
	s.ipHits[ip] = append(hits, now)
	if len(s.ipHits) > 10000 { // forget idle IPs
		for k, v := range s.ipHits {
			if len(v) == 0 || now.Sub(v[len(v)-1]) > time.Minute {
				delete(s.ipHits, k)
			}
		}
	}
	return true
}

func readJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 64<<10))
	if err := dec.Decode(v); err != nil {
		return userErr(400, "INVALID_INPUT", "Body must be JSON.")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func errBody(code, msg string) map[string]any {
	return map[string]any{"error": map[string]string{"code": code, "message": msg}}
}

func writeErr(w http.ResponseWriter, err error) {
	var ue *UserError
	if errors.As(err, &ue) {
		writeJSON(w, ue.Status, errBody(ue.Code, ue.Msg))
		return
	}
	writeJSON(w, 500, errBody("INTERNAL", "Something went wrong. Please try again."))
}

func (s *Server) fail(w http.ResponseWriter, r *http.Request, err error) {
	var ue *UserError
	if !errors.As(err, &ue) {
		s.Log.Error("request failed", "path", r.URL.Path, "error", err.Error())
	}
	writeErr(w, err)
}

// ---------------------------------------------------------------- phones and PCs

func (s *Server) connect(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if !s.allowIP(ip, 20) || s.Svc.RecentFailedLookups(r.Context(), ip) >= 20 {
		writeErr(w, userErr(429, "TOO_MANY", "Too many attempts. Try again in an hour."))
		return
	}
	key := r.URL.Query().Get("key")
	if strings.TrimSpace(key) == "" {
		writeErr(w, userErr(400, "INVALID_INPUT", "Enter the reference key."))
		return
	}
	c, err := s.Svc.Connect(r.Context(), key, ip)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, c)
}

func (s *Server) activate(w http.ResponseWriter, r *http.Request) {
	if !s.allowIP(clientIP(r), 10) {
		writeErr(w, userErr(429, "TOO_MANY", "Too many attempts. Try again in a minute."))
		return
	}
	var a Activation
	if err := readJSON(r, &a); err != nil {
		writeErr(w, err)
		return
	}
	out, err := s.Svc.Activate(r.Context(), a)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, out)
}

func (s *Server) heartbeat(w http.ResponseWriter, r *http.Request) {
	tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	var body struct {
		AppVersion string `json:"app_version"`
	}
	_ = readJSON(r, &body)
	out, err := s.Svc.Heartbeat(r.Context(), strings.TrimSpace(tok), body.AppVersion)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, out)
}

// pcLogin: the Tally PC's local page signs in with an admin account.
func (s *Server) pcLogin(w http.ResponseWriter, r *http.Request) {
	a, err := s.checkLogin(r)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "name": a.Name, "email": a.Email,
		"offline_until": time.Now().Add(7 * 24 * time.Hour).UTC().Format(time.RFC3339)})
}

func (s *Server) internalTenant(w http.ResponseWriter, r *http.Request) {
	if s.InternalToken == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Internal-Token")), []byte(s.InternalToken)) != 1 {
		writeErr(w, userErr(403, "FORBIDDEN", "Forbidden."))
		return
	}
	base, key, err := s.Svc.TenantForStaff(r.Context(), r.PathValue("slug"))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, map[string]string{"base_url": base, "service_key": key})
}

// ---------------------------------------------------------------- admin: sessions

func (s *Server) checkLogin(r *http.Request) (*adminInfo, error) {
	var in struct{ Email, Password string }
	if err := readJSON(r, &in); err != nil {
		return nil, err
	}
	email := strings.ToLower(strings.TrimSpace(in.Email))
	if err := s.limiter.Allow(email); err != nil {
		return nil, userErr(429, "LOCKED", "Too many failed sign-ins. Try again in 15 minutes.")
	}
	if !s.allowIP(clientIP(r), 30) {
		return nil, userErr(429, "TOO_MANY", "Too many attempts. Try again in a minute.")
	}
	var a adminInfo
	var hash string
	err := s.Svc.Store.DB.QueryRow(r.Context(), `select id, email, name, password_hash from admins where email = $1 and not disabled`, email).
		Scan(&a.ID, &a.Email, &a.Name, &hash)
	if err != nil || !auth.VerifyPassword(hash, in.Password) {
		s.limiter.Failure(email)
		return nil, userErr(401, "BAD_LOGIN", "Wrong email or password.")
	}
	s.limiter.Success(email)
	_, _ = s.Svc.Store.DB.Exec(r.Context(), `update admins set last_login_at = now() where id = $1`, a.ID)
	return &a, nil
}

func (s *Server) adminLogin(w http.ResponseWriter, r *http.Request) {
	a, err := s.checkLogin(r)
	if err != nil {
		writeErr(w, err)
		return
	}
	tok, err := s.sessions.Create(a.ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "admin.login", map[string]any{"ip": clientIP(r)})
	writeJSON(w, 200, map[string]any{"token": tok, "name": a.Name, "email": a.Email})
}

func (s *Server) adminLogout(w http.ResponseWriter, r *http.Request) {
	tok, _ := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	s.sessions.Revoke(strings.TrimSpace(tok))
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (s *Server) adminMe(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, adminOf(r)) }

// ---------------------------------------------------------------- admin: businesses

type businessRow struct {
	ID           string     `json:"id"`
	Slug         string     `json:"slug"`
	Name         string     `json:"name"`
	ContactName  *string    `json:"contact_name"`
	Phone        *string    `json:"phone"`
	Email        *string    `json:"email"`
	Status       string     `json:"status"`
	BaseURL      string     `json:"base_url"`
	PlanCode     string     `json:"plan_code"`
	PlanName     string     `json:"plan_name"`
	PaidUntil    string     `json:"paid_until"`
	GraceDays    int        `json:"grace_days"`
	RemindDays   int        `json:"remind_days"`
	State        string     `json:"state"`
	Devices      int        `json:"devices"`
	LastSeen     *time.Time `json:"last_seen_at"`
	CreatedAt    time.Time  `json:"created_at"`
	ReferenceKey *string    `json:"reference_key,omitempty"`
}

const businessSelect = `select b.id, b.slug, b.name, b.contact_name, b.phone, b.email, b.status, b.base_url,
	s.plan_code, p.name, s.paid_until, s.grace_days, s.remind_days,
	(select count(*) from devices d where d.business_id = b.id and d.revoked_at is null),
	(select max(d.last_seen_at) from devices d where d.business_id = b.id), b.created_at,
	(select k.key from reference_keys k where k.business_id = b.id and k.revoked_at is null)
	from businesses b join subscriptions s on s.business_id = b.id join plans p on p.code = s.plan_code`

func (s *Server) scanBusiness(row pgx.Row) (*businessRow, error) {
	var b businessRow
	var paid time.Time
	if err := row.Scan(&b.ID, &b.Slug, &b.Name, &b.ContactName, &b.Phone, &b.Email, &b.Status, &b.BaseURL,
		&b.PlanCode, &b.PlanName, &paid, &b.GraceDays, &b.RemindDays, &b.Devices, &b.LastSeen, &b.CreatedAt, &b.ReferenceKey); err != nil {
		return nil, err
	}
	b.PaidUntil = paid.Format("2006-01-02")
	b.State = AccessState(b.Status, paid, b.GraceDays, b.RemindDays, Today(s.Svc.Now()))
	return &b, nil
}

func (s *Server) listBusinesses(w http.ResponseWriter, r *http.Request) {
	rows, err := s.Svc.Store.DB.Query(r.Context(), businessSelect+` order by s.paid_until, b.name`)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []*businessRow{}
	for rows.Next() {
		b, err := s.scanBusiness(rows)
		if err != nil {
			s.fail(w, r, err)
			return
		}
		b.ReferenceKey = nil
		out = append(out, b)
	}
	writeJSON(w, 200, out)
}

func (s *Server) createBusiness(w http.ResponseWriter, r *http.Request) {
	var in CreateBusiness
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	out, err := s.Svc.Create(r.Context(), in, adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 201, out)
}

func (s *Server) getBusiness(w http.ResponseWriter, r *http.Request) {
	ctx, id := r.Context(), r.PathValue("id")
	b, err := s.scanBusiness(s.Svc.Store.DB.QueryRow(ctx, businessSelect+` where b.id::text = $1`, id))
	if err != nil {
		writeErr(w, userErr(404, "NOT_FOUND", "No such business."))
		return
	}
	type payment struct {
		ID         string  `json:"id"`
		Amount     float64 `json:"amount"`
		PaidOn     string  `json:"paid_on"`
		Mode       string  `json:"mode"`
		Reference  *string `json:"reference"`
		Months     int     `json:"months"`
		PeriodFrom string  `json:"period_from"`
		PeriodTo   string  `json:"period_to"`
		Note       *string `json:"note"`
		RecordedBy *string `json:"recorded_by"`
	}
	type device struct {
		ID          string     `json:"id"`
		Machine     string     `json:"machine"`
		WindowsUser string     `json:"windows_user"`
		AppVersion  string     `json:"app_version"`
		ActivatedAt time.Time  `json:"activated_at"`
		LastSeenAt  *time.Time `json:"last_seen_at"`
		RevokedAt   *time.Time `json:"revoked_at"`
	}
	type event struct {
		At      time.Time      `json:"at"`
		Admin   *string        `json:"admin"`
		Action  string         `json:"action"`
		Details map[string]any `json:"details"`
	}
	out := map[string]any{"business": b}

	pays := []payment{}
	rows, err := s.Svc.Store.DB.Query(ctx, `select p.id, p.amount::float8, p.paid_on, p.mode, p.reference, p.months, p.period_from, p.period_to, p.note, a.name
		from payments p left join admins a on a.id = p.recorded_by where p.business_id = $1 order by p.paid_on desc, p.created_at desc`, b.ID)
	if err == nil {
		for rows.Next() {
			var p payment
			var on, from, to time.Time
			if rows.Scan(&p.ID, &p.Amount, &on, &p.Mode, &p.Reference, &p.Months, &from, &to, &p.Note, &p.RecordedBy) == nil {
				p.PaidOn, p.PeriodFrom, p.PeriodTo = on.Format("2006-01-02"), from.Format("2006-01-02"), to.Format("2006-01-02")
				pays = append(pays, p)
			}
		}
		rows.Close()
	}
	out["payments"] = pays

	devs := []device{}
	rows, err = s.Svc.Store.DB.Query(ctx, `select id, machine, windows_user, app_version, activated_at, last_seen_at, revoked_at
		from devices where business_id = $1 order by activated_at desc`, b.ID)
	if err == nil {
		for rows.Next() {
			var d device
			if rows.Scan(&d.ID, &d.Machine, &d.WindowsUser, &d.AppVersion, &d.ActivatedAt, &d.LastSeenAt, &d.RevokedAt) == nil {
				devs = append(devs, d)
			}
		}
		rows.Close()
	}
	out["devices"] = devs

	events := []event{}
	rows, err = s.Svc.Store.DB.Query(ctx, `select l.at, a.name, l.action, l.details from audit_log l left join admins a on a.id = l.admin_id
		where l.business_id = $1 order by l.at desc limit 50`, b.ID)
	if err == nil {
		for rows.Next() {
			var e event
			if rows.Scan(&e.At, &e.Admin, &e.Action, &e.Details) == nil {
				events = append(events, e)
			}
		}
		rows.Close()
	}
	out["events"] = events
	writeJSON(w, 200, out)
}

func (s *Server) updateBusiness(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name        *string `json:"name"`
		ContactName *string `json:"contact_name"`
		Phone       *string `json:"phone"`
		Email       *string `json:"email"`
		PlanCode    *string `json:"plan_code"`
		GraceDays   *int    `json:"grace_days"`
		RemindDays  *int    `json:"remind_days"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, id, a := r.Context(), r.PathValue("id"), adminOf(r)
	if in.Name != nil && strings.TrimSpace(*in.Name) == "" {
		writeErr(w, userErr(400, "INVALID_INPUT", "The name cannot be empty."))
		return
	}
	tag, err := s.Svc.Store.DB.Exec(ctx, `update businesses set name = coalesce($2, name), contact_name = coalesce($3, contact_name),
		phone = coalesce($4, phone), email = coalesce($5, email), updated_at = now() where id::text = $1`,
		id, trimPtr(in.Name), trimPtr(in.ContactName), trimPtr(in.Phone), trimPtr(in.Email))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, userErr(404, "NOT_FOUND", "No such business."))
		return
	}
	if in.PlanCode != nil || in.GraceDays != nil || in.RemindDays != nil {
		var plan string
		var grace, remind int
		_ = s.Svc.Store.DB.QueryRow(ctx, `select plan_code, grace_days, remind_days from subscriptions where business_id::text = $1`, id).Scan(&plan, &grace, &remind)
		if in.PlanCode != nil {
			plan = *in.PlanCode
		}
		if in.GraceDays != nil {
			grace = *in.GraceDays
		}
		if in.RemindDays != nil {
			remind = *in.RemindDays
		}
		if err := s.Svc.UpdateSubscription(ctx, id, plan, grace, remind, a.ID); err != nil {
			s.fail(w, r, err)
			return
		}
	} else {
		s.Svc.Store.Audit(ctx, &a.ID, &id, "business.update", nil)
	}
	s.getBusiness(w, r)
}

func (s *Server) recordPayment(w http.ResponseWriter, r *http.Request) {
	var p Payment
	if err := readJSON(r, &p); err != nil {
		writeErr(w, err)
		return
	}
	period, err := s.Svc.RecordPayment(r.Context(), r.PathValue("id"), p, adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 201, map[string]string{"period_from": period.From.Format("2006-01-02"), "paid_until": period.To.Format("2006-01-02")})
}

func (s *Server) setStatus(w http.ResponseWriter, r *http.Request) {
	var in struct{ Status string }
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if err := s.Svc.SetStatus(r.Context(), r.PathValue("id"), in.Status, adminOf(r).ID); err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true, "status": in.Status})
}

func (s *Server) newActivationCode(w http.ResponseWriter, r *http.Request) {
	code, err := s.Svc.NewActivationCode(r.Context(), r.PathValue("id"), adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 201, map[string]string{"activation_code": code, "valid_for": "48 hours"})
}

func (s *Server) rotateReferenceKey(w http.ResponseWriter, r *http.Request) {
	key, err := s.Svc.RotateReferenceKey(r.Context(), r.PathValue("id"), adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 201, map[string]string{"reference_key": key})
}

func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	if err := s.Svc.RevokeDevice(r.Context(), r.PathValue("id"), adminOf(r).ID); err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, 200, map[string]any{"ok": true})
}

// ---------------------------------------------------------------- admin: plans, settings, admins

func (s *Server) listPlans(w http.ResponseWriter, r *http.Request) {
	type plan struct {
		Code         string  `json:"code"`
		Name         string  `json:"name"`
		MaxCompanies int     `json:"max_companies"`
		PriceMonth   float64 `json:"price_month"`
		Active       bool    `json:"active"`
	}
	rows, err := s.Svc.Store.DB.Query(r.Context(), `select code, name, max_companies, price_month::float8, active from plans order by price_month`)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []plan{}
	for rows.Next() {
		var p plan
		if err := rows.Scan(&p.Code, &p.Name, &p.MaxCompanies, &p.PriceMonth, &p.Active); err == nil {
			out = append(out, p)
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) putPlan(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name         string  `json:"name"`
		MaxCompanies int     `json:"max_companies"`
		PriceMonth   float64 `json:"price_month"`
		Active       *bool   `json:"active"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	active := in.Active == nil || *in.Active
	code, a := r.PathValue("code"), adminOf(r)
	_, err := s.Svc.Store.DB.Exec(r.Context(), `insert into plans (code, name, max_companies, price_month, active) values ($1,$2,$3,$4,$5)
		on conflict (code) do update set name = excluded.name, max_companies = excluded.max_companies,
		price_month = excluded.price_month, active = excluded.active`, code, strings.TrimSpace(in.Name), in.MaxCompanies, in.PriceMonth, active)
	if err != nil {
		writeErr(w, userErr(400, "INVALID_INPUT", "Plan: code 2–20 lowercase letters/digits, a name, 1–100 companies, price ≥ 0."))
		return
	}
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "plan.save", map[string]any{"code": code})
	s.resyncPlan(r.Context(), code)
	s.listPlans(w, r)
}

// resyncPlan refreshes the banners of every business on a changed plan.
func (s *Server) resyncPlan(ctx context.Context, code string) {
	rows, err := s.Svc.Store.DB.Query(ctx, `select business_id::text from subscriptions where plan_code = $1`, code)
	if err != nil {
		return
	}
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	for _, id := range ids {
		if err := s.Svc.SyncStatus(ctx, id); err != nil {
			s.Log.Warn("status sync failed", "business", id, "error", err.Error())
		}
	}
}

func (s *Server) getSettings(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]string{
		"renew_message": s.Svc.Store.Setting(r.Context(), "renew_message"),
		"contact":       s.Svc.Store.Setting(r.Context(), "contact"),
	})
}

func (s *Server) putSettings(w http.ResponseWriter, r *http.Request) {
	var in map[string]string
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	ctx, a := r.Context(), adminOf(r)
	for _, k := range []string{"renew_message", "contact"} {
		if v, ok := in[k]; ok {
			if _, err := s.Svc.Store.DB.Exec(ctx, `insert into settings (key, value) values ($1, $2)
				on conflict (key) do update set value = excluded.value`, k, strings.TrimSpace(v)); err != nil {
				s.fail(w, r, err)
				return
			}
		}
	}
	s.Svc.Store.Audit(ctx, &a.ID, nil, "settings.save", nil)
	// Every business shows the new text and contact.
	rows, err := s.Svc.Store.DB.Query(ctx, `select id::text from businesses where status <> 'closed'`)
	if err == nil {
		var ids []string
		for rows.Next() {
			var id string
			if rows.Scan(&id) == nil {
				ids = append(ids, id)
			}
		}
		rows.Close()
		for _, id := range ids {
			_ = s.Svc.SyncStatus(ctx, id)
		}
	}
	s.getSettings(w, r)
}

func (s *Server) migrateAll(w http.ResponseWriter, r *http.Request) {
	out, err := s.Svc.MigrateAll(r.Context(), adminOf(r).ID)
	status := 200
	if err != nil {
		status = 500
	}
	writeJSON(w, status, map[string]any{"ok": err == nil, "output": out})
}

func (s *Server) listAdmins(w http.ResponseWriter, r *http.Request) {
	type admin struct {
		ID          string     `json:"id"`
		Email       string     `json:"email"`
		Name        string     `json:"name"`
		Disabled    bool       `json:"disabled"`
		LastLoginAt *time.Time `json:"last_login_at"`
	}
	rows, err := s.Svc.Store.DB.Query(r.Context(), `select id, email, name, disabled, last_login_at from admins order by email`)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []admin{}
	for rows.Next() {
		var a admin
		if rows.Scan(&a.ID, &a.Email, &a.Name, &a.Disabled, &a.LastLoginAt) == nil {
			out = append(out, a)
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) createAdmin(w http.ResponseWriter, r *http.Request) {
	var in struct{ Email, Name, Password string }
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	id, err := CreateAdmin(r.Context(), s.Svc.Store, in.Email, in.Name, in.Password)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	a := adminOf(r)
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "admin.create", map[string]any{"email": in.Email})
	writeJSON(w, 201, map[string]string{"id": id})
}

// CreateAdmin is used by the API and by `wholeflow-control create-admin`.
func CreateAdmin(ctx context.Context, store *Store, email, name, password string) (string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if !strings.Contains(email, "@") {
		return "", userErr(400, "INVALID_INPUT", "Enter a valid email.")
	}
	hash, err := auth.HashPassword(password)
	if err != nil {
		return "", userErr(400, "INVALID_INPUT", err.Error())
	}
	var id string
	err = store.DB.QueryRow(ctx, `insert into admins (email, name, password_hash) values ($1, $2, $3)
		on conflict (email) do update set password_hash = excluded.password_hash, name = excluded.name, disabled = false
		returning id`, email, strings.TrimSpace(name), hash).Scan(&id)
	return id, err
}

func trimPtr(p *string) *string {
	if p == nil {
		return nil
	}
	t := strings.TrimSpace(*p)
	return &t
}
