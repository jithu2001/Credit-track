// Command wholeflow-api is the WholeFlow app API: the server side of the
// Owner and Staff apps, for every business (https://api.<domain>/b/<slug>/api/v1/…).
// See docs/API_PLAN.md.
//
// Configuration comes from the environment (systemd EnvironmentFile
// /opt/wholeflow/api.env): CONTROL_DB_URL, MASTER_KEY, KIT_DIR, PG_HOST
// (PostgreSQL as this process reaches it, default 127.0.0.1:5432), LISTEN
// (default 127.0.0.1:8300), API_TENANT_MAX_CONNS (connections per business as
// its data role, default 3), API_AUTH_MAX_CONNS (per business as its login
// role, default 2) and API_EXPECTED_MIGRATION (the newest business-database
// migration, e.g. 0009_lockdown.sql: businesses behind it are logged as a
// warning; empty = no check).
//
// From control_db it only reads (SELECT) the tables businesses and settings.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"wholeflow/internal/appapi"
	"wholeflow/internal/control"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := serve(ctx, log); err != nil {
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

func serve(ctx context.Context, log *slog.Logger) error {
	sealer, err := control.NewSealer(os.Getenv("MASTER_KEY"))
	if err != nil {
		return err
	}
	controlDB, err := pgxpool.New(ctx, os.Getenv("CONTROL_DB_URL"))
	if err != nil {
		return err
	}
	defer controlDB.Close()
	if err := controlDB.Ping(ctx); err != nil {
		return errors.New("control_db: " + err.Error())
	}
	tenantConns, err := conns("API_TENANT_MAX_CONNS", appapi.DefaultTenantMaxConns)
	if err != nil {
		return err
	}
	authConns, err := conns("API_AUTH_MAX_CONNS", appapi.DefaultAuthMaxConns)
	if err != nil {
		return err
	}
	api := &appapi.Server{
		Control:           controlDB,
		Sealer:            sealer,
		KitDir:            env("KIT_DIR", "/opt/wholeflow"),
		PGHost:            env("PG_HOST", "127.0.0.1:5432"),
		Log:               log,
		Now:               time.Now,
		TenantMaxConns:    tenantConns,
		AuthMaxConns:      authConns,
		ExpectedMigration: env("API_EXPECTED_MIGRATION", ""),
	}
	log.Info("connections per business", "data", tenantConns, "login", authConns)
	defer api.Close()
	srv := &http.Server{
		Addr:              env("LISTEN", "127.0.0.1:8300"),
		Handler:           api.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
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

// conns reads a pool size from the environment (1–50).
func conns(key string, def int32) (int32, error) {
	v := env(key, "")
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 || n > 50 {
		return 0, errors.New(key + " must be a number from 1 to 50")
	}
	return int32(n), nil
}
