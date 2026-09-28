// Command server is WholeFlow: the Tally shop-outstanding web app and the
// cloud sync service in one executable and one process.
//
//	wholeflow.exe                 run in the foreground (also what the Windows service executes)
//	wholeflow.exe run
//	wholeflow.exe run -background start hidden (no console window) and return
//	wholeflow.exe check           test the Tally and cloud connections and exit   (also: -check)
//	wholeflow.exe install         install as Windows service "WholeFlow" (starts at boot; Administrator)
//	wholeflow.exe autostart       start hidden at every logon of this user (no Administrator needed)
//	wholeflow.exe uninstall | start | stop | restart | status
//	wholeflow.exe sync            run one cloud synchronisation now and print the result
//	wholeflow.exe config          print the effective configuration (secrets redacted)
//	wholeflow.exe set-password    set the admin username and password that unlocks the app
//	wholeflow.exe version
//
// The app (dashboard, shops, outstanding report, Cloud Sync setup) is at
// http://127.0.0.1:8080 and is entirely behind the single admin login.
package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"wholeflow/internal/admin"
	"wholeflow/internal/api"
	"wholeflow/internal/auth"
	"wholeflow/internal/config"
	"wholeflow/internal/logging"
	"wholeflow/internal/secrets"
	"wholeflow/internal/syncer"
	"wholeflow/internal/tally"
	"wholeflow/web"
)

const (
	serviceName    = "WholeFlow"
	serviceDisplay = "WholeFlow (Tally Shop Outstanding & Cloud Sync)"
	serviceDesc    = "Shop outstanding web app for TallyPrime and background synchronisation of selected companies to the cloud."
	defaultTimeout = "180" // seconds; a full voucher fetch of ~6,000 vouchers takes ~11 s
)

func main() {
	args := os.Args[1:]
	cmd := "run"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		cmd, args = args[0], args[1:]
	}
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	dataFlag := fs.String("data", "", "data directory (default %ProgramData%\\WholeFlow, or WHOLEFLOW_DATA_DIR)")
	checkFlag := fs.Bool("check", false, "test the Tally and cloud connections, print the result and exit")
	background := fs.Bool("background", false, "run: start as a hidden background process (no console window) and return")
	user := fs.String("username", "", "set-password: developer username")
	anyLocation := fs.Bool("allow-any-location", false, "install: allow a service exe outside Program Files (development only)")
	fs.Parse(args)
	if *dataFlag != "" {
		os.Setenv("WHOLEFLOW_DATA_DIR", *dataFlag)
	}
	if *checkFlag {
		cmd = "check"
	}

	var code int
	switch cmd {
	case "run":
		switch {
		case isWindowsService():
			code = runService()
		case *background:
			code = report(startBackground())
		default:
			code = runForeground()
		}
	case "install":
		code = cmdInstall(*anyLocation)
	case "uninstall":
		code = report(uninstallService())
	case "autostart":
		code = cmdAutostart(fs.Args())
	case "start":
		code = report(cmdStart())
	case "stop":
		code = report(cmdStop())
	case "restart":
		if err := cmdStop(); err != nil && !strings.Contains(err.Error(), "not running") {
			code = report(err)
			break
		}
		code = report(cmdStart())
	case "status":
		code = cmdStatus()
	case "sync":
		code = cmdSync()
	case "check":
		code = cmdCheck()
	case "config":
		code = cmdConfig()
	case "set-password":
		code = cmdSetPassword(*user)
	case "version":
		fmt.Println("wholeflow", syncer.Version, runtime.GOOS+"/"+runtime.GOARCH)
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintln(os.Stderr, "unknown command:", cmd)
		usage()
		code = 2
	}
	os.Exit(code)
}

func usage() {
	fmt.Fprint(os.Stderr, `WholeFlow `+syncer.Version+` — Tally shop outstanding web app + cloud sync

usage: wholeflow.exe [command] [-data DIR]

  run            run in the foreground (default); web app at http://127.0.0.1:8080, Cloud Sync page inside it
  run -background
                 start hidden in the background (no console window) and return; stop with "stop"
  check          test the Tally and cloud connections and exit (also -check)
  install        install as Windows service "`+serviceName+`": starts at boot, before anyone logs in (Administrator)
  uninstall      remove the Windows service
  autostart      start hidden at every logon of the current Windows user (no Administrator needed)
  autostart off  remove that logon start
  start / stop / restart
                 the Windows service if installed, otherwise the background process
  status         Windows service / autostart / process state and cloud sync state per company
  sync           run one cloud synchronisation now (through the running app if there is one)
  config         print the effective configuration (secrets redacted)
  set-password   set the admin username and password that unlocks the whole app  [-username NAME]
  version
`)
}

