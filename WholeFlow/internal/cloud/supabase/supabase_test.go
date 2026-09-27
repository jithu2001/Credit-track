package supabase

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"wholeflow/internal/cloud"
)

// fakePostgREST records requests and answers like Supabase's REST layer.
type fakePostgREST struct {
	mu   sync.Mutex
	reqs []recorded
	srv  *httptest.Server
	// rows served by GET /transactions, to test paging
	txRows int
	status int // force this status on every request when non-zero
}

type recorded struct {
	Method, Path, Query, Prefer, Range, Auth, APIKey string
	Body                                             []byte
}

func newFake(t *testing.T) *fakePostgREST {
	f := &fakePostgREST{}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakePostgREST) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	f.mu.Lock()
	f.reqs = append(f.reqs, recorded{r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Prefer"), r.Header.Get("Range"),
		r.Header.Get("Authorization"), r.Header.Get("apikey"), body})
	status, txRows := f.status, f.txRows
	f.mu.Unlock()
	if status != 0 {
		w.WriteHeader(status)
		fmt.Fprintf(w, `{"message":"forced %d","code":"X"}`, status)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	switch {
	case strings.HasSuffix(r.URL.Path, "/businesses"):
		io.WriteString(w, `[{"id":"biz","name":"JMJ"}]`)
	case r.URL.Path == "/auth/v1/admin/users" && r.Method == http.MethodPost:
		if strings.Contains(string(body), "taken@example.com") {
			w.WriteHeader(422)
			io.WriteString(w, `{"code":422,"error_code":"email_exists","msg":"A user with this email address has already been registered"}`)
			return
		}
		io.WriteString(w, `{"id":"auth-uid-1","email":"owner@example.com"}`)
	case strings.HasPrefix(r.URL.Path, "/auth/v1/admin/users/"):
		io.WriteString(w, `{"id":"auth-uid-1"}`)
	case strings.HasSuffix(r.URL.Path, "/users") && r.Method == http.MethodPost:
		io.WriteString(w, `[{"id":"auth-uid-1","email":"owner@example.com","name":"Owner","role":"OWNER","is_active":true,"created_at":"2026-09-27T10:00:00Z"}]`)
	case strings.HasSuffix(r.URL.Path, "/users") && r.Method == http.MethodGet:
		io.WriteString(w, `[{"id":"auth-uid-1","email":"owner@example.com","name":"Owner","role":"OWNER","is_active":true,"created_at":"2026-09-27T10:00:00Z"}]`)
	case strings.HasSuffix(r.URL.Path, "/users") && r.Method == http.MethodPatch:
		w.WriteHeader(http.StatusNoContent)
	case strings.HasSuffix(r.URL.Path, "/tally_companies"), strings.HasSuffix(r.URL.Path, "/tally_connections"):
		io.WriteString(w, `[{"id":"cloud-id-1"}]`)
	case strings.HasSuffix(r.URL.Path, "/shops") && r.Method == http.MethodPost:
		var rows []map[string]any
		json.Unmarshal(body, &rows)
		var out []map[string]string
		for i, row := range rows {
			out = append(out, map[string]string{"id": fmt.Sprintf("shop-%d", i), "tally_ledger_id": row["tally_ledger_id"].(string)})
		}
		json.NewEncoder(w).Encode(out)
	case strings.HasSuffix(r.URL.Path, "/transactions") && r.Method == http.MethodGet:
		from, to := 0, pageSize-1
		fmt.Sscanf(r.Header.Get("Range"), "%d-%d", &from, &to)
		if from >= txRows {
			w.WriteHeader(http.StatusRequestedRangeNotSatisfiable)
			io.WriteString(w, `{"message":"HTTP 416"}`)
			return
		}
		if to >= txRows {
			to = txRows - 1
		}
		w.Header().Set("Content-Range", fmt.Sprintf("%d-%d/%d", from, to, txRows))
		var out []map[string]string
		for i := from; i <= to; i++ {
			out = append(out, map[string]string{"id": fmt.Sprintf("t%d", i), "tally_voucher_id": fmt.Sprintf("v%d", i), "tally_ledger_id": "l"})
		}
		json.NewEncoder(w).Encode(out)
	default:
		w.WriteHeader(http.StatusCreated)
		io.WriteString(w, `[]`)
	}
}

