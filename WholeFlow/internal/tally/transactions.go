package tally

import (
	"context"
	"sort"
	"strings"
)

// Transaction categories shown on the shop detail page, keyed by the
// predefined Tally voucher type each custom voucher type ultimately derives from.
const (
	CatSales       = "sales"
	CatReceipts    = "receipts"
	CatReturns     = "returns"     // Credit Notes (sales returns, tyre damage claims, ...)
	CatAdjustments = "adjustments" // Journals, Debit Notes, Payments, Contra, anything else
)

// Supplier-side categories.
const (
	CatPurchases       = "purchases"
	CatPayments        = "payments"
	CatPurchaseReturns = "purchase_returns" // Debit Notes
)

var (
	shopCategories     = []string{CatSales, CatReceipts, CatReturns, CatAdjustments}
	supplierCategories = []string{CatPurchases, CatPayments, CatPurchaseReturns, CatAdjustments}
)

func supplierCategoryFor(baseType string) string {
	switch strings.ToLower(baseType) {
	case "purchase":
		return CatPurchases
	case "payment":
		return CatPayments
	case "debit note":
		return CatPurchaseReturns
	}
	return CatAdjustments
}

func categoryFor(baseType string) string {
	switch strings.ToLower(baseType) {
	case "sales":
		return CatSales
	case "receipt":
		return CatReceipts
	case "credit note":
		return CatReturns
	}
	return CatAdjustments
}

type Transaction struct {
	Date        string  `json:"date"`
	VoucherType string  `json:"voucherType"`
	BaseType    string  `json:"baseType"`
	Category    string  `json:"category"`
	Number      string  `json:"number,omitempty"`
	Narration   string  `json:"narration,omitempty"`
	Amount      Balance `json:"amount"` // effect on the shop's account: DR raises dues, CR lowers them
}

type CategoryTotal struct {
	Category string  `json:"category"`
	Count    int     `json:"count"`
	Debit    float64 `json:"debit"`
	Credit   float64 `json:"credit"`
	Net      Balance `json:"net"`
	net      Amount
}

type TransactionSummary struct {
	Customer     string          `json:"customer"`
	From         string          `json:"from"`
	To           string          `json:"to"`
	Totals       []CategoryTotal `json:"totals"`
	Transactions []Transaction   `json:"transactions"` // newest first
	Excluded     struct {
		Optional  int `json:"optional"`
		Cancelled int `json:"cancelled"`
		PostDated int `json:"postDated"`
	} `json:"excluded"`

	// Reconciliation: opening + movement must equal Tally's own closing balance.
	Opening         Balance `json:"opening"`
	Movement        Balance `json:"movement"`
	ComputedClosing Balance `json:"computedClosing"`
	TallyClosing    Balance `json:"tallyClosing"`
	Reconciled      bool    `json:"reconciled"`
}

type xmlVoucher struct {
	GUID        string `xml:"GUID"`
	MasterID    string `xml:"MASTERID"`
	AlterID     string `xml:"ALTERID"`
	Date        string `xml:"DATE"`
	Type        string `xml:"VOUCHERTYPENAME"`
	Number      string `xml:"VOUCHERNUMBER"`
	Narration   string `xml:"NARRATION"`
	IsOptional  string `xml:"ISOPTIONAL"`
	IsCancelled string `xml:"ISCANCELLED"`
	IsPostDated string `xml:"ISPOSTDATED"`
	Entries     []struct {
		Ledger string `xml:"LEDGERNAME"`
		Amount string `xml:"AMOUNT"`
	} `xml:"ALLLEDGERENTRIES.LIST"`
}

// GetCustomerTransactions summarises every voucher touching the shop's ledger
// from the start of the books, and reconciles the result against Tally's
// closing balance so any mismatch is visible rather than silently wrong.
func (s *Service) GetCustomerTransactions(ctx context.Context, company *Company, cust *Customer) (*TransactionSummary, error) {
	return s.ledgerTransactions(ctx, "transactions", company, cust, shopCategories, categoryFor)
}

// GetSupplierTransactions is the same summary for a supplier ledger, grouped
// into purchases, payments, debit notes (purchase returns) and everything else.
func (s *Service) GetSupplierTransactions(ctx context.Context, company *Company, cust *Customer) (*TransactionSummary, error) {
	return s.ledgerTransactions(ctx, "supplier-transactions", company, cust, supplierCategories, supplierCategoryFor)
}

