package syncer

import (
	"strings"
	"time"

	"wholeflow/internal/cloud"
	"wholeflow/internal/tally"
)

// shopFromCustomer maps a Tally ledger (as interpreted by internal/tally) to
// the cloud shop row. Sign conventions are converted here, once.
func shopFromCustomer(businessID, companyID string, c tally.Customer, now time.Time) cloud.Shop {
	phone := ""
	if len(c.Phones) > 0 {
		phone = c.Phones[0]
	}
	return cloud.Shop{
		BusinessID: businessID, CompanyID: companyID, TallyLedgerID: c.ID, TallyMasterID: c.MasterID, TallyAlterID: c.AlterID,
		Name: c.Name, Aliases: c.Aliases, Group: c.Group, Phone: phone, Phones: c.Phones, PhoneSource: c.PhoneSource,
		ContactPerson: c.ContactPerson, Email: c.Email, GSTIN: c.GSTIN, GSTRegType: c.GSTRegType, Address: c.Address,
		State: c.State, Pincode: c.Pincode, Country: c.Country, Area: c.Area,
		OpeningAmount: c.OpeningBalance.Amount, OpeningType: c.OpeningBalance.Type,
		BalanceAmount: c.Balance.Amount, BalanceType: c.Balance.Type, Receivable: c.Receivable,
		SyncedAt: now,
	}
}

func companyFromTally(businessID, connectionID string, tc tally.Company, cs CompanySetting, status string, lastSync *time.Time) cloud.Company {
	return cloud.Company{
		BusinessID: businessID, ConnectionID: connectionID, TallyCompanyID: tc.GUID, Name: tc.Name, Number: strings.TrimSpace(tc.Number),
		FinancialYearFrom: tc.FinancialYear, BooksFrom: tc.BooksFrom, EndingAt: tc.EndingAt, PeriodFrom: tc.PeriodFrom, PeriodTo: tc.PeriodTo,
		LastVoucherDate: tc.LastVoucherDate, Enabled: cs.Enabled, SyncEnabled: cs.Enabled, SyncStatus: status, LastSyncAt: lastSync,
	}
}

// transformStats describes what happened to a batch of vouchers.
type transformStats struct {
	Vouchers   int // vouchers received from Tally
	Excluded   int // optional / cancelled / post-dated: not part of balances, not stored
	Unmapped   int // ledger entries that are not shops (sales accounts, tax, cash...)
	MaxAlterID int64
}

// transactionsFromVouchers turns vouchers into one transaction per (voucher,
// shop ledger). Entries on non-shop ledgers are ignored; several entries for
// the same shop in one voucher are summed.
func transactionsFromVouchers(businessID, companyID string, vouchers []tally.Voucher,
	ledgerIDByName map[string]string, shopIDByLedger map[string]string, now time.Time) ([]cloud.Transaction, transformStats) {

	var st transformStats
	out := make([]cloud.Transaction, 0, len(vouchers))
	for _, v := range vouchers {
		st.Vouchers++
		if v.AlterID > st.MaxAlterID {
			st.MaxAlterID = v.AlterID
		}
		if v.Excluded() {
			st.Excluded++
			continue
		}
		// Sum per shop ledger, preserving first-seen order for determinism.
		sums := map[string]tally.Amount{}
		var order []string
		for _, e := range v.Entries {
			ledgerID := ledgerIDByName[e.Ledger]
			if ledgerID == "" {
				st.Unmapped++
				continue
			}
			if _, seen := sums[ledgerID]; !seen {
				order = append(order, ledgerID)
			}
			sums[ledgerID] += e.Amount
		}
		for _, ledgerID := range order {
			amt := sums[ledgerID]
			if amt == 0 {
				continue
			}
			t := cloud.Transaction{
				BusinessID: businessID, CompanyID: companyID, ShopID: shopIDByLedger[ledgerID],
				TallyVoucherID: v.GUID, TallyLedgerID: ledgerID, TallyMasterID: v.MasterID, TallyAlterID: v.AlterID,
				Date: v.Date, VoucherNumber: v.Number, VoucherType: v.Type, BaseVoucherType: v.BaseType, Category: v.Category,
				Narration: v.Narration, Amount: amt.Receivable(), SyncedAt: now,
			}
			if amt < 0 {
				t.Debit = amt.Rupees()
			} else {
				t.Credit = amt.Rupees()
			}
			out = append(out, t)
		}
	}
	return out, st
}
