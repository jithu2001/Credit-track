package appapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/authn"
)

// Staff management (owner only; replaces the Deno manage-staff service):
//
//	GET  /b/{slug}/api/v1/staff                         everyone: owners first, then active staff, then disabled
//	POST /b/{slug}/api/v1/staff                         {"name", "email", "password", "companies": [...], "requires_check_in"}
//	PATCH /b/{slug}/api/v1/staff/{id}                   {"name"}
//	PUT  /b/{slug}/api/v1/staff/{id}/companies          {"companies": [...]}
//	PUT  /b/{slug}/api/v1/staff/{id}/check-in           {"required"}
//	PUT  /b/{slug}/api/v1/staff/{id}/active             {"active"}   (also blocks or unblocks their login)
//	POST /b/{slug}/api/v1/staff/{id}/password           {"password"} (temporary; they change it at sign-in)
//
// A company entry is {"company_id", "full_company", "site_ids", "can_view_transactions"}.
// After the owner check, changes run as the business's service role (as the
// Deno service did with its service key); logins change in the login tables
// (internal/authn).

// banForever blocks a disabled staff member's login (~100 years, as before).
const banForever = 876000 * time.Hour

var (
	uuidRE  = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
	emailRE = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)
)

const minPassword = 8

type companyGrant struct {
	CompanyID           string   `json:"company_id"`
	FullCompany         *bool    `json:"full_company"`
	SiteIDs             []string `json:"site_ids"`
	CanViewTransactions *bool    `json:"can_view_transactions"`
}

type grantOut struct {
	CompanyID           string   `json:"company_id"`
	FullCompany         bool     `json:"full_company"`
	SiteIDs             []string `json:"site_ids"`
	CanViewTransactions bool     `json:"can_view_transactions"`
}

// requireStaffOwner: the caller must be an active owner.
func requireStaffOwner(r *request) (callerID, businessID string, err error) {
	var role string
	var active bool
	err = r.tx.QueryRow(r.Context(), `select id::text, business_id::text, role, is_active from public.users where id = auth.uid()`).
		Scan(&callerID, &businessID, &role, &active)
	if err != nil || role != "OWNER" || !active {
		return "", "", fail(http.StatusForbidden, "NOT_OWNER", "Only the business owner can manage staff.")
	}
	return callerID, businessID, nil
}

// asService switches the rest of the transaction to the service role (no RLS).
func asService(r *request) error {
	_, err := r.tx.Exec(r.Context(), `set local role service_role`)
	return err
}

func requireName(v string) (string, error) {
	n := strings.TrimSpace(v)
	if n == "" || len([]rune(n)) > 100 {
		return "", fail(http.StatusBadRequest, "INVALID_INPUT", "Enter a name (up to 100 characters).")
	}
	return n, nil
}

func requirePassword(v string) error {
	if len(v) < minPassword || len(v) > 72 {
		return fail(http.StatusBadRequest, "INVALID_INPUT", fmt.Sprintf("Password must be %d to 72 characters.", minPassword))
	}
	return nil
}

// requireStaffMember: id is a staff member of the caller's business (service role).
func requireStaffMember(r *request, id, businessID string) error {
	if !uuidRE.MatchString(id) {
		return fail(http.StatusBadRequest, "INVALID_INPUT", "user_id is missing.")
	}
	var role, biz string
	err := r.tx.QueryRow(r.Context(), `select role, business_id::text from public.users where id = $1::uuid`, id).Scan(&role, &biz)
	if err != nil || biz != businessID {
		return fail(http.StatusNotFound, "NOT_FOUND", "No such staff member.")
	}
	if role != "STAFF" {
		return fail(http.StatusForbidden, "NOT_OWNER", "Owner accounts cannot be changed here.")
	}
	return nil
}

