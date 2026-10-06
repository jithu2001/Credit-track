package supabase

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"wholeflow/internal/cloud"
)

// Storage is the Supabase cloud.Provider.
type Storage struct {
	c          *client
	businessID string
}

// Config is everything the Supabase provider needs.
type Config struct {
	URL            string
	ServiceRoleKey string
	BusinessID     string
	Timeout        time.Duration
}

func New(cfg Config, log *slog.Logger) (*Storage, error) {
	if cfg.Timeout <= 0 {
		cfg.Timeout = 60 * time.Second
	}
	c, err := newClient(cfg.URL, cfg.ServiceRoleKey, cfg.Timeout, log)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(cfg.BusinessID) == "" {
		return nil, &cloud.Error{Kind: cloud.KindConfig, Op: "config", Msg: "BUSINESS_ID is required"}
	}
	return &Storage{c: c, businessID: cfg.BusinessID}, nil
}

func (s *Storage) Name() string { return "supabase" }

// Authenticate proves the key works and the business row exists.
func (s *Storage) Authenticate(ctx context.Context) error {
	q := url.Values{"id": {"eq." + s.businessID}, "select": {"id,name"}}
	raw, _, err := s.c.do(ctx, "authenticate", http.MethodGet, "businesses", q, "", "", nil)
	if err != nil {
		return err
	}
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		return &cloud.Error{Kind: cloud.KindError, Op: "authenticate", Msg: "unexpected response from businesses table", Err: err}
	}
	if len(rows) == 0 {
		return &cloud.Error{Kind: cloud.KindNotFound, Op: "authenticate", Msg: "business " + s.businessID + " does not exist; create it in the businesses table first"}
	}
	return nil
}

// ---------------------------------------------------------------- rows (JSON column names = SQL column names)

type connectionRow struct {
	BusinessID        string    `json:"business_id"`
	MachineIdentifier string    `json:"machine_identifier"`
	Hostname          string    `json:"hostname"`
	TallyHost         string    `json:"tally_host"`
	TallyPort         int       `json:"tally_port"`
	Status            string    `json:"status"`
	AppVersion        string    `json:"app_version"`
	LastSeenAt        time.Time `json:"last_seen_at"`
}

type companyRow struct {
	BusinessID        string     `json:"business_id"`
	ConnectionID      *string    `json:"connection_id"`
	TallyCompanyID    string     `json:"tally_company_id"`
	CompanyName       string     `json:"company_name"`
	CompanyNumber     string     `json:"company_number"`
	FinancialYearFrom *string    `json:"financial_year_from"`
	BooksFrom         *string    `json:"books_from"`
	EndingAt          *string    `json:"ending_at"`
	PeriodFrom        *string    `json:"period_from"`
	PeriodTo          *string    `json:"period_to"`
	LastVoucherDate   *string    `json:"last_voucher_date"`
	Enabled           bool       `json:"enabled"`
	SyncEnabled       bool       `json:"sync_enabled"`
	SyncStatus        string     `json:"sync_status"`
	LastSyncAt        *time.Time `json:"last_sync_at"`
}

type shopRow struct {
	BusinessID    string    `json:"business_id"`
	CompanyID     string    `json:"company_id"`
	TallyLedgerID string    `json:"tally_ledger_id"`
	TallyMasterID int       `json:"tally_master_id"`
	TallyAlterID  int64     `json:"tally_alter_id"`
	Name          string    `json:"name"`
	Aliases       []string  `json:"aliases"`
	LedgerGroup   string    `json:"ledger_group"`
	Phone         string    `json:"phone"`
	Phones        []string  `json:"phones"`
	PhoneSource   string    `json:"phone_source"`
	ContactPerson string    `json:"contact_person"`
	Email         string    `json:"email"`
	GSTIN         string    `json:"gstin"`
	GSTRegType    string    `json:"gst_registration_type"`
	Address       string    `json:"address"`
	AddressLines  []string  `json:"address_lines"`
	State         string    `json:"state"`
	Pincode       string    `json:"pincode"`
	Country       string    `json:"country"`
	Area          string    `json:"area"`
	OpeningAmount float64   `json:"opening_balance_amount"`
	OpeningType   string    `json:"opening_balance_type"`
	BalanceAmount float64   `json:"balance_amount"`
	BalanceType   string    `json:"balance_type"`
	Receivable    float64   `json:"receivable"`
	SyncedAt      time.Time `json:"synced_at"`
	DeletedAt     *string   `json:"deleted_at"` // always null on upsert: a re-appearing shop is undeleted
}