func report(err error) int {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	fmt.Println("ok")
	return 0
}

// ---------------------------------------------------------------- app assembly

type app struct {
	dataDir   string
	cfg       *config.Config
	log       *slog.Logger
	logFile   *logging.RotatingFile
	logPath   string
	settings  *syncer.SettingsStore
	state     *syncer.StateStore
	tally     *tally.Service
	engine    *syncer.Engine
	scheduler *syncer.Scheduler
	secrets   secrets.Store
	mode      string // "service", "background" or "foreground"
}

func dataDir() string {
	if d := strings.TrimSpace(os.Getenv("WHOLEFLOW_DATA_DIR")); d != "" {
		return d
	}
	if runtime.GOOS == "windows" {
		if pd := os.Getenv("ProgramData"); pd != "" {
			return filepath.Join(pd, "WholeFlow")
		}
		return `C:\ProgramData\WholeFlow`
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".wholeflow")
}

// newApp wires everything. console=true also logs to stdout.
func newApp(console bool) (*app, error) {
	dir := dataDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create data dir %s: %w", dir, err)
	}
	// Lock the data dir to SYSTEM, Administrators and this account. It fails
	// (harmlessly) when a later, less privileged console lacks WRITE_DAC.
	aclErr := secureDataDir(dir)
	// .env next to the executable and in the data dir, whatever the CWD is
	// (config.Load also reads ./.env, which is what a developer run uses).
	if exe, err := os.Executable(); err == nil {
		config.LoadDotEnv(filepath.Join(filepath.Dir(exe), ".env"))
	}
	config.LoadDotEnv(filepath.Join(dir, ".env"))
	if os.Getenv("TALLY_TIMEOUT_SECONDS") == "" {
		os.Setenv("TALLY_TIMEOUT_SECONDS", defaultTimeout)
	}
	if os.Getenv("LOG_DIR") == "" {
		os.Setenv("LOG_DIR", filepath.Join(dir, "logs"))
	}
	cfg, err := config.Load()
	if err != nil {
		return nil, fmt.Errorf("config: %w", err)
	}
	logPath := filepath.Join(cfg.LogDir, "app.log")
	lf, err := logging.OpenRotating(logPath, 20<<20, 5)
	if err != nil {
		if errors.Is(err, fs.ErrPermission) {
			return nil, fmt.Errorf("open log: %w (the data folder is restricted to Administrators: use an Administrator console)", err)
		}
		return nil, fmt.Errorf("open log: %w", err)
	}
	log := logging.New(lf, console, slog.LevelInfo)
	if aclErr != nil {
		log.Debug("data dir ACL not changed", "dir", dir, "error", aclErr.Error())
	}

	sec := secrets.Default()
	settings, err := syncer.LoadSettings(dir, sec)
	if err != nil {
		if errors.Is(err, fs.ErrPermission) {
			return nil, fmt.Errorf("settings: %w (the data folder is restricted to Administrators: use an Administrator console)", err)
		}
		return nil, fmt.Errorf("settings: %w", err)
	}
	if err := applyEnvPassword(settings); err != nil {
		return nil, err
	}
	state, err := syncer.LoadState(dir)
	if err != nil {
		return nil, fmt.Errorf("state: %w", err)
	}
	for _, w := range cfg.Warnings {
		log.Warn("config", "warning", w)
	}
	if cfg.DebugRaw {
		log.Warn("TALLY_DEBUG_RAW is on: raw Tally responses (accounting data) are written to " + filepath.Join(cfg.LogDir, "raw"))
	}

	client := tally.NewClient(cfg.TallyHost, cfg.TallyPort, cfg.TallyTimeout, log, cfg.LogDir, cfg.DebugRaw)
	svc := tally.NewService(client, log, cfg.TallyHost, cfg.TallyPort, cfg.ShopGroups)
	svc.SetSupplierGroups(cfg.SupplierGroups)
	host, _ := os.Hostname()
	engine := &syncer.Engine{Tally: svc, Provider: syncer.NewProviderFactory(log, 90*time.Second), Settings: settings, State: state,
		Log: log, TallyHost: cfg.TallyHost, TallyPort: cfg.TallyPort, Hostname: host}
	sched := syncer.NewScheduler(engine, settings, log)
	return &app{dataDir: dir, cfg: cfg, log: log, logFile: lf, logPath: logPath, settings: settings, state: state,
		tally: svc, engine: engine, scheduler: sched, secrets: sec}, nil
}

