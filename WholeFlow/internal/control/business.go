package control

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/authn"
)

// Service holds the control operations; the HTTP layer only validates and calls it.
type Service struct {
	Store     *Store
	Sealer    *Sealer
	KitDir    string // /opt/wholeflow
	PublicURL string // https://api.jitsuji.xyz
	HTTP      *http.Client
	Now       func() time.Time
}

// UserError is shown to the admin or app as is (HTTP 400/404/409).
type UserError struct {
	Status int
	Code   string
	Msg    string
}

func (e *UserError) Error() string { return e.Msg }

func userErr(status int, code, msg string) error { return &UserError{status, code, msg} }

var slugRE = regexp.MustCompile(`^[a-z][a-z0-9]{1,19}$`)

// ---------------------------------------------------------------- create

type CreateBusiness struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	ContactName string `json:"contact_name"`
	Phone       string `json:"phone"`
	Email       string `json:"email"`
	PlanCode    string `json:"plan_code"`
	PaidUntil   string `json:"paid_until"` // YYYY-MM-DD; empty = 14-day trial
	OwnerName   string `json:"owner_name"`
	OwnerEmail  string `json:"owner_email"`
}

type CreatedBusiness struct {
	ID             string `json:"id"`
	Slug           string `json:"slug"`
	BaseURL        string `json:"base_url"`
	ReferenceKey   string `json:"reference_key"`
	ActivationCode string `json:"activation_code"`
	OwnerEmail     string `json:"owner_email"`
	OwnerPassword  string `json:"owner_password"` // temporary; must be changed at first sign-in
	PaidUntil      string `json:"paid_until"`
}

