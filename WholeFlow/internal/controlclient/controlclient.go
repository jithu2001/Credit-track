// Package controlclient talks to the WholeFlow control service
// (https://api.jitsuji.xyz by default): activating this PC with a reference
// key and activation code, the periodic heartbeat, and checking logins for
// the local page. It uses only the standard library and knows nothing about
// Tally or the sync engine.
package controlclient

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Client is a control service client. It is cheap: build one per use.
type Client struct {
	base string
	http *http.Client
}

// New checks the base URL (https, or http on this PC for tests) and returns a client.
func New(baseURL string, timeout time.Duration) (*Client, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	u, err := url.Parse(baseURL)
	if err != nil || u.Host == "" {
		return nil, &Error{Code: "BAD_CONFIG", Message: "The WholeFlow server address is not a valid URL."}
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && isLoopback(u.Hostname())) {
		return nil, &Error{Code: "BAD_CONFIG", Message: "The WholeFlow server address must start with https://."}
	}
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	return &Client{base: baseURL, http: &http.Client{Timeout: timeout}}, nil
}

func isLoopback(h string) bool { return h == "localhost" || h == "127.0.0.1" || h == "::1" }

// Error is a failed control request. Message is plain English fit to show
// the user (the server's own text when it sent one).
type Error struct {
	Status  int // HTTP status; 0 when the server was not reached
	Code    string
	Message string
	Err     error
}

func (e *Error) Error() string {
	if e.Code != "" {
		return e.Code + ": " + e.Message
	}
	return e.Message
}

func (e *Error) Unwrap() error { return e.Err }

// Unreachable reports whether the server could not give an answer at all:
// no connection, a timeout, or a server-side failure (5xx). A clear "no"
// (401, 404, …) is not unreachable.
func (e *Error) Unreachable() bool { return e.Status == 0 || e.Status >= 500 }

// IsUnreachable is Unreachable for any error.
func IsUnreachable(err error) bool {
	var ce *Error
	if errors.As(err, &ce) {
		return ce.Unreachable()
	}
	return err != nil
}

// StatusOf returns the HTTP status of a control error, or 0.
func StatusOf(err error) int {
	var ce *Error
	if errors.As(err, &ce) {
		return ce.Status
	}
	return 0
}

// ---------------------------------------------------------------- calls

// ActivateRequest is sent once, when this PC is connected to a business.
type ActivateRequest struct {
	ReferenceKey   string `json:"reference_key"`
	ActivationCode string `json:"activation_code"`
	Machine        string `json:"machine"`
	WindowsUser    string `json:"windows_user"`
	AppVersion     string `json:"app_version"`
}

// Activation is what the server returns for a good code. DeviceKey is a
// secret: it is stored encrypted and authenticates this PC to the business's
// data API on the WholeFlow server.
type Activation struct {
	DeviceID          string `json:"device_id"`
	BusinessID        string `json:"business_id"`
	BusinessName      string `json:"business_name"`
	BaseURL           string `json:"base_url"`
	DeviceKey         string `json:"device_key"`
	MaxCompanies      int    `json:"max_companies"`
	SubscriptionState string `json:"subscription_state"`
}

func (c *Client) Activate(ctx context.Context, req ActivateRequest) (Activation, error) {
	var out Activation
	if err := c.post(ctx, "/control/activate", "", req, &out); err != nil {
		return Activation{}, err
	}
	if out.BaseURL == "" || out.DeviceKey == "" || out.BusinessID == "" {
		return Activation{}, &Error{Status: http.StatusOK, Code: "BAD_RESPONSE", Message: "The WholeFlow server gave an incomplete answer. Try again or contact WholeFlow support."}
	}
	return out, nil
}

// HeartbeatResult is the server's view of this PC and its business.
type HeartbeatResult struct {
	SubscriptionState string `json:"subscription_state"` // active | renewal_due | grace | ended
	MaxCompanies      int    `json:"max_companies"`
	Revoked           bool   `json:"revoked"`
	LatestPCVersion   string `json:"latest_pc_version"` // newest WholeFlow PC release; "" when the server doesn't say
}

// Outdated reports whether version current is older than latest (dotted
// numbers, "0.5.1" < "0.6.0" < "0.10.0"; a leading "v" and anything after
// "-" or "+" are ignored). Unreadable versions are never outdated.
func Outdated(current, latest string) bool {
	a, okA := versionParts(current)
	b, okB := versionParts(latest)
	if !okA || !okB {
		return false
	}
	for i := 0; i < len(a) || i < len(b); i++ {
		var x, y int
		if i < len(a) {
			x = a[i]
		}
		if i < len(b) {
			y = b[i]
		}
		if x != y {
			return x < y
		}
	}
	return false
}

func versionParts(v string) ([]int, bool) {
	v = strings.TrimPrefix(strings.TrimSpace(v), "v")
	if i := strings.IndexAny(v, "-+ "); i >= 0 {
		v = v[:i]
	}
	if v == "" {
		return nil, false
	}
	var out []int
	for _, p := range strings.Split(v, ".") {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return nil, false
		}
		out = append(out, n)
	}
	return out, true
}

func (c *Client) Heartbeat(ctx context.Context, deviceKey, appVersion string) (HeartbeatResult, error) {
	var out HeartbeatResult
	err := c.post(ctx, "/control/heartbeat", deviceKey, map[string]string{"app_version": appVersion}, &out)
	return out, err
}

// Login is a successful check of an email and password for the local page.
// OfflineUntil is sent by the server but not used: the PC has no offline login.
type Login struct {
	OK           bool      `json:"ok"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	OfflineUntil time.Time `json:"offline_until"`
}

func (c *Client) PCLogin(ctx context.Context, email, password string) (Login, error) {
	var out Login
	if err := c.post(ctx, "/control/pc/login", "", map[string]string{"email": email, "password": password}, &out); err != nil {
		return Login{}, err
	}
	if !out.OK {
		return Login{}, &Error{Status: http.StatusUnauthorized, Code: "BAD_LOGIN", Message: "Wrong email or password."}
	}
	return out, nil
}

// post sends a JSON body and decodes a 2xx JSON answer into out. Errors come
// back as *Error with the server's code and message.
func (c *Client) post(ctx context.Context, path, bearer string, body, out any) error {
	b, err := json.Marshal(body)
	if err != nil {
		return &Error{Code: "INTERNAL", Message: err.Error(), Err: err}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+path, bytes.NewReader(b))
	if err != nil {
		return &Error{Code: "INTERNAL", Message: err.Error(), Err: err}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return &Error{Code: "UNREACHABLE", Message: "Cannot reach the WholeFlow server. Check the internet connection and try again.", Err: err}
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return &Error{Status: 0, Code: "UNREACHABLE", Message: "The connection to the WholeFlow server broke off. Try again.", Err: err}
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		e := &Error{Status: resp.StatusCode, Code: fmt.Sprintf("HTTP_%d", resp.StatusCode),
			Message: fmt.Sprintf("The WholeFlow server answered HTTP %d. Try again later.", resp.StatusCode)}
		var env struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal(raw, &env) == nil && env.Error.Message != "" {
			e.Code, e.Message = env.Error.Code, env.Error.Message
		}
		return e
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return &Error{Status: resp.StatusCode, Code: "BAD_RESPONSE", Message: "The WholeFlow server gave an unexpected answer.", Err: err}
	}
	return nil
}