// parseGrants checks companies and sites belong to the business (service role).
func parseGrants(r *request, in []companyGrant, businessID string, requireOne bool) ([]grantOut, error) {
	if in == nil {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "companies must be a list.")
	}
	if requireOne && len(in) == 0 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Assign at least one company.")
	}
	companies := map[string]bool{}
	siteCompany := map[string]string{}
	rows, err := r.tx.Query(r.Context(), `select 'c', id::text, '' from public.tally_companies where business_id = $1::uuid
		union all select 's', id::text, company_id::text from public.sites where business_id = $1::uuid`, businessID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var kind, id, company string
		if err := rows.Scan(&kind, &id, &company); err != nil {
			rows.Close()
			return nil, err
		}
		if kind == "c" {
			companies[id] = true
		} else {
			siteCompany[id] = company
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	out := []grantOut{}
	for _, c := range in {
		id := strings.ToLower(c.CompanyID)
		if !uuidRE.MatchString(id) || !companies[id] {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "A selected company does not belong to your business.")
		}
		if seen[id] {
			continue
		}
		seen[id] = true
		full := c.FullCompany == nil || *c.FullCompany
		sites := []string{}
		if !full {
			uniq := map[string]bool{}
			for _, s := range c.SiteIDs {
				s = strings.ToLower(s)
				if siteCompany[s] != id {
					return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "A selected site does not belong to that company.")
				}
				if !uniq[s] {
					uniq[s] = true
					sites = append(sites, s)
				}
			}
			sort.Strings(sites)
			if len(sites) == 0 {
				return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Choose at least one site, or give the full company.")
			}
		}
		cvt := c.CanViewTransactions == nil || *c.CanViewTransactions
		out = append(out, grantOut{CompanyID: id, FullCompany: full, SiteIDs: sites, CanViewTransactions: cvt})
	}
	return out, nil
}

// ---------------------------------------------------------------- logins

// createLogin makes the staff member's login; EMAIL_TAKEN when the address is in use.
func (s *Server) createLogin(r *request, email, password string, meta map[string]any) (string, error) {
	var id string
	err := inAuthTx(r.Context(), r.tenant, func(tx pgx.Tx) (err error) {
		id, err = authn.CreateUser(r.Context(), tx, email, password, meta, s.Now())
		return err
	})
	switch {
	case errors.Is(err, authn.ErrEmailExists):
		return "", fail(http.StatusConflict, "EMAIL_TAKEN", "An account with this email already exists.")
	case errors.Is(err, authn.ErrWeakPassword):
		return "", fail(http.StatusBadRequest, "INVALID_INPUT", "Choose a stronger password.")
	}
	return id, err
}

func (s *Server) changeLogin(r *request, id string, up authn.Update) error {
	err := inAuthTx(r.Context(), r.tenant, func(tx pgx.Tx) error { return authn.AdminUpdate(r.Context(), tx, id, up, s.Now()) })
	if err == nil && (up.Password != nil || up.Ban != nil) {
		r.tenant.forgetSessions() // their sessions may have just ended
	}
	return err
}

// ---------------------------------------------------------------- handlers

func (s *Server) staffList(r *request) (any, error) {
	if _, _, err := requireStaffOwner(r); err != nil {
		return nil, err
	}
	rows, err := jsonRows(r, `select u.id, u.role, u.name, u.email, u.is_active, u.requires_check_in, u.created_at,
			coalesce((select json_agg(json_build_object(
					'user_id', a.user_id, 'company_id', a.company_id, 'full_company', a.full_company,
					'can_view_transactions', a.can_view_transactions,
					'site_ids', coalesce((select json_agg(ss.site_id order by ss.site_id) from public.staff_site_access ss
						join public.sites si on si.id = ss.site_id where ss.user_id = u.id and si.company_id = a.company_id), '[]'::json))
					order by a.company_id)
				from public.staff_company_access a where a.user_id = u.id), '[]'::json) as companies
		from public.users u
		order by case when u.role = 'OWNER' then 0 when u.is_active then 1 else 2 end,
			lower(coalesce(nullif(btrim(u.name), ''), u.email, 'User')), u.id`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"staff": rows}, nil
}