// Create provisions a business end to end: database, login and data API
// (scripts/new-business.sh), owner account, subscription, reference key and a
// first PC activation code.
func (s *Service) Create(ctx context.Context, in CreateBusiness, adminID string) (*CreatedBusiness, error) {
	in.Slug = strings.ToLower(strings.TrimSpace(in.Slug))
	in.Name = strings.TrimSpace(in.Name)
	in.OwnerEmail = strings.ToLower(strings.TrimSpace(in.OwnerEmail))
	switch {
	case !slugRE.MatchString(in.Slug):
		return nil, userErr(400, "INVALID_INPUT", "Short name: 2–20 lowercase letters or digits, starting with a letter.")
	case in.Name == "":
		return nil, userErr(400, "INVALID_INPUT", "Enter the business name.")
	case !strings.Contains(in.OwnerEmail, "@"):
		return nil, userErr(400, "INVALID_INPUT", "Enter the owner's email (their login).")
	}
	if in.PlanCode == "" {
		in.PlanCode = "basic"
	}
	var planOK, exists bool
	_ = s.Store.DB.QueryRow(ctx, `select exists(select 1 from plans where code = $1 and active)`, in.PlanCode).Scan(&planOK)
	if !planOK {
		return nil, userErr(400, "INVALID_INPUT", "Unknown plan.")
	}
	_ = s.Store.DB.QueryRow(ctx, `select exists(select 1 from businesses where slug = $1)`, in.Slug).Scan(&exists)
	if exists {
		return nil, userErr(409, "SLUG_TAKEN", "A business with this short name already exists.")
	}
	paidUntil := Today(s.Now()).AddDate(0, 0, 14)
	if in.PaidUntil != "" {
		p, err := time.Parse("2006-01-02", in.PaidUntil)
		if err != nil {
			return nil, userErr(400, "INVALID_INPUT", "Paid until must be a date (YYYY-MM-DD).")
		}
		paidUntil = p
	}

	// 1. Database, roles, keys, containers, route, migrations.
	if out, err := s.runScript(ctx, 10*time.Minute, "scripts/new-business.sh", in.Slug, in.Name); err != nil {
		return nil, fmt.Errorf("new-business.sh failed: %v\n%s", err, tail(out, 1500))
	}
	env, err := readEnvFile(filepath.Join(s.KitDir, "businesses", in.Slug, "env"))
	if err != nil {
		return nil, err
	}
	serviceKey, jwtSecret := env["SERVICE_KEY"], env["JWT_SECRET"]
	var authPort int
	_, _ = fmt.Sscan(env["AUTH_PORT"], &authPort)

	// 2. The business row and the owner inside the business database.
	tenant, err := s.Store.Tenant(ctx, in.Slug)
	if err != nil {
		return nil, err
	}
	defer tenant.Close(ctx)
	var tenantBusinessID string
	if err := tenant.QueryRow(ctx, `insert into public.businesses (name) values ($1) returning id`, in.Name).Scan(&tenantBusinessID); err != nil {
		return nil, fmt.Errorf("business row: %w", err)
	}
	ownerPassword, _ := RandomPassword()
	ownerName := strings.TrimSpace(in.OwnerName)
	if ownerName == "" {
		ownerName = strings.TrimSpace(in.ContactName)
	}
	var ownerID string
	err = pgx.BeginFunc(ctx, tenant, func(tx pgx.Tx) (err error) {
		ownerID, err = authn.CreateUser(ctx, tx, in.OwnerEmail, ownerPassword, map[string]any{
			"name": ownerName, "business_id": tenantBusinessID, "role": "OWNER", "must_change_password": true,
		}, s.Now())
		return err
	})
	if err != nil {
		return nil, fmt.Errorf("owner login: %w", err)
	}
	if _, err := tenant.Exec(ctx, `insert into public.users (id, business_id, role, name, email) values ($1, $2, 'OWNER', $3, $4)`,
		ownerID, tenantBusinessID, ownerName, in.OwnerEmail); err != nil {
		return nil, fmt.Errorf("owner row: %w", err)
	}

	// 3. control_db: business, subscription, reference key, first activation code.
	sealedKey, err := s.Sealer.Seal(serviceKey)
	if err != nil {
		return nil, err
	}
	sealedSecret, err := s.Sealer.Seal(jwtSecret)
	if err != nil {
		return nil, err
	}
	refKey, _ := NewReferenceKey(in.Slug)
	code, _ := NewActivationCode()
	out := &CreatedBusiness{Slug: in.Slug, BaseURL: env["BASE_URL"], ReferenceKey: refKey, ActivationCode: code,
		OwnerEmail: in.OwnerEmail, OwnerPassword: ownerPassword, PaidUntil: paidUntil.Format("2006-01-02")}
	err = pgx.BeginFunc(ctx, s.Store.DB, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `insert into businesses (slug, name, contact_name, phone, email, base_url, anon_key,
			service_key_sealed, jwt_secret_sealed, auth_port, tenant_business_id)
			values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) returning id`,
			in.Slug, in.Name, nullable(in.ContactName), nullable(in.Phone), nullable(in.Email), env["BASE_URL"], env["ANON_KEY"],
			sealedKey, sealedSecret, authPort, tenantBusinessID).Scan(&out.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `insert into subscriptions (business_id, plan_code, paid_until) values ($1,$2,$3)`,
			out.ID, in.PlanCode, paidUntil); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `insert into reference_keys (key, business_id) values ($1,$2)`, refKey, out.ID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `insert into activation_codes (code_hash, business_id, expires_at, created_by) values ($1,$2,$3,$4)`,
			HashCode(code), out.ID, s.Now().Add(48*time.Hour), nullable(adminID))
		return err
	})
	if err != nil {
		return nil, fmt.Errorf("control records: %w", err)
	}
	if err := s.SyncStatus(ctx, out.ID); err != nil {
		return nil, fmt.Errorf("subscription status: %w", err)
	}
	s.Store.Audit(ctx, nullable(adminID), &out.ID, "business.create", map[string]any{"slug": in.Slug, "plan": in.PlanCode})
	return out, nil
}

// ---------------------------------------------------------------- subscription

