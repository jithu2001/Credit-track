package appapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"wholeflow/internal/auth"
	"wholeflow/internal/control"
)

// Crash and error reports from the apps (instead of a third-party crash
// service): written to this API's log, nothing is stored in a database.
//
//	POST /b/{slug}/api/v1/client-errors   {"message", "stack", "app_version", "platform", "flavor"}
//	     signed-in users only; body at most 16 KB; 20 reports per user per hour → 204

const clientErrorMax = 16 << 10

var (
	clientErrorOnce    sync.Once
	clientErrorLimiter *auth.Limiter
)

func clientErrors() *auth.Limiter {
	clientErrorOnce.Do(func() { clientErrorLimiter = auth.NewLimiter(20, time.Hour, time.Hour) })
	return clientErrorLimiter
}

func clip(s string, n int) string {
	s = strings.ToValidUTF8(s, "?")
	if len(s) <= n {
		return s
	}
	for n > 0 && !utf8.RuneStart(s[n]) {
		n--
	}
	return s[:n] + "…"
}

func (s *Server) clientError(w http.ResponseWriter, r *http.Request) {
	fail := func(status int, code, msg string) {
		writeJSON(w, status, map[string]any{"error": &apiError{Status: status, Code: code, Message: msg}})
	}
	ctx := r.Context()
	t, err := s.tenant(ctx, r.PathValue("slug"))
	if err != nil {
		ae := toAPIError(err)
		if ae == nil {
			s.Log.Error("client error report: business lookup failed", "error", err.Error())
			ae = &apiError{Status: http.StatusInternalServerError, Code: "SERVER_ERROR", Message: "The server had a problem. Please try again in a moment."}
		}
		fail(ae.Status, ae.Code, ae.Message)
		return
	}
	token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || token == "" {
		fail(http.StatusUnauthorized, "UNAUTHENTICATED", "Sign in again.")
		return
	}
	claims, err := control.VerifyJWT(t.Secret, token, s.Now())
	if err != nil || claims["role"] != "authenticated" {
		fail(http.StatusUnauthorized, "UNAUTHENTICATED", "Sign in again.")
		return
	}
	user, _ := claims["sub"].(string)
	if sid, _ := claims["session_id"].(string); sid != "" {
		open, err := s.sessionOpen(ctx, t, sid)
		if err != nil || !open {
			fail(http.StatusUnauthorized, "UNAUTHENTICATED", "Sign in again.")
			return
		}
	}
	if clientErrors().Allow(t.slug+"|"+user) != nil {
		fail(http.StatusTooManyRequests, "TOO_MANY", "Too many error reports. Try again later.")
		return
	}
	var in struct {
		Message    string `json:"message"`
		Stack      string `json:"stack"`
		AppVersion string `json:"app_version"`
		Platform   string `json:"platform"`
		Flavor     string `json:"flavor"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, clientErrorMax)).Decode(&in); err != nil {
		fail(http.StatusBadRequest, "INVALID_INPUT", "The report is not valid JSON or is larger than 16 KB.")
		return
	}
	s.Log.Warn("app error report", "business", t.slug, "user", user,
		"app_version", clip(in.AppVersion, 40), "platform", clip(in.Platform, 20), "flavor", clip(in.Flavor, 20),
		"message", clip(in.Message, 1000), "stack", clip(in.Stack, 8000))
	w.WriteHeader(http.StatusNoContent)
}
