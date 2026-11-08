// Command localapi runs the WholeFlow app API on this computer against a
// local test database, so the phone apps can be tried before anything is
// deployed. It never talks to a real server; it is not for production.
//
//	db/tests/run_local.sh                                 # once: throwaway Postgres + every migration
//	WF_DB=wf_local db/tests/run_local.sh                  # or a separate database for this
//	psql postgres://postgres:pw@127.0.0.1:55432/wf_local -f db/local/seed.sql
//	LOCAL_PASSWORD=… go run ./cmd/localapi -db postgres://postgres:pw@127.0.0.1:55432/wf_local
//	adb reverse tcp:8100 tcp:8100                         # the phone's 127.0.0.1:8100 → this computer
//
// Then a local app build (env/local.json, -P wfLocal=true) connects with any
// reference key and signs in as the seeded owner (owner@local.test) with
// LOCAL_PASSWORD. It serves the control service's /control/connect and every
// app API route for one business, "local".
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"

	"wholeflow/internal/appapi"
)

const (
	slug       = "local"
	businessID = "b0000000-0000-0000-0000-0000000010ca"
	ownerEmail = "owner@local.test"
	// Signs this laptop's test tokens only.
	secret = "local-only-secret-local-only-secret-0001"
)

func main() {
	dbURL := flag.String("db", "postgres://postgres:pw@127.0.0.1:55432/wf_local", "local test database (as postgres)")
	listen := flag.String("listen", "127.0.0.1:8100", "address to serve on (adb reverse to the phone)")
	flag.Parse()
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	u, err := url.Parse(*dbURL)
	if err != nil || (u.Hostname() != "127.0.0.1" && u.Hostname() != "localhost") {
		log.Error("refusing: -db must be a database on this computer", "db", u.Redacted())
		os.Exit(1)
	}
	password := os.Getenv("LOCAL_PASSWORD")
	if len(password) < 8 {
		log.Error("set LOCAL_PASSWORD (8+ characters): the seeded owner's password")
		os.Exit(1)
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, *dbURL)
	if err != nil {
		log.Error("database", "error", err)
		os.Exit(1)
	}
	hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	tag, err := admin.Exec(ctx, `update auth.users set encrypted_password = $2 where email = $1`, ownerEmail, string(hash))
	admin.Close(ctx)
	if err != nil || tag.RowsAffected() != 1 {
		log.Error("seeded owner not found: run db/local/seed.sql first", "error", err)
		os.Exit(1)
	}

	// Data requests run as the test data role run_local.sh creates, like <slug>_api on the server.
	data := *u
	data.User = url.UserPassword("wftest_api", "pw")
	base := "http://" + *listen + "/b/" + slug
	srv := &appapi.Server{
		Log:         log,
		Now:         time.Now,
		MinAppBuild: func(context.Context) int { return 0 },
		Resolve: func(_ context.Context, s string) (appapi.TenantInfo, error) {
			if s != slug {
				return appapi.TenantInfo{}, errors.New("only the business \"local\" runs here")
			}
			return appapi.TenantInfo{Secret: secret, DBURL: data.String(), AuthDBURL: *dbURL, BusinessID: businessID, BaseURL: base}, nil
		},
	}
	defer srv.Close()

	mux := http.NewServeMux()
	// The control service's reference-key lookup: any key opens the local business.
	mux.HandleFunc("GET /control/connect", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"business_name": "Local Test Distributors", "base_url": base, "anon_key": "local-anon-key",
		})
	})
	mux.Handle("/", srv.Routes())
	log.Info("serving", "listen", *listen, "business", base, "owner", ownerEmail)
	if err := http.ListenAndServe(*listen, mux); err != nil {
		log.Error("exit", "error", err)
		os.Exit(1)
	}
}
