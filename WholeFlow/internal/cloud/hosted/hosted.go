// Package hosted is the Tally PC's cloud.Provider for a business on the
// WholeFlow server: it uploads through the app API (/b/<slug>/api/v1/pc/…)
// with this PC's key from the activation. It replaces the PostgREST client.
package hosted

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
	"strings"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/cloud/wire"
)

// batch is how many rows go in one upload (well under the server's limit).
const batch = 500

// Storage is the cloud.Provider for one business on the WholeFlow server.
type Storage struct {
	base       string // https://api.example/b/<slug>/api/v1/pc
	key        string
	businessID string
	http       *http.Client
	log        *slog.Logger
}

// Config: the business's address (https://api.example/b/<slug>), this PC's
// key and the business id from the activation.
type Config struct {
	URL        string
	Key        string
	BusinessID string
	Timeout    time.Duration
}

func New(cfg Config, log *slog.Logger) (*Storage, error) {
	if cfg.Timeout <= 0 {
		cfg.Timeout = 60 * time.Second
	}
	base := strings.TrimRight(strings.TrimSpace(cfg.URL), "/")
	if base == "" || cfg.Key == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "the business address and this PC's key are required"}
	}
	u, err := url.Parse(base)
	if err != nil || u.Host == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "the business address is not a valid URL"}
	}
	if h := u.Hostname(); u.Scheme != "https" && h != "localhost" && h != "127.0.0.1" && h != "::1" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "the business address must use https"}
	}
	if strings.TrimSpace(cfg.BusinessID) == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "business id is required"}
	}
	// Older activations stored the data API's address (…/rest/v1).
	base = strings.TrimSuffix(base, "/rest/v1")
	return &Storage{base: base + "/api/v1/pc", key: cfg.Key, businessID: cfg.BusinessID,
		http: &http.Client{Timeout: cfg.Timeout}, log: log}, nil
}

func (s *Storage) Name() string { return "wholeflow" }

// String describes the target without revealing the key.
func (s *Storage) String() string {
	return fmt.Sprintf("wholeflow %s (business %s)", s.base, s.businessID)
}

// call sends one request (body as JSON when not nil) and decodes the answer into out.
func (s *Storage) call(ctx context.Context, op, method, path string, query url.Values, body, out any) error {
	u := s.base + "/" + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	var rd io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return &cloud.Error{Kind: cloud.KindError, Op: op, Err: err}
		}
		rd = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, rd)
	if err != nil {
		return &cloud.Error{Kind: cloud.KindError, Op: op, Err: err}
	}
	req.Header.Set("Authorization", "Bearer "+s.key)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	start := time.Now()
	res, err := s.http.Do(req)
	if err != nil {
		kind := cloud.KindUnreachable
		var ne net.Error
		if errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &ne) && ne.Timeout()) {
			kind = cloud.KindTimeout
		}
		msg := strings.ReplaceAll(err.Error(), s.key, "[redacted]")
		s.log.Error("cloud request failed", "op", op, "method", method, "path", path, "kind", kind, "error", msg,
			"duration_ms", time.Since(start).Milliseconds())
		return &cloud.Error{Kind: kind, Op: op, Err: errors.New(msg)}
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, 64<<20))
	if err != nil {
		return &cloud.Error{Kind: cloud.KindUnreachable, Op: op, Err: err}
	}
	s.log.Info("cloud request", "op", op, "method", method, "path", path, "status", res.StatusCode,
		"bytes", len(raw), "duration_ms", time.Since(start).Milliseconds())
	if res.StatusCode/100 == 2 {
		if out != nil {
			if err := json.Unmarshal(raw, out); err != nil {
				return &cloud.Error{Kind: cloud.KindError, Op: op, Msg: "unexpected response", Err: err}
			}
		}
		return nil
	}
	return classify(op, res.StatusCode, raw)
}

