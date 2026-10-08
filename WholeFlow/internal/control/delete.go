package control

import (
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Deleting data: one Tally company of a business, or a whole business.
// Both are permanent, so the admin must type the exact name and their own
// password; the server checks both.

// BackupDir is where scripts/backup.sh keeps the nightly dumps.
const BackupDir = "/opt/wholeflow/backup"

// CompanyInfo is one Tally company in a business database.
type CompanyInfo struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	SyncStatus   string     `json:"sync_status"`
	LastSyncAt   *time.Time `json:"last_sync_at"`
	Shops        int        `json:"shops"`
	Transactions int64      `json:"transactions"`
}

func (s *Service) slugOf(ctx context.Context, businessID string) (slug, name string, err error) {
	err = s.Store.DB.QueryRow(ctx, `select slug, name from businesses where id::text = $1`, businessID).Scan(&slug, &name)
	if err != nil {
		return "", "", userErr(http.StatusNotFound, "NOT_FOUND", "No such business.")
	}
	return slug, name, nil
}

// Companies lists the Tally companies stored in a business database.
func (s *Service) Companies(ctx context.Context, businessID string) ([]CompanyInfo, error) {
	slug, _, err := s.slugOf(ctx, businessID)
	if err != nil {
		return nil, err
	}
	tenant, err := s.Store.Tenant(ctx, slug)
	if err != nil {
		return nil, err
	}
	defer tenant.Close(ctx)
	rows, err := tenant.Query(ctx, `select c.id::text, c.company_name, c.sync_status, c.last_sync_at,
			(select count(*) from public.shops s where s.company_id = c.id and s.deleted_at is null),
			(select count(*) from public.transactions t where t.company_id = c.id and t.deleted_at is null)
		from public.tally_companies c order by c.last_sync_at desc nulls last, c.company_name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []CompanyInfo{}
	for rows.Next() {
		var c CompanyInfo
		if err := rows.Scan(&c.ID, &c.Name, &c.SyncStatus, &c.LastSyncAt, &c.Shops, &c.Transactions); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// DeleteCompany removes one Tally company and everything stored for it
// (shops, transactions, suppliers, purchases, stock, sites, visits, staff
// access: all cascade from tally_companies). confirm must be its name.
func (s *Service) DeleteCompany(ctx context.Context, businessID, companyID, confirm, adminID string) (string, error) {
	slug, bizName, err := s.slugOf(ctx, businessID)
	if err != nil {
		return "", err
	}
	tenant, err := s.Store.Tenant(ctx, slug)
	if err != nil {
		return "", err
	}
	defer tenant.Close(ctx)
	var name string
	var shops int
	var txns int64
	err = tenant.QueryRow(ctx, `select c.company_name,
			(select count(*) from public.shops s where s.company_id = c.id),
			(select count(*) from public.transactions t where t.company_id = c.id)
		from public.tally_companies c where c.id::text = $1`, companyID).Scan(&name, &shops, &txns)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", userErr(http.StatusNotFound, "NOT_FOUND", "No such company in this business.")
	} else if err != nil {
		return "", err
	}
	if !sameName(confirm, name) {
		return "", userErr(http.StatusBadRequest, "CONFIRM_MISMATCH", "Type the company name exactly to confirm.")
	}
	if _, err := tenant.Exec(ctx, `delete from public.tally_companies where id::text = $1`, companyID); err != nil {
		return "", err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "company.delete",
		map[string]any{"company": name, "shops": shops, "transactions": txns, "business": bizName})
	return name, nil
}

// DeleteBusiness removes a business completely: containers, route, database,
// login roles, files and its control_db records (scripts/delete-business.sh),
// and with deleteBackups its nightly dumps on this server too (the off-site
// copies are kept by the bucket's retention rules, and the script's final
// backup is kept on purpose). confirm must be its short name.
func (s *Service) DeleteBusiness(ctx context.Context, businessID, confirm string, deleteBackups bool, adminID string) (string, error) {
	slug, name, err := s.slugOf(ctx, businessID)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(strings.ToLower(confirm)) != slug {
		return "", userErr(http.StatusBadRequest, "CONFIRM_MISMATCH", "Type the business's short name exactly to confirm.")
	}
	if out, err := s.runScript(ctx, 14*time.Minute, "scripts/delete-business.sh", slug, "--yes"); err != nil {
		return "", errors.New("delete-business.sh: " + err.Error() + ": " + tail(out, 300))
	}
	removed := 0
	if deleteBackups {
		// Encrypted nightly dumps (backup.sh), and plain ones from before encryption.
		var files []string
		for _, pat := range []string{"biz_" + slug + ".dump.age", "biz_" + slug + ".dump"} {
			m, _ := filepath.Glob(filepath.Join(BackupDir, "*", pat))
			files = append(files, m...)
		}
		for _, f := range files {
			if os.Remove(f) == nil {
				removed++
			}
		}
	}
	// The business row is gone (its history keeps business_id = null), so the
	// deletion is recorded with the name and short name.
	s.Store.Audit(ctx, nullable(adminID), nil, "business.delete",
		map[string]any{"slug": slug, "name": name, "backups_deleted": removed})
	return name, nil
}

func sameName(typed, name string) bool {
	return strings.EqualFold(strings.Join(strings.Fields(typed), " "), strings.Join(strings.Fields(name), " "))
}

// ---------------------------------------------------------------- HTTP

func (s *Server) deleteRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /control/admin/businesses/{id}/companies", s.admin(s.listCompanies))
	mux.HandleFunc("POST /control/admin/businesses/{id}/companies/{cid}/delete", s.admin(s.deleteCompany))
	mux.HandleFunc("POST /control/admin/businesses/{id}/delete", s.admin(s.deleteBusiness))
}

func (s *Server) listCompanies(w http.ResponseWriter, r *http.Request) {
	out, err := s.Svc.Companies(r.Context(), r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) deleteCompany(w http.ResponseWriter, r *http.Request) {
	longRequest(w, 15*time.Minute) // a big company's rows take a while to delete
	var in struct {
		Password string `json:"password"`
		Confirm  string `json:"confirm"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	// Wrong name first: it costs no password attempt.
	if strings.TrimSpace(in.Confirm) == "" {
		writeErr(w, userErr(http.StatusBadRequest, "CONFIRM_MISMATCH", "Type the company name exactly to confirm."))
		return
	}
	if err := s.checkOwnPassword(r, in.Password); err != nil {
		writeErr(w, err)
		return
	}
	name, err := s.Svc.DeleteCompany(r.Context(), r.PathValue("id"), r.PathValue("cid"), in.Confirm, adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.Log.Warn("company deleted", "business", r.PathValue("id"), "company", name, "admin", adminOf(r).Email)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": name})
}

func (s *Server) deleteBusiness(w http.ResponseWriter, r *http.Request) {
	longRequest(w, 15*time.Minute) // runs the delete script
	var in struct {
		Password      string `json:"password"`
		Confirm       string `json:"confirm"`
		DeleteBackups bool   `json:"delete_backups"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if strings.TrimSpace(in.Confirm) == "" {
		writeErr(w, userErr(http.StatusBadRequest, "CONFIRM_MISMATCH", "Type the business's short name exactly to confirm."))
		return
	}
	if err := s.checkOwnPassword(r, in.Password); err != nil {
		writeErr(w, err)
		return
	}
	name, err := s.Svc.DeleteBusiness(r.Context(), r.PathValue("id"), in.Confirm, in.DeleteBackups, adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.Log.Warn("business deleted", "business", name, "admin", adminOf(r).Email, "backups_deleted", in.DeleteBackups)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "deleted": name})
}
