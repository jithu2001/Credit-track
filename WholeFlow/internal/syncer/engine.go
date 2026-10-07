package syncer

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	gosync "sync"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/tally"
)

// Engine performs one synchronisation run: every enabled company, in a
// deterministic order, each independent of the others' failures.
type Engine struct {
	Tally     *tally.Service
	Provider  ProviderFactory
	Settings  *SettingsStore
	State     *StateStore
	Log       *slog.Logger
	TallyHost string
	TallyPort int
	Hostname  string
	Now       func() time.Time

	mu gosync.Mutex
	// stopCode is the refusal (subscription ended / PC revoked) the last run
	// stopped on, so it is logged once and "resumed" is logged when it clears.
	stopCode string
}

// RunResult summarises one run for the status page, logs and tests.
type RunResult struct {
	StartedAt    time.Time       `json:"startedAt"`
	CompletedAt  time.Time       `json:"completedAt"`
	Status       string          `json:"status"` // success | partial | failed | skipped | paused | revoked
	ErrorCode    string          `json:"errorCode,omitempty"`
	ErrorMessage string          `json:"errorMessage,omitempty"`
	Companies    []CompanyResult `json:"companies"`
	// Warnings about the run as a whole (e.g. companies left out by the plan's limit).
	Warnings []string `json:"warnings,omitempty"`
}

// Run statuses for a server that refuses on purpose. Neither counts as a
// failure: there is nothing to retry faster, and no data was touched.
const (
	RunPaused  = "paused"  // subscription ended; resumes by itself
	RunRevoked = "revoked" // this PC's key was revoked; needs a new activation code
)

// Failed reports whether the run should count towards backoff.
func (r *RunResult) Failed() bool { return r.Status == "failed" || r.Status == "partial" }

type CompanyResult struct {
	TallyID      string    `json:"tallyId"`
	Name         string    `json:"name"`
	CloudID      string    `json:"cloudId,omitempty"`
	Status       string    `json:"status"`
	Mode         string    `json:"mode,omitempty"` // full | incremental | reconcile
	ErrorCode    string    `json:"errorCode,omitempty"`
	ErrorMessage string    `json:"errorMessage,omitempty"`
	StartedAt    time.Time `json:"startedAt"`
	DurationMs   int64     `json:"durationMs"`
	Shops        Stats     `json:"shops"`
	Transactions Stats     `json:"transactions"`
	Vouchers     int       `json:"vouchersFetched"`
	Excluded     int       `json:"vouchersExcluded"`
	Cursor       int64     `json:"cursor"`

	// Secondary steps; nil when switched off or failed (see Warnings).
	Suppliers    *Stats   `json:"suppliers,omitempty"`
	StockItems   *Stats   `json:"stockItems,omitempty"`
	Purchases    *Stats   `json:"purchases,omitempty"`
	PurchaseMode string   `json:"purchaseMode,omitempty"`
	Warnings     []string `json:"warnings,omitempty"`
}

type Stats struct {
	Fetched int `json:"fetched"`
	Created int `json:"created"`
	Updated int `json:"updated"`
	Deleted int `json:"deleted"`
}

func (e *Engine) now() time.Time {
	if e.Now != nil {
		return e.Now()
	}
	return time.Now()
}

