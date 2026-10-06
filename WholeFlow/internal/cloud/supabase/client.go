// Package supabase implements cloud.Provider on top of Supabase's PostgREST
// API using only the standard library. The service-role key is used because
// the sync service is a trusted server-side component; it bypasses Row Level
// Security, which is why it must never leave the customer's PC or be embedded
// in the mobile app.
package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"wholeflow/internal/cloud"
)

// pageSize is PostgREST's default max-rows; we page explicitly with Range.
const pageSize = 1000

type client struct {
	base     string // https://xyz.supabase.co/rest/v1
	authBase string // https://xyz.supabase.co/auth/v1
	key      string
	http     *http.Client
	log      *slog.Logger
	batch    int
}

func newClient(projectURL, serviceKey string, timeout time.Duration, log *slog.Logger) (*client, error) {
	projectURL = strings.TrimRight(strings.TrimSpace(projectURL), "/")
	if projectURL == "" || serviceKey == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required"}
	}
	u, err := url.Parse(projectURL)
	if err != nil || u.Host == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "SUPABASE_URL is not a valid URL"}
	}
	if u.Scheme != "https" && !isLoopback(u.Hostname()) {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "SUPABASE_URL must use https"}
	}
	base := strings.TrimSuffix(projectURL, "/rest/v1")
	return &client{base: base + "/rest/v1", authBase: base + "/auth/v1", key: serviceKey,
		http: &http.Client{Timeout: timeout}, log: log, batch: 500}, nil
}

func isLoopback(h string) bool {
	return h == "localhost" || h == "127.0.0.1" || h == "::1"
}

// prefer values
const (
	preferUpsertRepr    = "resolution=merge-duplicates,return=representation"
	preferUpsertMinimal = "resolution=merge-duplicates,return=minimal"
)

// do performs one PostgREST request. body (if not nil) is JSON-encoded.
func (c *client) do(ctx context.Context, op, method, path string, query url.Values, prefer string, rangeHdr string, body any) ([]byte, http.Header, error) {
	u := c.base + "/" + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	return c.doURL(ctx, op, method, u, prefer, rangeHdr, body)
}

// doAuth performs one Supabase Auth (GoTrue) admin request.
func (c *client) doAuth(ctx context.Context, op, method, path string, body any) ([]byte, error) {
	raw, _, err := c.doURL(ctx, op, method, c.authBase+"/"+path, "", "", body)
	return raw, err
}

