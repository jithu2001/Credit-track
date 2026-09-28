package syncer

import (
	"context"
	"log/slog"
	"strconv"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/tally"
)

// Suppliers, stock items and purchase bills run after shops and transactions.
// They are secondary: a failure here (for example the 0003 migration not yet
// applied) is recorded as a warning, in the entity's sync_state row and in the
// local state, but does not stop the company from being SYNCED. Shops and
// balances stay the part that must always get through.

type purchasingResult struct {
	suppliers, stock, purchases *Stats
	purchaseMode                string
	purchaseCursor              int64
	lastReconcile               *time.Time
	supplierCount, stockCount   int
	purchaseCount               int
	warnings                    []string
}

func (e *Engine) syncPurchasing(ctx context.Context, prov cloud.Provider, set Settings, tc tally.Company, cloudID string,
	prev CompanyState, log *slog.Logger) purchasingResult {

	res := purchasingResult{purchaseCursor: prev.PurchaseCursor, lastReconcile: prev.LastPurchaseReconcileAt,
		supplierCount: prev.SupplierCount, stockCount: prev.StockItemCount, purchaseCount: prev.PurchaseCount}
	pp, ok := prov.(cloud.PurchasingProvider)
	if !ok || !(set.Sync.Suppliers || set.Sync.Inventory || set.Sync.Purchases) {
		return res
	}
	fail := func(entity string, err error) {
		code, msg := classify(err)
		log.Warn("SYNC STEP FAILED", "entity", entity, "code", code, "error", msg)
		res.warnings = append(res.warnings, entity+": "+code+" "+msg)
		e.writeState(ctx, prov, set, cloudID, entity, e.now(), nil, "", 0, code, msg)
	}

	// Name → cloud id maps let bills point at their supplier and items. When a
	// step is off or failed, the ids stay empty and bills keep the names.
	supplierIDByName := map[string]string{}
	if set.Sync.Suppliers {
		st, ids, err := e.syncSuppliers(ctx, pp, set, tc, cloudID, &res)
		if err != nil {
			fail(cloud.EntitySuppliers, err)
		} else {
			res.suppliers, supplierIDByName, res.supplierCount = &st, ids, st.Fetched
			now := e.now()
			e.writeState(ctx, prov, set, cloudID, cloud.EntitySuppliers, now, &now, "", st.Fetched, "", "")
			log.Info("suppliers synced", "fetched", st.Fetched, "created", st.Created, "updated", st.Updated, "deleted", st.Deleted)
		}
	}
	itemIDByName := map[string]string{}
	if set.Sync.Inventory {
		st, ids, err := e.syncStockItems(ctx, pp, set, tc, cloudID, &res)
		if err != nil {
			fail(cloud.EntityStockItems, err)
		} else {
			res.stock, itemIDByName, res.stockCount = &st, ids, st.Fetched
			now := e.now()
			e.writeState(ctx, prov, set, cloudID, cloud.EntityStockItems, now, &now, "", st.Fetched, "", "")
			log.Info("stock items synced", "fetched", st.Fetched, "created", st.Created, "updated", st.Updated, "deleted", st.Deleted)
		}
	}
	// Bills point at suppliers and items by id: if either step failed this
	// run, a full pass would upsert every bill with empty links. Wait instead.
	linksBroken := (set.Sync.Suppliers && res.suppliers == nil) || (set.Sync.Inventory && res.stock == nil)
	if set.Sync.Purchases && linksBroken {
		res.warnings = append(res.warnings, cloud.EntityPurchases+": skipped this run because the supplier or stock item step failed")
	}
	if set.Sync.Purchases && !linksBroken {
		mode := "incremental"
		switch {
		case prev.PurchaseCursor == 0:
			mode = "full"
		case prev.LastPurchaseReconcileAt == nil ||
			e.now().Sub(*prev.LastPurchaseReconcileAt) >= time.Duration(set.Sync.FullReconcileHours)*time.Hour:
			mode = "reconcile"
		}
		st, cursor, active, err := e.syncPurchases(ctx, pp, set, tc, cloudID, mode, prev.PurchaseCursor, supplierIDByName, itemIDByName, &res)
		if err != nil {
			fail(cloud.EntityPurchases, err)
		} else {
			res.purchases, res.purchaseMode, res.purchaseCursor, res.purchaseCount = &st, mode, cursor, active
			now := e.now()
			if mode != "incremental" {
				res.lastReconcile = &now
			}
			e.writeState(ctx, prov, set, cloudID, cloud.EntityPurchases, now, &now, strconv.FormatInt(cursor, 10), st.Fetched, "", "")
			log.Info("purchases synced", "mode", mode, "fetched", st.Fetched, "created", st.Created, "updated", st.Updated,
				"deleted", st.Deleted, "cursor", cursor)
		}
	}
	return res
}