// Run executes one full cycle. It never returns an error: everything that
// went wrong is in the result and in the persisted state.
func (e *Engine) Run(ctx context.Context) *RunResult {
	e.mu.Lock()
	defer e.mu.Unlock()

	set := e.Settings.Get()
	res := &RunResult{StartedAt: e.now(), Companies: []CompanyResult{}}
	defer func() {
		res.CompletedAt = e.now()
		e.State.Update(func(st *State) { st.LastRun = res })
	}()

	if ok, why := set.Configured(); !ok {
		res.Status, res.ErrorCode, res.ErrorMessage = "skipped", "NOT_CONFIGURED", why
		return res
	}
	enabled, over := set.SyncCompanies()
	if over > 0 {
		w := CompanyLimitWarning(set.CompanyLimit(), len(enabled)+over)
		e.Log.Warn("company limit", "detail", w)
		res.Warnings = append(res.Warnings, w)
	}
	e.Log.Info("sync run started", "business", set.Business.ID, "companies", len(enabled), "provider", set.Cloud.Provider)

	prov, err := e.Provider(set)
	if err != nil {
		e.failAll(res, enabled, err)
		return res
	}
	if err := prov.Authenticate(ctx); err != nil {
		e.failAll(res, enabled, err)
		return res
	}
	if e.stopCode != "" {
		e.Log.Info("the cloud accepts this PC again; sync resumed", "was", e.stopCode)
		e.stopCode = ""
	}

	tallyCompanies, err := e.Tally.GetCompanies(ctx)
	if err != nil {
		e.failAll(res, enabled, err)
		e.recordOutage(ctx, prov, set, enabled, err)
		return res
	}
	open := map[string]tally.Company{}
	for _, c := range tallyCompanies {
		open[c.GUID] = c
	}

	connID, err := prov.UpsertConnection(ctx, cloud.Connection{
		BusinessID: set.Business.ID, MachineIdentifier: e.Hostname, Hostname: e.Hostname,
		TallyHost: e.TallyHost, TallyPort: e.TallyPort, Status: "online", AppVersion: Version, LastSeenAt: e.now(),
	})
	if err != nil {
		e.failAll(res, enabled, err)
		return res
	}

	okCount := 0
	for _, cs := range enabled {
		if ctx.Err() != nil {
			e.failAll(res, enabled[len(res.Companies):], ctx.Err())
			break
		}
		tc, isOpen := open[cs.TallyID]
		var cr CompanyResult
		if !isOpen {
			cr = CompanyResult{TallyID: cs.TallyID, Name: cs.Name, StartedAt: e.now(), Status: StatusNotOpen,
				ErrorCode: string(tally.KindCompanyNotFound), ErrorMessage: "company is not open in TallyPrime"}
			e.recordCompanyFailure(ctx, prov, set, cs, cr)
		} else {
			cr = e.syncCompany(ctx, prov, set, cs, tc, connID)
		}
		if cr.Status == StatusSynced {
			okCount++
		}
		res.Companies = append(res.Companies, cr)
		if isStop(cr.ErrorCode) {
			// Every further request would be refused the same way.
			stopErr := &cloud.Error{Kind: cloud.ErrorKind(cr.ErrorCode), Op: "sync", Msg: cr.ErrorMessage}
			res.Companies = res.Companies[:len(res.Companies)-1]
			e.failAll(res, enabled[len(res.Companies):], stopErr)
			return res
		}
	}
	switch {
	case okCount == len(res.Companies):
		res.Status = "success"
	case okCount == 0:
		res.Status = "failed"
		res.ErrorCode, res.ErrorMessage = firstError(res.Companies)
	default:
		res.Status = "partial"
		res.ErrorCode, res.ErrorMessage = firstError(res.Companies)
	}
	e.Log.Info("sync run finished", "status", res.Status, "ok", okCount, "companies", len(res.Companies),
		"duration_ms", e.now().Sub(res.StartedAt).Milliseconds())
	return res
}

func firstError(crs []CompanyResult) (string, string) {
	for _, c := range crs {
		if c.ErrorCode != "" {
			return c.ErrorCode, c.ErrorMessage
		}
	}
	return "", ""
}

