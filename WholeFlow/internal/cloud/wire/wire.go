// Package wire is the format of the Tally PC's uploads to the WholeFlow app
// API (/b/<slug>/api/v1/pc/…): one struct per table row, JSON names = SQL
// column names. The PC client (internal/cloud/hosted) sends these and the
// server (internal/appapi) writes them, so both sides share one definition.
package wire

import (
	"time"

	"wholeflow/internal/cloud"
)

type Connection struct {
	BusinessID        string    `json:"business_id"`
	MachineIdentifier string    `json:"machine_identifier"`
	Hostname          string    `json:"hostname"`
	TallyHost         string    `json:"tally_host"`
	TallyPort         int       `json:"tally_port"`
	Status            string    `json:"status"`
	AppVersion        string    `json:"app_version"`
	LastSeenAt        time.Time `json:"last_seen_at"`
}

type Company struct {
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

type Shop struct {
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

type Transaction struct {
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

type SyncState struct {
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

type SyncLog struct {
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

type Supplier struct {
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
	ContactPerson string    `json:"contact_person"`
	Email         string    `json:"email"`
	GSTIN         string    `json:"gstin"`
	GSTRegType    string    `json:"gst_registration_type"`
	Address       string    `json:"address"`
	AddressLines  []string  `json:"address_lines"`
	State         string    `json:"state"`
	Pincode       string    `json:"pincode"`
	Country       string    `json:"country"`
	OpeningAmount float64   `json:"opening_balance_amount"`
	OpeningType   string    `json:"opening_balance_type"`
	BalanceAmount float64   `json:"balance_amount"`
	BalanceType   string    `json:"balance_type"`
	Payable       float64   `json:"payable"`
	SyncedAt      time.Time `json:"synced_at"`
	DeletedAt     *string   `json:"deleted_at"`
}

type StockItem struct {
	BusinessID    string    `json:"business_id"`
	CompanyID     string    `json:"company_id"`
	TallyItemID   string    `json:"tally_item_id"`
	Name          string    `json:"name"`
	Aliases       []string  `json:"aliases"`
	StockGroup    string    `json:"stock_group"`
	Category      string    `json:"category"`
	Unit          string    `json:"unit"`
	GSTApplicable bool      `json:"gst_applicable"`
	OpeningQty    float64   `json:"opening_qty"`
	OpeningValue  float64   `json:"opening_value"`
	ClosingQty    float64   `json:"closing_qty"`
	ClosingRate   float64   `json:"closing_rate"`
	ClosingValue  float64   `json:"closing_value"`
	ReorderLevel  float64   `json:"reorder_level"`
	MinOrderQty   float64   `json:"min_order_qty"`
	StockStatus   string    `json:"stock_status"`
	SyncedAt      time.Time `json:"synced_at"`
	DeletedAt     *string   `json:"deleted_at"`
}

type Purchase struct {
	BusinessID     string                      `json:"business_id"`
	CompanyID      string                      `json:"company_id"`
	TallyVoucherID string                      `json:"tally_voucher_id"`
	TallyAlterID   int64                       `json:"tally_alter_id"`
	SupplierID     *string                     `json:"supplier_id"`
	SupplierName   string                      `json:"supplier_name"`
	PurchaseDate   string                      `json:"purchase_date"`
	VoucherNumber  string                      `json:"voucher_number"`
	VoucherType    string                      `json:"voucher_type"`
	Reference      string                      `json:"supplier_bill_number"`
	Narration      string                      `json:"narration"`
	Taxable        float64                     `json:"taxable_amount"`
	Other          float64                     `json:"tax_and_other_amount"`
	Total          float64                     `json:"total_amount"`
	Qty            float64                     `json:"total_qty"`
	LineCount      int                         `json:"line_count"`
	LedgerEntries  []cloud.PurchaseLedgerEntry `json:"ledger_entries"`
	SyncedAt       time.Time                   `json:"synced_at"`
	DeletedAt      *string                     `json:"deleted_at"`
}

type PurchaseLine struct {
	BusinessID  string  `json:"business_id"`
	CompanyID   string  `json:"company_id"`
	PurchaseID  string  `json:"purchase_id"`
	LineNo      int     `json:"line_no"`
	StockItemID *string `json:"stock_item_id"`
	ItemName    string  `json:"item_name"`
	Godown      string  `json:"godown"`
	Qty         float64 `json:"qty"`
	ActualQty   float64 `json:"actual_qty"`
	Unit        string  `json:"unit"`
	Rate        float64 `json:"rate"`
	Discount    float64 `json:"discount_percent"`
	Amount      float64 `json:"amount"`
}

// Rows of a batch to upsert.
type Batch[T any] struct {
	Rows []T `json:"rows"`
}

// IDs maps a row's Tally key (ledger, item or voucher id) to its id.
type IDs struct {
	IDs map[string]string `json:"ids"`
}

// ID is the id of one upserted row.
type ID struct {
	ID string `json:"id"`
}

// Ref is an active row's id and Tally key.
type Ref struct {
	ID  string `json:"id"`
	Key string `json:"key"`
}

// Refs lists active rows.
type Refs struct {
	Refs []Ref `json:"refs"`
}

// TxnRef is an active voucher line's id and keys.
type TxnRef struct {
	ID             string `json:"id"`
	TallyVoucherID string `json:"tally_voucher_id"`
	TallyLedgerID  string `json:"tally_ledger_id"`
}

// TxnRefs lists active voucher lines.
type TxnRefs struct {
	Refs []TxnRef `json:"refs"`
}

// TxnQuery asks for a company's voucher lines, all of them (VoucherIDs nil)
// or only those of the given vouchers.
type TxnQuery struct {
	CompanyID  string   `json:"company_id"`
	VoucherIDs []string `json:"voucher_ids"`
}

// Delete soft-deletes rows by id.
type Delete struct {
	IDs []string `json:"ids"`
}

// Purchases is a batch of bills with their lines: the server replaces each
// bill's lines in the same transaction.
type Purchases struct {
	Bills []PurchaseWithLines `json:"bills"`
}

// PurchaseWithLines is one bill and its item lines (PurchaseID is set by the server).
type PurchaseWithLines struct {
	Purchase Purchase       `json:"purchase"`
	Lines    []PurchaseLine `json:"lines"`
}

// Authenticate asks whether this PC's key works for business BusinessID.
type Authenticate struct {
	BusinessID string `json:"business_id"`
}

// SyncStateAnswer is one sync_state row (State nil when there is none).
type SyncStateAnswer struct {
	State *SyncState `json:"state"`
}
