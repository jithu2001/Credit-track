// Package cloud defines the provider-neutral contract between the sync engine
// and whatever stores the synchronised data. The engine only ever imports this
// package; concrete backends (Supabase today, others later) live in
// sub-packages and must not leak their types upward.
package cloud

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// Provider is implemented by every cloud backend. All methods must be safe to
// call repeatedly with the same data: the sync engine relies on upserts keyed
// by Tally identifiers, never on "insert once".
type Provider interface {
	// Name identifies the backend for logs and status ("supabase", "memory").
	Name() string
	// Authenticate verifies credentials and that the configured business exists.
	Authenticate(ctx context.Context) error

	// UpsertConnection records this machine's Tally connection and returns its cloud id.
	UpsertConnection(ctx context.Context, c Connection) (string, error)
	// UpsertCompany creates or updates a Tally company (keyed by business + Tally GUID)
	// and returns its cloud id.
	UpsertCompany(ctx context.Context, c Company) (string, error)

	// UpsertShops writes shops keyed by (company, Tally ledger GUID) and returns
	// the cloud id for every Tally ledger GUID written.
	UpsertShops(ctx context.Context, shops []Shop) (map[string]string, error)
	// ListShops returns the active (not soft-deleted) shops of a company.
	ListShops(ctx context.Context, companyID string) ([]ShopRef, error)
	// SoftDeleteShops marks shops as deleted; they are never physically removed.
	SoftDeleteShops(ctx context.Context, ids []string) error

	// UpsertTransactions writes transactions keyed by (company, voucher GUID, ledger GUID).
	UpsertTransactions(ctx context.Context, txns []Transaction) error
	// ListTransactions returns active transactions of a company, optionally
	// restricted to the given voucher GUIDs (nil = all).
	ListTransactions(ctx context.Context, companyID string, voucherIDs []string) ([]TransactionRef, error)
	// SoftDeleteTransactions marks transactions as deleted.
	SoftDeleteTransactions(ctx context.Context, ids []string) error

	GetSyncState(ctx context.Context, companyID, entityType string) (*SyncState, error)
	UpdateSyncState(ctx context.Context, s SyncState) error
	CreateSyncLog(ctx context.Context, l SyncLog) error
}

// UserManager is an optional capability of a Provider: managing the
// business's own login accounts (owner / staff) for the mobile app. The sync
// engine never uses it; only the Cloud Sync page does.
type UserManager interface {
	// ListUsers returns the accounts of the configured business.
	ListUsers(ctx context.Context) ([]User, error)
	// CreateUser creates a login (email + password) and its users row.
	CreateUser(ctx context.Context, u NewUser) (User, error)
	// SetUserPassword replaces the password of an account.
	SetUserPassword(ctx context.Context, id, password string) error
	// SetUserActive enables or disables an account.
	SetUserActive(ctx context.Context, id string, active bool) error
}

const (
	RoleOwner = "OWNER"
	RoleStaff = "STAFF"
)

type User struct {
	ID        string
	Email     string
	Name      string
	Role      string
	IsActive  bool
	CreatedAt time.Time
}

type NewUser struct {
	Email    string
	Password string
	Name     string
	Role     string
}

// ---------------------------------------------------------------- models

type Connection struct {
	BusinessID        string
	MachineIdentifier string
	Hostname          string
	TallyHost         string
	TallyPort         int
	Status            string
	AppVersion        string
	LastSeenAt        time.Time
}

type Company struct {
	BusinessID        string
	ConnectionID      string
	TallyCompanyID    string // Tally company GUID: stable even if the company is renamed
	Name              string
	Number            string
	FinancialYearFrom string
	BooksFrom         string
	EndingAt          string
	PeriodFrom        string
	PeriodTo          string
	LastVoucherDate   string
	Enabled           bool
	SyncEnabled       bool
	SyncStatus        string
	LastSyncAt        *time.Time
}

