package control

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"sort"
	"strconv"
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
	MonitorDir    string // scripts/monitor.sh's logs; empty = MonitorDir

	limiter      *auth.Limiter // wrong passwords/codes per email and address
	emailLimiter *auth.Limiter // per email from anywhere
	ipMu         sync.Mutex
	ipHits       map[string][]time.Time
	minAppBuild  settingCache
}

func NewServer(svc *Service, log *slog.Logger, internalToken string) *Server {
	s := &Server{Svc: svc, Log: log, InternalToken: internalToken,
		limiter:      auth.NewLimiter(8, 15*time.Minute, 15*time.Minute),
		emailLimiter: auth.NewLimiter(30, 15*time.Minute, 15*time.Minute),
		ipHits:       map[string][]time.Time{}}
	s.minAppBuild.load = func(ctx context.Context) (int, error) { return svc.Store.IntSetting(ctx, "min_app_build") }
	return s
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
	mux.HandleFunc("POST /control/admin/logout", s.adminOrEnrol(s.adminLogout))
	mux.HandleFunc("GET /control/admin/me", s.adminOrEnrol(s.adminMe))
	mux.HandleFunc("POST /control/admin/2fa/setup", s.adminOrEnrol(s.totpSetup))
	mux.HandleFunc("POST /control/admin/2fa/confirm", s.adminOrEnrol(s.totpConfirm))
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
	mux.HandleFunc("POST /control/admin/admins/{id}/reset-2fa", s.admin(s.resetAdminTOTP))
	mux.HandleFunc("POST /control/admin/admins/{id}/disabled", s.admin(s.setAdminDisabled))
	mux.HandleFunc("POST /control/admin/password", s.admin(s.changePassword))
	s.webRoutes(mux)
	s.deleteRoutes(mux)
	s.leadRoutes(mux)
	s.ownerRoutes(mux)
	s.monitorRoutes(mux)
	return s.recoverer(mux)
}

// ---------------------------------------------------------------- plumbing

type adminKey struct{}

type adminInfo struct {
	ID    string `json:"id"`
	Email string `json:"email"`
	Name  string `json:"name"`
	Role  string `json:"role"`
	Stage string `json:"-"`
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

// allowIP: at most n requests per IP per minute for a public endpoint.
func (s *Server) allowIP(ip string, n int) bool {
	ip = auth.IPKey(ip)
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

// TooOld: the phone app is older than the setting min_app_build allows.
func (s *Server) TooOld(r *http.Request) bool {
	return TooOld(r, s.minAppBuild.get(r.Context()))
}

// writeUpgrade answers an outdated phone app (426: it shows "please update").
func writeUpgrade(w http.ResponseWriter) {
	writeJSON(w, http.StatusUpgradeRequired, errBody("UPGRADE_REQUIRED", UpgradeMessage))
}

// longRequest lets an admin request that runs a script (creating a business,
// updating every database, a backup) write its answer after the server's
// usual write timeout.
func longRequest(w http.ResponseWriter, d time.Duration) {
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(d))
}

func (s *Server) connect(w http.ResponseWriter, r *http.Request) {
	if s.TooOld(r) {
		writeUpgrade(w)
		return
	}
	ip := auth.ClientIP(r)
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
	if !s.allowIP(auth.ClientIP(r), 10) {
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
	longRequest(w, 15*time.Minute) // runs the provisioning script
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
	out["latest_pc_version"] = s.Svc.Store.Setting(ctx, "latest_pc_version")
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
	ctx := r.Context()
	minBuild, _ := s.Svc.Store.IntSetting(ctx, "min_app_build")
	writeJSON(w, 200, map[string]any{
		"renew_message":     s.Svc.Store.Setting(ctx, "renew_message"),
		"contact":           s.Svc.Store.Setting(ctx, "contact"),
		"min_app_build":     minBuild,
		"latest_pc_version": s.Svc.Store.Setting(ctx, "latest_pc_version"),
	})
}

var pcVersionRE = regexp.MustCompile(`^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$`)

// putSettings saves any of renew_message, contact (texts), min_app_build
// (whole number, 0 = no minimum) and latest_pc_version ("0.6.0" or empty).
func (s *Server) putSettings(w http.ResponseWriter, r *http.Request) {
	var in map[string]any
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	values := map[string]string{}
	for _, k := range []string{"renew_message", "contact", "latest_pc_version"} {
		if v, ok := in[k]; ok {
			str, isStr := v.(string)
			if !isStr {
				writeErr(w, userErr(400, "INVALID_INPUT", k+" must be text."))
				return
			}
			values[k] = strings.TrimSpace(str)
		}
	}
	if v := values["latest_pc_version"]; v != "" && !pcVersionRE.MatchString(v) {
		writeErr(w, userErr(400, "INVALID_INPUT", "Latest PC version: numbers and dots, like 0.6.0 (or empty)."))
		return
	}
	if v, ok := in["min_app_build"]; ok {
		var n float64
		switch x := v.(type) {
		case float64:
			n = x
		case string:
			f, err := strconv.ParseFloat(strings.TrimSpace(x), 64)
			if err != nil && strings.TrimSpace(x) != "" {
				writeErr(w, userErr(400, "INVALID_INPUT", "Minimum app build: a whole number (0 = no minimum)."))
				return
			}
			n = f
		default:
			writeErr(w, userErr(400, "INVALID_INPUT", "Minimum app build: a whole number (0 = no minimum)."))
			return
		}
		if n < 0 || n > 1_000_000_000 || n != float64(int64(n)) {
			writeErr(w, userErr(400, "INVALID_INPUT", "Minimum app build: a whole number (0 = no minimum)."))
			return
		}
		values["min_app_build"] = strconv.FormatInt(int64(n), 10)
	}
	ctx, a := r.Context(), adminOf(r)
	for k, v := range values {
		if _, err := s.Svc.Store.DB.Exec(ctx, `insert into settings (key, value) values ($1, $2)
			on conflict (key) do update set value = excluded.value`, k, v); err != nil {
			s.fail(w, r, err)
			return
		}
	}
	s.Svc.Store.Audit(ctx, &a.ID, nil, "settings.save", map[string]any{"keys": keysOf(values)})
	_, msg := values["renew_message"]
	_, contact := values["contact"]
	if msg || contact {
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
	}
	s.getSettings(w, r)
}

func keysOf(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func (s *Server) migrateAll(w http.ResponseWriter, r *http.Request) {
	longRequest(w, 31*time.Minute) // MigrateAll allows the script 30 minutes
	out, err := s.Svc.MigrateAll(r.Context(), adminOf(r).ID)
	status := 200
	if err != nil {
		status = 500
	}
	writeJSON(w, status, map[string]any{"ok": err == nil, "output": out})
}

func trimPtr(p *string) *string {
	if p == nil {
		return nil
	}
	t := strings.TrimSpace(*p)
	return &t
}
