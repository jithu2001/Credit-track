package appapi

import (
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// The business env's AUTH_DB_URL carries search_path; localURL adds sslmode.
func TestLocalURLKeepsSearchPath(t *testing.T) {
	s := &Server{PGHost: "127.0.0.1:5432"}
	u, err := s.localURL("postgres://demo_auth:pw@db:5432/biz_demo?search_path=auth")
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := pgxpool.ParseConfig(u)
	if err != nil {
		t.Fatalf("%s: %v", u, err)
	}
	cc := cfg.ConnConfig
	if cc.Host != "127.0.0.1" || cc.Port != 5432 || cc.User != "demo_auth" || cc.Database != "biz_demo" {
		t.Fatalf("parsed: %+v", cc)
	}
	if cc.RuntimeParams["search_path"] != "auth" || cc.TLSConfig != nil {
		t.Fatalf("search_path %q, tls %v", cc.RuntimeParams["search_path"], cc.TLSConfig)
	}
}