// failAll marks the run and every listed company as failed with the same
// error. A deliberate refusal (subscription ended, PC revoked) pauses or
// stops the run instead, and is logged only when it first appears.
func (e *Engine) failAll(res *RunResult, companies []CompanySetting, err error) {
	code, msg := classify(err)
	res.Status, res.ErrorCode, res.ErrorMessage = "failed", code, msg
	if isStop(code) {
		e.stop(res, code, msg)
		code, msg = res.ErrorCode, res.ErrorMessage
	} else {
		e.Log.Error("sync run failed", "code", code, "error", msg)
	}
	status := statusFor(code)
	now := e.now()
	for _, cs := range companies {
		res.Companies = append(res.Companies, CompanyResult{TallyID: cs.TallyID, Name: cs.Name, StartedAt: now,
			Status: status, ErrorCode: code, ErrorMessage: msg})
		e.State.UpdateCompany(cs.TallyID, func(c *CompanyState) {
			c.Name, c.Status, c.LastErrorCode, c.LastError = cs.Name, status, code, msg
			c.LastAttemptAt = &now
		})
	}
}

// isStop reports whether code is a deliberate refusal by the server.
func isStop(code string) bool {
	return code == string(cloud.KindSubscriptionEnded) || code == string(cloud.KindDeviceRevoked)
}

// stop turns the run into "paused" (subscription ended) or "revoked". A
// revoked PC is remembered in the settings so no further requests are made
// until it is connected again.
func (e *Engine) stop(res *RunResult, code, serverMsg string) {
	res.ErrorCode = code
	if code == string(cloud.KindDeviceRevoked) {
		res.Status, res.ErrorMessage = RunRevoked, MsgDeviceRevoked
		if err := e.Settings.Update(func(s *Settings) error {
			if s.Linked() {
				s.Cloud.Link.Revoked = true
			}
			return nil
		}); err != nil {
			e.Log.Warn("could not save the revoked state", "error", err.Error())
		}
	} else {
		res.Status, res.ErrorMessage = RunPaused, MsgSubscriptionEnded
	}
	if e.stopCode != code {
		e.stopCode = code
		e.Log.Warn(res.ErrorMessage, "code", code, "server", serverMsg)
	}
}

// recordOutage writes the Tally-offline error to the cloud sync state so the
// mobile app can show "last sync failed" — without touching any data rows.
func (e *Engine) recordOutage(ctx context.Context, prov cloud.Provider, set Settings, companies []CompanySetting, err error) {
	code, msg := classify(err)
	for _, cs := range companies {
		cloudID := e.State.Company(cs.TallyID).CloudID
		if cloudID == "" {
			continue
		}
		st := cloud.SyncState{BusinessID: set.Business.ID, CompanyID: cloudID, EntityType: cloud.EntityCompany,
			LastAttemptAt: e.now(), Status: "error", ErrorCode: code, ErrorMessage: msg}
		if prev, perr := prov.GetSyncState(ctx, cloudID, cloud.EntityCompany); perr == nil && prev != nil {
			st.LastSuccessfulSyncAt, st.LastCursor, st.RecordsProcessed = prev.LastSuccessfulSyncAt, prev.LastCursor, prev.RecordsProcessed
		}
		if uerr := prov.UpdateSyncState(ctx, st); uerr != nil {
			e.Log.Warn("could not record outage in cloud", "company", cs.Name, "error", uerr.Error())
		}
	}
}

func (e *Engine) recordCompanyFailure(ctx context.Context, prov cloud.Provider, set Settings, cs CompanySetting, cr CompanyResult) {
	now := e.now()
	e.State.UpdateCompany(cs.TallyID, func(c *CompanyState) {
		c.Name, c.Status, c.LastErrorCode, c.LastError = cs.Name, cr.Status, cr.ErrorCode, cr.ErrorMessage
		c.LastAttemptAt = &now
	})
	e.recordOutage(ctx, prov, set, []CompanySetting{cs}, &tally.Error{Kind: tally.ErrorKind(cr.ErrorCode), Op: "company", Msg: cr.ErrorMessage})
}

// ---------------------------------------------------------------- one company

