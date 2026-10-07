package rest

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"wholeflow/internal/cloud"
)

// Owner / staff accounts live in the server's GoTrue (accounts) plus a row in
// public.users that ties the account to the business (Row Level Security keys
// on it). Both are created here with this PC's key through the GoTrue admin API.

type userRow struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Name      string    `json:"name"`
	Role      string    `json:"role"`
	IsActive  bool      `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

func (r userRow) user() cloud.User {
	return cloud.User{ID: r.ID, Email: r.Email, Name: r.Name, Role: r.Role, IsActive: r.IsActive, CreatedAt: r.CreatedAt}
}

func (s *Storage) ListUsers(ctx context.Context) ([]cloud.User, error) {
	q := url.Values{"business_id": {"eq." + s.businessID}, "select": {"id,email,name,role,is_active,created_at"}, "order": {"created_at"}}
	raw, _, err := s.c.do(ctx, "list-users", http.MethodGet, "users", q, "", "", nil)
	if err != nil {
		return nil, err
	}
	var rows []userRow
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, &cloud.Error{Kind: cloud.KindError, Op: "list-users", Msg: "unexpected response", Err: err}
	}
	out := make([]cloud.User, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.user())
	}
	return out, nil
}

// CreateUser creates the Auth user (email confirmed, so no verification mail
// is needed) and then the users row. If the second step fails the Auth user
// is removed again so no orphaned login remains.
func (s *Storage) CreateUser(ctx context.Context, n cloud.NewUser) (cloud.User, error) {
	email := strings.ToLower(strings.TrimSpace(n.Email))
	body := map[string]any{
		"email": email, "password": n.Password, "email_confirm": true,
		"user_metadata": map[string]any{"name": n.Name, "business_id": s.businessID, "role": n.Role},
	}
	raw, err := s.c.doAuth(ctx, "create-auth-user", http.MethodPost, "admin/users", body)
	if err != nil {
		return cloud.User{}, err
	}
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &created); err != nil || created.ID == "" {
		return cloud.User{}, &cloud.Error{Kind: cloud.KindError, Op: "create-auth-user", Msg: "auth did not return a user id"}
	}
	row := map[string]any{"id": created.ID, "business_id": s.businessID, "role": n.Role, "name": n.Name, "email": email, "is_active": true}
	raw, _, err = s.c.do(ctx, "create-user-row", http.MethodPost, "users", nil, "return=representation", "", []map[string]any{row})
	if err != nil {
		s.c.doAuth(ctx, "rollback-auth-user", http.MethodDelete, "admin/users/"+created.ID, nil)
		return cloud.User{}, err
	}
	var rows []userRow
	if err := json.Unmarshal(raw, &rows); err != nil || len(rows) == 0 {
		return cloud.User{}, &cloud.Error{Kind: cloud.KindError, Op: "create-user-row", Msg: "unexpected response", Err: err}
	}
	return rows[0].user(), nil
}

func (s *Storage) SetUserPassword(ctx context.Context, id, password string) error {
	if err := s.ownUser(ctx, id); err != nil {
		return err
	}
	_, err := s.c.doAuth(ctx, "set-user-password", http.MethodPut, "admin/users/"+id, map[string]any{"password": password})
	return err
}

// SetUserActive flips users.is_active (which RLS checks) and bans/unbans the
// Auth user so an existing mobile session stops working too.
func (s *Storage) SetUserActive(ctx context.Context, id string, active bool) error {
	if err := s.ownUser(ctx, id); err != nil {
		return err
	}
	q := url.Values{"id": {"eq." + id}, "business_id": {"eq." + s.businessID}}
	if _, _, err := s.c.do(ctx, "set-user-active", http.MethodPatch, "users", q, "return=minimal", "", map[string]any{"is_active": active}); err != nil {
		return err
	}
	ban := "none"
	if !active {
		ban = "876000h" // ~100 years
	}
	_, err := s.c.doAuth(ctx, "ban-auth-user", http.MethodPut, "admin/users/"+id, map[string]any{"ban_duration": ban})
	return err
}

// ownUser refuses to touch accounts of other businesses.
func (s *Storage) ownUser(ctx context.Context, id string) error {
	q := url.Values{"id": {"eq." + id}, "business_id": {"eq." + s.businessID}, "select": {"id"}}
	raw, _, err := s.c.do(ctx, "check-user", http.MethodGet, "users", q, "", "", nil)
	if err != nil {
		return err
	}
	var rows []struct{ ID string }
	if json.Unmarshal(raw, &rows) != nil || len(rows) == 0 {
		return &cloud.Error{Kind: cloud.KindNotFound, Op: "check-user", Msg: "no such user in this business"}
	}
	return nil
}