type transactionRow struct {
	BusinessID      string    `json:"business_id"`
	CompanyID       string    `json:"company_id"`
	ShopID          string    `json:"shop_id"`
	TallyVoucherID  string    `json:"tally_voucher_id"`
	TallyLedgerID   string    `json:"tally_ledger_id"`
	TallyMasterID   int64     `json:"tally_master_id"`
	TallyAlterID    int64     `json:"tally_alter_id"`
	TransactionDate string    `json:"transaction_date"`
	VoucherNumber   string    `json:"voucher_number"`
	VoucherType     string    `json:"voucher_type"`
	BaseVoucherType string    `json:"base_voucher_type"`
	Category        string    `json:"category"`
	Narration       string    `json:"narration"`
	Debit           float64   `json:"debit"`
	Credit          float64   `json:"credit"`
	Amount          float64   `json:"amount"`
	SyncedAt        time.Time `json:"synced_at"`
	DeletedAt       *string   `json:"deleted_at"`
}

type syncStateRow struct {
	BusinessID           string     `json:"business_id"`
	CompanyID            string     `json:"company_id"`
	EntityType           string     `json:"entity_type"`
	LastSuccessfulSyncAt *time.Time `json:"last_successful_sync_at"`
	LastAttemptAt        time.Time  `json:"last_attempt_at"`
	LastCursor           string     `json:"last_cursor"`
	RecordsProcessed     int        `json:"records_processed"`
	Status               string     `json:"status"`
	ErrorCode            string     `json:"error_code"`
	ErrorMessage         string     `json:"error_message"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

type syncLogRow struct {
	BusinessID          string    `json:"business_id"`
	CompanyID           string    `json:"company_id"`
	StartedAt           time.Time `json:"started_at"`
	CompletedAt         time.Time `json:"completed_at"`
	Status              string    `json:"status"`
	Mode                string    `json:"mode"`
	RecordsProcessed    int       `json:"records_processed"`
	RecordsCreated      int       `json:"records_created"`
	RecordsUpdated      int       `json:"records_updated"`
	RecordsDeleted      int       `json:"records_deleted"`
	RecordsFailed       int       `json:"records_failed"`
	ShopsProcessed      int       `json:"shops_processed"`
	TransactionsFetched int       `json:"transactions_fetched"`
	ErrorCode           string    `json:"error_code"`
	ErrorMessage        string    `json:"error_message"`
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

// ---------------------------------------------------------------- Provider

func (s *Storage) UpsertConnection(ctx context.Context, c cloud.Connection) (string, error) {
	row := connectionRow{BusinessID: c.BusinessID, MachineIdentifier: c.MachineIdentifier, Hostname: c.Hostname,
		TallyHost: c.TallyHost, TallyPort: c.TallyPort, Status: c.Status, AppVersion: c.AppVersion, LastSeenAt: c.LastSeenAt.UTC()}
	raw, err := s.c.upsert(ctx, "upsert-connection", "tally_connections", "business_id,machine_identifier", []connectionRow{row}, "id")
	if err != nil {
		return "", err
	}
	return firstID("upsert-connection", raw)
}

func (s *Storage) UpsertCompany(ctx context.Context, c cloud.Company) (string, error) {
	row := companyRow{
		BusinessID: c.BusinessID, ConnectionID: nullable(c.ConnectionID), TallyCompanyID: c.TallyCompanyID,
		CompanyName: c.Name, CompanyNumber: c.Number, FinancialYearFrom: nullable(c.FinancialYearFrom), BooksFrom: nullable(c.BooksFrom),
		EndingAt: nullable(c.EndingAt), PeriodFrom: nullable(c.PeriodFrom), PeriodTo: nullable(c.PeriodTo), LastVoucherDate: nullable(c.LastVoucherDate),
		Enabled: c.Enabled, SyncEnabled: c.SyncEnabled, SyncStatus: c.SyncStatus, LastSyncAt: c.LastSyncAt,
	}
	raw, err := s.c.upsert(ctx, "upsert-company", "tally_companies", "business_id,tally_company_id", []companyRow{row}, "id")
	if err != nil {
		return "", err
	}
	return firstID("upsert-company", raw)
}

func firstID(op string, raw []byte) (string, error) {
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil || len(rows) == 0 || rows[0].ID == "" {
		return "", &cloud.Error{Kind: cloud.KindError, Op: op, Msg: "upsert did not return an id", Err: err}
	}
	return rows[0].ID, nil
}

func (s *Storage) UpsertShops(ctx context.Context, shops []cloud.Shop) (map[string]string, error) {
	ids := make(map[string]string, len(shops))
	for _, batch := range chunk(shops, s.c.batch) {
		rows := make([]shopRow, 0, len(batch))
		for _, sh := range batch {
			rows = append(rows, shopRow{
				BusinessID: sh.BusinessID, CompanyID: sh.CompanyID, TallyLedgerID: sh.TallyLedgerID,
				TallyMasterID: sh.TallyMasterID, TallyAlterID: sh.TallyAlterID, Name: sh.Name, Aliases: nonNil(sh.Aliases),
				LedgerGroup: sh.Group, Phone: sh.Phone, Phones: nonNil(sh.Phones), PhoneSource: sh.PhoneSource,
				ContactPerson: sh.ContactPerson, Email: sh.Email, GSTIN: sh.GSTIN, GSTRegType: sh.GSTRegType,
				Address: strings.Join(sh.Address, "\n"), AddressLines: nonNil(sh.Address), State: sh.State, Pincode: sh.Pincode,
				Country: sh.Country, Area: sh.Area, OpeningAmount: sh.OpeningAmount, OpeningType: sh.OpeningType,
				BalanceAmount: sh.BalanceAmount, BalanceType: sh.BalanceType, Receivable: sh.Receivable, SyncedAt: sh.SyncedAt.UTC(),
			})
		}
		raw, err := s.c.upsert(ctx, "upsert-shops", "shops", "company_id,tally_ledger_id", rows, "id,tally_ledger_id")
		if err != nil {
			return nil, err
		}
		var out []struct {
			ID            string `json:"id"`
			TallyLedgerID string `json:"tally_ledger_id"`
		}
		if err := json.Unmarshal(raw, &out); err != nil {
			return nil, &cloud.Error{Kind: cloud.KindError, Op: "upsert-shops", Msg: "unexpected response", Err: err}
		}
		for _, r := range out {
			ids[r.TallyLedgerID] = r.ID
		}
	}
	return ids, nil
}

func (s *Storage) ListShops(ctx context.Context, companyID string) ([]cloud.ShopRef, error) {
	q := url.Values{"company_id": {"eq." + companyID}, "deleted_at": {"is.null"}, "select": {"id,tally_ledger_id"}, "order": {"id"}}
	var out []cloud.ShopRef
	err := s.c.selectAll(ctx, "list-shops", "shops", q, func(raw []byte) (int, error) {
		var rows []struct {
			ID            string `json:"id"`
			TallyLedgerID string `json:"tally_ledger_id"`
		}
		if err := json.Unmarshal(raw, &rows); err != nil {
			return 0, err
		}
		for _, r := range rows {
			out = append(out, cloud.ShopRef{ID: r.ID, TallyLedgerID: r.TallyLedgerID})
		}
		return len(rows), nil
	})
	return out, err
}

func (s *Storage) SoftDeleteShops(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-shops", "shops", ids)
}

func (s *Storage) softDelete(ctx context.Context, op, table string, ids []string) error {
	now := time.Now().UTC().Format(time.RFC3339)
	for _, batch := range chunk(ids, 100) { // ~4.5 KB of ids: stays under common 8 KB URL limits
		q := url.Values{"id": {inList(batch)}}
		if _, _, err := s.c.do(ctx, op, http.MethodPatch, table, q, "return=minimal", "", map[string]any{"deleted_at": now}); err != nil {
			return err
		}
	}
	return nil
}

func (s *Storage) UpsertTransactions(ctx context.Context, txns []cloud.Transaction) error {
	for _, batch := range chunk(txns, s.c.batch) {
		rows := make([]transactionRow, 0, len(batch))
		for _, t := range batch {
			rows = append(rows, transactionRow{
				BusinessID: t.BusinessID, CompanyID: t.CompanyID, ShopID: t.ShopID, TallyVoucherID: t.TallyVoucherID,
				TallyLedgerID: t.TallyLedgerID, TallyMasterID: t.TallyMasterID, TallyAlterID: t.TallyAlterID,
				TransactionDate: t.Date, VoucherNumber: t.VoucherNumber, VoucherType: t.VoucherType, BaseVoucherType: t.BaseVoucherType,
				Category: t.Category, Narration: t.Narration, Debit: t.Debit, Credit: t.Credit, Amount: t.Amount, SyncedAt: t.SyncedAt.UTC(),
			})
		}
		if _, err := s.c.upsert(ctx, "upsert-transactions", "transactions", "company_id,tally_voucher_id,tally_ledger_id", rows, ""); err != nil {
			return err
		}
	}
	return nil
}

func (s *Storage) ListTransactions(ctx context.Context, companyID string, voucherIDs []string) ([]cloud.TransactionRef, error) {
	var out []cloud.TransactionRef
	collect := func(raw []byte) (int, error) {
		var rows []struct {
			ID             string `json:"id"`
			TallyVoucherID string `json:"tally_voucher_id"`
			TallyLedgerID  string `json:"tally_ledger_id"`
		}
		if err := json.Unmarshal(raw, &rows); err != nil {
			return 0, err
		}
		for _, r := range rows {
			out = append(out, cloud.TransactionRef{ID: r.ID, TallyVoucherID: r.TallyVoucherID, TallyLedgerID: r.TallyLedgerID})
		}
		return len(rows), nil
	}
	base := func() url.Values {
		return url.Values{"company_id": {"eq." + companyID}, "deleted_at": {"is.null"},
			"select": {"id,tally_voucher_id,tally_ledger_id"}, "order": {"id"}}
	}
	if voucherIDs == nil {
		return out, s.c.selectAll(ctx, "list-transactions", "transactions", base(), collect)
	}
	for _, batch := range chunk(voucherIDs, 100) {
		q := base()
		q.Set("tally_voucher_id", inList(batch))
		if err := s.c.selectAll(ctx, "list-transactions", "transactions", q, collect); err != nil {
			return nil, err
		}
	}
	return out, nil
}

func (s *Storage) SoftDeleteTransactions(ctx context.Context, ids []string) error {
	return s.softDelete(ctx, "delete-transactions", "transactions", ids)
}

func (s *Storage) GetSyncState(ctx context.Context, companyID, entityType string) (*cloud.SyncState, error) {
	q := url.Values{"company_id": {"eq." + companyID}, "entity_type": {"eq." + entityType}, "select": {"*"}}
	raw, _, err := s.c.do(ctx, "get-sync-state", http.MethodGet, "sync_state", q, "", "", nil)
	if err != nil {
		return nil, err
	}
	var rows []syncStateRow
	if err := json.Unmarshal(raw, &rows); err != nil {
		return nil, &cloud.Error{Kind: cloud.KindError, Op: "get-sync-state", Msg: "unexpected response", Err: err}
	}
	if len(rows) == 0 {
		return nil, nil
	}
	r := rows[0]
	return &cloud.SyncState{BusinessID: r.BusinessID, CompanyID: r.CompanyID, EntityType: r.EntityType,
		LastSuccessfulSyncAt: r.LastSuccessfulSyncAt, LastAttemptAt: r.LastAttemptAt, LastCursor: r.LastCursor,
		RecordsProcessed: r.RecordsProcessed, Status: r.Status, ErrorCode: r.ErrorCode, ErrorMessage: r.ErrorMessage}, nil
}

func (s *Storage) UpdateSyncState(ctx context.Context, st cloud.SyncState) error {
	row := syncStateRow{BusinessID: st.BusinessID, CompanyID: st.CompanyID, EntityType: st.EntityType,
		LastSuccessfulSyncAt: st.LastSuccessfulSyncAt, LastAttemptAt: st.LastAttemptAt.UTC(), LastCursor: st.LastCursor,
		RecordsProcessed: st.RecordsProcessed, Status: st.Status, ErrorCode: st.ErrorCode, ErrorMessage: truncate(st.ErrorMessage, 2000),
		UpdatedAt: time.Now().UTC()}
	_, err := s.c.upsert(ctx, "update-sync-state", "sync_state", "company_id,entity_type", []syncStateRow{row}, "")
	return err
}

func (s *Storage) CreateSyncLog(ctx context.Context, l cloud.SyncLog) error {
	row := syncLogRow{BusinessID: l.BusinessID, CompanyID: l.CompanyID, StartedAt: l.StartedAt.UTC(), CompletedAt: l.CompletedAt.UTC(),
		Status: l.Status, Mode: l.Mode, RecordsProcessed: l.RecordsProcessed, RecordsCreated: l.RecordsCreated, RecordsUpdated: l.RecordsUpdated,
		RecordsDeleted: l.RecordsDeleted, RecordsFailed: l.RecordsFailed, ShopsProcessed: l.ShopsProcessed, TransactionsFetched: l.TransactionsFetched,
		ErrorCode: l.ErrorCode, ErrorMessage: truncate(l.ErrorMessage, 2000)}
	_, _, err := s.c.do(ctx, "create-sync-log", http.MethodPost, "sync_logs", nil, "return=minimal", "", []syncLogRow{row})
	return err
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// String describes the target without revealing the key.
func (s *Storage) String() string {
	return fmt.Sprintf("supabase %s (business %s)", s.c.base, s.businessID)
}
