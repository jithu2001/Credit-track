package control

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMonitorReport(t *testing.T) {
	dir := t.TempDir()
	if r := MonitorReport(dir); !r.Missing || len(r.Recent) != 0 {
		t.Fatalf("empty dir: %+v", r)
	}
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("monitor-2026-10-07.log", "t1 OK api\nt2 PROBLEM api answered 000 | disk=5%\n")
	write("monitor-2026-10-08.log", "t3 OK api\nt4 OK api\n")
	write("daily-2026-10-07.log", "old")
	write("daily-2026-10-08.log", "WholeFlow daily summary 2026-10-08")
	r := MonitorReport(dir)
	if r.Missing || len(r.Recent) != 4 || r.Recent[0] != "t4 OK api" || r.Recent[3] != "t1 OK api" {
		t.Fatalf("recent: %+v", r.Recent)
	}
	if len(r.Problems) != 1 || r.Problems[0] != "t2 PROBLEM api answered 000 | disk=5%" {
		t.Fatalf("problems: %+v", r.Problems)
	}
	if r.DailyDay != "2026-10-08" || r.Daily != "WholeFlow daily summary 2026-10-08" {
		t.Fatalf("daily: %q %q", r.DailyDay, r.Daily)
	}
}
