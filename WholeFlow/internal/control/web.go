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
}

// backup dumps one business database (pg_dump custom format) for download.
// The dump is written to a temporary file first so a failed dump is an error,
// not a truncated download.
func (s *Server) backup(w http.ResponseWriter, r *http.Request) {
	longRequest(w, 30*time.Minute) // pg_dump (10 minutes at most), then the download
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
