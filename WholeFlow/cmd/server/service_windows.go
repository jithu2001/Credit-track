//go:build windows

package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

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

func installService(name, display, desc, exe string, args []string) error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("open service manager (run as Administrator): %w", err)
	}
	defer m.Disconnect()
	if s, err := m.OpenService(name); err == nil {
		s.Close()
		return errors.New("service already installed; run uninstall first")
	}
	s, err := m.CreateService(name, exe, mgr.Config{
		DisplayName:      display,
		Description:      desc,
		StartType:        mgr.StartAutomatic,
		DelayedAutoStart: true, // let TallyPrime and the network come up first
		ErrorControl:     mgr.ErrorNormal,
	}, args...)
	if err != nil {
		return fmt.Errorf("create service: %w", err)
	}
	defer s.Close()
	// Restart on crash: 30 s, 60 s, then every 5 min; reset the counter after a day.
	err = s.SetRecoveryActions([]mgr.RecoveryAction{
		{Type: mgr.ServiceRestart, Delay: 30 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 60 * time.Second},
		{Type: mgr.ServiceRestart, Delay: 5 * time.Minute},
	}, 86400)
	if err != nil {
		return fmt.Errorf("set recovery actions: %w", err)
	}
	return nil
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
		return errors.New("service did not reach Running state; see logs\\sync.log and startup-error.txt in the data dir")
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
