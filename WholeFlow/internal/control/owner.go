package control

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/jackc/pgx/v5"
)

// Resetting the owner's password, for an owner who has forgotten theirs. The
// admin gets a new temporary password to pass on; the owner must change it at
// the next sign-in, as after creating the business.

// OwnerReset is the owner's login after a reset. Password is shown once.
type OwnerReset struct {
	Email     string `json:"email"`
	Password  string `json:"password"`
	SignedOut bool   `json:"signed_out"`
}

// ResetOwnerPassword gives the business's owner a new temporary password, and
// with signOut ends their sessions on every phone.
func (s *Service) ResetOwnerPassword(ctx context.Context, businessID string, signOut bool, adminID string) (*OwnerReset, error) {
	var slug, sealed string
	var authPort int
	err := s.Store.DB.QueryRow(ctx, `select slug, service_key_sealed, auth_port from businesses where id::text = $1`, businessID).
		Scan(&slug, &sealed, &authPort)
	if err != nil {
		return nil, userErr(http.StatusNotFound, "NOT_FOUND", "No such business.")
	}
	serviceKey, err := s.Sealer.Open(sealed)
	if err != nil {
		return nil, err
	}
	tenant, err := s.Store.Tenant(ctx, slug)
	if err != nil {
		return nil, err
	}
	defer tenant.Close(ctx)
	var ownerID, email string
	err = tenant.QueryRow(ctx, `select id::text, coalesce(email, '') from public.users
		where role = 'OWNER' and is_active order by created_at limit 1`).Scan(&ownerID, &email)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, userErr(http.StatusNotFound, "NOT_FOUND", "This business has no owner login.")
	} else if err != nil {
		return nil, err
	}

	// Keep the owner's other metadata (name, business, role).
	var user struct {
		Email    string         `json:"email"`
		Metadata map[string]any `json:"user_metadata"`
	}
	if err := s.authAdmin(ctx, authPort, serviceKey, http.MethodGet, ownerID, nil, &user); err != nil {
		return nil, err
	}
	if user.Metadata == nil {
		user.Metadata = map[string]any{}
	}
	user.Metadata["must_change_password"] = true
	password, err := RandomPassword()
	if err != nil {
		return nil, err
	}
	if err := s.authAdmin(ctx, authPort, serviceKey, http.MethodPut, ownerID,
		map[string]any{"password": password, "user_metadata": user.Metadata}, nil); err != nil {
		return nil, err
	}
	if user.Email != "" {
		email = user.Email
	}
	if signOut {
		// Refresh tokens belong to sessions and go with them; access tokens
		// already handed out stop working when they expire (within an hour).
		if _, err := tenant.Exec(ctx, `delete from auth.sessions where user_id::text = $1`, ownerID); err != nil {
			return nil, fmt.Errorf("signing out: %w", err)
		}
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "owner.password_reset", map[string]any{"email": email, "signed_out": signOut})
	return &OwnerReset{Email: email, Password: password, SignedOut: signOut}, nil
}

// authAdmin calls the business login service's admin API for one user.
func (s *Service) authAdmin(ctx context.Context, port int, serviceKey, method, userID string, body any, out any) error {
	var rd io.Reader
	if body != nil {
		raw, _ := json.Marshal(body)
		rd = bytes.NewReader(raw)
	}
	req, _ := http.NewRequestWithContext(ctx, method, fmt.Sprintf("http://127.0.0.1:%d/admin/users/%s", port, userID), rd)
	req.Header.Set("Authorization", "Bearer "+serviceKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("login service %d: %s", resp.StatusCode, tail(string(raw), 300))
	}
	if out != nil {
		return json.Unmarshal(raw, out)
	}
	return nil
}

// ---------------------------------------------------------------- HTTP

func (s *Server) ownerRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /control/admin/businesses/{id}/owner-password", s.admin(s.resetOwnerPassword))
}

func (s *Server) resetOwnerPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string `json:"password"`
		SignOut  bool   `json:"sign_out"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if err := s.checkOwnPassword(r, in.Password); err != nil {
		writeErr(w, err)
		return
	}
	out, err := s.Svc.ResetOwnerPassword(r.Context(), r.PathValue("id"), in.SignOut, adminOf(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	s.Log.Warn("owner password reset", "business", r.PathValue("id"), "admin", adminOf(r).Email, "signed_out", in.SignOut)
	writeJSON(w, http.StatusOK, out)
}