type Shop struct {
	BusinessID    string
	CompanyID     string
	TallyLedgerID string
	TallyMasterID int
	TallyAlterID  int64
	Name          string
	Aliases       []string
	Group         string
	Phone         string // primary phone
	Phones        []string
	PhoneSource   string
	ContactPerson string
	Email         string
	GSTIN         string
	GSTRegType    string
	Address       []string
	State         string
	Pincode       string
	Country       string
	Area          string
	// Balances in rupees. Type is "DR", "CR" or "" (zero).
	OpeningAmount float64
	OpeningType   string
	BalanceAmount float64
	BalanceType   string
	// Receivable is signed: positive = the shop owes the business.
	Receivable float64
	SyncedAt   time.Time
}

type ShopRef struct {
	ID            string
	TallyLedgerID string
}

type Transaction struct {
	BusinessID      string
	CompanyID       string
	ShopID          string
	TallyVoucherID  string
	TallyLedgerID   string
	TallyMasterID   int64
	TallyAlterID    int64
	Date            string // YYYY-MM-DD
	VoucherNumber   string
	VoucherType     string
	BaseVoucherType string
	Category        string
	Narration       string
	// Debit and Credit are positive rupee amounts (at most one is non-zero).
	// Amount is signed: positive raises what the shop owes (debit), negative lowers it.
	Debit    float64
	Credit   float64
	Amount   float64
	SyncedAt time.Time
}

// Key identifies a transaction independent of the cloud id.
func (t Transaction) Key() string { return t.TallyVoucherID + "|" + t.TallyLedgerID }

type TransactionRef struct {
	ID             string
	TallyVoucherID string
	TallyLedgerID  string
}

func (r TransactionRef) Key() string { return r.TallyVoucherID + "|" + r.TallyLedgerID }

const (
	EntityCompany      = "company"
	EntityShops        = "shops"
	EntityTransactions = "transactions"
)

type SyncState struct {
	BusinessID           string
	CompanyID            string
	EntityType           string
	LastSuccessfulSyncAt *time.Time
	LastAttemptAt        time.Time
	LastCursor           string
	RecordsProcessed     int
	Status               string
	ErrorCode            string
	ErrorMessage         string
}

type SyncLog struct {
	BusinessID          string
	CompanyID           string
	StartedAt           time.Time
	CompletedAt         time.Time
	Status              string // "success", "partial", "failed", "skipped"
	Mode                string // "full" or "incremental"
	RecordsProcessed    int
	RecordsCreated      int
	RecordsUpdated      int
	RecordsDeleted      int
	RecordsFailed       int
	ShopsProcessed      int
	TransactionsFetched int
	ErrorCode           string
	ErrorMessage        string
}

// ---------------------------------------------------------------- errors

// ErrorKind classifies cloud failures the same way internal/tally classifies
// Tally failures, so the scheduler can choose backoff and the UI a message.
type ErrorKind string

const (
	KindUnreachable ErrorKind = "CLOUD_UNREACHABLE"
	KindTimeout     ErrorKind = "CLOUD_TIMEOUT"
	KindAuth        ErrorKind = "CLOUD_AUTH_ERROR"
	KindNotFound    ErrorKind = "CLOUD_NOT_FOUND"
	KindError       ErrorKind = "CLOUD_ERROR"
	KindConfig      ErrorKind = "CLOUD_NOT_CONFIGURED"
)

type Error struct {
	Kind ErrorKind
	Op   string
	Msg  string
	Err  error
}

func (e *Error) Error() string {
	s := fmt.Sprintf("cloud %s: %s", e.Op, e.Kind)
	if e.Msg != "" {
		s += ": " + e.Msg
	}
	if e.Err != nil {
		s += ": " + e.Err.Error()
	}
	return s
}

func (e *Error) Unwrap() error { return e.Err }

// KindOf returns the ErrorKind of err, or "" if it is not a cloud error.
func KindOf(err error) ErrorKind {
	var ce *Error
	if errors.As(err, &ce) {
		return ce.Kind
	}
	return ""
}
