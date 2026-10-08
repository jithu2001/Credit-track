package control

import (
	"bufio"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
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
		writeJSON(w, http.StatusOK, MonitorReport(dir))
	}))
}