func (e *Engine) syncCompany(ctx context.Context, prov cloud.Provider, set Settings, cs CompanySetting, tc tally.Company, connID string) CompanyResult {
	start := e.now()
	cr := CompanyResult{TallyID: tc.GUID, Name: tc.Name, StartedAt: start, Status: StatusSyncing}
	prev := e.State.Company(tc.GUID)
	log := e.Log.With("company", tc.Name)
	log.Info("SYNC START", "business", set.Business.ID)

	e.State.UpdateCompany(tc.GUID, func(c *CompanyState) {
		c.Name, c.Status, c.LastAttemptAt = tc.Name, StatusSyncing, &start
	})

	finish := func(err error, entity string) CompanyResult {
		code, msg := classify(err)
		cr.Status, cr.ErrorCode, cr.ErrorMessage = statusFor(code), code, msg
		cr.DurationMs = e.now().Sub(start).Milliseconds()
		log.Error("SYNC FAILED", "entity", entity, "code", code, "error", msg, "duration_ms", cr.DurationMs)
		now := e.now()
		e.State.UpdateCompany(tc.GUID, func(c *CompanyState) {
			c.Status, c.LastErrorCode, c.LastError, c.LastAttemptAt = cr.Status, code, msg, &now
			if cr.CloudID != "" {
				c.CloudID = cr.CloudID
			}
		})
		if k := cloud.KindOf(err); cr.CloudID != "" && k != cloud.KindUnreachable && k != cloud.KindTimeout && k != cloud.KindAuth &&
			k != cloud.KindSubscriptionEnded && k != cloud.KindDeviceRevoked {
			e.writeState(ctx, prov, set, cr.CloudID, entity, now, nil, "", 0, code, msg)
			e.writeState(ctx, prov, set, cr.CloudID, cloud.EntityCompany, now, prev.LastSuccessAt, strconv.FormatInt(prev.VoucherCursor, 10), 0, code, msg)
			prov.UpsertCompany(ctx, companyFromTally(set.Business.ID, connID, tc, cs, cr.Status, prev.LastSuccessAt))
			e.writeLog(ctx, prov, set, cr, "failed")
		}
		return cr
	}

	// 3. company metadata
	cloudID, err := prov.UpsertCompany(ctx, companyFromTally(set.Business.ID, connID, tc, cs, StatusSyncing, prev.LastSuccessAt))
	if err != nil {
		return finish(err, cloud.EntityCompany)
	}
	cr.CloudID = cloudID
	// The cursors in state.json describe what was sent to *this* cloud company
	// row. A different id means a different business id, a switched provider
	// or cloud data that was wiped: start over with full syncs, otherwise the
	// new row would only ever receive changes made from now on.
	if prev.CloudID != "" && prev.CloudID != cloudID {
		log.Warn("cloud company changed; resetting cursors for a full sync", "previous_cloud_id", prev.CloudID, "cloud_id", cloudID)
		prev.VoucherCursor, prev.LastFullReconcileAt, prev.TransactionCount = 0, nil, 0
		prev.PurchaseCursor, prev.LastPurchaseReconcileAt = 0, nil
	}
	e.State.UpdateCompany(tc.GUID, func(c *CompanyState) { c.CloudID = cloudID })

	// 4 + 5. shops with current balances (always a full snapshot: cheap, and
	// ledgers carry no reliable change marker we can filter on server-side)
	customers, err := e.Tally.GetCustomers(ctx, tc.Name)
	if err != nil {
		return finish(err, cloud.EntityShops)
	}
	cr.Shops.Fetched = len(customers)
	now := e.now()
	shops := make([]cloud.Shop, 0, len(customers))
	ledgerIDByName := make(map[string]string, len(customers))
	for _, c := range customers {
		shops = append(shops, shopFromCustomer(set.Business.ID, cloudID, c, now))
		ledgerIDByName[c.Name] = c.ID
		for _, a := range c.Aliases {
			if _, taken := ledgerIDByName[a]; !taken {
				ledgerIDByName[a] = c.ID
			}
		}
	}
	existingShops, err := prov.ListShops(ctx, cloudID)
	if err != nil {
		return finish(err, cloud.EntityShops)
	}
	existingByLedger := make(map[string]string, len(existingShops))
	for _, r := range existingShops {
		existingByLedger[r.TallyLedgerID] = r.ID
	}
	shopIDByLedger := map[string]string{}
	if len(shops) > 0 {
		shopIDByLedger, err = prov.UpsertShops(ctx, shops)
		if err != nil {
			return finish(err, cloud.EntityShops)
		}
	}
	for _, s := range shops {
		if _, ok := existingByLedger[s.TallyLedgerID]; ok {
			cr.Shops.Updated++
		} else {
			cr.Shops.Created++
		}
	}
	// Shops that Tally no longer returns (deleted, moved out of the shop group)
	// are soft-deleted — only now, after a successful read from Tally.
	var goneShops []string
	for ledgerID, id := range existingByLedger {
		if _, still := shopIDByLedger[ledgerID]; !still {
			goneShops = append(goneShops, id)
		}
	}
	if massDeleteBlocked(len(existingByLedger), len(goneShops)) {
		w := massDeleteWarning(cloud.EntityShops, len(existingByLedger), len(goneShops))
		log.Warn("SAFETY CHECK", "detail", w)
		cr.Warnings = append(cr.Warnings, w)
		goneShops = nil
	}
	if len(goneShops) > 0 {
		if err := prov.SoftDeleteShops(ctx, goneShops); err != nil {
			return finish(err, cloud.EntityShops)
		}
		cr.Shops.Deleted = len(goneShops)
	}
	e.writeState(ctx, prov, set, cloudID, cloud.EntityShops, now, &now, "", len(shops), "", "")
	log.Info("shops synced", "fetched", cr.Shops.Fetched, "created", cr.Shops.Created, "updated", cr.Shops.Updated, "deleted", cr.Shops.Deleted)

	// 6. transactions (incremental by AlterID; deletions found by periodic reconcile)
	cursor := prev.VoucherCursor
	lastReconcile := prev.LastFullReconcileAt
	if set.Sync.Transactions {
		switch {
		case cursor == 0:
			cr.Mode = "full"
		case lastReconcile == nil || e.now().Sub(*lastReconcile) >= time.Duration(set.Sync.FullReconcileHours)*time.Hour:
			cr.Mode = "reconcile"
		default:
			cr.Mode = "incremental"
		}
		// A shop that is new in the cloud (created in Tally, moved into a shop
		// group, restored) has history older than the cursor: read everything.
		if cr.Mode == "incremental" && cr.Shops.Created > 0 {
			cr.Mode = "reconcile"
		}
		// full and reconcile re-read every voucher, so gaps (unparsed amounts,
		// ledgers that became shops, post-dated vouchers) heal on schedule.
		since := cursor
		if cr.Mode != "incremental" {
			since = 0
		}
		vouchers, err := e.Tally.GetVouchers(ctx, &tc, since)
		if err != nil {
			return finish(err, cloud.EntityTransactions)
		}
		txns, ts := transactionsFromVouchers(set.Business.ID, cloudID, vouchers, ledgerIDByName, shopIDByLedger, e.now())
		cr.Vouchers, cr.Excluded, cr.Transactions.Fetched = ts.Vouchers, ts.Excluded, len(txns)

		// Which cloud rows may be affected: all (full/reconcile) or only the vouchers we fetched.
		var scope []string
		if cr.Mode == "incremental" {
			scope = make([]string, 0, len(vouchers))
			for _, v := range vouchers {
				scope = append(scope, v.GUID)
			}
		}
		var existing []cloud.TransactionRef
		if cr.Mode != "incremental" || len(scope) > 0 {
			existing, err = prov.ListTransactions(ctx, cloudID, scope)
			if err != nil {
				return finish(err, cloud.EntityTransactions)
			}
		}
		existingByKey := make(map[string]cloud.TransactionRef, len(existing))
		for _, r := range existing {
			existingByKey[r.Key()] = r
		}
		newKeys := make(map[string]bool, len(txns))
		for _, t := range txns {
			newKeys[t.Key()] = true
			if _, ok := existingByKey[t.Key()]; ok {
				cr.Transactions.Updated++
			} else {
				cr.Transactions.Created++
			}
		}
		if len(txns) > 0 {
			if err := prov.UpsertTransactions(ctx, txns); err != nil {
				return finish(err, cloud.EntityTransactions)
			}
		}

		// Deletions. Full: anything not in this snapshot. Reconcile: vouchers
		// Tally no longer lists at all, plus entries of touched vouchers that
		// no longer hit a shop. Incremental: only the latter, within scope.
		var gone []string
		switch cr.Mode {
		case "full", "reconcile":
			for key, r := range existingByKey {
				if !newKeys[key] {
					gone = append(gone, r.ID)
				}
			}
		default:
			for key, r := range existingByKey {
				if !newKeys[key] {
					gone = append(gone, r.ID)
				}
			}
		}
		if cr.Mode != "incremental" && massDeleteBlocked(len(existingByKey), len(gone)) {
			w := massDeleteWarning(cloud.EntityTransactions, len(existingByKey), len(gone))
			log.Warn("SAFETY CHECK", "detail", w)
			cr.Warnings = append(cr.Warnings, w)
			gone = nil
		}
		if len(gone) > 0 {
			if err := prov.SoftDeleteTransactions(ctx, gone); err != nil {
				return finish(err, cloud.EntityTransactions)
			}
			cr.Transactions.Deleted = len(gone)
		}
		if ts.MaxAlterID > cursor {
			cursor = ts.MaxAlterID
		}
		cr.Cursor = cursor
		doneAt := e.now()
		if cr.Mode != "incremental" {
			lastReconcile = &doneAt
		}
		e.writeState(ctx, prov, set, cloudID, cloud.EntityTransactions, doneAt, &doneAt, strconv.FormatInt(cursor, 10), len(txns), "", "")
		log.Info("transactions synced", "mode", cr.Mode, "vouchers", cr.Vouchers, "excluded", cr.Excluded, "fetched", cr.Transactions.Fetched,
			"created", cr.Transactions.Created, "updated", cr.Transactions.Updated, "deleted", cr.Transactions.Deleted, "cursor", cursor)
	}

	// 6b. suppliers, stock items, purchase bills (secondary: failures are warnings)
	pr := e.syncPurchasing(ctx, prov, set, tc, cloudID, prev, log)
	cr.Suppliers, cr.StockItems, cr.Purchases, cr.PurchaseMode = pr.suppliers, pr.stock, pr.purchases, pr.purchaseMode
	cr.Warnings = append(cr.Warnings, pr.warnings...)

	// 7 + 8. company status, sync state, sync log — only now is it "synced".
	done := e.now()
	cr.Status = StatusSynced
	cr.DurationMs = done.Sub(start).Milliseconds()
	if _, err := prov.UpsertCompany(ctx, companyFromTally(set.Business.ID, connID, tc, cs, StatusSynced, &done)); err != nil {
		return finish(err, cloud.EntityCompany)
	}
	e.writeState(ctx, prov, set, cloudID, cloud.EntityCompany, done, &done, strconv.FormatInt(cursor, 10), len(shops)+cr.Transactions.Fetched, "", "")
	e.writeLog(ctx, prov, set, cr, "success")

	txCount := prev.TransactionCount
	if set.Sync.Transactions {
		txCount = txCount + cr.Transactions.Created - cr.Transactions.Deleted
		if cr.Mode == "full" {
			txCount = cr.Transactions.Fetched
		}
		if txCount < 0 {
			txCount = 0
		}
	}
	e.State.UpdateCompany(tc.GUID, func(c *CompanyState) {
		c.Status, c.LastErrorCode, c.LastError = StatusSynced, "", ""
		c.LastAttemptAt, c.LastSuccessAt = &done, &done
		c.VoucherCursor, c.LastFullReconcileAt = cursor, lastReconcile
		c.ShopCount, c.TransactionCount, c.CloudID = len(shops), txCount, cloudID
		c.SupplierCount, c.StockItemCount, c.PurchaseCount = pr.supplierCount, pr.stockCount, pr.purchaseCount
		c.PurchaseCursor, c.LastPurchaseReconcileAt, c.Warnings = pr.purchaseCursor, pr.lastReconcile, cr.Warnings
	})
	log.Info("SYNC COMPLETE", "shops", cr.Shops.Fetched, "transactions", cr.Transactions.Fetched, "mode", cr.Mode, "duration_ms", cr.DurationMs)
	return cr
}

