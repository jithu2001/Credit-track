package control

import (
	"bufio"
	"context"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Server health in the admin app: what scripts/monitor.sh logged on this
// server (no alerts are sent; see deploy/server/scripts/monitor.sh).
//
//	GET /control/admin/monitor   recent checks, problems of the last 7 days, the latest daily summary

// MonitorDir is where scripts/monitor.sh writes monitor-*.log and daily-*.log.
const MonitorDir = "/var/log/wholeflow"

const (
	monitorRecent   = 48  // checks shown (4 hours at one every 5 minutes)
	monitorProblems = 200 // problem lines shown
)

type monitorReport struct {
	Recent   []string `json:"recent"`   // newest first
	Problems []string `json:"problems"` // newest first, last 7 days
	Daily    string   `json:"daily"`    // the latest daily summary
	DailyDay string   `json:"daily_day"`
	Missing  bool     `json:"missing"` // the monitor has not written anything yet

	LatestPCVersion string       `json:"latest_pc_version"` // setting; "" = not set
	OutdatedPCs     []outdatedPC `json:"outdated_pcs"`      // active PCs older than that
}

type outdatedPC struct {
	BusinessID   string     `json:"business_id"`
	BusinessName string     `json:"business_name"`
	Machine      string     `json:"machine"`
	AppVersion   string     `json:"app_version"`
	LastSeenAt   *time.Time `json:"last_seen_at"`
}

// outdatedPCs lists the PCs (not revoked, of open businesses) whose version is below latest.
func (s *Server) outdatedPCs(ctx context.Context, latest string) []outdatedPC {
	out := []outdatedPC{}
	if latest == "" {
		return out
	}
	rows, err := s.Svc.Store.DB.Query(ctx, `select b.id::text, b.name, d.machine, d.app_version, d.last_seen_at
		from devices d join businesses b on b.id = d.business_id
		where d.revoked_at is null and b.status <> 'closed' order by b.name, d.machine`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var p outdatedPC
		if rows.Scan(&p.BusinessID, &p.BusinessName, &p.Machine, &p.AppVersion, &p.LastSeenAt) == nil && VersionLess(p.AppVersion, latest) {
			out = append(out, p)
		}
	}
	return out
}

func readLines(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if line := strings.TrimSpace(sc.Text()); line != "" {
			out = append(out, line)
		}
	}
	return out
}

// MonitorReport reads the monitor's logs in dir.
func MonitorReport(dir string) monitorReport {
	r := monitorReport{Recent: []string{}, Problems: []string{}}
	logs, _ := filepath.Glob(filepath.Join(dir, "monitor-*.log"))
	sort.Sort(sort.Reverse(sort.StringSlice(logs))) // newest day first (names are monitor-YYYY-MM-DD.log)
	if len(logs) == 0 {
		r.Missing = true
	}
	for i, path := range logs {
		lines := readLines(path)
		for j := len(lines) - 1; j >= 0; j-- {
			if len(r.Recent) < monitorRecent {
				r.Recent = append(r.Recent, lines[j])
			}
			if i < 7 && strings.Contains(lines[j], " PROBLEM ") && len(r.Problems) < monitorProblems {
				r.Problems = append(r.Problems, lines[j])
			}
		}
	}
	daily, _ := filepath.Glob(filepath.Join(dir, "daily-*.log"))
	sort.Strings(daily)
	if n := len(daily); n > 0 {
		raw, err := os.ReadFile(daily[n-1])
		if err == nil {
			if len(raw) > 64<<10 {
				raw = raw[:64<<10]
			}
			r.Daily = string(raw)
			r.DailyDay = strings.TrimSuffix(strings.TrimPrefix(filepath.Base(daily[n-1]), "daily-"), ".log")
		}
	}
	return r
}

func (s *Server) monitorRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /control/admin/monitor", s.admin(func(w http.ResponseWriter, r *http.Request) {
		dir := s.MonitorDir
		if dir == "" {
			dir = MonitorDir
		}
		rep := MonitorReport(dir)
		rep.LatestPCVersion = s.Svc.Store.Setting(r.Context(), "latest_pc_version")
		rep.OutdatedPCs = s.outdatedPCs(r.Context(), rep.LatestPCVersion)
		writeJSON(w, http.StatusOK, rep)
	}))
}