func (c *client) doURL(ctx context.Context, op, method, u, prefer, rangeHdr string, body any) ([]byte, http.Header, error) {
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, nil, &cloud.Error{Kind: cloud.KindError, Op: op, Err: err}
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, rdr)
	if err != nil {
		return nil, nil, &cloud.Error{Kind: cloud.KindError, Op: op, Err: err}
	}
	req.Header.Set("apikey", c.key)
	req.Header.Set("Authorization", "Bearer "+c.key)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if prefer != "" {
		req.Header.Set("Prefer", prefer)
	}
	if rangeHdr != "" {
		req.Header.Set("Range-Unit", "items")
		req.Header.Set("Range", rangeHdr)
	}

	path := strings.TrimPrefix(strings.TrimPrefix(u, c.base), c.authBase)
	if i := strings.Index(path, "?"); i >= 0 {
		path = path[:i]
	}
	start := time.Now()
	resp, err := c.http.Do(req)
	if err != nil {
		kind := cloud.KindUnreachable
		var ne net.Error
		if errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &ne) && ne.Timeout()) {
			kind = cloud.KindTimeout
		}
		c.log.Error("cloud request failed", "op", op, "method", method, "path", path, "kind", kind,
			"error", redact(err.Error(), c.key), "duration_ms", time.Since(start).Milliseconds())
		return nil, nil, &cloud.Error{Kind: kind, Op: op, Err: errors.New(redact(err.Error(), c.key))}
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, nil, &cloud.Error{Kind: cloud.KindUnreachable, Op: op, Err: err}
	}
	c.log.Info("cloud request", "op", op, "method", method, "path", path, "status", resp.StatusCode,
		"bytes", len(raw), "duration_ms", time.Since(start).Milliseconds())

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return raw, resp.Header, nil
	}
	msg := postgrestMessage(raw)
	// The WholeFlow server's access check: 402 once the subscription has
	// ended, 403 device_revoked for a PC whose key was revoked.
	if resp.StatusCode == http.StatusPaymentRequired {
		return nil, nil, &cloud.Error{Kind: cloud.KindSubscriptionEnded, Op: op, Msg: msg}
	}
	if resp.StatusCode == http.StatusForbidden && isDeviceRevoked(raw) {
		return nil, nil, &cloud.Error{Kind: cloud.KindDeviceRevoked, Op: op, Msg: msg}
	}
	if resp.StatusCode == http.StatusUnprocessableEntity || resp.StatusCode == http.StatusConflict {
		// Auth admin validation errors (email exists, weak password): the caller's fault, not an outage.
		return nil, nil, &cloud.Error{Kind: cloud.KindError, Op: op, Msg: msg}
	}
	switch {
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden:
		return nil, nil, &cloud.Error{Kind: cloud.KindAuth, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", resp.StatusCode, msg)}
	case resp.StatusCode == http.StatusNotFound:
		return nil, nil, &cloud.Error{Kind: cloud.KindNotFound, Op: op, Msg: fmt.Sprintf("HTTP 404: %s", msg)}
	case resp.StatusCode == http.StatusGatewayTimeout:
		return nil, nil, &cloud.Error{Kind: cloud.KindTimeout, Op: op, Msg: msg}
	case resp.StatusCode >= 500:
		return nil, nil, &cloud.Error{Kind: cloud.KindUnreachable, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", resp.StatusCode, msg)}
	}
	return nil, nil, &cloud.Error{Kind: cloud.KindError, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", resp.StatusCode, msg)}
}

// postgrestMessage extracts {"message":..,"details":..,"hint":..,"code":..}
// (PostgREST) or {"msg":..,"error_code":..} / {"error":..,"error_description":..} (Auth).
func postgrestMessage(raw []byte) string {
	var e struct {
		Message   string `json:"message"`
		Details   string `json:"details"`
		Hint      string `json:"hint"`
		Code      any    `json:"code"`
		Msg       string `json:"msg"`
		ErrorCode string `json:"error_code"`
		Error     string `json:"error"`
		ErrorDesc string `json:"error_description"`
	}
	if json.Unmarshal(raw, &e) == nil && (e.Message != "" || e.Msg != "" || e.ErrorDesc != "" || e.Error != "") {
		s := e.Message
		if s == "" {
			s = e.Msg
		}
		if s == "" {
			s = e.ErrorDesc
		}
		if s == "" {
			s = e.Error
		}
		if e.ErrorCode != "" {
			s = e.ErrorCode + " " + s
		}
		if code, ok := e.Code.(string); ok && code != "" {
			s = code + " " + s
		}
		if e.Details != "" {
			s += " (" + e.Details + ")"
		}
		if e.Hint != "" {
			s += " hint: " + e.Hint
		}
		return s
	}
	s := strings.TrimSpace(string(raw))
	if len(s) > 300 {
		s = s[:300] + "…"
	}
	return s
}

// isDeviceRevoked recognises {"code":"PT403","message":"device_revoked",...}.
func isDeviceRevoked(raw []byte) bool {
	var e struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	}
	return json.Unmarshal(raw, &e) == nil && e.Message == "device_revoked"
}

func redact(s, secret string) string {
	if secret == "" {
		return s
	}
	return strings.ReplaceAll(s, secret, "[redacted]")
}

// upsert POSTs rows with merge-duplicates on the given conflict columns.
func (c *client) upsert(ctx context.Context, op, table, onConflict string, rows any, returning string) ([]byte, error) {
	q := url.Values{"on_conflict": {onConflict}}
	prefer := preferUpsertMinimal
	if returning != "" {
		q.Set("select", returning)
		prefer = preferUpsertRepr
	}
	raw, _, err := c.do(ctx, op, http.MethodPost, table, q, prefer, "", rows)
	return raw, err
}

// selectAll pages through a filtered select until all rows are read.
func (c *client) selectAll(ctx context.Context, op, table string, query url.Values, into func([]byte) (int, error)) error {
	// Advance by the rows actually returned: a project whose "Max rows" is
	// below pageSize still gets paged to the end (the exact count says when).
	for from := 0; ; {
		raw, hdr, err := c.do(ctx, op, http.MethodGet, table, query, "count=exact", fmt.Sprintf("%d-%d", from, from+pageSize-1), nil)
		if err != nil {
			// PostgREST answers 416 when the range starts past the end.
			var ce *cloud.Error
			if errors.As(err, &ce) && strings.HasPrefix(ce.Msg, "HTTP 416") {
				return nil
			}
			return err
		}
		n, err := into(raw)
		if err != nil {
			return &cloud.Error{Kind: cloud.KindError, Op: op, Msg: "unexpected response", Err: err}
		}
		total := contentRangeTotal(hdr.Get("Content-Range"))
		if n == 0 || (total >= 0 && from+n >= total) || (total < 0 && n < pageSize) {
			return nil
		}
		from += n
	}
}

// contentRangeTotal parses "0-999/5842" → 5842, or -1 when unknown ("*").
func contentRangeTotal(h string) int {
	_, tot, ok := strings.Cut(h, "/")
	if !ok {
		return -1
	}
	n, err := strconv.Atoi(strings.TrimSpace(tot))
	if err != nil {
		return -1
	}
	return n
}

// inList formats values for PostgREST's in.(...) operator.
func inList(vals []string) string {
	q := make([]string, len(vals))
	for i, v := range vals {
		q[i] = `"` + strings.ReplaceAll(v, `"`, `\"`) + `"`
	}
	return "in.(" + strings.Join(q, ",") + ")"
}

func chunk[T any](xs []T, n int) [][]T {
	var out [][]T
	for len(xs) > n {
		out = append(out, xs[:n])
		xs = xs[n:]
	}
	if len(xs) > 0 {
		out = append(out, xs)
	}
	return out
}
