package appapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"wholeflow/internal/control"
)

// Runs the API against a real, fully migrated business database:
//
//	db/tests/run_local.sh                 # throwaway Postgres (Docker) with every migration
//	WF_TEST_PG=postgres://postgres:pw@127.0.0.1:55432/wf go test ./internal/appapi -run Integration
//
// Seeds two businesses, then checks the numbers and that the database's rules
// still decide who sees what. Removes its rows afterwards.

const (
	bizA    = "b0000000-0000-0000-0000-00000000a001"
	bizB    = "b0000000-0000-0000-0000-00000000a002"
	ownerA  = "a0000000-0000-0000-0000-00000000a001"
	staffA  = "a0000000-0000-0000-0000-00000000a002"
	ownerB  = "a0000000-0000-0000-0000-00000000a003"
	companA = "c0000000-0000-0000-0000-00000000a001"
	shopA1  = "d0000000-0000-0000-0000-00000000a001"
	shopA2  = "d0000000-0000-0000-0000-00000000a002"
	siteA   = "e0000000-0000-0000-0000-00000000a001"
	secret  = "test-secret-test-secret-test-secret-32"
)

func TestIntegration(t *testing.T) {
	admin := os.Getenv("WF_TEST_PG")
	if admin == "" {
		t.Skip("set WF_TEST_PG (see the comment at the top of this file)")
	}
	ctx := context.Background()
	db, err := pgx.Connect(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close(ctx) }) // runs after the row cleanup below

	// The business data API's role, as scripts/new-business.sh makes it.
	mustExec(t, db, `do $$ begin
		if not exists (select 1 from pg_roles where rolname = 'wftest_api') then
			create role wftest_api login noinherit password 'pw';
		end if; end $$`)
	mustExec(t, db, `grant anon, authenticated, service_role to wftest_api`)
	cleanup := func() {
		mustExec(t, db, `delete from public.businesses where id in ($1, $2)`, bizA, bizB)
		mustExec(t, db, `delete from auth.users where id in ($1, $2, $3)`, ownerA, staffA, ownerB)
		mustExec(t, db, `delete from public.service_status`)
	}
	cleanup()
	t.Cleanup(cleanup)

	mustExec(t, db, `insert into public.businesses (id, name) values ($1, 'API Biz'), ($2, 'Other Biz')`, bizA, bizB)
	mustExec(t, db, `insert into auth.users (id, email) values ($1, 'o@a.test'), ($2, 's@a.test'), ($3, 'o@b.test')`, ownerA, staffA, ownerB)
	mustExec(t, db, `insert into public.users (id, business_id, role, name, email) values
		($1, $4, 'OWNER', 'Owner', 'o@a.test'), ($2, $4, 'STAFF', 'Staff', 's@a.test'), ($3, $5, 'OWNER', 'Other', 'o@b.test')`,
		ownerA, staffA, ownerB, bizA, bizB)
	mustExec(t, db, `insert into public.tally_companies (id, business_id, tally_company_id, company_name, books_from, period_from)
		values ($1, $2, 'g-api', 'API Co', '2025-04-01', '2026-04-01')`, companA, bizA)
	mustExec(t, db, `insert into public.sites (id, business_id, company_id, name) values ($1, $2, $3, 'Town')`, siteA, bizA, companA)
	// Shop 1: ₹1,000 opening (Dr), bills 1 May ₹500 and 15 Jun ₹800, ₹1,200 paid 10 Jul → owes ₹1,100.
	// Shop 2: ₹200 advance (Cr opening), bill 1 Jul ₹150 → ₹50 advance.
	mustExec(t, db, `insert into public.shops (id, business_id, company_id, tally_ledger_id, name, phone, opening_balance_amount,
			opening_balance_type, receivable, site_id, synced_at) values
		($1, $3, $4, 'l1', 'Alpha Stores', '9800000001', 1000, 'DR', 1100, $5, now()),
		($2, $3, $4, 'l2', 'Beta Traders', null, 200, 'CR', -50, null, now())`, shopA1, shopA2, bizA, companA, siteA)
	mustExec(t, db, `insert into public.transactions (business_id, company_id, shop_id, tally_voucher_id, tally_ledger_id,
			transaction_date, voucher_type, voucher_number, category, debit, credit, amount, synced_at) values
		($1, $2, $3, 'v1', 'l1', '2026-05-01', 'Sales', '1', 'sales', 500, 0, 500, now()),
		($1, $2, $3, 'v2', 'l1', '2026-06-15', 'Sales', '2', 'sales', 800, 0, 800, now()),
		($1, $2, $3, 'v3', 'l1', '2026-07-10', 'Receipt', 'R1', 'receipts', 0, 1200, -1200, now()),
		($1, $2, $4, 'v4', 'l2', '2026-07-01', 'Sales', '3', 'sales', 150, 0, 150, now())`, bizA, companA, shopA1, shopA2)

	// A stand-in for the business's login service (GoTrue admin API): logins
	// go into auth.users so the users rows can refer to them.
	logins := map[string]map[string]any{} // id → last attributes sent
	gotrue := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		if req.Header.Get("Authorization") != "Bearer service-key" {
			w.WriteHeader(401)
			return
		}
		var body map[string]any
		_ = json.NewDecoder(req.Body).Decode(&body)
		id := strings.TrimPrefix(req.URL.Path, "/admin/users/")
		switch {
		case req.Method == "POST" && req.URL.Path == "/admin/users":
			var newID string
			err := db.QueryRow(context.Background(), `insert into auth.users (id, email) values (gen_random_uuid(), $1)
				on conflict do nothing returning id::text`, body["email"]).Scan(&newID)
			var exists bool
			_ = db.QueryRow(context.Background(), `select count(*) > 1 from auth.users where email = $1`, body["email"]).Scan(&exists)
			if err != nil || exists {
				if newID != "" {
					_, _ = db.Exec(context.Background(), `delete from auth.users where id = $1`, newID)
				}
				w.WriteHeader(422)
				_, _ = w.Write([]byte(`{"code":"email_exists","msg":"A user with this email address has already been registered"}`))
				return
			}
			logins[newID] = body
			_ = json.NewEncoder(w).Encode(map[string]any{"id": newID})
		case req.Method == "GET":
			meta := map[string]any{"name": "x", "must_change_password": false}
			_ = json.NewEncoder(w).Encode(map[string]any{"id": id, "user_metadata": meta})
		case req.Method == "PUT":
			logins[id] = body
			_ = json.NewEncoder(w).Encode(map[string]any{"id": id})
		case req.Method == "DELETE":
			_, _ = db.Exec(context.Background(), `delete from auth.users where id::text = $1`, id)
			w.WriteHeader(200)
		}
	}))
	defer gotrue.Close()

	mustExec(t, db, `insert into public.sync_logs (business_id, company_id, started_at, completed_at, status, mode, records_processed)
		values ($1, $2, '2026-07-20 05:00:00+00', '2026-07-20 05:00:09+00', 'success', 'incremental', 12)`, bizA, companA)
	mustExec(t, db, `insert into public.tally_connections (business_id, machine_identifier, hostname, status, app_version, last_seen_at)
		values ($1, 'pc-1', 'SHOP-PC', 'online', '0.5.1', '2026-07-20 05:00:00+00')`, bizA)

	u, _ := url.Parse(admin)
	u.User = url.UserPassword("wftest_api", "pw")
	srv := &Server{
		Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Now: func() time.Time { return time.Date(2026, 7, 20, 6, 0, 0, 0, time.UTC) },
		Resolve: func(_ context.Context, slug string) (TenantInfo, error) {
			if slug != "apitest" {
				return TenantInfo{}, fail(http.StatusNotFound, "NOT_FOUND", "No such business.")
			}
			return TenantInfo{Secret: secret, DBURL: u.String(), AuthURL: gotrue.URL, ServiceKey: "service-key"}, nil
		},
	}
	defer srv.Close()
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	token := func(sub string) string {
		tok, err := control.SignJWT(secret, map[string]any{"sub": sub, "role": "authenticated", "aud": "authenticated",
			"exp": time.Now().Add(time.Hour).Unix()})
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	// lastRaw is the last response body; save() keeps it as a fixture for the
	// app's contract test (test/unit/api_contract_test.dart) when
	// WF_WRITE_FIXTURES=1, so the app parses exactly what this server sends.
	var lastRaw []byte
	save := func(name string) {
		t.Helper()
		if os.Getenv("WF_WRITE_FIXTURES") != "1" {
			return
		}
		dir := filepath.Join("..", "..", "..", "wholeflow_app", "test", "fixtures", "api")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		var pretty bytes.Buffer
		if err := json.Indent(&pretty, lastRaw, "", "  "); err != nil {
			t.Fatalf("fixture %s: %v", name, err)
		}
		pretty.WriteByte('\n')
		if err := os.WriteFile(filepath.Join(dir, name+".json"), pretty.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	do := func(req *http.Request) (int, map[string]any) {
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		lastRaw, _ = io.ReadAll(res.Body)
		var body map[string]any
		_ = json.Unmarshal(lastRaw, &body)
		return res.StatusCode, body
	}
	get := func(path, tok string) (int, map[string]any) {
		req, _ := http.NewRequest(http.MethodGet, ts.URL+path, nil)
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		return do(req)
	}
	summaryPath := "/b/apitest/api/v1/payments?company=" + companA

	t.Run("owner gets the summary", func(t *testing.T) {
		code, body := get(summaryPath, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("payments")
		// Opening dated at the period start (1 Apr); 30 days credit; today 20 Jul.
		// FIFO: ₹1,200 settles the opening (₹1,000) and ₹200 of the May bill → May ₹300 (due 31 May)
		// and June ₹800 (due 15 Jul) are overdue.
		eqv(t, body["books_from"], "2026-04-01", "books_from")
		eqv(t, body["overdue"], "1100.00", "overdue")
		eqv(t, body["overdue_shops"], 1.0, "overdue shops")
		eqv(t, body["open_amount"], "1100.00", "open amount")
		shops := body["shops"].([]any)
		if len(shops) != 2 {
			t.Fatalf("shops = %d", len(shops))
		}
		alpha := shops[0].(map[string]any)
		eqv(t, alpha["shop"].(map[string]any)["site_name"], "Town", "site")
		eqv(t, alpha["max_days_overdue"], 50.0, "max days overdue") // May bill due 31 May
		eqv(t, alpha["reconciled"], true, "alpha reconciled")
		eqv(t, alpha["last_payment_date"], "2026-07-10", "last payment")
		beta := shops[1].(map[string]any)
		eqv(t, beta["advance"], "50.00", "beta advance")
		eqv(t, beta["reconciled"], true, "beta reconciled")
		// 30 days ago (20 Jun): opening (due 1 May) and May bill (due 31 May) unpaid.
		eqv(t, body["overdue_month_ago"], "1500.00", "overdue a month ago")
	})

	t.Run("credit days change what is late", func(t *testing.T) {
		_, body := get(summaryPath+"&credit_days=60", token(ownerA))
		eqv(t, body["overdue"], "300.00", "overdue at 60 days") // only the May bill is past 60 days
	})

	t.Run("shop view has the bills", func(t *testing.T) {
		code, body := get("/b/apitest/api/v1/payments/shops/"+shopA1, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("payments_shop")
		bills := body["bills"].([]any)
		if len(bills) != 3 {
			t.Fatalf("bills = %d", len(bills))
		}
		first := bills[0].(map[string]any)
		eqv(t, first["is_opening"], true, "opening bill")
		eqv(t, first["settled_on"], "2026-07-10", "opening settled")
		eqv(t, first["allocations"].([]any)[0].(map[string]any)["kind"], "payment", "allocation kind")
		eqv(t, bills[1].(map[string]any)["remaining"], "300.00", "May bill remaining")
		eqv(t, body["closed_bills"], 1.0, "closed bills")
	})

	t.Run("staff are refused", func(t *testing.T) {
		code, body := get(summaryPath, token(staffA))
		eqv(t, code, 403, "status")
		eqv(t, body["error"].(map[string]any)["code"], "NOT_OWNER", "code")
	})

	t.Run("another business's owner sees nothing", func(t *testing.T) {
		code, _ := get(summaryPath, token(ownerB))
		eqv(t, code, 404, "summary status") // the company is invisible to them
		code, _ = get("/b/apitest/api/v1/payments/shops/"+shopA1, token(ownerB))
		eqv(t, code, 404, "shop status")
	})

	t.Run("no token, bad token, a PC key", func(t *testing.T) {
		code, _ := get(summaryPath, "")
		eqv(t, code, 401, "no token")
		bad, _ := control.SignJWT("another-secret-another-secret-another", map[string]any{"sub": ownerA, "role": "authenticated"})
		code, _ = get(summaryPath, bad)
		eqv(t, code, 401, "wrong secret")
		pc, _ := control.SignJWT(secret, map[string]any{"role": "service_role", "device_id": "x"})
		code, _ = get(summaryPath, pc)
		eqv(t, code, 403, "PC key")
		code, _ = get("/b/nobody/api/v1/payments?company="+companA, token(ownerA))
		eqv(t, code, 404, "unknown business")
		code, _ = get("/b/apitest/api/v1/payments?company=not-a-uuid", token(ownerA))
		eqv(t, code, 400, "malformed id")
	})

	statementPath := "/b/apitest/api/v1/shops/" + shopA1 + "/statement"
	t.Run("owner gets the statement with running balances", func(t *testing.T) {
		code, body := get(statementPath, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("statement")
		eqv(t, body["ledger_opening"], "1000.00", "ledger opening")
		eqv(t, body["tally_balance"], "1100.00", "tally balance")
		eqv(t, body["reconciled"], true, "reconciled")
		lines := body["lines"].([]any)
		eqv(t, len(lines), 3, "lines")
		newest := lines[0].(map[string]any)
		eqv(t, newest["voucher_number"], "R1", "newest first")
		eqv(t, newest["balance_after"], "1100.00", "balance after receipt")
		eqv(t, lines[2].(map[string]any)["balance_after"], "1500.00", "balance after first bill")
	})

	t.Run("a period brings the balance forward", func(t *testing.T) {
		code, body := get(statementPath+"?from=2026-06-01&to=2026-06-30", token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("statement_period")
		eqv(t, body["opening"], "1500.00", "brought forward")
		eqv(t, body["closing"], "2300.00", "closing")
		eqv(t, body["total_debit"], "800.00", "debits")
		eqv(t, len(body["lines"].([]any)), 1, "June lines")
		code, _ = get(statementPath+"?from=2026-07-01&to=2026-06-01", token(ownerA))
		eqv(t, code, 400, "from after to")
		code, _ = get(statementPath+"?from=yesterday", token(ownerA))
		eqv(t, code, 400, "bad date")
	})

	t.Run("staff need the company's transaction access", func(t *testing.T) {
		code, _ := get(statementPath, token(staffA))
		eqv(t, code, 404, "unassigned staff can't see the shop")
		mustExec(t, db, `insert into public.staff_company_access (user_id, business_id, company_id, full_company, can_view_transactions)
			values ($1, $2, $3, true, true)`, staffA, bizA, companA)
		code, body := get(statementPath, token(staffA))
		eqv(t, code, 200, "assigned staff")
		eqv(t, len(body["lines"].([]any)), 3, "staff lines")
		mustExec(t, db, `update public.staff_company_access set can_view_transactions = false where user_id = $1`, staffA)
		code, body = get(statementPath, token(staffA))
		eqv(t, code, 403, "no transaction access")
		eqv(t, body["error"].(map[string]any)["code"], "NO_TRANSACTIONS", "code")
		code, _ = get(statementPath, token(ownerB))
		eqv(t, code, 404, "another business")
	})

	t.Run("dashboard in one call", func(t *testing.T) {
		mustExec(t, db, `insert into public.sync_state (business_id, company_id, entity_type, last_successful_sync_at, status)
			values ($1, $2, 'company', '2026-07-20 05:00:00+00', 'ok')`, bizA, companA)
		code, body := get("/b/apitest/api/v1/dashboard?company="+companA+"&month=2026-06", token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("dashboard")
		sum := body["summary"].(map[string]any)
		eqv(t, sum["shops"], 2.0, "shops")
		eqv(t, sum["shops_with_dues"], 1.0, "shops with dues")
		eqv(t, sum["total_outstanding"], "1100.00", "outstanding")
		eqv(t, sum["total_credit"], "50.00", "credit")
		eqv(t, body["sync_state"].(map[string]any)["status"], "ok", "sync state")
		sales := body["month_sales"].(map[string]any)
		eqv(t, sales["amount"], "800.00", "June sales")
		eqv(t, sales["bills"], 1.0, "June bills")
		top := body["top_dues"].([]any)
		eqv(t, len(top), 1, "top dues")
		eqv(t, top[0].(map[string]any)["site_name"], "Town", "top due site")

		// Staff without transaction access (set above): totals yes, sales no.
		code, body = get("/b/apitest/api/v1/dashboard?company="+companA, token(staffA))
		eqv(t, code, 200, "staff")
		eqv(t, body["month_sales"], nil, "staff sales hidden")
		code, _ = get("/b/apitest/api/v1/dashboard?company="+companA, token(ownerB))
		eqv(t, code, 404, "another business")
		code, _ = get("/b/apitest/api/v1/dashboard?company="+companA+"&month=June", token(ownerA))
		eqv(t, code, 400, "bad month")
	})

	t.Run("shops list: filters, search, sites, sort", func(t *testing.T) {
		list := func(query string) []string {
			t.Helper()
			code, body := get("/b/apitest/api/v1/shops?company="+companA+query, token(ownerA))
			if code != 200 {
				t.Fatalf("%s: status %d: %v", query, code, body)
			}
			var names []string
			for _, s := range body["shops"].([]any) {
				names = append(names, s.(map[string]any)["name"].(string))
			}
			return names
		}
		join := func(n []string) string { return strings.Join(n, ",") }
		eqv(t, join(list("")), "Alpha Stores,Beta Traders", "default: biggest balance first")
		eqv(t, join(list("&sort=balance_asc")), "Beta Traders,Alpha Stores", "low to high")
		eqv(t, join(list("&balance=owes")), "Alpha Stores", "owes")
		eqv(t, join(list("&balance=credit")), "Beta Traders", "credit")
		eqv(t, join(list("&balance=settled")), "", "settled")
		eqv(t, join(list("&q=beta")), "Beta Traders", "search by name")
		eqv(t, join(list("&q=980000")), "Alpha Stores", "search by phone")
		eqv(t, join(list("&q=%25")), "", "% is matched literally")
		eqv(t, join(list("&sites="+siteA)), "Alpha Stores", "one site")
		eqv(t, join(list("&sites=no-site")), "Beta Traders", "no site")
		eqv(t, join(list("&sites="+siteA+",no-site")), "Alpha Stores,Beta Traders", "site or none")
		eqv(t, join(list("&page=1")), "", "second page empty")
		code, _ := get("/b/apitest/api/v1/shops?company="+companA+"&balance=rich", token(ownerA))
		eqv(t, code, 400, "bad balance filter")
		code, body := get("/b/apitest/api/v1/shops?company="+companA, token(ownerB))
		eqv(t, code, 200, "other business")
		eqv(t, len(body["shops"].([]any)), 0, "other business sees no shops")
	})

	t.Run("shop detail", func(t *testing.T) {
		get("/b/apitest/api/v1/shops?company="+companA, token(ownerA))
		save("shops")
		code, body := get("/b/apitest/api/v1/shops/"+shopA1, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("shop_detail")
		eqv(t, body["name"], "Alpha Stores", "name")
		eqv(t, body["opening_balance_amount"], "1000.00", "opening")
		eqv(t, body["opening_balance_type"], "DR", "opening side")
		eqv(t, body["site_name"], "Town", "site")
		eqv(t, len(body["phones"].([]any)), 0, "phones is a list")
		code, _ = get("/b/apitest/api/v1/shops/"+shopA1, token(ownerB))
		eqv(t, code, 404, "other business")
	})

	t.Run("outstanding report grouped by site", func(t *testing.T) {
		code, body := get("/b/apitest/api/v1/reports/outstanding?company="+companA, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("report_outstanding")
		eqv(t, body["company_name"], "API Co", "company")
		eqv(t, body["total"], "1100.00", "total")
		groups := body["groups"].([]any)
		eqv(t, len(groups), 1, "only sites with dues")
		eqv(t, groups[0].(map[string]any)["site_name"], "Town", "site")
		code, _ = get("/b/apitest/api/v1/reports/outstanding?company="+companA, token(ownerB))
		eqv(t, code, 404, "other business")
	})

	t.Run("overdue report", func(t *testing.T) {
		code, body := get("/b/apitest/api/v1/reports/overdue?company="+companA, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("report_overdue")
		eqv(t, body["total"], "1100.00", "overdue at 30 days")
		shop := body["groups"].([]any)[0].(map[string]any)["shops"].([]any)[0].(map[string]any)
		eqv(t, shop["max_days_overdue"], 50.0, "days")
		eqv(t, shop["bills_visible"], true, "owner sees bills")
		eqv(t, len(shop["bills"].([]any)), 2, "overdue bills")
		_, body = get("/b/apitest/api/v1/reports/overdue?company="+companA+"&credit_days=60", token(ownerA))
		eqv(t, body["total"], "300.00", "overdue at 60 days")
		// Staff without transaction access: amounts yes, bills no.
		code, body = get("/b/apitest/api/v1/reports/overdue?company="+companA, token(staffA))
		eqv(t, code, 200, "staff")
		shop = body["groups"].([]any)[0].(map[string]any)["shops"].([]any)[0].(map[string]any)
		eqv(t, shop["bills_visible"], false, "staff bills hidden")
		eqv(t, shop["bills"], nil, "no bills sent")
	})

	const (
		item1 = "f0000000-0000-0000-0000-00000000a001"
		item2 = "f0000000-0000-0000-0000-00000000a002"
		supA  = "f0000000-0000-0000-0000-00000000b001"
		purA  = "f0000000-0000-0000-0000-00000000c001"
	)
	mustExec(t, db, `insert into public.stock_items (id, business_id, company_id, tally_item_id, name, unit, closing_qty, closing_value,
			reorder_level, synced_at) values
		($1, $3, $4, 'i1', 'TYRE', 'Nos', 3, 300, 0, now()), ($2, $3, $4, 'i2', 'TUBE', 'Nos', 0, 0, 5, now())`, item1, item2, bizA, companA)
	mustExec(t, db, `insert into public.suppliers (id, business_id, company_id, tally_ledger_id, name, payable, synced_at)
		values ($1, $2, $3, 's1', 'Supplier One', 2500, now())`, supA, bizA, companA)
	mustExec(t, db, `insert into public.purchases (id, business_id, company_id, tally_voucher_id, purchase_date, supplier_id, supplier_name,
			voucher_number, total_amount, line_count, synced_at)
		values ($1, $2, $3, 'p1', '2026-07-05', $4, 'Supplier One', 'PB/1', 1180, 1, now())`, purA, bizA, companA, supA)
	mustExec(t, db, `insert into public.purchase_lines (business_id, company_id, purchase_id, line_no, stock_item_id, item_name, qty, unit, rate, amount)
		values ($1, $2, $3, 1, $4, 'TYRE', 10, 'Nos', 100, 1000)`, bizA, companA, purA, item1)
	put := func(path, tok, body string) (int, map[string]any) {
		req, _ := http.NewRequest(http.MethodPut, ts.URL+path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		return do(req)
	}

	t.Run("stock with minimums, status and the alert", func(t *testing.T) {
		code, body := put("/b/apitest/api/v1/stock/minimum", token(ownerA), `{"company":"`+companA+`","items":["`+item1+`"],"min":4}`)
		if code != 200 {
			t.Fatalf("set minimum: %d %v", code, body)
		}
		save("stock_minimum")
		eqv(t, body["changed"], 1.0, "changed")
		code, body = get("/b/apitest/api/v1/stock?company="+companA, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("stock")
		items := body["items"].([]any)
		eqv(t, len(items), 2, "items")
		tube, tyre := items[0].(map[string]any), items[1].(map[string]any) // by name
		eqv(t, tyre["min_qty"], 4.0, "owner's minimum")
		eqv(t, tyre["status"], "low", "3 of 4 is low")
		eqv(t, tyre["closing_value"], "300.00", "owner sees value")
		eqv(t, tube["effective_min"], 5.0, "Tally reorder level")
		eqv(t, tube["status"], "zero", "out of stock")
		alerts := body["alerts"].([]any)
		eqv(t, len(alerts), 2, "alerts")
		eqv(t, alerts[0], item2, "furthest below first")
		sum := body["summary"].(map[string]any)
		eqv(t, sum["value"], "300.00", "stock value")
		eqv(t, sum["by_status"].(map[string]any)["low"], 1.0, "low count")

		code, body = get("/b/apitest/api/v1/stock/"+item1, token(ownerA))
		save("stock_item")
		eqv(t, code, 200, "one item")
		eqv(t, body["status"], "low", "item status")
		code, body = get("/b/apitest/api/v1/stock/"+item1+"/purchases", token(ownerA))
		save("stock_item_purchases")
		eqv(t, code, 200, "item purchases")
		bills := body["purchases"].([]any)
		eqv(t, len(bills), 1, "item bills")
		eqv(t, len(bills[0].(map[string]any)["purchase_lines"].([]any)), 1, "item lines")

		// Staff (assigned above): quantities and alerts, no costs, can't set minimums or see purchases.
		code, body = get("/b/apitest/api/v1/stock?company="+companA, token(staffA))
		eqv(t, code, 200, "staff stock")
		staffTyre := body["items"].([]any)[1].(map[string]any)
		eqv(t, staffTyre["status"], "low", "staff see the alert status")
		_, hasValue := staffTyre["closing_value"]
		eqv(t, hasValue, false, "no value for staff")
		code, body = put("/b/apitest/api/v1/stock/minimum", token(staffA), `{"company":"`+companA+`","items":["`+item1+`"],"min":9}`)
		eqv(t, code, 403, "staff can't set minimum")
		eqv(t, body["error"].(map[string]any)["code"], "NOT_OWNER", "code")
		code, _ = get("/b/apitest/api/v1/stock/"+item1+"/purchases", token(staffA))
		eqv(t, code, 403, "staff can't see purchases")
		code, body = put("/b/apitest/api/v1/stock/minimum", token(ownerA), `{"company":"`+companA+`","items":["`+item1+`"],"min":-1}`)
		eqv(t, code, 400, "negative minimum")
		code, _ = put("/b/apitest/api/v1/stock/minimum", token(ownerA), `{"company":"`+companA+`","items":[]}`)
		eqv(t, code, 400, "no items")
		code, _ = put("/b/apitest/api/v1/stock/minimum", token(ownerA), `not json`)
		eqv(t, code, 400, "bad body")
		code, _ = put("/b/apitest/api/v1/stock/minimum", token(ownerA), `{"company":"`+companA+`","items":["`+item1+`"],"min":null}`)
		eqv(t, code, 200, "remove minimum")
		_, body = get("/b/apitest/api/v1/stock/"+item1, token(ownerA))
		eqv(t, body["min_qty"], nil, "removed")
		eqv(t, body["status"], "in_stock", "no minimum, in stock")
	})

	t.Run("purchases and suppliers", func(t *testing.T) {
		code, body := get("/b/apitest/api/v1/purchases?company="+companA, token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("purchases")
		bills := body["purchases"].([]any)
		eqv(t, len(bills), 1, "bills")
		eqv(t, bills[0].(map[string]any)["voucher_number"], "PB/1", "voucher")
		_, body = get("/b/apitest/api/v1/purchases?company="+companA+"&q=pb/1", token(ownerA))
		eqv(t, len(body["purchases"].([]any)), 1, "search")
		_, body = get("/b/apitest/api/v1/purchases?company="+companA+"&q=nothing", token(ownerA))
		eqv(t, len(body["purchases"].([]any)), 0, "search miss")
		code, body = get("/b/apitest/api/v1/purchases/"+purA, token(ownerA))
		save("purchase_detail")
		eqv(t, code, 200, "bill detail")
		eqv(t, len(body["purchase_lines"].([]any)), 1, "lines")
		_, body = get("/b/apitest/api/v1/purchases/months?company="+companA+"&from=2026-01-01", token(ownerA))
		save("purchase_months")
		months := body["months"].([]any)
		eqv(t, len(months), 1, "months")
		eqv(t, months[0].(map[string]any)["month"], "2026-07-01", "month")
		eqv(t, months[0].(map[string]any)["bills"], 1.0, "bills in month")
		code, body = get("/b/apitest/api/v1/suppliers?company="+companA, token(ownerA))
		save("suppliers")
		eqv(t, code, 200, "suppliers")
		eqv(t, len(body["suppliers"].([]any)), 1, "supplier count")
		code, body = get("/b/apitest/api/v1/suppliers/"+supA, token(ownerA))
		save("supplier_detail")
		eqv(t, code, 200, "supplier")
		eqv(t, body["payable"], 2500.0, "payable")
		for _, path := range []string{"/purchases?company=" + companA, "/purchases/" + purA, "/suppliers?company=" + companA} {
			code, _ = get("/b/apitest/api/v1"+path, token(staffA))
			eqv(t, code, 403, "staff: "+path)
		}
		code, _ = get("/b/apitest/api/v1/purchases/"+purA, token(ownerB))
		eqv(t, code, 404, "other business")
	})

	t.Run("me, companies, access, areas, service status, sync", func(t *testing.T) {
		code, body := get("/b/apitest/api/v1/me", token(ownerA))
		if code != 200 {
			t.Fatalf("status %d: %v", code, body)
		}
		save("me")
		eqv(t, body["user"].(map[string]any)["role"], "OWNER", "role")
		eqv(t, body["business_name"], "API Biz", "business")
		_, body = get("/b/apitest/api/v1/companies", token(ownerA))
		save("companies")
		eqv(t, len(body["companies"].([]any)), 1, "owner companies")
		_, body = get("/b/apitest/api/v1/companies", token(ownerB))
		eqv(t, len(body["companies"].([]any)), 0, "other business sees none of ours")
		_, body = get("/b/apitest/api/v1/me/access", token(staffA))
		save("me_access")
		access := body["access"].([]any)
		eqv(t, len(access), 1, "staff access")
		eqv(t, access[0].(map[string]any)["can_view_transactions"], false, "as set above")
		code, body = get("/b/apitest/api/v1/companies/"+companA+"/areas", token(ownerA))
		save("company_areas")
		eqv(t, code, 200, "areas")
		eqv(t, len(body["areas"].([]any)), 0, "no areas in test shops")
		code, body = get("/b/apitest/api/v1/service-status", token(ownerA))
		save("service_status")
		eqv(t, code, 200, "service status")
		eqv(t, body["service_status"], nil, "none set")
		_, body = get("/b/apitest/api/v1/sync/logs", token(ownerA))
		save("sync_logs")
		eqv(t, len(body["logs"].([]any)), 1, "seeded sync log")
		eqv(t, body["logs"].([]any)[0].(map[string]any)["records_processed"], 12.0, "log fields")
		_, body = get("/b/apitest/api/v1/sync/connections", token(ownerA))
		save("sync_connections")
		eqv(t, len(body["connections"].([]any)), 1, "seeded PC")
		_, body = get("/b/apitest/api/v1/sync/connections", token(staffA))
		eqv(t, len(body["connections"].([]any)), 0, "staff see no PCs")
		code, _ = get("/b/apitest/api/v1/sync/logs?limit=0", token(ownerA))
		eqv(t, code, 400, "bad limit")
	})

	send := func(method, path, tok, body string) (int, map[string]any) {
		req, _ := http.NewRequest(method, ts.URL+path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		return do(req)
	}

	t.Run("sites: create, rename, shops, report, delete", func(t *testing.T) {
		code, body := send("POST", "/b/apitest/api/v1/sites", token(ownerA), `{"company":"`+companA+`","name":" Hills ","shops":["`+shopA2+`"]}`)
		if code != 200 {
			t.Fatalf("create: %d %v", code, body)
		}
		save("site_created")
		hills := body["id"].(string)
		code, body = send("POST", "/b/apitest/api/v1/sites", token(ownerA), `{"company":"`+companA+`","name":"Town","shops":[]}`)
		eqv(t, code, 409, "duplicate name")
		eqv(t, body["error"].(map[string]any)["code"], "NAME_TAKEN", "code")
		code, _ = send("POST", "/b/apitest/api/v1/sites", token(staffA), `{"company":"`+companA+`","name":"Staff site","shops":[]}`)
		eqv(t, code, 403, "staff can't create sites")

		_, body = get("/b/apitest/api/v1/sites?company="+companA, token(ownerA))
		save("sites")
		eqv(t, len(body["sites"].([]any)), 2, "two sites")
		_, body = get("/b/apitest/api/v1/sites/"+hills+"/shops", token(ownerA))
		save("site_shops")
		eqv(t, body["shops"].([]any)[0].(map[string]any)["name"], "Beta Traders", "shop moved in")
		_, body = get("/b/apitest/api/v1/companies/"+companA+"/site-shops", token(ownerA))
		save("company_site_shops")
		eqv(t, len(body["shops"].([]any)), 2, "editor shops")

		code, _ = send("PATCH", "/b/apitest/api/v1/sites/"+hills, token(ownerA), `{"name":"High Range"}`)
		eqv(t, code, 200, "rename")
		code, _ = send("PUT", "/b/apitest/api/v1/sites/"+hills+"/shops", token(ownerA), `{"shops":[]}`)
		eqv(t, code, 200, "empty the site")
		_, body = get("/b/apitest/api/v1/sites/"+hills+"/shops", token(ownerA))
		eqv(t, len(body["shops"].([]any)), 0, "site emptied")

		code, body = get("/b/apitest/api/v1/reports/sites?company="+companA+"&from=2026-04-01&to=2026-07-31", token(ownerA))
		if code != 200 {
			t.Fatalf("site report: %d %v", code, body)
		}
		save("report_sites")
		eqv(t, len(body["rows"].([]any)) > 0, true, "report rows")

		code, _ = send("DELETE", "/b/apitest/api/v1/sites/"+hills, token(ownerA), ``)
		eqv(t, code, 200, "delete")
		code, _ = send("DELETE", "/b/apitest/api/v1/sites/"+hills, token(ownerA), ``)
		eqv(t, code, 404, "already gone")
	})

	t.Run("shop locations", func(t *testing.T) {
		path := "/b/apitest/api/v1/shops/" + shopA1 + "/location"
		_, body := get(path, token(ownerA))
		eqv(t, body["location"], nil, "no pin yet")
		code, body := send("PUT", path, token(ownerA), `{"latitude":9.85,"longitude":76.97,"radius_m":50}`)
		if code != 200 {
			t.Fatalf("set: %d %v", code, body)
		}
		_, body = get(path, token(ownerA))
		save("shop_location")
		eqv(t, body["location"].(map[string]any)["radius_m"], 50.0, "radius")
		code, _ = send("PUT", path, token(staffA), `{"latitude":9.85,"longitude":76.97,"radius_m":50}`)
		eqv(t, code, 403, "staff can't set pins")
		code, _ = send("DELETE", path, token(ownerA), ``)
		eqv(t, code, 200, "clear")
		_, body = get(path, token(ownerA))
		eqv(t, body["location"], nil, "cleared")
		_, body = get("/b/apitest/api/v1/location-suggestions", token(ownerA))
		save("location_suggestions")
		eqv(t, len(body["suggestions"].([]any)), 0, "no suggestions")
	})

	t.Run("visits: plans, tasks, check-in, notes", func(t *testing.T) {
		var today string
		if err := db.QueryRow(context.Background(), `select public.business_today()::text`).Scan(&today); err != nil {
			t.Fatal(err)
		}
		plan := `{"site":"` + siteA + `","staff":"` + staffA + `","date":"` + today + `"}`
		code, body := send("POST", "/b/apitest/api/v1/visits/plans", token(ownerA), plan)
		eqv(t, code, 400, "check-in off")
		eqv(t, strings.Contains(body["error"].(map[string]any)["message"].(string), "Must check in"), true, "explains why")
		mustExec(t, db, `update public.users set requires_check_in = true where id = $1`, staffA)
		code, body = send("POST", "/b/apitest/api/v1/visits/plans", token(ownerA), plan)
		if code != 200 {
			t.Fatalf("plan: %d %v", code, body)
		}
		code, _ = send("POST", "/b/apitest/api/v1/visits/plans", token(staffA), plan)
		eqv(t, code, 403, "staff can't plan")
		_, body = get("/b/apitest/api/v1/visits/plans?company="+companA, token(ownerA))
		save("visit_plans")
		plans := body["plans"].([]any)
		eqv(t, len(plans), 1, "plans")
		planID := plans[0].(map[string]any)["id"].(string)
		eqv(t, plans[0].(map[string]any)["sites"].(map[string]any)["name"], "Town", "site name")

		code, body = get("/b/apitest/api/v1/visits/tasks?from="+today+"&to="+today, token(staffA))
		if code != 200 {
			t.Fatalf("tasks: %d %v", code, body)
		}
		save("visit_tasks")
		tasks := body["tasks"].([]any)
		eqv(t, len(tasks), 1, "today's task: Alpha Stores in Town")
		taskID := tasks[0].(map[string]any)["task_id"].(string)

		code, body = send("POST", "/b/apitest/api/v1/visits/tasks/"+taskID+"/check-in", token(staffA),
			`{"latitude":9.85,"longitude":76.97,"accuracy_m":8,"is_mocked":false,"developer_mode":false}`)
		if code != 200 {
			t.Fatalf("check-in: %d %v", code, body)
		}
		save("check_in")
		id, _ := body["visit_id"].(string)
		eqv(t, id != "", true, "check-in made a visit")
		{
			code, _ = send("POST", "/b/apitest/api/v1/visits/"+id+"/note", token(staffA), `{"note":"Paid next week"}`)
			eqv(t, code, 200, "add note")
			code, _ = send("POST", "/b/apitest/api/v1/visits/"+id+"/note", token(staffA), `{"note":"again"}`)
			eqv(t, code, 403, "one note per visit")
			code, body = get("/b/apitest/api/v1/visits/"+id, token(ownerA))
			save("visit")
			eqv(t, code, 200, "visit detail")
			eqv(t, body["visit"] != nil, true, "visit found")
		}
		_, body = get("/b/apitest/api/v1/visits/tasks/"+taskID+"/failed-attempts", token(ownerA))
		save("failed_attempts")
		_, isList := body["attempts"].([]any)
		eqv(t, isList, true, "attempts list")

		code, _ = send("PATCH", "/b/apitest/api/v1/visits/plans/"+planID, token(ownerA), `{"active":false}`)
		eqv(t, code, 200, "pause plan")
		code, _ = send("DELETE", "/b/apitest/api/v1/visits/plans/"+planID, token(ownerA), ``)
		eqv(t, code, 200, "delete plan")
		code, _ = get("/b/apitest/api/v1/visits/tasks?from="+today, token(staffA))
		eqv(t, code, 400, "to is required")
	})

	t.Run("staff management", func(t *testing.T) {
		defer mustExec(t, db, `delete from auth.users where email like '%@new.test'`)
		body := `{"name":"New Staff","email":"New@New.test","password":"secret123","requires_check_in":true,
			"companies":[{"company_id":"` + companA + `","full_company":false,"site_ids":["` + siteA + `"],"can_view_transactions":false}]}`
		code, out := send("POST", "/b/apitest/api/v1/staff", token(ownerA), body)
		if code != 200 {
			t.Fatalf("create: %d %v", code, out)
		}
		save("staff_created")
		newID := out["id"].(string)
		eqv(t, out["email"], "new@new.test", "email normalised")
		eqv(t, logins[newID]["user_metadata"].(map[string]any)["must_change_password"], true, "must change password")

		code, out = send("POST", "/b/apitest/api/v1/staff", token(ownerA), body)
		eqv(t, code, 409, "same email again")
		eqv(t, out["error"].(map[string]any)["code"], "EMAIL_TAKEN", "code")
		code, _ = send("POST", "/b/apitest/api/v1/staff", token(staffA), body)
		eqv(t, code, 403, "staff can't add staff")
		for _, bad := range []string{
			`{"name":"","email":"a@new.test","password":"secret123","companies":[{"company_id":"` + companA + `"}]}`,
			`{"name":"A","email":"not-an-email","password":"secret123","companies":[{"company_id":"` + companA + `"}]}`,
			`{"name":"A","email":"a@new.test","password":"short","companies":[{"company_id":"` + companA + `"}]}`,
			`{"name":"A","email":"a@new.test","password":"secret123","companies":[]}`,
			`{"name":"A","email":"a@new.test","password":"secret123","companies":[{"company_id":"c0000000-0000-0000-0000-00000000dead"}]}`,
			`{"name":"A","email":"a@new.test","password":"secret123","companies":[{"company_id":"` + companA + `","full_company":false,"site_ids":[]}]}`,
		} {
			code, _ = send("POST", "/b/apitest/api/v1/staff", token(ownerA), bad)
			eqv(t, code, 400, "invalid: "+bad)
		}

		code, out = get("/b/apitest/api/v1/staff", token(ownerA))
		if code != 200 {
			t.Fatalf("list: %d %v", code, out)
		}
		save("staff")
		list := out["staff"].([]any)
		eqv(t, list[0].(map[string]any)["role"], "OWNER", "owner first")
		var created map[string]any
		for _, m := range list {
			if m.(map[string]any)["id"] == newID {
				created = m.(map[string]any)
			}
		}
		comp := created["companies"].([]any)[0].(map[string]any)
		eqv(t, comp["full_company"], false, "site-limited")
		eqv(t, comp["site_ids"].([]any)[0], siteA, "site kept")
		eqv(t, created["requires_check_in"], true, "check-in on")
		code, _ = get("/b/apitest/api/v1/staff", token(staffA))
		eqv(t, code, 403, "staff can't list staff")

		staffPath := "/b/apitest/api/v1/staff/" + newID
		code, _ = send("PATCH", staffPath, token(ownerA), `{"name":"Renamed"}`)
		eqv(t, code, 200, "rename")
		code, _ = send("PUT", staffPath+"/companies", token(ownerA), `{"companies":[{"company_id":"`+companA+`"}]}`)
		eqv(t, code, 200, "full company")
		code, _ = send("PUT", staffPath+"/check-in", token(ownerA), `{"required":false}`)
		eqv(t, code, 200, "check-in off")
		code, _ = send("PUT", staffPath+"/active", token(ownerA), `{"active":false}`)
		eqv(t, code, 200, "disable")
		eqv(t, logins[newID]["ban_duration"], banForever, "login blocked")
		code, _ = send("PUT", staffPath+"/active", token(ownerA), `{"active":true}`)
		eqv(t, code, 200, "enable")
		eqv(t, logins[newID]["ban_duration"], "none", "login unblocked")
		code, _ = send("POST", staffPath+"/password", token(ownerA), `{"password":"another123"}`)
		eqv(t, code, 200, "reset password")
		eqv(t, logins[newID]["user_metadata"].(map[string]any)["must_change_password"], true, "must change again")
		code, _ = send("PATCH", "/b/apitest/api/v1/staff/"+ownerA, token(ownerA), `{"name":"Me"}`)
		eqv(t, code, 403, "owner accounts not here")
		code, _ = send("PATCH", "/b/apitest/api/v1/staff/"+ownerB, token(ownerA), `{"name":"Them"}`)
		eqv(t, code, 404, "other business's user")
		var name string
		_ = db.QueryRow(context.Background(), `select name from public.users where id = $1`, newID).Scan(&name)
		eqv(t, name, "Renamed", "renamed in the database")
	})

	t.Run("a paused business gets 402", func(t *testing.T) {
		mustExec(t, db, `insert into public.service_status (status, message, contact) values ('suspended', 'Paused for testing', '98000 00000')`)
		defer mustExec(t, db, `delete from public.service_status`)
		code, body := get(summaryPath, token(ownerA))
		eqv(t, code, 402, "status")
		e := body["error"].(map[string]any)
		eqv(t, e["code"], "SUBSCRIPTION_ENDED", "code")
		eqv(t, e["details"], "Paused for testing", "details")
		eqv(t, e["hint"], "98000 00000", "hint")
	})
}

func mustExec(t *testing.T, db *pgx.Conn, sql string, args ...any) {
	t.Helper()
	if _, err := db.Exec(context.Background(), sql, args...); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
}

func eqv(t *testing.T, got, want any, what string) {
	t.Helper()
	if got != want {
		t.Fatalf("%s = %v (%T), want %v (%T)", what, got, got, want, want)
	}
}