// SyncStatus writes the business's status, dates, plan and owner message into
// its database (service_status), where the apps and the data API read them.
func (s *Service) SyncStatus(ctx context.Context, businessID string) error {
	var slug, status, planName string
	var paidUntil time.Time
	var grace, remind, maxCompanies int
	var price float64
	err := s.Store.DB.QueryRow(ctx, `select b.slug, b.status, s.paid_until, s.grace_days, s.remind_days,
			p.name, p.max_companies, p.price_month::float8
		from businesses b join subscriptions s on s.business_id = b.id join plans p on p.code = s.plan_code
		where b.id = $1`, businessID).Scan(&slug, &status, &paidUntil, &grace, &remind, &planName, &maxCompanies, &price)
	if err != nil {
		return err
	}
	graceUntil, remindFrom := StatusDates(paidUntil, grace, remind)
	msg := RenewMessage(s.Store.Setting(ctx, "renew_message"), planName, price)
	tenant, err := s.Store.Tenant(ctx, slug)
	if err != nil {
		return err
	}
	defer tenant.Close(ctx)
	_, err = tenant.Exec(ctx, `insert into public.service_status
			(id, status, paid_until, grace_until, remind_from, plan_name, max_companies, message, contact, updated_at)
		values (true, $1, $2, $3, $4, $5, $6, $7, $8, now())
		on conflict (id) do update set status = excluded.status, paid_until = excluded.paid_until,
			grace_until = excluded.grace_until, remind_from = excluded.remind_from, plan_name = excluded.plan_name,
			max_companies = excluded.max_companies, message = excluded.message, contact = excluded.contact, updated_at = now()`,
		status, paidUntil, graceUntil, remindFrom, planName, maxCompanies, msg, s.Store.Setting(ctx, "contact"))
	return err
}

type Payment struct {
	Amount    float64 `json:"amount"`
	PaidOn    string  `json:"paid_on"` // YYYY-MM-DD, default today
	Mode      string  `json:"mode"`    // cash | upi | bank | other
	Reference string  `json:"reference"`
	Months    int     `json:"months"`
	Note      string  `json:"note"`
}

