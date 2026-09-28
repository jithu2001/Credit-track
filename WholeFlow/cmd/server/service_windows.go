//go:build windows

package main

import (
	"bufio"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

func isWindowsService() bool {
	ok, err := svc.IsWindowsService()
	return err == nil && ok
}

// handler adapts serve() to the Service Control Manager protocol.
type handler struct {
	serve func(ctx context.Context) error
}

func (h *handler) Execute(args []string, req <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	status <- svc.Status{State: svc.StartPending}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- h.serve(ctx) }()
	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case c := <-req:
			switch c.Cmd {
			case svc.Interrogate:
				status <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending}
				cancel()
				select {
				case <-done:
				case <-time.After(20 * time.Second):
				}
				return false, 0
			}
		case err := <-done:
			if err != nil {
				return true, 1 // service-specific exit code → SCM recovery restarts us
			}
			return false, 0
		}
	}
}

func runAsService(name string, serve func(ctx context.Context) error) error {
	return svc.Run(name, &handler{serve: serve})
}

// installService registers the service, or, when it already exists, points
// it at this executable (upgrade in place). updated reports the latter.
func installService(name, display, desc, exe string, args []string) (updated bool, err error) {
	m, err := mgr.Connect()
	if err != nil {
		return false, fmt.Errorf("open service manager (run as Administrator): %w", err)
	}
	defer m.Disconnect()
	cfg := mgr.Config{
		DisplayName:      display,
		Description:      desc,
		StartType:        mgr.StartAutomatic,
		DelayedAutoStart: true, // let TallyPrime and the network come up first
		ErrorControl:     mgr.ErrorNormal,
	}
	s, err := m.OpenService(name)
	if err == nil {
		updated = true
		cfg.BinaryPathName = windows.ComposeCommandLine(append([]string{exe}, args...))
		if err := s.UpdateConfig(cfg); err != nil {
			s.Close()
			return true, fmt.Errorf("update service: %w", err)
		}
	} else {
		s, err = m.CreateService(name, exe, cfg, args...)
		if err != nil {
			return false, fmt.Errorf("create service: %w", err)
		}
	}
	defer s.Close()
	// Restart on crash: 30 s, 60 s, then every 5 min; reset the counter after a day.
	err = s.SetRecoveryActions([]mgr.RecoveryAction{
		{Type: mgr.ServiceRestart, Delay: 30 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 60 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 5 * time.Minute},
	}, 86400)
	if err != nil {
		return updated, fmt.Errorf("set recovery actions: %w", err)
	}
	return updated, nil
}

// ---------------------------------------------------------------- background process

// spawnHidden starts exe with args as a detached process without a console
// window. stdin/stdout/stderr go to NUL; the app logs to its file.
func spawnHidden(exe string, args []string, env ...string) error {
	cmd := exec.Command(exe, args...)
	cmd.Dir = filepath.Dir(exe)
	cmd.Env = append(os.Environ(), env...)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: windows.CREATE_NO_WINDOW | windows.CREATE_NEW_PROCESS_GROUP,
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	// Do not wait: the child outlives us. Release the handle.
	return cmd.Process.Release()
}

// ---------------------------------------------------------------- logon task (no Administrator)

// Task Scheduler is driven through schtasks.exe with an XML definition so we
// can turn off the 72-hour execution limit that the plain /Create form applies.
const taskXML = `<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>%[1]s</Description>
    <URI>\%[2]s</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>%[3]s</UserId>
      <Delay>PT20S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>%[3]s</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>%[4]s</Command>
      <Arguments>%[5]s</Arguments>
      <WorkingDirectory>%[6]s</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
`

// taskName is the Task Scheduler task name; a variable so tests can use their own.
var taskName = serviceName

