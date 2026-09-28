package memory

import (
	"context"
	"sort"
	"time"

	"wholeflow/internal/cloud"
)

// keyed is one row of a company-scoped table, keyed by a Tally identifier.
type keyed[T any] struct {
	ID        string
	CompanyID string
	Key       string
	Row       T
	DeletedAt *time.Time
}

type table[T any] map[string]*keyed[T] // by id

func (s *Store) ensurePurchasing() {
	if s.suppliers == nil {
		s.suppliers, s.stockItems, s.purchases = table[cloud.Supplier]{}, table[cloud.StockItem]{}, table[cloud.Purchase]{}
	}
}

func upsertKeyed[T any](s *Store, t table[T], prefix, companyID, key string, row T) string {
	for _, r := range t {
		if r.CompanyID == companyID && r.Key == key {
			r.Row, r.DeletedAt = row, nil
			return r.ID
		}
	}
	id := s.newID(prefix)
	t[id] = &keyed[T]{ID: id, CompanyID: companyID, Key: key, Row: row}
	return id
}

func listKeyed[T any](t table[T], companyID string) []cloud.Ref {
	var out []cloud.Ref
	for _, r := range t {
		if r.CompanyID == companyID && r.DeletedAt == nil {
			out = append(out, cloud.Ref{ID: r.ID, Key: r.Key})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func softDeleteKeyed[T any](t table[T], ids []string) {
	now := time.Now()
	for _, id := range ids {
		if r := t[id]; r != nil {
			r.DeletedAt = &now
		}
	}
}

func (s *Store) UpsertSuppliers(ctx context.Context, sups []cloud.Supplier) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertSuppliers"); err != nil {
		return nil, err
	}
	s.ensurePurchasing()
	ids := map[string]string{}
	for _, x := range sups {
		if err := s.checkTenant("UpsertSuppliers", x.BusinessID); err != nil {
			return nil, err
		}
		ids[x.TallyLedgerID] = upsertKeyed(s, s.suppliers, "sup", x.CompanyID, x.TallyLedgerID, x)
	}
	return ids, nil
}

func (s *Store) ListSuppliers(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListSuppliers"); err != nil {
		return nil, err
	}
	s.ensurePurchasing()
	return listKeyed(s.suppliers, companyID), nil
}

func (s *Store) SoftDeleteSuppliers(ctx context.Context, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SoftDeleteSuppliers"); err != nil {
		return err
	}
	s.ensurePurchasing()
	softDeleteKeyed(s.suppliers, ids)
	return nil
}

func (s *Store) UpsertStockItems(ctx context.Context, items []cloud.StockItem) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertStockItems"); err != nil {
		return nil, err
	}
	s.ensurePurchasing()
	ids := map[string]string{}
	for _, x := range items {
		if err := s.checkTenant("UpsertStockItems", x.BusinessID); err != nil {
			return nil, err
		}
		ids[x.TallyItemID] = upsertKeyed(s, s.stockItems, "item", x.CompanyID, x.TallyItemID, x)
	}
	return ids, nil
}

func (s *Store) ListStockItems(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListStockItems"); err != nil {
		return nil, err
	}
	s.ensurePurchasing()
	return listKeyed(s.stockItems, companyID), nil
}

func (s *Store) SoftDeleteStockItems(ctx context.Context, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SoftDeleteStockItems"); err != nil {
		return err
	}
	s.ensurePurchasing()
	softDeleteKeyed(s.stockItems, ids)
	return nil
}

func (s *Store) UpsertPurchases(ctx context.Context, ps []cloud.Purchase) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "UpsertPurchases"); err != nil {
		return err
	}
	s.ensurePurchasing()
	for _, p := range ps {
		if err := s.checkTenant("UpsertPurchases", p.BusinessID); err != nil {
			return err
		}
		p.Lines = append([]cloud.PurchaseLine(nil), p.Lines...) // lines are replaced wholesale
		upsertKeyed(s, s.purchases, "pur", p.CompanyID, p.TallyVoucherID, p)
	}
	return nil
}

func (s *Store) ListPurchases(ctx context.Context, companyID string) ([]cloud.Ref, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "ListPurchases"); err != nil {
		return nil, err
	}
	s.ensurePurchasing()
	return listKeyed(s.purchases, companyID), nil
}

func (s *Store) SoftDeletePurchases(ctx context.Context, ids []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.enter(ctx, "SoftDeletePurchases"); err != nil {
		return err
	}
	s.ensurePurchasing()
	softDeleteKeyed(s.purchases, ids)
	return nil
}

// ---------------------------------------------------------------- inspection helpers

type PurchasingCounts struct {
	Suppliers, SuppliersDeleted, StockItems, StockItemsDeleted, Purchases, PurchasesDeleted, PurchaseLines int
}

func (s *Store) PurchasingCounts() PurchasingCounts {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ensurePurchasing()
	var c PurchasingCounts
	for _, r := range s.suppliers {
		if r.DeletedAt != nil {
			c.SuppliersDeleted++
		} else {
			c.Suppliers++
		}
	}
	for _, r := range s.stockItems {
		if r.DeletedAt != nil {
			c.StockItemsDeleted++
		} else {
			c.StockItems++
		}
	}
	for _, r := range s.purchases {
		if r.DeletedAt != nil {
			c.PurchasesDeleted++
		} else {
			c.Purchases++
			c.PurchaseLines += len(r.Row.Lines)
		}
	}
	return c
}

// Purchase returns the active bill with the given Tally voucher GUID.
func (s *Store) Purchase(voucherID string) (cloud.Purchase, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ensurePurchasing()
	for _, r := range s.purchases {
		if r.Key == voucherID && r.DeletedAt == nil {
			return r.Row, true
		}
	}
	return cloud.Purchase{}, false
}

// StockItem returns the active item with the given Tally GUID.
func (s *Store) StockItem(itemID string) (cloud.StockItem, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ensurePurchasing()
	for _, r := range s.stockItems {
		if r.Key == itemID && r.DeletedAt == nil {
			return r.Row, true
		}
	}
	return cloud.StockItem{}, false
}

var _ cloud.PurchasingProvider = (*Store)(nil)
