package tally

import (
	"context"
	"strconv"
	"strings"
)

// Voucher is one Tally voucher with every ledger entry, as needed by the sync
// service. Unlike GetCustomerTransactions it is not restricted to one ledger.
type Voucher struct {
	GUID      string
	MasterID  int64
	AlterID   int64  // increases whenever the voucher is created or altered
	Date      string // YYYY-MM-DD
	Type      string // voucher type name as configured in Tally, e.g. "JK RECEIPT"
	BaseType  string // predefined type it derives from, e.g. "Receipt"
	Category  string // CatSales, CatReceipts, CatReturns or CatAdjustments
	Number    string
	Narration string
	Optional  bool
	Cancelled bool
	PostDated bool
	Entries   []VoucherEntry
}

// Excluded reports whether Tally leaves this voucher out of ledger balances.
func (v Voucher) Excluded() bool { return v.Optional || v.Cancelled || v.PostDated }

type VoucherEntry struct {
	Ledger string
	Amount Amount // Tally sign: negative = Dr, positive = Cr
}

// VoucherRef is the identity of a voucher without its contents.
type VoucherRef struct {
	GUID    string
	AlterID int64
}

const voucherFetch = `DATE,GUID,MASTERID,ALTERID,VOUCHERTYPENAME,VOUCHERNUMBER,NARRATION,ISOPTIONAL,ISCANCELLED,ISPOSTDATED,` +
	`ALLLEDGERENTRIES.LEDGERNAME,ALLLEDGERENTRIES.AMOUNT`

// GetVouchers returns every voucher of the company, or only those whose
// AlterID is greater than sinceAlterID when it is positive. Tally assigns a
// new, higher AlterID every time a voucher is created or altered, so this is
// the incremental-sync primitive. Deleted vouchers simply disappear; use
// GetVoucherIDs to detect them.
//
// Verified on TallyPrime 6 (Sep 2026): the FILTER on $AlterID is applied
// server-side, but SVFROMDATE/SVTODATE are NOT honoured by a Voucher
// collection, so the date range only documents intent.
func (s *Service) GetVouchers(ctx context.Context, company *Company, sinceAlterID int64) ([]Voucher, error) {
	const op = "vouchers"
	baseTypes, err := s.voucherBaseTypes(ctx, company.Name)
	if err != nil {
		return nil, err
	}
	tdl := `<COLLECTION NAME="WFC"><TYPE>Voucher</TYPE><FETCH>` + voucherFetch + `</FETCH>`
	if sinceAlterID > 0 {
		tdl += `<FILTER>WFNEWER</FILTER></COLLECTION>` +
			`<SYSTEM TYPE="Formulae" NAME="WFNEWER">$AlterID &gt; ` + strconv.FormatInt(sinceAlterID, 10) + `</SYSTEM>`
	} else {
		tdl += `</COLLECTION>`
	}
	body, err := s.client.post(ctx, op, voucherRequest(company, tdl).Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlVoucher `xml:"BODY>DATA>COLLECTION>VOUCHER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]Voucher, 0, len(env.Items))
	for _, x := range env.Items {
		v := Voucher{
			GUID: clean(x.GUID), Date: ISODate(x.Date), Type: clean(x.Type), Number: clean(x.Number),
			Narration: clean(x.Narration), Optional: yes(x.IsOptional), Cancelled: yes(x.IsCancelled), PostDated: yes(x.IsPostDated),
		}
		v.MasterID, _ = strconv.ParseInt(clean(x.MasterID), 10, 64)
		v.AlterID, _ = strconv.ParseInt(clean(x.AlterID), 10, 64)
		v.BaseType = baseTypes[v.Type]
		if v.BaseType == "" {
			v.BaseType = v.Type
		}
		v.Category = categoryFor(v.BaseType)
		for _, e := range x.Entries {
			amt, err := ParseAmount(e.Amount)
			if err != nil {
				s.log.Warn("unparsed voucher amount", "voucher", v.Number, "ledger", e.Ledger, "error", err.Error())
				continue
			}
			v.Entries = append(v.Entries, VoucherEntry{Ledger: clean(e.Ledger), Amount: amt})
		}
		if v.GUID != "" {
			out = append(out, v)
		}
	}
	return out, nil
}

// GetVoucherIDs lists the GUID and AlterID of every voucher in the company.
// It is much lighter than GetVouchers and is used to find deleted vouchers.
func (s *Service) GetVoucherIDs(ctx context.Context, company *Company) ([]VoucherRef, error) {
	const op = "voucher-ids"
	tdl := `<COLLECTION NAME="WFC"><TYPE>Voucher</TYPE><FETCH>GUID,ALTERID</FETCH></COLLECTION>`
	body, err := s.client.post(ctx, op, voucherRequest(company, tdl).Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []struct {
			GUID    string `xml:"GUID"`
			AlterID string `xml:"ALTERID"`
		} `xml:"BODY>DATA>COLLECTION>VOUCHER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]VoucherRef, 0, len(env.Items))
	for _, x := range env.Items {
		id := clean(x.GUID)
		if id == "" {
			continue
		}
		n, _ := strconv.ParseInt(clean(x.AlterID), 10, 64)
		out = append(out, VoucherRef{GUID: id, AlterID: n})
	}
	return out, nil
}

func voucherRequest(company *Company, tdl string) Request {
	to := maxDate(company.PeriodTo, company.EndingAt, company.LastVoucherDate)
	return Request{
		Company:  company.Name,
		FromDate: strings.ReplaceAll(company.BooksFrom, "-", ""),
		ToDate:   strings.ReplaceAll(to, "-", ""),
		TDL:      tdl,
	}
}