func (e *Engine) writeState(ctx context.Context, prov cloud.Provider, set Settings, cloudID, entity string, attempt time.Time,
	success *time.Time, cursor string, processed int, code, msg string) {
	st := cloud.SyncState{BusinessID: set.Business.ID, CompanyID: cloudID, EntityType: entity, LastAttemptAt: attempt,
		LastSuccessfulSyncAt: success, LastCursor: cursor, RecordsProcessed: processed, Status: "ok", ErrorCode: code, ErrorMessage: msg}
	if code != "" {
		st.Status = "error"
		// keep the previous success timestamp/cursor so "last successful sync" survives failures
		if prev, err := prov.GetSyncState(ctx, cloudID, entity); err == nil && prev != nil {
			st.LastSuccessfulSyncAt = prev.LastSuccessfulSyncAt
			if st.LastCursor == "" {
				st.LastCursor = prev.LastCursor
			}
			st.RecordsProcessed = prev.RecordsProcessed
		}
	}
	if err := prov.UpdateSyncState(ctx, st); err != nil {
		e.Log.Warn("could not update cloud sync state", "entity", entity, "error", err.Error())
	}
}

func (e *Engine) writeLog(ctx context.Context, prov cloud.Provider, set Settings, cr CompanyResult, status string) {
	all := Stats{Fetched: cr.Shops.Fetched + cr.Transactions.Fetched, Created: cr.Shops.Created + cr.Transactions.Created,
		Updated: cr.Shops.Updated + cr.Transactions.Updated, Deleted: cr.Shops.Deleted + cr.Transactions.Deleted}
	for _, s := range []*Stats{cr.Suppliers, cr.StockItems, cr.Purchases} {
		if s != nil {
			all.Fetched, all.Created, all.Updated, all.Deleted = all.Fetched+s.Fetched, all.Created+s.Created, all.Updated+s.Updated, all.Deleted+s.Deleted
		}
	}
	code, msg := cr.ErrorCode, cr.ErrorMessage
	if code == "" && len(cr.Warnings) > 0 {
		code, msg = "STEP_WARNINGS", strings.Join(cr.Warnings, "; ")
	}
	l := cloud.SyncLog{BusinessID: set.Business.ID, CompanyID: cr.CloudID, StartedAt: cr.StartedAt,
		CompletedAt: cr.StartedAt.Add(time.Duration(cr.DurationMs) * time.Millisecond), Status: status, Mode: cr.Mode,
		RecordsProcessed: all.Fetched, RecordsCreated: all.Created, RecordsUpdated: all.Updated, RecordsDeleted: all.Deleted,
		ShopsProcessed: cr.Shops.Fetched, TransactionsFetched: cr.Transactions.Fetched, ErrorCode: code, ErrorMessage: msg}
	if err := prov.CreateSyncLog(ctx, l); err != nil {
		e.Log.Warn("could not write cloud sync log", "error", err.Error())
	}
}

