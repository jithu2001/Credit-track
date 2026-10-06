package control

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var controlMigrations embed.FS

// Store is control_db plus short connections into each business database
// (as the server's postgres user, which the business data API never is).
type Store struct {
	DB       *pgxpool.Pool
	adminURL *url.URL // postgres://postgres:…@127.0.0.1:5432/postgres
}

func OpenStore(ctx context.Context, controlURL, adminURL string) (*Store, error) {
	u, err := url.Parse(adminURL)
	if err != nil {
		return nil, fmt.Errorf("PG_ADMIN_URL: %w", err)
	}
	pool, err := pgxpool.New(ctx, controlURL)
	if err != nil {
		return nil, fmt.Errorf("CONTROL_DB_URL: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("control_db: %w", err)
	}
	return &Store{DB: pool, adminURL: u}, nil
}

func (s *Store) Close() { s.DB.Close() }

// Migrate applies the embedded control_db migrations not yet recorded.
func (s *Store) Migrate(ctx context.Context) ([]string, error) {
	if _, err := s.DB.Exec(ctx, `create table if not exists schema_migrations (
		name text primary key, applied_at timestamptz not null default now())`); err != nil {
		return nil, err
	}
	names, err := fs.Glob(controlMigrations, "migrations/*.sql")
	if err != nil {
		return nil, err
	}
	sort.Strings(names)
	var applied []string
	for _, n := range names {
		base := strings.TrimPrefix(n, "migrations/")
		var done bool
		if err := s.DB.QueryRow(ctx, `select exists(select 1 from schema_migrations where name = $1)`, base).Scan(&done); err != nil {
			return applied, err
		}
		if done {
			continue
		}
		sql, err := controlMigrations.ReadFile(n)
		if err != nil {
			return applied, err
		}
		tx, err := s.DB.Begin(ctx)
		if err != nil {
			return applied, err
		}
		if _, err := tx.Exec(ctx, string(sql)); err != nil {
			_ = tx.Rollback(ctx)
			return applied, fmt.Errorf("%s: %w", base, err)
		}
		if _, err := tx.Exec(ctx, `insert into schema_migrations (name) values ($1)`, base); err != nil {
			_ = tx.Rollback(ctx)
			return applied, err
		}
		if err := tx.Commit(ctx); err != nil {
			return applied, err
		}
		applied = append(applied, base)
	}
	return applied, nil
}

// Tenant opens a connection to a business database (biz_<slug>).
func (s *Store) Tenant(ctx context.Context, slug string) (*pgx.Conn, error) {
	u := *s.adminURL
	u.Path = "/biz_" + slug
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return pgx.Connect(ctx, u.String())
}

// Audit records an admin action (best effort: never fails the action).
func (s *Store) Audit(ctx context.Context, adminID, businessID *string, action string, details map[string]any) {
	if details == nil {
		details = map[string]any{}
	}
	_, _ = s.DB.Exec(ctx, `insert into audit_log (admin_id, business_id, action, details) values ($1, $2, $3, $4)`,
		adminID, businessID, action, details)
}

// Setting reads one settings value ("" when missing).
func (s *Store) Setting(ctx context.Context, key string) string {
	var v string
	_ = s.DB.QueryRow(ctx, `select value from settings where key = $1`, key).Scan(&v)
	return v
}