// classify turns an error answer {"error": {"code", "message", "details"}} into a cloud.Error.
func classify(op string, status int, raw []byte) error {
	var e struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
			Details string `json:"details"`
		} `json:"error"`
	}
	_ = json.Unmarshal(raw, &e)
	msg := e.Error.Message
	if e.Error.Details != "" {
		msg += " (" + e.Error.Details + ")"
	}
	if msg == "" {
		msg = strings.TrimSpace(string(raw))
		if len(msg) > 300 {
			msg = msg[:300] + "…"
		}
	}
	switch {
	case status == http.StatusPaymentRequired:
		return &cloud.Error{Kind: cloud.KindSubscriptionEnded, Op: op, Msg: msg}
	case status == http.StatusForbidden && e.Error.Message == "device_revoked":
		return &cloud.Error{Kind: cloud.KindDeviceRevoked, Op: op, Msg: msg}
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return &cloud.Error{Kind: cloud.KindAuth, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", status, msg)}
	case status == http.StatusNotFound:
		return &cloud.Error{Kind: cloud.KindNotFound, Op: op, Msg: fmt.Sprintf("HTTP 404: %s", msg)}
	case status == http.StatusGatewayTimeout:
		return &cloud.Error{Kind: cloud.KindTimeout, Op: op, Msg: msg}
	case status >= 500:
		return &cloud.Error{Kind: cloud.KindUnreachable, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", status, msg)}
	}
	return &cloud.Error{Kind: cloud.KindError, Op: op, Msg: fmt.Sprintf("HTTP %d: %s", status, msg)}
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

func nullable(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func nonNil(xs []string) []string {
	if xs == nil {
		return []string{}
	}
	return xs
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// ---------------------------------------------------------------- cloud.Provider

// Authenticate proves the key works and the business exists.
func (s *Storage) Authenticate(ctx context.Context) error {
	err := s.call(ctx, "authenticate", http.MethodPost, "authenticate", nil, wire.Authenticate{BusinessID: s.businessID}, nil)
	var ce *cloud.Error
	if errors.As(err, &ce) && ce.Kind == cloud.KindNotFound {
		return &cloud.Error{Kind: cloud.KindNotFound, Op: "authenticate", Msg: "business " + s.businessID + " does not exist on the server"}
	}
	return err
}

func (s *Storage) UpsertConnection(ctx context.Context, c cloud.Connection) (string, error) {
	var out wire.ID
	err := s.call(ctx, "upsert-connection", http.MethodPost, "connection", nil, wire.Connection{
		BusinessID: c.BusinessID, MachineIdentifier: c.MachineIdentifier, Hostname: c.Hostname, TallyHost: c.TallyHost,
		TallyPort: c.TallyPort, Status: c.Status, AppVersion: c.AppVersion, LastSeenAt: c.LastSeenAt.UTC()}, &out)
	return out.ID, err
}

func (s *Storage) UpsertCompany(ctx context.Context, c cloud.Company) (string, error) {
	var out wire.ID
	err := s.call(ctx, "upsert-company", http.MethodPost, "company", nil, wire.Company{
		BusinessID: c.BusinessID, ConnectionID: nullable(c.ConnectionID), TallyCompanyID: c.TallyCompanyID,
		CompanyName: c.Name, CompanyNumber: c.Number, FinancialYearFrom: nullable(c.FinancialYearFrom), BooksFrom: nullable(c.BooksFrom),
		EndingAt: nullable(c.EndingAt), PeriodFrom: nullable(c.PeriodFrom), PeriodTo: nullable(c.PeriodTo),
		LastVoucherDate: nullable(c.LastVoucherDate), Enabled: c.Enabled, SyncEnabled: c.SyncEnabled, SyncStatus: c.SyncStatus,
		LastSyncAt: c.LastSyncAt}, &out)
	return out.ID, err
}

// upsertIDs uploads rows in batches and collects key → id.
func upsertIDs[T any](s *Storage, ctx context.Context, op, path string, rows []T) (map[string]string, error) {
	ids := make(map[string]string, len(rows))
	for _, b := range chunk(rows, batch) {
		var out wire.IDs
		if err := s.call(ctx, op, http.MethodPost, path, nil, wire.Batch[T]{Rows: b}, &out); err != nil {
			return nil, err
		}
		for k, v := range out.IDs {
			ids[k] = v
		}
	}
	return ids, nil
}

func (s *Storage) refs(ctx context.Context, op, path, companyID string) ([]cloud.Ref, error) {
	var out wire.Refs
	if err := s.call(ctx, op, http.MethodGet, path, url.Values{"company": {companyID}}, nil, &out); err != nil {
		return nil, err
	}
	refs := make([]cloud.Ref, len(out.Refs))
	for i, r := range out.Refs {
		refs[i] = cloud.Ref{ID: r.ID, Key: r.Key}
	}
	return refs, nil
}

func (s *Storage) softDelete(ctx context.Context, op, path string, ids []string) error {
	for _, b := range chunk(ids, 5000) {
		if err := s.call(ctx, op, http.MethodPost, path+"/delete", nil, wire.Delete{IDs: b}, nil); err != nil {
			return err
		}
	}
	return nil
}

func (s *Storage) UpsertShops(ctx context.Context, shops []cloud.Shop) (map[string]string, error) {
	rows := make([]wire.Shop, 0, len(shops))
	for _, sh := range shops {
		rows = append(rows, wire.Shop{
			BusinessID: sh.BusinessID, CompanyID: sh.CompanyID, TallyLedgerID: sh.TallyLedgerID,
			TallyMasterID: sh.TallyMasterID, TallyAlterID: sh.TallyAlterID, Name: sh.Name, Aliases: nonNil(sh.Aliases),
			LedgerGroup: sh.Group, Phone: sh.Phone, Phones: nonNil(sh.Phones), PhoneSource: sh.PhoneSource,
			ContactPerson: sh.ContactPerson, Email: sh.Email, GSTIN: sh.GSTIN, GSTRegType: sh.GSTRegType,
			Address: strings.Join(sh.Address, "\n"), AddressLines: nonNil(sh.Address), State: sh.State, Pincode: sh.Pincode,
			Country: sh.Country, Area: sh.Area, OpeningAmount: sh.OpeningAmount, OpeningType: sh.OpeningType,
			BalanceAmount: sh.BalanceAmount, BalanceType: sh.BalanceType, Receivable: sh.Receivable, SyncedAt: sh.SyncedAt.UTC(),
		})
	}
	return upsertIDs(s, ctx, "upsert-shops", "shops", rows)
}

func (s *Storage) ListShops(ctx context.Context, companyID string) ([]cloud.ShopRef, error) {
	refs, err := s.refs(ctx, "list-shops", "shops", companyID)
	out := make([]cloud.ShopRef, len(refs))
	for i, r := range refs {
		out[i] = cloud.ShopRef{ID: r.ID, TallyLedgerID: r.Key}
	}
	return out, err
}

func (s *Storage) SoftDeleteShops(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-shops", "shops", ids)
}

func (s *Storage) UpsertTransactions(ctx context.Context, txns []cloud.Transaction) error {
	for _, b := range chunk(txns, batch) {
		rows := make([]wire.Transaction, 0, len(b))
		for _, t := range b {
			rows = append(rows, wire.Transaction{
				BusinessID: t.BusinessID, CompanyID: t.CompanyID, ShopID: t.ShopID, TallyVoucherID: t.TallyVoucherID,
				TallyLedgerID: t.TallyLedgerID, TallyMasterID: t.TallyMasterID, TallyAlterID: t.TallyAlterID,
				TransactionDate: t.Date, VoucherNumber: t.VoucherNumber, VoucherType: t.VoucherType, BaseVoucherType: t.BaseVoucherType,
				Category: t.Category, Narration: t.Narration, Debit: t.Debit, Credit: t.Credit, Amount: t.Amount, SyncedAt: t.SyncedAt.UTC(),
			})
		}
		if err := s.call(ctx, "upsert-transactions", http.MethodPost, "transactions", nil, wire.Batch[wire.Transaction]{Rows: rows}, nil); err != nil {
			return err
		}
	}
	return nil
}

func (s *Storage) ListTransactions(ctx context.Context, companyID string, voucherIDs []string) ([]cloud.TransactionRef, error) {
	var out []cloud.TransactionRef
	ask := func(ids []string) error {
		var res wire.TxnRefs
		if err := s.call(ctx, "list-transactions", http.MethodPost, "transactions/refs", nil,
			wire.TxnQuery{CompanyID: companyID, VoucherIDs: ids}, &res); err != nil {
			return err
		}
		for _, r := range res.Refs {
			out = append(out, cloud.TransactionRef{ID: r.ID, TallyVoucherID: r.TallyVoucherID, TallyLedgerID: r.TallyLedgerID})
		}
		return nil
	}
	if voucherIDs == nil {
		return out, ask(nil)
	}
	for _, b := range chunk(voucherIDs, 5000) {
		if err := ask(b); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func (s *Storage) SoftDeleteTransactions(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-transactions", "transactions", ids)
}

func (s *Storage) GetSyncState(ctx context.Context, companyID, entityType string) (*cloud.SyncState, error) {
	var out wire.SyncStateAnswer
	if err := s.call(ctx, "get-sync-state", http.MethodGet, "sync-state", url.Values{"company": {companyID}, "entity": {entityType}},
		nil, &out); err != nil {
		return nil, err
	}
	if out.State == nil {
		return nil, nil
	}
	r := out.State
	return &cloud.SyncState{BusinessID: r.BusinessID, CompanyID: r.CompanyID, EntityType: r.EntityType,
		LastSuccessfulSyncAt: r.LastSuccessfulSyncAt, LastAttemptAt: r.LastAttemptAt, LastCursor: r.LastCursor,
		RecordsProcessed: r.RecordsProcessed, Status: r.Status, ErrorCode: r.ErrorCode, ErrorMessage: r.ErrorMessage}, nil
}

func (s *Storage) UpdateSyncState(ctx context.Context, st cloud.SyncState) error {
	return s.call(ctx, "update-sync-state", http.MethodPut, "sync-state", nil, wire.SyncState{
		BusinessID: st.BusinessID, CompanyID: st.CompanyID, EntityType: st.EntityType,
		LastSuccessfulSyncAt: st.LastSuccessfulSyncAt, LastAttemptAt: st.LastAttemptAt.UTC(), LastCursor: st.LastCursor,
		RecordsProcessed: st.RecordsProcessed, Status: st.Status, ErrorCode: st.ErrorCode,
		ErrorMessage: truncate(st.ErrorMessage, 2000)}, nil)
}

func (s *Storage) CreateSyncLog(ctx context.Context, l cloud.SyncLog) error {
	return s.call(ctx, "create-sync-log", http.MethodPost, "sync-logs", nil, wire.SyncLog{
		BusinessID: l.BusinessID, CompanyID: l.CompanyID, StartedAt: l.StartedAt.UTC(), CompletedAt: l.CompletedAt.UTC(),
		Status: l.Status, Mode: l.Mode, RecordsProcessed: l.RecordsProcessed, RecordsCreated: l.RecordsCreated,
		RecordsUpdated: l.RecordsUpdated, RecordsDeleted: l.RecordsDeleted, RecordsFailed: l.RecordsFailed,
		ShopsProcessed: l.ShopsProcessed, TransactionsFetched: l.TransactionsFetched, ErrorCode: l.ErrorCode,
		ErrorMessage: truncate(l.ErrorMessage, 2000)}, nil)
}

// ---------------------------------------------------------------- cloud.PurchasingProvider

func (s *Storage) UpsertSuppliers(ctx context.Context, sups []cloud.Supplier) (map[string]string, error) {
	rows := make([]wire.Supplier, 0, len(sups))
	for _, x := range sups {
		rows = append(rows, wire.Supplier{
			BusinessID: x.BusinessID, CompanyID: x.CompanyID, TallyLedgerID: x.TallyLedgerID, TallyMasterID: x.TallyMasterID,
			TallyAlterID: x.TallyAlterID, Name: x.Name, Aliases: nonNil(x.Aliases), LedgerGroup: x.Group, Phone: x.Phone,
			Phones: nonNil(x.Phones), ContactPerson: x.ContactPerson, Email: x.Email, GSTIN: x.GSTIN, GSTRegType: x.GSTRegType,
			Address: strings.Join(x.Address, "\n"), AddressLines: nonNil(x.Address), State: x.State, Pincode: x.Pincode,
			Country: x.Country, OpeningAmount: x.OpeningAmount, OpeningType: x.OpeningType, BalanceAmount: x.BalanceAmount,
			BalanceType: x.BalanceType, Payable: x.Payable, SyncedAt: x.SyncedAt.UTC(),
		})
	}
	return upsertIDs(s, ctx, "upsert-suppliers", "suppliers", rows)
}

func (s *Storage) ListSuppliers(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.refs(ctx, "list-suppliers", "suppliers", companyID)
}

func (s *Storage) SoftDeleteSuppliers(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-suppliers", "suppliers", ids)
}

func (s *Storage) UpsertStockItems(ctx context.Context, items []cloud.StockItem) (map[string]string, error) {
	rows := make([]wire.StockItem, 0, len(items))
	for _, x := range items {
		rows = append(rows, wire.StockItem{
			BusinessID: x.BusinessID, CompanyID: x.CompanyID, TallyItemID: x.TallyItemID, Name: x.Name, Aliases: nonNil(x.Aliases),
			StockGroup: x.Group, Category: x.Category, Unit: x.Unit, GSTApplicable: x.GST, OpeningQty: x.OpeningQty,
			OpeningValue: x.OpeningValue, ClosingQty: x.ClosingQty, ClosingRate: x.ClosingRate, ClosingValue: x.ClosingValue,
			ReorderLevel: x.ReorderLevel, MinOrderQty: x.MinOrderQty, StockStatus: x.Status, SyncedAt: x.SyncedAt.UTC(),
		})
	}
	return upsertIDs(s, ctx, "upsert-stock-items", "stock-items", rows)
}

func (s *Storage) ListStockItems(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.refs(ctx, "list-stock-items", "stock-items", companyID)
}

func (s *Storage) SoftDeleteStockItems(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-stock-items", "stock-items", ids)
}

// UpsertPurchases uploads bills with their lines; the server replaces each
// bill's lines in the same transaction.
func (s *Storage) UpsertPurchases(ctx context.Context, ps []cloud.Purchase) error {
	for _, b := range chunk(ps, 100) {
		bills := make([]wire.PurchaseWithLines, 0, len(b))
		for _, p := range b {
			le := p.LedgerEntries
			if le == nil {
				le = []cloud.PurchaseLedgerEntry{}
			}
			w := wire.PurchaseWithLines{Purchase: wire.Purchase{
				BusinessID: p.BusinessID, CompanyID: p.CompanyID, TallyVoucherID: p.TallyVoucherID, TallyAlterID: p.TallyAlterID,
				SupplierID: nullable(p.SupplierID), SupplierName: p.SupplierName, PurchaseDate: p.Date, VoucherNumber: p.VoucherNumber,
				VoucherType: p.VoucherType, Reference: p.Reference, Narration: p.Narration, Taxable: p.Taxable, Other: p.Other,
				Total: p.Total, Qty: p.Qty, LineCount: len(p.Lines), LedgerEntries: le, SyncedAt: p.SyncedAt.UTC(),
			}, Lines: []wire.PurchaseLine{}}
			for _, l := range p.Lines {
				w.Lines = append(w.Lines, wire.PurchaseLine{BusinessID: p.BusinessID, CompanyID: p.CompanyID, LineNo: l.LineNo,
					StockItemID: nullable(l.StockItemID), ItemName: l.ItemName, Godown: l.Godown, Qty: l.Qty, ActualQty: l.ActualQty,
					Unit: l.Unit, Rate: l.Rate, Discount: l.Discount, Amount: l.Amount})
			}
			bills = append(bills, w)
		}
		if err := s.call(ctx, "upsert-purchases", http.MethodPost, "purchases", nil, wire.Purchases{Bills: bills}, nil); err != nil {
			return err
		}
	}
	return nil
}

func (s *Storage) ListPurchases(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	return s.refs(ctx, "list-purchases", "purchases", companyID)
}

func (s *Storage) SoftDeletePurchases(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-purchases", "purchases", ids)
}

var (
	_ cloud.Provider           = (*Storage)(nil)
	_ cloud.PurchasingProvider = (*Storage)(nil)
)