// ---------------------------------------------------------------- error mapping

// classify turns any error into (code, safe message) using the Tally and
// cloud classifications; nothing else is ever invented.
func classify(err error) (string, string) {
	if err == nil {
		return "", ""
	}
	var te *tally.Error
	if errors.As(err, &te) {
		msg := te.Msg
		if msg == "" && te.Err != nil {
			msg = te.Err.Error()
		}
		return string(te.Kind), msg
	}
	var ce *cloud.Error
	if errors.As(err, &ce) {
		msg := ce.Msg
		if msg == "" && ce.Err != nil {
			msg = ce.Err.Error()
		}
		return string(ce.Kind), msg
	}
	if errors.Is(err, context.Canceled) {
		return "CANCELLED", "sync was stopped"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "TIMEOUT", "sync timed out"
	}
	return "INTERNAL", err.Error()
}

// statusFor maps an error code to the company status vocabulary.
func statusFor(code string) string {
	switch {
	case code == "":
		return StatusSynced
	case code == string(cloud.KindSubscriptionEnded):
		return StatusSubscriptionEnded
	case code == string(cloud.KindDeviceRevoked):
		return StatusDeviceRevoked
	case code == string(tally.KindUnreachable), code == string(tally.KindTimeout):
		return StatusTallyOffline
	case code == string(cloud.KindUnreachable), code == string(cloud.KindTimeout):
		return StatusCloudOffline
	case code == string(cloud.KindAuth), code == string(cloud.KindConfig), code == string(cloud.KindNotFound):
		return StatusAuthError
	case code == string(tally.KindCompanyNotFound):
		return StatusNotOpen
	case strings.HasPrefix(code, "TALLY_"), strings.HasPrefix(code, "CLOUD_"):
		return StatusSyncError
	}
	return StatusSyncError
}