// RecordPayment extends paid_until by the months paid and unblocks the apps.
func (s *Service) RecordPayment(ctx context.Context, businessID string, p Payment, adminID string) (Period, error) {
	if p.Amount <= 0 || p.Months < 1 || p.Months > 36 {
		return Period{}, userErr(400, "INVALID_INPUT", "Enter the amount and 1–36 months.")
	}
	switch p.Mode {
	case "cash", "upi", "bank", "other":
	default:
		return Period{}, userErr(400, "INVALID_INPUT", "Mode must be cash, upi, bank or other.")
	}
	paidOn := Today(s.Now())
	if p.PaidOn != "" {
		t, err := time.Parse("2006-01-02", p.PaidOn)
		if err != nil {
			return Period{}, userErr(400, "INVALID_INPUT", "Paid on must be a date (YYYY-MM-DD).")
		}
		paidOn = t
	}
	var period Period
	err := pgx.BeginFunc(ctx, s.Store.DB, func(tx pgx.Tx) error {
		var paidUntil time.Time
		if err := tx.QueryRow(ctx, `select paid_until from subscriptions where business_id = $1 for update`, businessID).Scan(&paidUntil); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return userErr(404, "NOT_FOUND", "No such business.")
			}
			return err
		}
		period = PaymentPeriod(paidUntil, paidOn, p.Months)
		if _, err := tx.Exec(ctx, `insert into payments (business_id, amount, paid_on, mode, reference, months, period_from, period_to, note, recorded_by)
			values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, businessID, p.Amount, paidOn, p.Mode, nullable(p.Reference), p.Months,
			period.From, period.To, nullable(p.Note), nullable(adminID)); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `update subscriptions set paid_until = $2, updated_at = now() where business_id = $1`, businessID, period.To)
		return err
	})
	if err != nil {
		return Period{}, err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "payment.record",
		map[string]any{"amount": p.Amount, "months": p.Months, "mode": p.Mode, "paid_until": period.To.Format("2006-01-02")})
	return period, s.SyncStatus(ctx, businessID)
}

// SetStatus: active (resume), suspended, or closed. Suspending or closing
// blocks the apps and the PCs at once (via service_status).
func (s *Service) SetStatus(ctx context.Context, businessID, status, adminID string) error {
	switch status {
	case "active", "suspended", "closed":
	default:
		return userErr(400, "INVALID_INPUT", "Unknown status.")
	}
	tag, err := s.Store.DB.Exec(ctx, `update businesses set status = $2, updated_at = now(),
		closed_at = case when $2 = 'closed' then now() else null end where id = $1`, businessID, status)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return userErr(404, "NOT_FOUND", "No such business.")
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "business.status", map[string]any{"status": status})
	return s.SyncStatus(ctx, businessID)
}

// UpdateSubscription changes the plan and the grace / reminder days.
func (s *Service) UpdateSubscription(ctx context.Context, businessID, planCode string, graceDays, remindDays int, adminID string) error {
	tag, err := s.Store.DB.Exec(ctx, `update subscriptions set plan_code = coalesce(nullif($2, ''), plan_code),
		grace_days = $3, remind_days = $4, updated_at = now() where business_id = $1`, businessID, planCode, graceDays, remindDays)
	if err != nil {
		var pg interface{ SQLState() string }
		if errors.As(err, &pg) && (pg.SQLState() == "23503" || pg.SQLState() == "23514") {
			return userErr(400, "INVALID_INPUT", "Unknown plan, or grace / reminder days outside 0–60.")
		}
		return err
	}
	if tag.RowsAffected() == 0 {
		return userErr(404, "NOT_FOUND", "No such business.")
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "subscription.update",
		map[string]any{"plan": planCode, "grace_days": graceDays, "remind_days": remindDays})
	return s.SyncStatus(ctx, businessID)
}

// ---------------------------------------------------------------- keys, codes, PCs

func (s *Service) NewActivationCode(ctx context.Context, businessID, adminID string) (string, error) {
	code, err := NewActivationCode()
	if err != nil {
		return "", err
	}
	if _, err := s.Store.DB.Exec(ctx, `insert into activation_codes (code_hash, business_id, expires_at, created_by) values ($1,$2,$3,$4)`,
		HashCode(code), businessID, s.Now().Add(48*time.Hour), nullable(adminID)); err != nil {
		var pg interface{ SQLState() string }
		if errors.As(err, &pg) && pg.SQLState() == "23503" {
			return "", userErr(404, "NOT_FOUND", "No such business.")
		}
		return "", err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "activation_code.create", nil)
	return code, nil
}

// RotateReferenceKey revokes the current key and issues a new one. Phones
// already connected keep working; new phones need the new key.
func (s *Service) RotateReferenceKey(ctx context.Context, businessID, adminID string) (string, error) {
	var slug string
	if err := s.Store.DB.QueryRow(ctx, `select slug from businesses where id = $1`, businessID).Scan(&slug); err != nil {
		return "", userErr(404, "NOT_FOUND", "No such business.")
	}
	key, _ := NewReferenceKey(slug)
	err := pgx.BeginFunc(ctx, s.Store.DB, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `update reference_keys set revoked_at = now() where business_id = $1 and revoked_at is null`, businessID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `insert into reference_keys (key, business_id) values ($1, $2)`, key, businessID)
		return err
	})
	if err != nil {
		return "", err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "reference_key.rotate", nil)
	return key, nil
}

// RevokeDevice cuts one Tally PC off; the business's other PCs keep working.
func (s *Service) RevokeDevice(ctx context.Context, deviceID, adminID string) error {
	var businessID, slug string
	err := s.Store.DB.QueryRow(ctx, `update devices d set revoked_at = coalesce(d.revoked_at, now()) from businesses b
		where d.id = $1 and b.id = d.business_id returning d.business_id, b.slug`, deviceID).Scan(&businessID, &slug)
	if err != nil {
		return userErr(404, "NOT_FOUND", "No such PC.")
	}
	tenant, err := s.Store.Tenant(ctx, slug)
	if err != nil {
		return err
	}
	defer tenant.Close(ctx)
	if _, err := tenant.Exec(ctx, `insert into public.revoked_devices (device_id) values ($1) on conflict do nothing`, deviceID); err != nil {
		return err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "device.revoke", map[string]any{"device_id": deviceID})
	return nil
}

// ---------------------------------------------------------------- public: phones and PCs

type Connection struct {
	BusinessName string `json:"business_name"`
	BaseURL      string `json:"base_url"`
	AnonKey      string `json:"anon_key"`
	State        string `json:"state"`
}

// Connect resolves a reference key for the phone apps.
func (s *Service) Connect(ctx context.Context, key, ip string) (*Connection, error) {
	var c Connection
	var status string
	var paidUntil time.Time
	var grace, remind int
	err := s.Store.DB.QueryRow(ctx, `select b.name, b.base_url, b.anon_key, b.status, s.paid_until, s.grace_days, s.remind_days
		from reference_keys k join businesses b on b.id = k.business_id join subscriptions s on s.business_id = b.id
		where k.key = $1 and k.revoked_at is null and b.status <> 'closed'`, NormalizeKey(key)).
		Scan(&c.BusinessName, &c.BaseURL, &c.AnonKey, &status, &paidUntil, &grace, &remind)
	_, _ = s.Store.DB.Exec(ctx, `insert into key_lookups (ip, ok) values ($1, $2)`, ip, err == nil)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, userErr(404, "UNKNOWN_KEY", "No business has this reference key. Check it and try again.")
		}
		return nil, err
	}
	c.State = AccessState(status, paidUntil, grace, remind, Today(s.Now()))
	return &c, nil
}

// RecentFailedLookups counts an IP's failed key lookups in the last hour.
func (s *Service) RecentFailedLookups(ctx context.Context, ip string) int {
	var n int
	_ = s.Store.DB.QueryRow(ctx, `select count(*) from key_lookups where ip = $1 and not ok and at > now() - interval '1 hour'`, ip).Scan(&n)
	return n
}

type Activation struct {
	ReferenceKey string `json:"reference_key"`
	Code         string `json:"activation_code"`
	Machine      string `json:"machine"`
	WindowsUser  string `json:"windows_user"`
	AppVersion   string `json:"app_version"`
}

type Activated struct {
	DeviceID          string `json:"device_id"`
	BusinessID        string `json:"business_id"` // businesses.id inside the business database
	BusinessName      string `json:"business_name"`
	BaseURL           string `json:"base_url"`
	DeviceKey         string `json:"device_key"`
	MaxCompanies      int    `json:"max_companies"`
	SubscriptionState string `json:"subscription_state"`
}

// Activate exchanges a reference key + single-use code for this PC's own key.
func (s *Service) Activate(ctx context.Context, a Activation) (*Activated, error) {
	var out Activated
	var businessID, slug, sealedSecret, status string
	var paidUntil time.Time
	var grace, remind int
	err := pgx.BeginFunc(ctx, s.Store.DB, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `select b.id, b.slug, b.name, b.base_url, b.jwt_secret_sealed, b.status, coalesce(b.tenant_business_id::text, ''),
				s.paid_until, s.grace_days, s.remind_days, p.max_companies
			from reference_keys k join businesses b on b.id = k.business_id
			join subscriptions s on s.business_id = b.id join plans p on p.code = s.plan_code
			where k.key = $1 and k.revoked_at is null`, NormalizeKey(a.ReferenceKey)).
			Scan(&businessID, &slug, &out.BusinessName, &out.BaseURL, &sealedSecret, &status, &out.BusinessID,
				&paidUntil, &grace, &remind, &out.MaxCompanies)
		if errors.Is(err, pgx.ErrNoRows) {
			return userErr(404, "UNKNOWN_KEY", "No business has this reference key.")
		} else if err != nil {
			return err
		}
		if status == "closed" {
			return userErr(403, "CLOSED", "This business has been closed.")
		}
		tag, err := tx.Exec(ctx, `update activation_codes set used_at = now()
			where code_hash = $1 and business_id = $2 and used_at is null and expires_at > now()`, HashCode(a.Code), businessID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return userErr(403, "BAD_CODE", "This activation code is wrong, already used or expired. Ask for a new one.")
		}
		if err := tx.QueryRow(ctx, `insert into devices (business_id, machine, windows_user, app_version, last_seen_at)
			values ($1, $2, $3, $4, now()) returning id`, businessID, clip(a.Machine, 100), clip(a.WindowsUser, 100), clip(a.AppVersion, 40)).
			Scan(&out.DeviceID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `update activation_codes set used_by = $2 where code_hash = $1`, HashCode(a.Code), out.DeviceID)
		return err
	})
	if err != nil {
		return nil, err
	}
	secret, err := s.Sealer.Open(sealedSecret)
	if err != nil {
		return nil, err
	}
	if out.DeviceKey, err = DeviceKey(secret, slug, out.DeviceID, s.Now()); err != nil {
		return nil, err
	}
	out.SubscriptionState = AccessState(status, paidUntil, grace, remind, Today(s.Now()))
	s.Store.Audit(ctx, nil, &businessID, "device.activate", map[string]any{"device_id": out.DeviceID, "machine": a.Machine})
	return &out, nil
}

type DeviceStatus struct {
	SubscriptionState string `json:"subscription_state"`
	MaxCompanies      int    `json:"max_companies"`
	Revoked           bool   `json:"revoked"`
	// LatestPCVersion is the newest Tally PC release (setting latest_pc_version;
	// omitted when not set). PCs 0.6.0 and older ignore it.
	LatestPCVersion string `json:"latest_pc_version,omitempty"`
}

// Heartbeat: a PC reports its version and learns its subscription state and
// company limit. Authenticated by the PC's own key.
func (s *Service) Heartbeat(ctx context.Context, deviceKey, appVersion string) (*DeviceStatus, error) {
	claims, err := ParseJWTUnverified(deviceKey)
	if err != nil {
		return nil, userErr(401, "BAD_KEY", "Invalid PC key.")
	}
	slug, _ := claims["ref"].(string)
	deviceID, _ := claims["device_id"].(string)
	var sealedSecret, status string
	var revokedAt *time.Time
	var paidUntil time.Time
	var grace, remind, maxCompanies int
	err = s.Store.DB.QueryRow(ctx, `select b.jwt_secret_sealed, b.status, d.revoked_at, s.paid_until, s.grace_days, s.remind_days, p.max_companies
		from devices d join businesses b on b.id = d.business_id join subscriptions s on s.business_id = b.id
		join plans p on p.code = s.plan_code where d.id::text = $1 and b.slug = $2`, deviceID, slug).
		Scan(&sealedSecret, &status, &revokedAt, &paidUntil, &grace, &remind, &maxCompanies)
	if err != nil {
		return nil, userErr(401, "BAD_KEY", "Invalid PC key.")
	}
	secret, err := s.Sealer.Open(sealedSecret)
	if err != nil {
		return nil, err
	}
	if _, err := VerifyJWT(secret, deviceKey, s.Now()); err != nil {
		return nil, userErr(401, "BAD_KEY", "Invalid PC key.")
	}
	if revokedAt == nil {
		_, _ = s.Store.DB.Exec(ctx, `update devices set last_seen_at = now(), app_version = $2 where id::text = $1`, deviceID, clip(appVersion, 40))
	}
	return &DeviceStatus{SubscriptionState: AccessState(status, paidUntil, grace, remind, Today(s.Now())),
		MaxCompanies: maxCompanies, Revoked: revokedAt != nil, LatestPCVersion: s.Store.Setting(ctx, "latest_pc_version")}, nil
}

// TenantForStaff gives the staff service a business's address and service key.
func (s *Service) TenantForStaff(ctx context.Context, slug string) (baseURL, serviceKey string, err error) {
	var sealed string
	if err := s.Store.DB.QueryRow(ctx, `select base_url, service_key_sealed from businesses where slug = $1 and status <> 'closed'`, slug).
		Scan(&baseURL, &sealed); err != nil {
		return "", "", userErr(404, "NOT_FOUND", "No such business.")
	}
	serviceKey, err = s.Sealer.Open(sealed)
	return baseURL, serviceKey, err
}

// MigrateAll applies new migrations to every business database.
func (s *Service) MigrateAll(ctx context.Context, adminID string) (string, error) {
	out, err := s.runScript(ctx, 30*time.Minute, "scripts/migrate.sh", "--all")
	s.Store.Audit(ctx, nullable(adminID), nil, "migrate.all", map[string]any{"ok": err == nil})
	return out, err
}

// ---------------------------------------------------------------- helpers

func (s *Service) runScript(ctx context.Context, timeout time.Duration, script string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, filepath.Join(s.KitDir, script), args...)
	cmd.Dir = s.KitDir
	cmd.Stdin = nil
	var buf bytes.Buffer
	cmd.Stdout, cmd.Stderr = &buf, &buf
	err := cmd.Run()
	return buf.String(), err
}

// ReadEnvFile reads a KEY=VALUE file such as businesses/<slug>/env.
func ReadEnvFile(path string) (map[string]string, error) { return readEnvFile(path) }

func readEnvFile(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	out := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if k, v, ok := strings.Cut(sc.Text(), "="); ok {
			out[k] = v
		}
	}
	return out, sc.Err()
}

func nullable(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	t := strings.TrimSpace(s)
	return &t
}

func clip(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		return s[:n]
	}
	return s
}

func tail(s string, n int) string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}
