// Package memory is an in-process cloud.Provider. It backs the sync engine
// tests and the CLOUD_PROVIDER=memory "dry run" mode, and doubles as the
// reference for how a backend must behave (upsert semantics, soft deletes,
// tenant scoping).
package memory

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"wholeflow/internal/cloud"
)

type Store struct {
	mu sync.Mutex

	BusinessID string
	// Fail, when set, is returned by every call: simulates an outage.
	Fail error
	// FailOn makes only the named operation fail (e.g. "UpsertTransactions").
	FailOn map[string]error
	// Delay is added to every call (for timeout tests).
	Delay time.Duration

	Calls map[string]int

	connections  map[string]cloud.Connection // by id
	companies    map[string]*cloud.Company   // by id
	shops        map[string]*shopRow         // by id
	transactions map[string]*txnRow          // by id
	states       map[string]cloud.SyncState  // by companyID|entity
	Logs         []cloud.SyncLog
	users        map[string]*userRow
	seq          int
}

type userRow struct {
	cloud.User
	Password string
}

type shopRow struct {
	cloud.Shop
	ID        string
	DeletedAt *time.Time
}

type txnRow struct {
	cloud.Transaction
	ID        string
	DeletedAt *time.Time
}

func New(businessID string) *Store {
	return &Store{
		BusinessID:   businessID,
		FailOn:       map[string]error{},
		Calls:        map[string]int{},
		connections:  map[string]cloud.Connection{},
		companies:    map[string]*cloud.Company{},
		shops:        map[string]*shopRow{},
		transactions: map[string]*txnRow{},
		states:       map[string]cloud.SyncState{},
		users:        map[string]*userRow{},
	}
}

// ---------------------------------------------------------------- users (cloud.UserManager)

func (s *Store) ListUsers(ctx context.Context) ([]cloud.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListUsers"); err != nil {
		return nil, err
	}
	out := make([]cloud.User, 0, len(s.users))
	for _, u := range s.users {
		out = append(out, u.User)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out, nil
}

func (s *Store) CreateUser(ctx context.Context, n cloud.NewUser) (cloud.User, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "CreateUser"); err != nil {
		return cloud.User{}, err
	}
	for _, u := range s.users {
		if strings.EqualFold(u.Email, n.Email) {
			return cloud.User{}, &cloud.Error{Kind: cloud.KindError, Op: "create-user", Msg: "a user with this email already exists"}
		}
	}
	u := &userRow{User: cloud.User{ID: s.newID("user"), Email: n.Email, Name: n.Name, Role: n.Role, IsActive: true, CreatedAt: time.Now()}, Password: n.Password}
	s.users[u.ID] = u
	return u.User, nil
}

func (s *Store) SetUserPassword(ctx context.Context, id, password string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SetUserPassword"); err != nil {
		return err
	}
	u := s.users[id]
	if u == nil {
		return &cloud.Error{Kind: cloud.KindNotFound, Op: "set-password", Msg: "no such user"}
	}
	u.Password = password
	return nil
}

func (s *Store) SetUserActive(ctx context.Context, id string, active bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SetUserActive"); err != nil {
		return err
	}
	u := s.users[id]
	if u == nil {
		return &cloud.Error{Kind: cloud.KindNotFound, Op: "set-active", Msg: "no such user"}
	}
	u.IsActive = active
	return nil
}

func (s *Store) Name() string { return "memory" }

func (s *Store) enter(ctx context.Context, op string) error {
	s.Calls[op]++
	if s.Delay > 0 {
		select {
		case <-time.After(s.Delay):
		case <-ctx.Done():
			return &cloud.Error{Kind: cloud.KindTimeout, Op: op, Err: ctx.Err()}
		}
	}
	if s.Fail != nil {
		return s.Fail
	}
	if err := s.FailOn[op]; err != nil {
		return err
	}
	return nil
}

func (s *Store) newID(prefix string) string {
	s.seq++
	return fmt.Sprintf("%s-%04d", prefix, s.seq)
}

func (s *Store) checkTenant(op, businessID string) error {
	if businessID != s.BusinessID {
		return &cloud.Error{Kind: cloud.KindAuth, Op: op, Msg: "record belongs to another business"}
	}
	return nil
}

func (s *Store) Authenticate(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.BusinessID == "" {
		return &cloud.Error{Kind: cloud.KindConfig, Op: "authenticate", Msg: "no business id"}
	}
	return s.enter(ctx, "Authenticate")
}

func (s *Store) UpsertConnection(ctx context.Context, c cloud.Connection) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertConnection"); err != nil {
		return "", err
	}
	if err := s.checkTenant("UpsertConnection", c.BusinessID); err != nil {
		return "", err
	}
	for id, x := range s.connections {
		if x.MachineIdentifier == c.MachineIdentifier {
			s.connections[id] = c
			return id, nil
		}
	}
	id := s.newID("conn")
	s.connections[id] = c
	return id, nil
}

func (s *Store) UpsertCompany(ctx context.Context, c cloud.Company) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertCompany"); err != nil {
		return "", err
	}
	if err := s.checkTenant("UpsertCompany", c.BusinessID); err != nil {
		return "", err
	}
	for id, x := range s.companies {
		if x.TallyCompanyID == c.TallyCompanyID {
			cp := c
			s.companies[id] = &cp
			return id, nil
		}
	}
	id := s.newID("cmp")
	cp := c
	s.companies[id] = &cp
	return id, nil
}

