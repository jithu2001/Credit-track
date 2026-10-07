package control

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"wholeflow/internal/auth"
)

// The admin app (admin.jitsuji.xyz): static files served by the control
// service; nginx forwards the whole admin host here.
//
//go:embed web
var webFiles embed.FS

func (s *Server) webRoutes(mux *http.ServeMux) {
	sub, _ := fs.Sub(webFiles, "web")
	files := http.FileServer(http.FS(sub))
	page := func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Cache-Control", "no-cache")
		files.ServeHTTP(w, r)
	}
	mux.HandleFunc("GET /{$}", page)
	mux.HandleFunc("GET /assets/", page)

	mux.HandleFunc("GET /control/admin/businesses/{id}/backup", s.admin(s.backup))
	mux.HandleFunc("POST /control/admin/admins/{id}/disabled", s.admin(s.setAdminDisabled))
	mux.HandleFunc("POST /control/admin/password", s.admin(s.changePassword))
}

// backup dumps one business database (pg_dump custom format) for download.
// The dump is written to a temporary file first so a failed dump is an error,
// not a truncated download.
func (s *Server) backup(w http.ResponseWriter, r *http.Request) {
	ctx, id, a := r.Context(), r.PathValue("id"), adminOf(r)
	var slug string
	if err := s.Svc.Store.DB.QueryRow(ctx, `select slug from businesses where id::text = $1`, id).Scan(&slug); err != nil {
		writeErr(w, userErr(404, "NOT_FOUND", "No such business."))
		return
	}
	f, err := os.CreateTemp("", "wf-backup-*.dump")
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer os.Remove(f.Name())
	defer f.Close()

	dctx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(dctx, "docker", "compose", "exec", "-T", "db", "pg_dump", "-U", "postgres", "-Fc", "biz_"+slug)
	cmd.Dir = s.Svc.KitDir
	var stderr strings.Builder
	cmd.Stdout, cmd.Stderr = f, &stderr
	if err := cmd.Run(); err != nil {
		s.fail(w, r, fmt.Errorf("pg_dump %s: %w: %s", slug, err, tail(stderr.String(), 300)))
		return
	}
	s.Svc.Store.Audit(ctx, &a.ID, &id, "business.backup", nil)
	name := fmt.Sprintf("%s-%s.dump", slug, s.Svc.Now().In(India).Format("2006-01-02-1504"))
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
	http.ServeContent(w, r, name, time.Time{}, f)
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
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.disabled", map[string]any{"admin": id, "disabled": in.Disabled})
	s.listAdmins(w, r)
}

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
	var hash string
	if err := s.Svc.Store.DB.QueryRow(ctx, `select password_hash from admins where id = $1`, a.ID).Scan(&hash); err != nil {
		s.fail(w, r, err)
		return
	}
	if err := s.limiter.Allow(a.Email); err != nil {
		writeErr(w, userErr(429, "LOCKED", "Too many failed attempts. Try again in 15 minutes."))
		return
	}
	if !auth.VerifyPassword(hash, in.Current) {
		s.limiter.Failure(a.Email)
		writeErr(w, userErr(400, "BAD_PASSWORD", "The current password is wrong."))
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
	s.Svc.Store.Audit(ctx, &a.ID, nil, "admin.password", nil)
	writeJSON(w, 200, map[string]any{"ok": true})
}