// syncSuppliers is a full snapshot with diff-based soft deletes, like shops.
func (e *Engine) syncSuppliers(ctx context.Context, pp cloud.PurchasingProvider, set Settings, tc tally.Company, cloudID string, res *purchasingResult) (Stats, map[string]string, error) {
	var st Stats
	list, err := e.Tally.GetSuppliers(ctx, tc.Name)
	if err != nil {
		return st, nil, err
	}
	now := e.now()
	rows := make([]cloud.Supplier, 0, len(list))
	for _, c := range list {
		rows = append(rows, supplierFromCustomer(set.Business.ID, cloudID, c, now))
	}
	existing, err := pp.ListSuppliers(ctx, cloudID)
	if err != nil {
		return st, nil, err
	}
	ids := map[string]string{}
	if len(rows) > 0 {
		if ids, err = pp.UpsertSuppliers(ctx, rows); err != nil {
			return st, nil, err
		}
	}
	st.Fetched = len(rows)
	gone, created := diffRefs(existing, ids)
	st.Created, st.Updated = created, len(rows)-created
	if massDeleteBlocked(len(existing), len(gone)) {
		res.warnings = append(res.warnings, massDeleteWarning(cloud.EntitySuppliers, len(existing), len(gone)))
		gone = nil
	}
	if len(gone) > 0 {
		if err := pp.SoftDeleteSuppliers(ctx, gone); err != nil {
			return st, nil, err
		}
		st.Deleted = len(gone)
	}
	byName := make(map[string]string, len(list))
	for _, c := range list {
		byName[c.Name] = ids[c.ID]
		for _, a := range c.Aliases {
			if _, taken := byName[a]; !taken {
				byName[a] = ids[c.ID]
			}
		}
	}
	return st, byName, nil
}

// syncStockItems is a full snapshot with diff-based soft deletes.
func (e *Engine) syncStockItems(ctx context.Context, pp cloud.PurchasingProvider, set Settings, tc tally.Company, cloudID string, res *purchasingResult) (Stats, map[string]string, error) {
	var st Stats
	items, err := e.Tally.GetStockItems(ctx, tc.Name)
	if err != nil {
		return st, nil, err
	}
	now := e.now()
	rows := make([]cloud.StockItem, 0, len(items))
	for _, it := range items {
		if it.ID != "" {
			rows = append(rows, stockItemFromTally(set.Business.ID, cloudID, it, now))
		}
	}
	existing, err := pp.ListStockItems(ctx, cloudID)
	if err != nil {
		return st, nil, err
	}
	ids := map[string]string{}
	if len(rows) > 0 {
		if ids, err = pp.UpsertStockItems(ctx, rows); err != nil {
			return st, nil, err
		}
	}
	st.Fetched = len(rows)
	gone, created := diffRefs(existing, ids)
	st.Created, st.Updated = created, len(rows)-created
	if massDeleteBlocked(len(existing), len(gone)) {
		res.warnings = append(res.warnings, massDeleteWarning(cloud.EntityStockItems, len(existing), len(gone)))
		gone = nil
	}
	if len(gone) > 0 {
		if err := pp.SoftDeleteStockItems(ctx, gone); err != nil {
			return st, nil, err
		}
		st.Deleted = len(gone)
	}
	byName := make(map[string]string, len(items))
	for _, it := range items {
		byName[it.Name] = ids[it.ID]
	}
	return st, byName, nil
}

// syncPurchases: "full" and "reconcile" read every purchase bill and
// soft-delete the ones Tally no longer has; "incremental" reads only bills
// altered since the cursor and soft-deletes those that became cancelled or
// optional. Returns the new cursor and the number of active bills.
func (e *Engine) syncPurchases(ctx context.Context, pp cloud.PurchasingProvider, set Settings, tc tally.Company, cloudID, mode string,
	cursor int64, supplierIDByName, itemIDByName map[string]string, res *purchasingResult) (Stats, int64, int, error) {
	var st Stats
	since := cursor
	if mode != "incremental" {
		since = 0
	}
	list, err := e.Tally.GetPurchasesSince(ctx, &tc, since)
	if err != nil {
		return st, cursor, 0, err
	}
	existing, err := pp.ListPurchases(ctx, cloudID)
	if err != nil {
		return st, cursor, 0, err
	}
	have := make(map[string]string, len(existing))
	for _, r := range existing {
		have[r.Key] = r.ID
	}
	now := e.now()
	rows := make([]cloud.Purchase, 0, len(list.Purchases))
	seen := make(map[string]bool, len(list.Purchases))
	for _, p := range list.Purchases {
		rows = append(rows, purchaseFromTally(set.Business.ID, cloudID, p, supplierIDByName, itemIDByName, now))
		seen[p.ID] = true
		if _, ok := have[p.ID]; ok {
			st.Updated++
		} else {
			st.Created++
		}
	}
	if len(rows) > 0 {
		if err := pp.UpsertPurchases(ctx, rows); err != nil {
			return st, cursor, 0, err
		}
	}
	st.Fetched = len(rows)

	var gone []string
	if mode == "incremental" {
		for _, id := range list.ExcludedIDs {
			if cid, ok := have[id]; ok {
				gone = append(gone, cid)
			}
		}
	} else {
		for key, cid := range have {
			if !seen[key] {
				gone = append(gone, cid)
			}
		}
	}
	if mode != "incremental" && massDeleteBlocked(len(have), len(gone)) {
		res.warnings = append(res.warnings, massDeleteWarning(cloud.EntityPurchases, len(have), len(gone)))
		gone = nil
	}
	if len(gone) > 0 {
		if err := pp.SoftDeletePurchases(ctx, gone); err != nil {
			return st, cursor, 0, err
		}
		st.Deleted = len(gone)
	}
	cursor = max(cursor, list.MaxAlterID)
	active := len(have) + st.Created - st.Deleted
	if mode != "incremental" {
		active = len(rows)
	}
	return st, cursor, max(active, 0), nil
}