func (f *fakePostgREST) last() recorded {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.reqs[len(f.reqs)-1]
}

func newStorage(t *testing.T, url string, timeout time.Duration) *Storage {
	t.Helper()
	s, err := New(Config{URL: url, ServiceRoleKey: "sk-secret", BusinessID: "biz", Timeout: timeout}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestConfigValidation(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if _, err := New(Config{URL: "", ServiceRoleKey: "k", BusinessID: "b"}, log); cloud.KindOf(err) != cloud.KindConfig {
		t.Error("empty URL accepted")
	}
	if _, err := New(Config{URL: "http://insecure.example", ServiceRoleKey: "k", BusinessID: "b"}, log); cloud.KindOf(err) != cloud.KindConfig {
		t.Error("plain http accepted")
	}
	if _, err := New(Config{URL: "https://x.supabase.co", ServiceRoleKey: "k"}, log); cloud.KindOf(err) != cloud.KindConfig {
		t.Error("missing business accepted")
	}
}

func TestAuthenticateAndHeaders(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	if err := s.Authenticate(context.Background()); err != nil {
		t.Fatal(err)
	}
	r := f.last()
	if r.APIKey != "sk-secret" || r.Auth != "Bearer sk-secret" || !strings.Contains(r.Query, "id=eq.biz") || r.Path != "/rest/v1/businesses" {
		t.Fatalf("%+v", r)
	}
}

func TestUpsertShopsUsesMergeDuplicates(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	ids, err := s.UpsertShops(context.Background(), []cloud.Shop{{BusinessID: "biz", CompanyID: "c", TallyLedgerID: "L1", Name: "A"}, {BusinessID: "biz", CompanyID: "c", TallyLedgerID: "L2", Name: "B"}})
	if err != nil {
		t.Fatal(err)
	}
	if ids["L1"] != "shop-0" || ids["L2"] != "shop-1" {
		t.Fatalf("ids: %v", ids)
	}
	r := f.last()
	if r.Method != http.MethodPost || !strings.Contains(r.Query, "on_conflict=company_id%2Ctally_ledger_id") ||
		!strings.Contains(r.Prefer, "resolution=merge-duplicates") || !strings.Contains(r.Prefer, "return=representation") {
		t.Fatalf("%+v", r)
	}
	var rows []map[string]any
	json.Unmarshal(r.Body, &rows)
	if rows[0]["deleted_at"] != nil || rows[0]["phones"] == nil {
		t.Fatalf("row shape: %v", rows[0])
	}
}

func TestUpsertTransactionsBatches(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	var txns []cloud.Transaction
	for i := 0; i < 1201; i++ {
		txns = append(txns, cloud.Transaction{BusinessID: "biz", CompanyID: "c", ShopID: "s", TallyVoucherID: fmt.Sprint(i), TallyLedgerID: "l"})
	}
	if err := s.UpsertTransactions(context.Background(), txns); err != nil {
		t.Fatal(err)
	}
	f.mu.Lock()
	n := len(f.reqs)
	f.mu.Unlock()
	if n != 3 {
		t.Fatalf("expected 3 batches of ≤500, got %d requests", n)
	}
	if !strings.Contains(f.last().Query, "on_conflict=company_id%2Ctally_voucher_id%2Ctally_ledger_id") {
		t.Fatalf("%s", f.last().Query)
	}
}

func TestListTransactionsPages(t *testing.T) {
	f := newFake(t)
	f.txRows = 2350
	s := newStorage(t, f.srv.URL, 5*time.Second)
	refs, err := s.ListTransactions(context.Background(), "c", nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 2350 || refs[2349].ID != "t2349" {
		t.Fatalf("got %d refs", len(refs))
	}
	f.mu.Lock()
	n := len(f.reqs)
	f.mu.Unlock()
	if n != 3 {
		t.Fatalf("expected 3 pages, got %d requests", n)
	}
}

func TestSoftDeleteAndInList(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	if err := s.SoftDeleteTransactions(context.Background(), []string{"a", "b"}); err != nil {
		t.Fatal(err)
	}
	r := f.last()
	if r.Method != http.MethodPatch || !strings.Contains(r.Query, `id=in.%28%22a%22%2C%22b%22%29`) || !strings.Contains(string(r.Body), "deleted_at") {
		t.Fatalf("%+v %s", r, r.Body)
	}
}

func TestCreateOwnerUsesAuthAdminThenUsersRow(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	u, err := s.CreateUser(context.Background(), cloud.NewUser{Email: "Owner@Example.com", Password: "owner-pass-1", Name: "Owner", Role: cloud.RoleOwner})
	if err != nil {
		t.Fatal(err)
	}
	if u.ID != "auth-uid-1" || u.Role != "OWNER" || !u.IsActive {
		t.Fatalf("%+v", u)
	}
	f.mu.Lock()
	reqs := append([]recorded(nil), f.reqs...)
	f.mu.Unlock()
	if len(reqs) != 2 || reqs[0].Path != "/auth/v1/admin/users" || reqs[1].Path != "/rest/v1/users" {
		t.Fatalf("requests: %+v", reqs)
	}
	if !strings.Contains(string(reqs[0].Body), `"email_confirm":true`) || !strings.Contains(string(reqs[0].Body), `"email":"owner@example.com"`) || reqs[0].Auth != "Bearer sk-secret" {
		t.Fatalf("auth request: %s", reqs[0].Body)
	}
	if !strings.Contains(string(reqs[1].Body), `"business_id":"biz"`) || !strings.Contains(string(reqs[1].Body), `"role":"OWNER"`) {
		t.Fatalf("users row: %s", reqs[1].Body)
	}

	_, err = s.CreateUser(context.Background(), cloud.NewUser{Email: "taken@example.com", Password: "owner-pass-1", Role: cloud.RoleOwner})
	if cloud.KindOf(err) != cloud.KindError || !strings.Contains(err.Error(), "email_exists") {
		t.Fatalf("duplicate: %v", err)
	}

	if err := s.SetUserActive(context.Background(), "auth-uid-1", false); err != nil {
		t.Fatal(err)
	}
	last := f.last()
	if last.Path != "/auth/v1/admin/users/auth-uid-1" || !strings.Contains(string(last.Body), "ban_duration") {
		t.Fatalf("ban request: %+v", last)
	}
	users, err := s.ListUsers(context.Background())
	if err != nil || len(users) != 1 || users[0].Email != "owner@example.com" {
		t.Fatalf("list: %v %v", users, err)
	}
}

func TestErrorClassification(t *testing.T) {
	f := newFake(t)
	s := newStorage(t, f.srv.URL, 5*time.Second)
	for status, want := range map[int]cloud.ErrorKind{401: cloud.KindAuth, 403: cloud.KindAuth, 404: cloud.KindNotFound, 500: cloud.KindUnreachable, 503: cloud.KindUnreachable, 400: cloud.KindError} {
		f.mu.Lock()
		f.status = status
		f.mu.Unlock()
		err := s.Authenticate(context.Background())
		if cloud.KindOf(err) != want {
			t.Errorf("status %d → %v; want %s", status, err, want)
		}
	}

	// unreachable
	dead := newStorage(t, "http://127.0.0.1:1", time.Second)
	if err := dead.Authenticate(context.Background()); cloud.KindOf(err) != cloud.KindUnreachable {
		t.Errorf("dead server → %v", err)
	}
	// timeout, and the key never appears in the error text
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { time.Sleep(300 * time.Millisecond) }))
	defer slow.Close()
	st := newStorage(t, slow.URL, 50*time.Millisecond)
	err := st.Authenticate(context.Background())
	if cloud.KindOf(err) != cloud.KindTimeout || strings.Contains(err.Error(), "sk-secret") {
		t.Errorf("slow server → %v", err)
	}
}
