package control

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/authn"
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
	slug, _, err := s.slugOf(ctx, businessID)
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
	password, err := RandomPassword()
	if err != nil {
		return nil, err
	}
	err = pgx.BeginFunc(ctx, tenant, func(tx pgx.Tx) error {
		u, err := authn.GetUser(ctx, tx, ownerID)
		if err != nil {
			return fmt.Errorf("owner login: %w", err)
		}
		if u.Email != "" {
			email = u.Email
		}
		if err := authn.AdminUpdate(ctx, tx, ownerID, authn.Update{Password: &password,
			Metadata: map[string]any{"must_change_password": true}}, s.Now()); err != nil {
			return err
		}
		if signOut {
			// Access tokens already handed out stop working when they expire (within an hour).
			return authn.EndSessions(ctx, tx, ownerID)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.Store.Audit(ctx, nullable(adminID), &businessID, "owner.password_reset", map[string]any{"email": email, "signed_out": signOut})
	return &OwnerReset{Email: email, Password: password, SignedOut: signOut}, nil
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
