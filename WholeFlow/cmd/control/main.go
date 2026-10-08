// Command wholeflow-control is the WholeFlow server's control service: it
// creates businesses, resolves reference keys for the phone apps, activates
// Tally PCs, records manual payments and serves the admin app's API.
//
//	wholeflow-control serve                     run the HTTP API (LISTEN, default 127.0.0.1:8100)
//	wholeflow-control create-admin EMAIL NAME   create or reset an admin (password read from stdin)
//	wholeflow-control reset-2fa EMAIL           turn off an admin's two-step sign-in (lost phone);
//	                                            they set it up again at the next sign-in
//
// Configuration comes from the environment (systemd EnvironmentFile
// /opt/wholeflow/control.env): CONTROL_DB_URL, PG_ADMIN_URL, MASTER_KEY,
// PUBLIC_URL, KIT_DIR, INTERNAL_TOKEN, LISTEN.
package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"wholeflow/internal/control"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: wholeflow-control serve | create-admin EMAIL NAME | reset-2fa EMAIL")
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var err error
	switch os.Args[1] {
	case "serve":
		err = serve(ctx, log)
	case "create-admin":
		err = createAdmin(ctx, os.Args[2:])
	case "reset-2fa":
		err = resetTOTP(ctx, os.Args[2:])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		log.Error("exit", "error", err.Error())
		os.Exit(1)
	}
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func openStore(ctx context.Context) (*control.Store, error) {
	store, err := control.OpenStore(ctx, os.Getenv("CONTROL_DB_URL"), os.Getenv("PG_ADMIN_URL"))
	if err != nil {
		return nil, err
	}
	if applied, err := store.Migrate(ctx); err != nil {
		store.Close()
		return nil, err
	} else if len(applied) > 0 {
		fmt.Fprintln(os.Stderr, "control_db migrations applied:", strings.Join(applied, ", "))
	}
	return store, nil
}

func serve(ctx context.Context, log *slog.Logger) error {
	sealer, err := control.NewSealer(os.Getenv("MASTER_KEY"))
	if err != nil {
		return err
	}
	// Only the LEGACY Deno staff service uses INTERNAL_TOKEN (/control/internal/);
	// leave it unset once that service is retired and the route is gone.
	token := os.Getenv("INTERNAL_TOKEN")
	if token != "" && len(token) < 32 {
		return errors.New("INTERNAL_TOKEN must be at least 32 characters")
	}
	store, err := openStore(ctx)
	if err != nil {
		return err
	}
	defer store.Close()
	svc := &control.Service{Store: store, Sealer: sealer, KitDir: env("KIT_DIR", "/opt/wholeflow"),
		PublicURL: env("PUBLIC_URL", ""), HTTP: &http.Client{Timeout: 30 * time.Second}, Now: time.Now}
	srv := &http.Server{
		Addr:              env("LISTEN", "127.0.0.1:8100"),
		Handler:           control.NewServer(svc, log, token).Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		// Public endpoints answer within a minute; the admin requests that run
		// scripts (creating a business, updating every database, backups)
		// extend their own deadline (control.longRequest).
		WriteTimeout: 60 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdown)
	}()
	log.Info("listening", "addr", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func createAdmin(ctx context.Context, args []string) error {
	if len(args) < 1 {
		return errors.New("usage: create-admin EMAIL [NAME]  (password on stdin)")
	}
	name := ""
	if len(args) > 1 {
		name = strings.Join(args[1:], " ")
	}
	fmt.Fprint(os.Stderr, "Password (min 10 characters): ")
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil && line == "" {
		return errors.New("no password given")
	}
	store, err := openStore(ctx)
	if err != nil {
		return err
	}
	defer store.Close()
	id, err := control.CreateAdmin(ctx, store, args[0], name, strings.TrimRight(line, "\r\n"))
	if err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "\nAdmin saved:", id)
	return nil
}

func resetTOTP(ctx context.Context, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: reset-2fa EMAIL")
	}
	store, err := openStore(ctx)
	if err != nil {
		return err
	}
	defer store.Close()
	id, err := control.AdminIDByEmail(ctx, store, args[0])
	if err != nil {
		return err
	}
	if err := control.ResetTOTP(ctx, store, id); err != nil {
		return err
	}
	store.Audit(ctx, nil, nil, "admin.2fa_reset", map[string]any{"admin": id, "by": "command line"})
	fmt.Fprintln(os.Stderr, "Two-step sign-in turned off for", args[0]+"; they set it up again at the next sign-in.")
	return nil
}