// applyEnvPassword lets DEVELOPER_PASSWORD (development only) set the
// developer account; it is hashed and stored, never kept in clear text.
func applyEnvPassword(st *syncer.SettingsStore) error {
	pw := os.Getenv("DEVELOPER_PASSWORD")
	if pw == "" {
		return nil
	}
	hash, err := auth.HashPassword(pw)
	if err != nil {
		return fmt.Errorf("DEVELOPER_PASSWORD: %w", err)
	}
	return st.Update(func(s *syncer.Settings) error {
		if s.Developer.Username == "" {
			s.Developer.Username = "admin"
		}
		s.Developer.PasswordHash = hash
		return nil
	})
}

// localURL is where the CLI reaches the running app.
func (a *app) localURL() string {
	host, port, err := net.SplitHostPort(a.cfg.ListenAddr)
	if err != nil {
		return "http://" + a.cfg.ListenAddr
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port)
}

// serve runs the web app, the sync API and the scheduler until ctx is cancelled.
func (a *app) serve(ctx context.Context) error {
	set := a.settings.Get()
	token, err := writeControlToken(a.dataDir)
	if err != nil {
		return err
	}
	defer os.Remove(filepath.Join(a.dataDir, "control.token"))

	// "wholeflow.exe stop" ends a background or foreground process through
	// POST /api/sync/quit (control token only).
	ctx, quit := context.WithCancel(ctx)
	defer quit()
	syncAPI := &admin.Server{Settings: a.settings, Scheduler: a.scheduler, Engine: a.engine, Tally: a.tally, Cfg: a.cfg,
		Provider: a.engine.Provider, Sessions: auth.NewSessions(12 * time.Hour), Limiter: auth.NewLimiter(8, 10*time.Minute, 5*time.Minute),
		Log: a.log, LogPath: a.logPath, DataDir: a.dataDir, ControlToken: token, SecretScheme: a.secrets.Scheme(), Quit: quit, Mode: a.mode}
	mux := http.NewServeMux()
	syncAPI.Routes(mux) // /api/sync/login and /api/sync/session are the only endpoints open without a session
	webAPI := http.NewServeMux()
	api.New(a.tally, a.cfg, a.log).Routes(webAPI)
	mux.Handle("/api/", syncAPI.RequireLogin(webAPI)) // dashboards, shops, exports: admin login required
	static, _ := fs.Sub(web.Files, "static")
	mux.Handle("/", http.FileServer(http.FS(static)))

	ln, err := net.Listen("tcp", a.cfg.ListenAddr)
	if err != nil {
		if _, ok := openControl(a); ok {
			return fmt.Errorf("another WholeFlow is already running at %s (see: wholeflow.exe status)", a.localURL())
		}
		return fmt.Errorf("cannot listen on %s (port in use? set APP_ADDR in .env): %w", a.cfg.ListenAddr, err)
	}
	// No WriteTimeout: "sync ?wait=1" from the CLI may run for many minutes.
	httpSrv := &http.Server{Handler: hostCheck(a.cfg.ListenAddr, accessLog(a.log, mux)), ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout: 60 * time.Second, IdleTimeout: 120 * time.Second}
	a.log.Info("wholeflow started", "version", syncer.Version, "mode", a.mode, "url", a.localURL(), "data_dir", a.dataDir,
		"tally", a.tally.Endpoint(), "port_source", a.cfg.PortSource, "provider", set.Cloud.Provider,
		"sync_enabled", set.Sync.Enabled, "interval_s", set.Sync.IntervalSeconds, "secrets", a.secrets.Scheme())
	if ok, why := set.Configured(); !ok {
		a.log.Info("cloud sync not configured", "reason", why, "setup", a.localURL()+"/#/sync")
	}

	errCh := make(chan error, 1)
	go func() {
		if err := httpSrv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()
	done := make(chan struct{})
	go func() { a.scheduler.Run(ctx); close(done) }()

	select {
	case <-ctx.Done():
	case err := <-errCh:
		a.log.Error("http server stopped", "error", err.Error())
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	httpSrv.Shutdown(shutdownCtx)
	<-done
	a.log.Info("wholeflow stopped")
	return nil
}

func accessLog(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rec, r)
		if strings.HasPrefix(r.URL.Path, "/api/") {
			log.Info("http", "method", r.Method, "path", r.URL.Path, "status", rec.status, "duration_ms", time.Since(start).Milliseconds())
		}
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func writeControlToken(dir string) (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	tok := hex.EncodeToString(b)
	return tok, os.WriteFile(filepath.Join(dir, "control.token"), []byte(tok), 0o600)
}

// backgroundEnv marks the hidden child started by "run -background": it has
// no console, so it logs to the file only.
const backgroundEnv = "WHOLEFLOW_BACKGROUND"

func runForeground() int {
	bg := os.Getenv(backgroundEnv) == "1"
	a, err := newApp(!bg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	a.mode = "foreground"
	if bg {
		a.mode = "background"
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := a.serve(ctx); err != nil {
		a.log.Error("service failed", "error", err.Error())
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	return 0
}

// runService is invoked by the Windows Service Control Manager.
func runService() int {
	a, err := newApp(false)
	if err != nil {
		os.WriteFile(filepath.Join(dataDir(), "startup-error.txt"), []byte(time.Now().Format(time.RFC3339)+" "+err.Error()+"\n"), 0o600)
		return 1
	}
	defer a.logFile.Close()
	a.mode = "service"
	if err := runAsService(serviceName, a.serve); err != nil {
		a.log.Error("service control failed", "error", err.Error())
		return 1
	}
	return 0
}

// startBackground launches "wholeflow.exe run" as a hidden, detached process
// (no console window) and returns once it answers on its port. This is what
// the logon task created by "autostart" runs, and what "start" does when the
// Windows service is not installed.
func startBackground() error {
	a, err := newApp(false)
	if err != nil {
		return err
	}
	defer a.logFile.Close()
	if _, ok := openControl(a); ok {
		fmt.Println("WholeFlow is already running at " + a.localURL())
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	exe, _ = filepath.Abs(exe)
	if err := spawnHidden(exe, []string{"run", "-data", a.dataDir}, backgroundEnv+"=1"); err != nil {
		return fmt.Errorf("start background process: %w", err)
	}
	for deadline := time.Now().Add(15 * time.Second); time.Now().Before(deadline); {
		if _, ok := openControl(a); ok {
			fmt.Println("WholeFlow running in the background at " + a.localURL())
			return nil
		}
		time.Sleep(300 * time.Millisecond)
	}
	return errors.New("background process did not answer within 15 s; see " + a.logPath)
}

func serviceInstalled() bool {
	st, err := serviceStatus()
	return err == nil && st != "not installed"
}

// cmdStart starts the Windows service if it is installed, otherwise a hidden
// background process.
func cmdStart() error {
	if serviceInstalled() {
		return startService()
	}
	return startBackground()
}

// cmdStop stops whatever is running: the Windows service through the service
// manager, a background or foreground process through its control API.
func cmdStop() error {
	a, err := newApp(false)
	if err != nil {
		return err
	}
	defer a.logFile.Close()
	c, ok := openControl(a)
	if !ok {
		if serviceInstalled() {
			return errors.New("service is not running")
		}
		return errors.New("WholeFlow is not running")
	}
	if c.mode == "service" {
		return stopService()
	}
	if _, err := c.call(http.MethodPost, "/api/sync/quit", 5*time.Second); err != nil {
		return err
	}
	for deadline := time.Now().Add(30 * time.Second); time.Now().Before(deadline); {
		if _, ok := openControl(a); !ok {
			return nil
		}
		time.Sleep(300 * time.Millisecond)
	}
	return errors.New("process did not stop in time")
}

// cmdAutostart registers (or with "off" removes) a Task Scheduler logon task
// for the current Windows user that runs "wholeflow.exe run -background".
// It needs no Administrator rights; the Windows service is the better option
// where they are available.
func cmdAutostart(args []string) int {
	off := len(args) > 0 && (args[0] == "off" || args[0] == "remove" || args[0] == "disable")
	if off {
		if err := removeLogonTask(); err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			return 1
		}
		fmt.Println("Logon autostart removed. A running background process keeps running until: wholeflow.exe stop")
		return 0
	}
	if st, _ := serviceStatus(); serviceInstalled() {
		fmt.Fprintln(os.Stderr, "error: the Windows service is installed ("+st+"), which already starts WholeFlow at boot.\n"+
			"Run 'wholeflow.exe uninstall' (Administrator) first if you really want the logon task instead.")
		return 1
	}
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	exe, _ = filepath.Abs(exe)
	if err := installLogonTask(exe, []string{"run", "-background", "-data", a.dataDir}); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	fmt.Printf("Logon autostart registered (Task Scheduler task %q).\n  Executable: %s\n  Data dir:   %s\n", serviceName, exe, a.dataDir)
	fmt.Println("WholeFlow will start hidden each time this Windows user logs on. Note: unlike the Windows service it does not run before logon.")
	if a.settings.Get().Developer.PasswordHash == "" {
		fmt.Println("No admin account yet: open " + a.localURL() + " right after starting to create it.")
	}
	if err := startBackground(); err != nil {
		fmt.Println("Registered but not started:", err)
		return 1
	}
	fmt.Printf("Web app: %s  ·  Cloud Sync setup: %s/#/sync\n", a.localURL(), a.localURL())
	return 0
}

// ---------------------------------------------------------------- CLI commands

// control talks to the running app's sync API with the control token.
type control struct {
	base  string
	token string
	mode  string // how the running instance was started
	pid   int
}

func openControl(a *app) (*control, bool) {
	tok, err := os.ReadFile(filepath.Join(a.dataDir, "control.token"))
	if err != nil {
		return nil, false
	}
	c := &control{base: a.localURL(), token: strings.TrimSpace(string(tok))}
	b, err := c.call(http.MethodGet, "/api/sync/status", 3*time.Second)
	if err != nil {
		return nil, false
	}
	var resp struct {
		Mode string `json:"mode"`
		PID  int    `json:"pid"`
	}
	json.Unmarshal(b, &resp)
	c.mode, c.pid = resp.Mode, resp.PID
	if c.mode == "" {
		c.mode = "process"
	}
	return c, true
}

func (c *control) call(method, path string, timeout time.Duration) ([]byte, error) {
	req, _ := http.NewRequest(method, c.base+path, nil)
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-Requested-With", "WholeFlowSync")
	resp, err := (&http.Client{Timeout: timeout}).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("app answered HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	return b, nil
}

func cmdStatus() int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	svcState, svcErr := serviceStatus()
	fmt.Println("WholeFlow", syncer.Version)
	fmt.Println("-------------------------")
	if svcErr != nil {
		fmt.Println("Windows service:", svcErr)
	} else {
		fmt.Println("Windows service:", svcState)
	}
	task, _ := logonTaskStatus()
	fmt.Println("Logon autostart:", task)
	if svcState == "not installed" && task == "not registered" {
		fmt.Println("                 (not starting at boot: run 'install' as Administrator, or 'autostart')")
	}
	var st syncer.Status
	if c, ok := openControl(a); ok {
		b, err := c.call(http.MethodGet, "/api/sync/status", 5*time.Second)
		if err == nil {
			var resp struct {
				Sync syncer.Status `json:"sync"`
			}
			json.Unmarshal(b, &resp)
			st = resp.Sync
			fmt.Printf("Process:         running as %s, pid %d, version %s (%s)\n", c.mode, c.pid, st.Version, a.localURL())
			if st.Version != "" && st.Version != syncer.Version {
				fmt.Printf("                 (this exe is %s: restart or re-run install to switch to it)\n", syncer.Version)
			}
		}
	} else {
		fmt.Println("Process:         not running")
		st = a.scheduler.Status()
	}
	fmt.Println("Cloud sync:     ", st.State)
	fmt.Println("Background sync:", onOff(st.Enabled), "every", st.IntervalSeconds, "s")
	fmt.Println("Provider:       ", st.Provider)
	if !st.Configured {
		fmt.Println("Configuration:  ", st.ConfigMessage, "(open "+a.localURL()+"/#/sync)")
	}
	if st.NextRunAt != nil {
		fmt.Println("Next sync:      ", st.NextRunAt.Local().Format("02 Jan 2006 15:04:05"))
	}
	fmt.Println("Data dir:       ", a.dataDir)
	fmt.Println()
	for _, c := range st.Companies {
		fmt.Printf("Company: %s\n  Status: %s", c.Name, c.Status)
		if c.LastError != "" {
			fmt.Printf(" (%s: %s)", c.LastErrorCode, c.LastError)
		}
		fmt.Println()
		if c.LastSuccessAt != nil {
			fmt.Printf("  Last successful sync: %s\n", c.LastSuccessAt.Local().Format("02 Jan 2006 15:04"))
		}
		fmt.Printf("  Records: %d shops, %d transactions (voucher cursor %d)\n", c.ShopCount, c.TransactionCount, c.VoucherCursor)
	}
	return 0
}

func onOff(b bool) string {
	if b {
		return "on"
	}
	return "off"
}

func cmdSync() int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	var res *syncer.RunResult
	if c, ok := openControl(a); ok {
		fmt.Println("Asking the running app to synchronise now…")
		b, err := c.call(http.MethodPost, "/api/sync/run?wait=1", 50*time.Minute)
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			return 1
		}
		var resp struct {
			Run *syncer.RunResult `json:"run"`
		}
		if err := json.Unmarshal(b, &resp); err != nil || resp.Run == nil {
			fmt.Fprintln(os.Stderr, "error: unexpected answer from the app")
			return 1
		}
		res = resp.Run
	} else {
		fmt.Println("App not running; synchronising in this process…")
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		res = a.engine.Run(ctx)
	}
	fmt.Println(res.String())
	if res.Status == "success" {
		return 0
	}
	return 1
}

func cmdCheck() int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	code := 0

	st := a.tally.TestConnection(ctx)
	fmt.Println("Tally Status")
	fmt.Println("-------------------------")
	if st.Connected {
		fmt.Printf("Connection: Connected\nHost: %s\nPort: %d (%s)\nResponse: %d ms\n", st.Host, st.Port, a.cfg.PortSource, st.ResponseMs)
		for _, c := range st.Companies {
			fmt.Printf("Company: %s\n  GUID: %s  books from %s  period %s to %s\n", c.Name, c.GUID, c.BooksFrom, c.PeriodFrom, c.PeriodTo)
		}
		fmt.Println("Status:", st.State)
	} else {
		fmt.Printf("Connection: Not Connected\nHost: %s\nPort: %d (%s)\n", st.Host, st.Port, a.cfg.PortSource)
		if st.ProcessRunning != nil {
			fmt.Printf("tally.exe running: %v\n", *st.ProcessRunning)
		}
		fmt.Println("Error:", st.Error)
		fmt.Println("\nPossible reasons:\n- TallyPrime is not running\n- Server/data access is disabled\n- Incorrect port\n- Firewall/network issue")
		code = 1
	}

	set := a.settings.Get()
	fmt.Println("\nCloud Sync")
	fmt.Println("-------------------------")
	fmt.Println("Provider:", set.Cloud.Provider)
	fmt.Println("Business:", set.Business.ID)
	if ok, why := set.Configured(); !ok {
		fmt.Println("Not configured:", why)
		fmt.Println("Open", a.localURL()+"/#/sync", "to set it up.")
		return code
	}
	prov, err := a.engine.Provider(set)
	if err == nil {
		err = prov.Authenticate(ctx)
	}
	if err != nil {
		fmt.Println("Connection: FAILED")
		fmt.Println("Error:", err)
		code = 1
	} else {
		fmt.Println("Connection: OK")
	}
	fmt.Printf("Selected companies: %d, interval %d s, background sync %s\n", len(set.EnabledCompanies()), set.Sync.IntervalSeconds, onOff(set.Sync.Enabled))
	return code
}

func cmdConfig() int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	set := a.settings.Get()
	out := map[string]any{
		"dataDir": a.dataDir, "configFile": a.settings.Path(), "logFile": a.logPath, "url": a.localURL(),
		"tally":    map[string]any{"host": a.cfg.TallyHost, "port": a.cfg.TallyPort, "portSource": a.cfg.PortSource, "timeout": a.cfg.TallyTimeout.String(), "shopGroups": a.cfg.ShopGroups},
		"business": set.Business,
		"cloud":    map[string]any{"provider": set.Cloud.Provider, "supabaseUrl": set.Cloud.SupabaseURL, "keyStored": set.Cloud.SupabaseKey != "", "keyFromEnv": set.Cloud.KeyFromEnv, "keyError": set.Cloud.KeyError, "secretScheme": a.secrets.Scheme()},
		"sync":     set.Sync, "companies": set.Companies,
		"developer":    map[string]any{"username": set.Developer.Username, "passwordSet": set.Developer.PasswordHash != ""},
		"envOverrides": a.settings.EnvOverrides(),
	}
	b, _ := json.MarshalIndent(out, "", "  ")
	fmt.Println(string(b))
	return 0
}

func cmdSetPassword(username string) int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	in := bufio.NewReader(os.Stdin)
	cur := a.settings.Get().Developer
	if username == "" {
		def := cur.Username
		if def == "" {
			def = "admin"
		}
		fmt.Printf("Admin username [%s]: ", def)
		line, _ := in.ReadString('\n')
		username = strings.TrimSpace(line)
		if username == "" {
			username = def
		}
	}
	pw, err := readPassword(in, "Admin password (min 10 characters): ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	pw2, err := readPassword(in, "Repeat password: ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	if pw != pw2 {
		fmt.Fprintln(os.Stderr, "error: passwords do not match")
		return 1
	}
	hash, err := auth.HashPassword(pw)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	if err := a.settings.Update(func(s *syncer.Settings) error {
		s.Developer.Username, s.Developer.PasswordHash = username, hash
		return nil
	}); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	a.log.Info("developer password set", "username", username)
	fmt.Printf("Admin account %q saved to %s. The whole app now requires this login.\n", username, a.settings.Path())
	return 0
}

func cmdInstall(allowAnyLocation bool) int {
	a, err := newApp(false)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	defer a.logFile.Close()
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	exe, _ = filepath.Abs(exe)
	if !allowAnyLocation && !underProgramFiles(exe) {
		fmt.Fprintln(os.Stderr, "error: the service runs as LocalSystem, so its exe must be in a folder only Administrators can change.\n"+
			`Copy it to C:\Program Files\WholeFlow (or use deploy\Install-WholeFlow.cmd), or pass -allow-any-location on a development PC.`)
		return 1
	}
	// A background process or logon task would fight the service for the port.
	if st, _ := logonTaskStatus(); st != "not registered" {
		if err := removeLogonTask(); err == nil {
			fmt.Println("Removed the logon autostart task; the service replaces it.")
		}
	}
	if c, ok := openControl(a); ok && c.mode != "service" {
		if err := cmdStop(); err == nil {
			fmt.Println("Stopped the running WholeFlow process; the service replaces it.")
		}
	}
	updated, err := installService(serviceName, serviceDisplay, serviceDesc, exe, []string{"run", "-data", a.dataDir})
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 1
	}
	if updated {
		fmt.Printf("Service %q already installed; updated to this executable.\n", serviceName)
		if err := stopService(); err != nil && !strings.Contains(err.Error(), "not running") {
			fmt.Println("Could not stop the old instance:", err)
		}
	} else {
		fmt.Printf("Service %q installed (automatic start at boot).\n", serviceName)
	}
	fmt.Printf("  Executable: %s\n  Data dir:   %s\n", exe, a.dataDir)
	if err := startService(); err != nil {
		fmt.Println("Installed but not started:", err)
		return 1
	}
	fmt.Printf("Service started. Web app: %s  ·  Cloud Sync setup: %s/#/sync\n", a.localURL(), a.localURL())
	if a.settings.Get().Developer.PasswordHash == "" {
		fmt.Println("No admin account yet: open the web app NOW and create it (the first person to open the page claims the account).")
	}
	return 0
}

// hostCheck defeats DNS rebinding: when the app listens on loopback only, a
// request must name a loopback host, so a web page on another domain that
// re-points its name to 127.0.0.1 cannot talk to the app from the browser.
func hostCheck(listen string, next http.Handler) http.Handler {
	host, port, err := net.SplitHostPort(listen)
	if err != nil || !(host == "127.0.0.1" || host == "localhost" || host == "::1") {
		return next // listening on the LAN on purpose (APP_ADDR): nothing to pin
	}
	allowed := map[string]bool{}
	for _, h := range []string{"127.0.0.1", "localhost", "[::1]"} {
		allowed[h+":"+port] = true
		if port == "80" {
			allowed[h] = true
		}
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !allowed[strings.ToLower(r.Host)] {
			http.Error(w, "Misdirected request", http.StatusMisdirectedRequest)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// underProgramFiles reports whether path is inside Program Files, which only
// Administrators can modify.
func underProgramFiles(path string) bool {
	p := strings.ToLower(filepath.Clean(path))
	for _, env := range []string{"ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"} {
		if root := os.Getenv(env); root != "" && strings.HasPrefix(p, strings.ToLower(filepath.Clean(root))+string(filepath.Separator)) {
			return true
		}
	}
	return false
}
