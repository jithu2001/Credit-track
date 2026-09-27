package syncer

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	gosync "sync"
	"time"
)

// Company sync statuses shown on the status page and stored in the cloud.
const (
	StatusPending      = "PENDING"
	StatusSyncing      = "SYNCING"
	StatusSynced       = "SYNCED"
	StatusTallyOffline = "TALLY_OFFLINE"
	StatusCloudOffline = "CLOUD_OFFLINE"
	StatusAuthError    = "AUTH_ERROR"
	StatusSyncError    = "SYNC_ERROR"
	StatusDisabled     = "DISABLED"
	StatusNotOpen      = "COMPANY_NOT_OPEN"
)

// State is what the service remembers between runs and restarts. It lives in
// state.json next to config.json. Losing it is safe: the next run simply
// performs a full sync, which is idempotent.
type State struct {
	Companies map[string]*CompanyState `json:"companies"` // by Tally company GUID
	LastRun   *RunResult               `json:"lastRun,omitempty"`
	UpdatedAt time.Time                `json:"updatedAt"`
}

type CompanyState struct {
	TallyID             string     `json:"tallyId"`
	Name                string     `json:"name"`
	CloudID             string     `json:"cloudId,omitempty"`
	Status              string     `json:"status"`
	LastAttemptAt       *time.Time `json:"lastAttemptAt,omitempty"`
	LastSuccessAt       *time.Time `json:"lastSuccessAt,omitempty"`
	LastErrorCode       string     `json:"lastErrorCode,omitempty"`
	LastError           string     `json:"lastError,omitempty"`
	VoucherCursor       int64      `json:"voucherCursor"` // highest Tally AlterID synced
	LastFullReconcileAt *time.Time `json:"lastFullReconcileAt,omitempty"`
	ShopCount           int        `json:"shopCount"`
	TransactionCount    int        `json:"transactionCount"`
}

type StateStore struct {
	path string
	mu   gosync.Mutex
	st   State
}

func LoadState(dataDir string) (*StateStore, error) {
	s := &StateStore{path: filepath.Join(dataDir, stateFileName), st: State{Companies: map[string]*CompanyState{}}}
	b, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(b, &s.st); err != nil {
		// A corrupt state file must not stop the service: start fresh (full sync).
		s.st = State{Companies: map[string]*CompanyState{}}
	}
	if s.st.Companies == nil {
		s.st.Companies = map[string]*CompanyState{}
	}
	return s, nil
}

// Get returns a deep copy.
func (s *StateStore) Get() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.copyLocked()
}

func (s *StateStore) copyLocked() State {
	out := State{Companies: make(map[string]*CompanyState, len(s.st.Companies)), UpdatedAt: s.st.UpdatedAt}
	for k, v := range s.st.Companies {
		cp := *v
		out.Companies[k] = &cp
	}
	if s.st.LastRun != nil {
		lr := *s.st.LastRun
		lr.Companies = append([]CompanyResult(nil), lr.Companies...)
		out.LastRun = &lr
	}
	return out
}

// Company returns a copy of one company's state (zero value if unknown).
func (s *StateStore) Company(tallyID string) CompanyState {
	s.mu.Lock()
	defer s.mu.Unlock()
	if c := s.st.Companies[tallyID]; c != nil {
		return *c
	}
	return CompanyState{TallyID: tallyID, Status: StatusPending}
}

// Update mutates the state under the lock and persists it.
func (s *StateStore) Update(fn func(*State)) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	fn(&s.st)
	s.st.UpdatedAt = time.Now()
	return writeJSONAtomic(s.path, s.st)
}

// UpdateCompany is a convenience for Update on one company.
func (s *StateStore) UpdateCompany(tallyID string, fn func(*CompanyState)) error {
	return s.Update(func(st *State) {
		c := st.Companies[tallyID]
		if c == nil {
			c = &CompanyState{TallyID: tallyID, Status: StatusPending}
			st.Companies[tallyID] = c
		}
		fn(c)
	})
}

// Forget drops local state for a company (e.g. removed from the selection).
func (s *StateStore) Forget(tallyID string) error {
	return s.Update(func(st *State) { delete(st.Companies, tallyID) })
}