func (s *Service) ledgerTransactions(ctx context.Context, op string, company *Company, cust *Customer,
	cats []string, catFor func(string) string) (*TransactionSummary, error) {
	baseTypes, err := s.voucherBaseTypes(ctx, company.Name)
	if err != nil {
		return nil, err
	}

	from := strings.ReplaceAll(company.BooksFrom, "-", "")
	to := maxDate(company.PeriodTo, company.EndingAt, company.LastVoucherDate)
	tdl := `<COLLECTION NAME="WFC"><TYPE>Voucher</TYPE>` +
		`<FETCH>DATE,VOUCHERTYPENAME,VOUCHERNUMBER,NARRATION,ISOPTIONAL,ISCANCELLED,ISPOSTDATED,` +
		`ALLLEDGERENTRIES.LEDGERNAME,ALLLEDGERENTRIES.AMOUNT</FETCH>` +
		`<FILTER>WFHASLEDGER</FILTER></COLLECTION>` +
		`<SYSTEM TYPE="Formulae" NAME="WFHASLEDGER">$$FilterCount:AllLedgerEntries:WFISLEDGER &gt; 0</SYSTEM>` +
		`<SYSTEM TYPE="Formulae" NAME="WFISLEDGER">$LedgerName = ##WFLEDGER</SYSTEM>`
	req := Request{Company: company.Name, FromDate: from, ToDate: strings.ReplaceAll(to, "-", ""),
		Vars: map[string]string{"WFLEDGER": cust.Name}, TDL: tdl}

	body, err := s.client.Post(ctx, op, req.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlVoucher `xml:"BODY>DATA>COLLECTION>VOUCHER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}

	sum := &TransactionSummary{Customer: cust.Name, From: company.BooksFrom, To: to, Transactions: []Transaction{}}
	totals := map[string]*CategoryTotal{}
	for _, cat := range cats {
		totals[cat] = &CategoryTotal{Category: cat}
	}
	var movement Amount
	for _, v := range env.Items {
		switch {
		case yes(v.IsCancelled):
			sum.Excluded.Cancelled++
			continue
		case yes(v.IsOptional):
			sum.Excluded.Optional++
			continue
		case yes(v.IsPostDated):
			sum.Excluded.PostDated++
			continue
		}
		var amt Amount
		for _, e := range v.Entries {
			if clean(e.Ledger) != cust.Name {
				continue
			}
			a, err := ParseAmount(e.Amount)
			if err != nil {
				s.log.Warn("unparsed voucher amount", "voucher", v.Number, "error", err.Error())
				continue
			}
			amt += a
		}
		vt := clean(v.Type)
		base := baseTypes[vt]
		if base == "" {
			base = vt
		}
		cat := catFor(base)
		t := totals[cat]
		t.Count++
		if amt < 0 {
			t.Debit += amt.Rupees()
		} else {
			t.Credit += amt.Rupees()
		}
		t.net += amt
		movement += amt
		sum.Transactions = append(sum.Transactions, Transaction{
			Date: ISODate(v.Date), VoucherType: vt, BaseType: base, Category: cat,
			Number: clean(v.Number), Narration: clean(v.Narration), Amount: amt.Balance(),
		})
	}
	for _, cat := range cats {
		t := totals[cat]
		t.Net = t.net.Balance()
		sum.Totals = append(sum.Totals, *t)
	}
	sort.SliceStable(sum.Transactions, func(i, j int) bool { return sum.Transactions[i].Date > sum.Transactions[j].Date })

	computed := cust.OpeningSigned + movement
	sum.Opening = cust.OpeningSigned.Balance()
	sum.Movement = movement.Balance()
	sum.ComputedClosing = computed.Balance()
	sum.TallyClosing = cust.ClosingSigned.Balance()
	sum.Reconciled = computed == cust.ClosingSigned
	if !sum.Reconciled {
		s.log.Warn("transaction reconciliation mismatch", "ledger", cust.Name,
			"opening", int64(cust.OpeningSigned), "movement", int64(movement), "tally_closing", int64(cust.ClosingSigned))
	}
	return sum, nil
}

// voucherBaseTypes maps each voucher type name to the predefined type it
// derives from (e.g. "JK RECEIPT" -> "Receipt").
func (s *Service) voucherBaseTypes(ctx context.Context, company string) (map[string]string, error) {
	const op = "voucher-types"
	tdl := `<COLLECTION NAME="WFC"><TYPE>VoucherType</TYPE><FETCH>NAME,PARENT</FETCH></COLLECTION>`
	body, err := s.client.Post(ctx, op, Request{Company: company, TDL: tdl}.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []struct {
			Name   string `xml:"NAME,attr"`
			Parent string `xml:"PARENT"`
		} `xml:"BODY>DATA>COLLECTION>VOUCHERTYPE"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	parent := map[string]string{}
	for _, v := range env.Items {
		parent[clean(v.Name)] = clean(v.Parent)
	}
	base := map[string]string{}
	for name := range parent {
		cur := name
		for i := 0; i < 20; i++ { // guard against cycles
			p := parent[cur]
			if p == "" || p == cur {
				break
			}
			cur = p
		}
		base[name] = cur
	}
	return base, nil
}

func yes(s string) bool { return strings.EqualFold(clean(s), "yes") }

func maxDate(dates ...string) string {
	best := ""
	for _, d := range dates {
		if d > best {
			best = d
		}
	}
	return best
}