func schtasks(args ...string) (string, error) {
	cmd := exec.Command(filepath.Join(os.Getenv("SystemRoot"), "System32", "schtasks.exe"), args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func xmlEscape(s string) string {
	var b strings.Builder
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

// installLogonTask registers (replacing any previous one) a Task Scheduler
// task that runs exe with args when the current user logs on.
func installLogonTask(exe string, args []string) error {
	user, err := currentUserName()
	if err != nil {
		return err
	}
	def := fmt.Sprintf(taskXML, xmlEscape(serviceDesc), taskName, xmlEscape(user), xmlEscape(exe),
		xmlEscape(windows.ComposeCommandLine(args)), xmlEscape(filepath.Dir(exe)))
	// schtasks wants the XML file in UTF-16 LE with a BOM.
	u16 := utf16.Encode([]rune(def))
	buf := make([]byte, 2, 2+2*len(u16))
	buf[0], buf[1] = 0xFF, 0xFE
	for _, c := range u16 {
		buf = append(buf, byte(c), byte(c>>8))
	}
	f, err := os.CreateTemp("", "wholeflow-task-*.xml")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err := f.Write(buf); err != nil {
		f.Close()
		return err
	}
	f.Close()
	if out, err := schtasks("/Create", "/TN", taskName, "/XML", f.Name(), "/F"); err != nil {
		return fmt.Errorf("schtasks: %s", firstLine(out, err))
	}
	return nil
}

func removeLogonTask() error {
	if st, _ := logonTaskStatus(); st == "not registered" {
		return errors.New("logon autostart is not registered")
	}
	if out, err := schtasks("/Delete", "/TN", taskName, "/F"); err != nil {
		return fmt.Errorf("schtasks: %s", firstLine(out, err))
	}
	return nil
}

// logonTaskStatus reports "not registered", or the task's status and user.
func logonTaskStatus() (string, error) {
	out, err := schtasks("/Query", "/TN", taskName, "/FO", "CSV", "/NH")
	if err != nil {
		return "not registered", nil
	}
	// "\WholeFlow","Next Run Time","Status"
	fields := strings.Split(out, "\",\"")
	status := "registered"
	if len(fields) == 3 {
		status = strings.ToLower(strings.Trim(fields[2], "\"\r\n "))
	}
	user, _ := currentUserName()
	if status == "running" {
		// The task itself only spawns the hidden process and exits; report it plainly.
		status = "registered"
	}
	return fmt.Sprintf("%s (runs at logon of %s)", status, user), nil
}

func currentUserName() (string, error) {
	u, err := user.Current()
	if err != nil {
		return "", fmt.Errorf("current user: %w", err)
	}
	return u.Username, nil // DOMAIN\name or PC\name, what Task Scheduler expects
}

func firstLine(out string, err error) string {
	if out == "" {
		return err.Error()
	}
	if i := strings.IndexAny(out, "\r\n"); i >= 0 {
		out = out[:i]
	}
	return strings.TrimPrefix(out, "ERROR: ")
}

func uninstallService() error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("open service manager (run as Administrator): %w", err)
	}
	defer m.Disconnect()
	s, err := m.OpenService(serviceName)
	if err != nil {
		return errors.New("service is not installed")
	}
	defer s.Close()
	if st, err := s.Query(); err == nil && st.State != svc.Stopped {
		s.Control(svc.Stop)
		waitFor(s, svc.Stopped, 30*time.Second)
	}
	return s.Delete()
}

func startService() error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("open service manager (run as Administrator): %w", err)
	}
	defer m.Disconnect()
	s, err := m.OpenService(serviceName)
	if err != nil {
		return errors.New("service is not installed; run: wholeflow.exe install")
	}
	defer s.Close()
	if st, err := s.Query(); err == nil && st.State == svc.Running {
		return nil
	}
	if err := s.Start(); err != nil {
		return fmt.Errorf("start: %w", err)
	}
	if !waitFor(s, svc.Running, 30*time.Second) {
		return errors.New("service did not reach Running state; see logs\\app.log and startup-error.txt in the data dir")
	}
	return nil
}