func (s *Store) UpsertShops(ctx context.Context, shops []cloud.Shop) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertShops"); err != nil {
		return nil, err
	}
	ids := map[string]string{}
	for _, sh := range shops {
		if err := s.checkTenant("UpsertShops", sh.BusinessID); err != nil {
			return nil, err
		}
		key := sh.CompanyID + "|" + sh.TallyLedgerID
		var row *shopRow
		for _, r := range s.shops {
			if r.CompanyID+"|"+r.TallyLedgerID == key {
				row = r
				break
			}
		}
		if row == nil {
			row = &shopRow{ID: s.newID("shop")}
			s.shops[row.ID] = row
		}
		row.Shop = sh
		row.DeletedAt = nil
		ids[sh.TallyLedgerID] = row.ID
	}
	return ids, nil
}

func (s *Store) ListShops(ctx context.Context, companyID string) ([]cloud.ShopRef, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListShops"); err != nil {
		return nil, err
	}
	var out []cloud.ShopRef
	for _, r := range s.shops {
		if r.CompanyID == companyID && r.DeletedAt == nil {
			out = append(out, cloud.ShopRef{ID: r.ID, TallyLedgerID: r.TallyLedgerID})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

func (s *Store) SoftDeleteShops(ctx context.Context, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SoftDeleteShops"); err != nil {
		return err
	}
	now := time.Now()
	for _, id := range ids {
		if r := s.shops[id]; r != nil {
			r.DeletedAt = &now
		}
	}
	return nil
}

func (s *Store) UpsertTransactions(ctx context.Context, txns []cloud.Transaction) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertTransactions"); err != nil {
		return err
	}
	index := map[string]*txnRow{}
	for _, r := range s.transactions {
		index[r.CompanyID+"|"+r.Key()] = r
	}
	for _, t := range txns {
		if err := s.checkTenant("UpsertTransactions", t.BusinessID); err != nil {
			return err
		}
		if t.ShopID == "" {
			return &cloud.Error{Kind: cloud.KindError, Op: "UpsertTransactions", Msg: "transaction without shop id"}
		}
		key := t.CompanyID + "|" + t.Key()
		row := index[key]
		if row == nil {
			row = &txnRow{ID: s.newID("txn")}
			s.transactions[row.ID] = row
			index[key] = row
		}
		row.Transaction = t
		row.DeletedAt = nil
	}
	return nil
}

func (s *Store) ListTransactions(ctx context.Context, companyID string, voucherIDs []string) ([]cloud.TransactionRef, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListTransactions"); err != nil {
		return nil, err
	}
	var want map[string]bool
	if voucherIDs != nil {
		want = map[string]bool{}
		for _, v := range voucherIDs {
			want[v] = true
		}
	}
	var out []cloud.TransactionRef
	for _, r := range s.transactions {
		if r.CompanyID != companyID || r.DeletedAt != nil {
			continue
		}
		if want != nil && !want[r.TallyVoucherID] {
			continue
		}
		out = append(out, cloud.TransactionRef{ID: r.ID, TallyVoucherID: r.TallyVoucherID, TallyLedgerID: r.TallyLedgerID})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

func (s *Store) SoftDeleteTransactions(ctx context.Context, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SoftDeleteTransactions"); err != nil {
		return err
	}
	now := time.Now()
	for _, id := range ids {
		if r := s.transactions[id]; r != nil {
			r.DeletedAt = &now
		}
	}
	return nil
}

func (s *Store) GetSyncState(ctx context.Context, companyID, entityType string) (*cloud.SyncState, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "GetSyncState"); err != nil {
		return nil, err
	}
	st, ok := s.states[companyID+"|"+entityType]
	if !ok {
		return nil, nil
	}
	return &st, nil
}

func (s *Store) UpdateSyncState(ctx context.Context, st cloud.SyncState) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpdateSyncState"); err != nil {
		return err
	}
	if err := s.checkTenant("UpdateSyncState", st.BusinessID); err != nil {
		return err
	}
	s.states[st.CompanyID+"|"+st.EntityType] = st
	return nil
}

func (s *Store) CreateSyncLog(ctx context.Context, l cloud.SyncLog) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "CreateSyncLog"); err != nil {
		return err
	}
	if err := s.checkTenant("CreateSyncLog", l.BusinessID); err != nil {
		return err
	}
	s.Logs = append(s.Logs, l)
	return nil
}

// ---------------------------------------------------------------- inspection helpers (tests, dry run)

type Counts struct {
	Companies, Shops, ShopsDeleted, Transactions, TransactionsDeleted, Logs int
}

func (s *Store) Counts() Counts {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := Counts{Companies: len(s.companies), Logs: len(s.Logs)}
	for _, r := range s.shops {
		if r.DeletedAt != nil {
			c.ShopsDeleted++
		} else {
			c.Shops++
		}
	}
	for _, r := range s.transactions {
		if r.DeletedAt != nil {
			c.TransactionsDeleted++
		} else {
			c.Transactions++
		}
	}
	return c
}

// Shop returns the active shop with the given Tally ledger id, if any.
func (s *Store) Shop(tallyLedgerID string) (cloud.Shop, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, r := range s.shops {
		if r.TallyLedgerID == tallyLedgerID && r.DeletedAt == nil {
			return r.Shop, true
		}
	}
	return cloud.Shop{}, false
}

// Transactions returns active transactions, optionally filtered by voucher id prefix.
func (s *Store) Transactions(voucherPrefix string) []cloud.Transaction {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []cloud.Transaction
	for _, r := range s.transactions {
		if r.DeletedAt == nil && strings.HasPrefix(r.TallyVoucherID, voucherPrefix) {
			out = append(out, r.Transaction)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key() < out[j].Key() })
	return out
}

func (s *Store) State(companyID, entity string) (cloud.SyncState, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st, ok := s.states[companyID+"|"+entity]
	return st, ok
}

func (s *Store) Company(tallyID string) (cloud.Company, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, c := range s.companies {
		if c.TallyCompanyID == tallyID {
			return *c, true
		}
	}
	return cloud.Company{}, false
}