// diffRefs returns the cloud ids of rows no longer written (to soft-delete)
// and how many written keys are new.
func diffRefs(existing []cloud.Ref, written map[string]string) (gone []string, created int) {
	had := make(map[string]bool, len(existing))
	for _, r := range existing {
		had[r.Key] = true
		if _, still := written[r.Key]; !still {
			gone = append(gone, r.ID)
		}
	}
	for key := range written {
		if !had[key] {
			created++
		}
	}
	return gone, created
}

// ---------------------------------------------------------------- transforms

func supplierFromCustomer(businessID, companyID string, c tally.Customer, now time.Time) cloud.Supplier {
	phone := ""
	if len(c.Phones) > 0 {
		phone = c.Phones[0]
	}
	return cloud.Supplier{
		BusinessID: businessID, CompanyID: companyID, TallyLedgerID: c.ID, TallyMasterID: c.MasterID, TallyAlterID: c.AlterID,
		Name: c.Name, Aliases: c.Aliases, Group: c.Group, Phone: phone, Phones: c.Phones, ContactPerson: c.ContactPerson,
		Email: c.Email, GSTIN: c.GSTIN, GSTRegType: c.GSTRegType, Address: c.Address, State: c.State, Pincode: c.Pincode,
		Country: c.Country, OpeningAmount: c.OpeningBalance.Amount, OpeningType: c.OpeningBalance.Type,
		BalanceAmount: c.Balance.Amount, BalanceType: c.Balance.Type, Payable: -c.Receivable, SyncedAt: now,
	}
}

func stockItemFromTally(businessID, companyID string, it tally.StockItem, now time.Time) cloud.StockItem {
	return cloud.StockItem{
		BusinessID: businessID, CompanyID: companyID, TallyItemID: it.ID, Name: it.Name, Aliases: it.Aliases, Group: it.Group,
		Category: it.Category, Unit: it.Unit, GST: it.GST, OpeningQty: it.OpeningQty, OpeningValue: it.OpeningValue,
		ClosingQty: it.ClosingQty, ClosingRate: it.ClosingRate, ClosingValue: it.ClosingValue, ReorderLevel: it.ReorderLevel,
		MinOrderQty: it.MinOrderQty, Status: it.Status, SyncedAt: now,
	}
}

func purchaseFromTally(businessID, companyID string, p tally.Purchase, supplierIDByName, itemIDByName map[string]string, now time.Time) cloud.Purchase {
	out := cloud.Purchase{
		BusinessID: businessID, CompanyID: companyID, TallyVoucherID: p.ID, TallyAlterID: p.AlterID,
		SupplierID: supplierIDByName[p.Supplier], SupplierName: p.Supplier, Date: p.Date, VoucherNumber: p.Number,
		VoucherType: p.VoucherType, Reference: p.Reference, Narration: p.Narration, Taxable: p.Taxable, Other: p.Other,
		Total: p.Total, Qty: p.Qty, SyncedAt: now,
	}
	for _, l := range p.Ledgers {
		out.LedgerEntries = append(out.LedgerEntries, cloud.PurchaseLedgerEntry{Ledger: l.Ledger, Amount: l.Amount.Amount, Type: l.Amount.Type})
	}
	for i, l := range p.Lines {
		out.Lines = append(out.Lines, cloud.PurchaseLine{LineNo: i + 1, StockItemID: itemIDByName[l.Item], ItemName: l.Item,
			Godown: l.Godown, Qty: l.Qty, ActualQty: l.ActualQt, Unit: l.Unit, Rate: l.Rate, Discount: l.Discount, Amount: l.Amount})
	}
	return out
}