func stopService() error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("open service manager (run as Administrator): %w", err)
	}
	defer m.Disconnect()
	s, err := m.OpenService(serviceName)
	if err != nil {
		return errors.New("service is not installed")
	}
	defer s.Close()
	st, err := s.Query()
	if err != nil {
		return err
	}
	if st.State == svc.Stopped {
		return errors.New("service is not running")
	}
	if _, err := s.Control(svc.Stop); err != nil {
		return fmt.Errorf("stop: %w", err)
	}
	if !waitFor(s, svc.Stopped, 30*time.Second) {
		return errors.New("service did not stop in time")
	}
	return nil
}

func waitFor(s *mgr.Service, want svc.State, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		st, err := s.Query()
		if err == nil && st.State == want {
			return true
		}
		time.Sleep(300 * time.Millisecond)
	}
	return false
}

// serviceStatus works from a non-elevated console: it opens the service
// manager and the service with query rights only (mgr.Connect asks for all
// access, which needs Administrator).
func serviceStatus() (string, error) {
	mh, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return "", fmt.Errorf("cannot query service manager: %w", err)
	}
	m := &mgr.Mgr{Handle: mh}
	defer m.Disconnect()
	name, _ := windows.UTF16PtrFromString(serviceName)
	sh, err := windows.OpenService(mh, name, windows.SERVICE_QUERY_STATUS|windows.SERVICE_QUERY_CONFIG)
	if err != nil {
		return "not installed", nil
	}
	s := &mgr.Service{Name: serviceName, Handle: sh}
	defer s.Close()
	st, err := s.Query()
	if err != nil {
		return "", err
	}
	cfg, _ := s.Config()
	start := ""
	switch cfg.StartType {
	case mgr.StartAutomatic:
		start = " (automatic start)"
	case mgr.StartManual:
		start = " (manual start)"
	case mgr.StartDisabled:
		start = " (disabled)"
	}
	return stateName(st.State) + start, nil
}

func stateName(s svc.State) string {
	switch s {
	case svc.Stopped:
		return "stopped"
	case svc.StartPending:
		return "starting"
	case svc.StopPending:
		return "stopping"
	case svc.Running:
		return "running"
	case svc.ContinuePending, svc.PausePending, svc.Paused:
		return "paused"
	}
	return fmt.Sprintf("state %d", s)
}

// readPassword reads a line without echo when stdin is a console.
func readPassword(in *bufio.Reader, prompt string) (string, error) {
	fmt.Print(prompt)
	h := windows.Handle(os.Stdin.Fd())
	var mode uint32
	if err := windows.GetConsoleMode(h, &mode); err != nil {
		line, err := in.ReadString('\n')
		return strings.TrimRight(line, "\r\n"), err
	}
	windows.SetConsoleMode(h, mode&^windows.ENABLE_ECHO_INPUT)
	defer windows.SetConsoleMode(h, mode)
	line, err := in.ReadString('\n')
	fmt.Println()
	if err != nil && line == "" {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

// secureDataDir replaces the data directory's inherited ACL (ProgramData lets
// every local user read files and create new ones) with a protected one:
// SYSTEM, Administrators and the account this process runs as, full control;
// nobody else. Children inherit it, so config.json (DPAPI-encrypted key,
// password hash), control.token, state.json, .env and the logs are covered.
func secureDataDir(dir string) error {
	sddl := "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"
	if tok := windows.GetCurrentProcessToken(); tok != 0 {
		if u, err := tok.GetTokenUser(); err == nil {
			if sid := u.User.Sid.String(); sid != "S-1-5-18" { // not already SYSTEM
				sddl += "(A;OICI;FA;;;" + sid + ")"
			}
		}
	}
	sd, err := windows.SecurityDescriptorFromString(sddl)
	if err != nil {
		return err
	}
	dacl, _, err := sd.DACL()
	if err != nil {
		return err
	}
	return windows.SetNamedSecurityInfo(dir, windows.SE_FILE_OBJECT,
		windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION, nil, nil, dacl, nil)
}