// String renders a run the way the logs describe it.
func (r *RunResult) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "Run %s: %s", r.StartedAt.Format("02 Jan 2006 15:04:05"), r.Status)
	if r.ErrorCode != "" {
		fmt.Fprintf(&b, " (%s: %s)", r.ErrorCode, r.ErrorMessage)
	}
	for _, c := range r.Companies {
		fmt.Fprintf(&b, "\n  %-40s %-16s", c.Name, c.Status)
		if c.Status == StatusSynced {
			fmt.Fprintf(&b, " shops %d (+%d ~%d -%d)  txns %d (+%d ~%d -%d)  %s  %.1fs",
				c.Shops.Fetched, c.Shops.Created, c.Shops.Updated, c.Shops.Deleted,
				c.Transactions.Fetched, c.Transactions.Created, c.Transactions.Updated, c.Transactions.Deleted,
				c.Mode, float64(c.DurationMs)/1000)
			for _, x := range []struct {
				label string
				s     *Stats
			}{{"suppliers", c.Suppliers}, {"items", c.StockItems}, {"purchases", c.Purchases}} {
				if x.s != nil {
					fmt.Fprintf(&b, "  %s %d (+%d ~%d -%d)", x.label, x.s.Fetched, x.s.Created, x.s.Updated, x.s.Deleted)
				}
			}
			for _, w := range c.Warnings {
				fmt.Fprintf(&b, "\n    warning: %s", w)
			}
		} else if c.ErrorCode != "" {
			fmt.Fprintf(&b, " %s: %s", c.ErrorCode, c.ErrorMessage)
		}
	}
	return b.String()
}

// massDeleteBlocked is the safety check before soft-deleting what Tally no
// longer returns. An empty read, or one that would remove more than half of
// ten or more cloud rows, usually means a wrong group setting or a damaged
// company rather than real deletions, so the deletes are skipped (with a
// warning) unless SYNC_ALLOW_MASS_DELETE=true.
func massDeleteBlocked(existing, gone int) bool {
	if gone == 0 || isTrue(os.Getenv("SYNC_ALLOW_MASS_DELETE")) {
		return false
	}
	return gone == existing || (existing >= 10 && gone*2 > existing)
}

func massDeleteWarning(entity string, existing, gone int) string {
	return fmt.Sprintf("%s: %d of %d cloud rows would be deleted; skipped as a safety check. Check the company and group settings in Tally; if the deletions are real, set SYNC_ALLOW_MASS_DELETE=true for one run", entity, gone, existing)
}
