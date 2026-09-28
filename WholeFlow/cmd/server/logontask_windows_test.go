//go:build windows

package main

import (
	"os"
	"strings"
	"testing"
)

// Registers, queries and removes a real Task Scheduler logon task under a
// test-only name. Needs no Administrator rights.
func TestLogonTaskLifecycle(t *testing.T) {
	if os.Getenv("WHOLEFLOW_SKIP_SCHTASKS") != "" {
		t.Skip("WHOLEFLOW_SKIP_SCHTASKS set")
	}
	old := taskName
	taskName = "WholeFlowTest-" + strings.ReplaceAll(t.Name(), "/", "-")
	t.Cleanup(func() { schtasks("/Delete", "/TN", taskName, "/F"); taskName = old })

	if st, _ := logonTaskStatus(); st != "not registered" {
		t.Fatalf("before install: want 'not registered', got %q", st)
	}
	exe, _ := os.Executable()
	if err := installLogonTask(exe, []string{"run", "-background", "-data", `C:\ProgramData\WholeFlow Test`}); err != nil {
		t.Fatalf("install: %v", err)
	}
	st, err := logonTaskStatus()
	if err != nil || !strings.HasPrefix(st, "ready") {
		t.Fatalf("after install: want 'ready (...)', got %q, %v", st, err)
	}
	out, err := schtasks("/Query", "/TN", taskName, "/XML")
	if err != nil {
		t.Fatalf("query xml: %v", err)
	}
	for _, want := range []string{"<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>", "<LogonTrigger>", `<Arguments>run -background -data "C:\ProgramData\WholeFlow Test"</Arguments>`} {
		if !strings.Contains(out, want) {
			t.Errorf("task XML lacks %s:\n%s", want, out)
		}
	}
	if strings.Contains(out, "HighestAvailable") {
		t.Errorf("task must not ask for elevation:\n%s", out)
	}
	// Re-registering replaces the task instead of failing.
	if err := installLogonTask(exe, []string{"run", "-background"}); err != nil {
		t.Fatalf("re-install: %v", err)
	}
	if err := removeLogonTask(); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if st, _ := logonTaskStatus(); st != "not registered" {
		t.Fatalf("after remove: want 'not registered', got %q", st)
	}
	if err := removeLogonTask(); err == nil {
		t.Fatal("second remove should fail")
	}
}