func (s *Server) createStaff(r *request) (any, error) {
	caller, business, err := requireStaffOwner(r)
	if err != nil {
		return nil, err
	}
	var in struct {
		Name            string         `json:"name"`
		Email           string         `json:"email"`
		Password        string         `json:"password"`
		Companies       []companyGrant `json:"companies"`
		RequiresCheckIn bool           `json:"requires_check_in"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	name, err := requireName(in.Name)
	if err != nil {
		return nil, err
	}
	email := strings.ToLower(strings.TrimSpace(in.Email))
	if !emailRE.MatchString(email) || len(email) > 254 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Enter a valid email address.")
	}
	if err := requirePassword(in.Password); err != nil {
		return nil, err
	}
	if err := asService(r); err != nil {
		return nil, err
	}
	grants, err := parseGrants(r, in.Companies, business, true)
	if err != nil {
		return nil, err
	}
	id, err := s.createLogin(r, email, in.Password,
		map[string]any{"name": name, "business_id": business, "role": "STAFF", "must_change_password": true})
	if err != nil {
		return nil, err
	}
	grantsJSON, _ := json.Marshal(grants)
	_, err = r.tx.Exec(r.Context(), `select public.admin_insert_staff($1::uuid, $2::uuid, $3, $4, $5::uuid, $6::jsonb)`,
		id, business, name, email, caller, string(grantsJSON))
	if err == nil && in.RequiresCheckIn {
		_, err = r.tx.Exec(r.Context(), `update public.users set requires_check_in = true where id = $1::uuid`, id)
	}
	if err != nil {
		// Don't leave a login without a staff row.
		if derr := inAuthTx(context.WithoutCancel(r.Context()), r.tenant, func(tx pgx.Tx) error {
			return authn.DeleteUser(context.WithoutCancel(r.Context()), tx, id)
		}); derr != nil {
			s.Log.Error("staff login left behind", "user", id, "error", derr.Error())
		}
		return nil, err
	}
	return map[string]any{"id": id, "email": email, "name": name, "role": "STAFF", "is_active": true,
		"requires_check_in": in.RequiresCheckIn, "companies": grants}, nil
}

// staffChange runs fn for a staff member of the caller's business, as the service role.
func (s *Server) staffChange(r *request, fn func(id, business, caller string) (any, error)) (any, error) {
	caller, business, err := requireStaffOwner(r)
	if err != nil {
		return nil, err
	}
	if err := asService(r); err != nil {
		return nil, err
	}
	id := r.PathValue("id")
	if err := requireStaffMember(r, id, business); err != nil {
		return nil, err
	}
	return fn(id, business, caller)
}

func (s *Server) renameStaff(r *request) (any, error) {
	var in struct {
		Name string `json:"name"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	return s.staffChange(r, func(id, business, _ string) (any, error) {
		name, err := requireName(in.Name)
		if err != nil {
			return nil, err
		}
		_, err = r.tx.Exec(r.Context(), `update public.users set name = $2 where id = $1::uuid and role = 'STAFF'`, id, name)
		return map[string]any{"id": id}, err
	})
}

func (s *Server) setStaffCompanies(r *request) (any, error) {
	var in struct {
		Companies []companyGrant `json:"companies"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	return s.staffChange(r, func(id, business, caller string) (any, error) {
		grants, err := parseGrants(r, in.Companies, business, false)
		if err != nil {
			return nil, err
		}
		raw, _ := json.Marshal(grants)
		_, err = r.tx.Exec(r.Context(), `select public.admin_set_staff_companies($1::uuid, $2::uuid, $3::uuid, $4::jsonb)`,
			id, business, caller, string(raw))
		return map[string]any{"id": id, "companies": grants}, err
	})
}

func (s *Server) setStaffCheckIn(r *request) (any, error) {
	var in struct {
		Required *bool `json:"required"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	return s.staffChange(r, func(id, _, _ string) (any, error) {
		if in.Required == nil {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "required must be true or false.")
		}
		_, err := r.tx.Exec(r.Context(), `update public.users set requires_check_in = $2 where id = $1::uuid and role = 'STAFF'`, id, *in.Required)
		return map[string]any{"id": id, "requires_check_in": *in.Required}, err
	})
}

func (s *Server) setStaffActive(r *request) (any, error) {
	var in struct {
		Active *bool `json:"active"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	return s.staffChange(r, func(id, _, _ string) (any, error) {
		if in.Active == nil {
			return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "active must be true or false.")
		}
		var was bool
		if err := r.tx.QueryRow(r.Context(), `update public.users u set is_active = $2 from public.users old
				where u.id = $1::uuid and u.role = 'STAFF' and old.id = u.id returning old.is_active`, id, *in.Active).Scan(&was); err != nil {
			return nil, err
		}
		// The login is blocked (or unblocked) in the login tables, which commit
		// first; if this request's data change then fails, that is undone.
		ban, undo := banForever, time.Duration(0)
		if *in.Active {
			ban, undo = 0, banForever
		}
		if err := s.changeLogin(r, id, authn.Update{Ban: &ban}); err != nil {
			return nil, err
		}
		if was != *in.Active {
			r.onRollback(func(ctx context.Context) error {
				return inAuthTx(ctx, r.tenant, func(tx pgx.Tx) error { return authn.AdminUpdate(ctx, tx, id, authn.Update{Ban: &undo}, s.Now()) })
			})
		}
		return map[string]any{"id": id, "is_active": *in.Active}, nil
	})
}

func (s *Server) resetStaffPassword(r *request) (any, error) {
	var in struct {
		Password string `json:"password"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	return s.staffChange(r, func(id, _, _ string) (any, error) {
		if err := requirePassword(in.Password); err != nil {
			return nil, err
		}
		// A new password also signs them out on every phone (authn.AdminUpdate).
		if err := s.changeLogin(r, id, authn.Update{Password: &in.Password,
			Metadata: map[string]any{"must_change_password": true}}); err != nil {
			return nil, err
		}
		return map[string]any{"id": id}, nil
	})
}
