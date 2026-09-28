package tally

import (
	"context"
	"sort"
	"strconv"
	"strings"
)

// Purchase is one purchase voucher (any voucher type deriving from
// "Purchase", e.g. "Purchase Tcs") with its item lines.
type Purchase struct {
	ID          string `json:"id"` // voucher GUID
	AlterID     int64  `json:"-"`  // Tally change counter (incremental sync cursor)
	Date        string `json:"date"`
	VoucherType string `json:"voucherType"`
	Number      string `json:"number,omitempty"`
	Reference   string `json:"reference,omitempty"` // supplier's bill number
	Supplier    string `json:"supplier"`            // party ledger
	Narration   string `json:"narration,omitempty"`

	Total   float64 `json:"total"`   // bill amount credited to the supplier, rupees
	Taxable float64 `json:"taxable"` // sum of the item lines
	Other   float64 `json:"other"`   // taxes, freight, round off: Total - Taxable
	Qty     float64 `json:"qty"`     // sum of billed quantities (mixed units are simply added)

	Lines   []PurchaseLine   `json:"lines,omitempty"`
	Ledgers []PurchaseLedger `json:"ledgers,omitempty"` // accounting side, party excluded
}

type PurchaseLine struct {
	Item     string  `json:"item"`
	Godown   string  `json:"godown,omitempty"`
	Qty      float64 `json:"qty"` // billed quantity
	ActualQt float64 `json:"actualQty"`
	Unit     string  `json:"unit,omitempty"`
	Rate     float64 `json:"rate"`
	Discount float64 `json:"discount,omitempty"` // percent
	Amount   float64 `json:"amount"`             // rupees, positive
}

type PurchaseLedger struct {
	Ledger string  `json:"ledger"`
	Amount Balance `json:"amount"` // DR = expense/tax booked, CR = e.g. a negative round off
}

// PurchaseList is the register plus what was left out.
type PurchaseList struct {
	Purchases []Purchase `json:"purchases"` // newest first
	// ExcludedIDs are the GUIDs of the cancelled and optional purchase vouchers.
	ExcludedIDs []string `json:"-"`
	// MaxAlterID is the highest AlterID seen, excluded vouchers included.
	MaxAlterID int64 `json:"-"`
	Cancelled  int   `json:"cancelled"`
	Optional   int   `json:"optional"`
}

const purchaseFetch = `DATE,GUID,ALTERID,VOUCHERTYPENAME,VOUCHERNUMBER,REFERENCE,PARTYLEDGERNAME,NARRATION,ISOPTIONAL,ISCANCELLED,` +
	`ALLLEDGERENTRIES.LEDGERNAME,ALLLEDGERENTRIES.AMOUNT,` +
	`ALLINVENTORYENTRIES.STOCKITEMNAME,ALLINVENTORYENTRIES.GODOWNNAME,ALLINVENTORYENTRIES.ACTUALQTY,` +
	`ALLINVENTORYENTRIES.BILLEDQTY,ALLINVENTORYENTRIES.RATE,ALLINVENTORYENTRIES.DISCOUNT,ALLINVENTORYENTRIES.AMOUNT`

type xmlPurchase struct {
	GUID        string `xml:"GUID"`
	AlterID     string `xml:"ALTERID"`
	Date        string `xml:"DATE"`
	Type        string `xml:"VOUCHERTYPENAME"`
	Number      string `xml:"VOUCHERNUMBER"`
	Reference   string `xml:"REFERENCE"`
	Party       string `xml:"PARTYLEDGERNAME"`
	Narration   string `xml:"NARRATION"`
	IsOptional  string `xml:"ISOPTIONAL"`
	IsCancelled string `xml:"ISCANCELLED"`
	Ledgers     []struct {
		Ledger string `xml:"LEDGERNAME"`
		Amount string `xml:"AMOUNT"`
	} `xml:"ALLLEDGERENTRIES.LIST"`
	Items []struct {
		Item     string `xml:"STOCKITEMNAME"`
		Godown   string `xml:"GODOWNNAME"`
		Actual   string `xml:"ACTUALQTY"`
		Billed   string `xml:"BILLEDQTY"`
		Rate     string `xml:"RATE"`
		Discount string `xml:"DISCOUNT"`
		Amount   string `xml:"AMOUNT"`
	} `xml:"ALLINVENTORYENTRIES.LIST"`
}

// GetPurchases returns every purchase voucher of the company. The filter
// ($$IsPurchase on the voucher type) runs inside Tally, so sales and receipts
// never cross the wire. Verified on TallyPrime 6 (Sep 2026): 413 purchase
// invoices with ~7,000 item lines in one 7.7 MB response.
func (s *Service) GetPurchases(ctx context.Context, company *Company) (*PurchaseList, error) {
	return s.GetPurchasesSince(ctx, company, 0)
}

// GetPurchasesSince returns only purchase vouchers whose AlterID is greater
// than sinceAlterID (all of them when it is 0). Both filters run inside Tally.
func (s *Service) GetPurchasesSince(ctx context.Context, company *Company, sinceAlterID int64) (*PurchaseList, error) {
	const op = "purchases"
	filters := `WFISPURCHASE`
	formulae := `<SYSTEM TYPE="Formulae" NAME="WFISPURCHASE">$$IsPurchase:$VoucherTypeName</SYSTEM>`
	if sinceAlterID > 0 {
		filters += `,WFNEWER`
		formulae += `<SYSTEM TYPE="Formulae" NAME="WFNEWER">$AlterID &gt; ` + strconv.FormatInt(sinceAlterID, 10) + `</SYSTEM>`
	}
	tdl := `<COLLECTION NAME="WFC"><TYPE>Voucher</TYPE><FETCH>` + purchaseFetch + `</FETCH>` +
		`<FILTER>` + filters + `</FILTER></COLLECTION>` + formulae
	body, err := s.client.post(ctx, op, voucherRequest(company, tdl).Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlPurchase `xml:"BODY>DATA>COLLECTION>VOUCHER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := &PurchaseList{Purchases: make([]Purchase, 0, len(env.Items))}
	for _, x := range env.Items {
		alter, _ := strconv.ParseInt(clean(x.AlterID), 10, 64)
		if alter > out.MaxAlterID {
			out.MaxAlterID = alter
		}
		switch {
		case yes(x.IsCancelled):
			out.Cancelled++
			out.ExcludedIDs = append(out.ExcludedIDs, clean(x.GUID))
			continue
		case yes(x.IsOptional):
			out.Optional++
			out.ExcludedIDs = append(out.ExcludedIDs, clean(x.GUID))
			continue
		}
		if p := s.toPurchase(x); p.ID != "" {
			p.AlterID = alter
			out.Purchases = append(out.Purchases, p)
		}
	}
	sort.SliceStable(out.Purchases, func(i, j int) bool {
		a, b := out.Purchases[i], out.Purchases[j]
		if a.Date != b.Date {
			return a.Date > b.Date
		}
		return a.Number > b.Number
	})
	return out, nil
}

func (s *Service) toPurchase(x xmlPurchase) Purchase {
	p := Purchase{ID: clean(x.GUID), Date: ISODate(x.Date), VoucherType: clean(x.Type), Number: clean(x.Number),
		Reference: clean(x.Reference), Supplier: clean(x.Party), Narration: clean(x.Narration)}
	warn := func(field, v string, err error) {
		s.log.Warn("unparsed purchase value", "voucher", p.Number, "field", field, "value", v, "error", err.Error())
	}
	var total Amount
	for _, e := range x.Ledgers {
		name := clean(e.Ledger)
		a, err := ParseAmount(e.Amount)
		if err != nil {
			warn("ledger amount", e.Amount, err)
			continue
		}
		if name == p.Supplier {
			total += a // credited to the supplier: positive
			continue
		}
		p.Ledgers = append(p.Ledgers, PurchaseLedger{Ledger: name, Amount: a.Balance()})
	}
	p.Total = float64(total) / 100
	var taxable Amount
	for _, it := range x.Items {
		l := PurchaseLine{Item: clean(it.Item), Godown: clean(it.Godown)}
		if q, err := ParseQuantity(it.Billed); err == nil {
			l.Qty, l.Unit = q.Value, q.Unit
		} else {
			warn("billed qty", it.Billed, err)
		}
		if q, err := ParseQuantity(it.Actual); err == nil {
			l.ActualQt = q.Value
			if l.Unit == "" {
				l.Unit = q.Unit
			}
		} else {
			warn("actual qty", it.Actual, err)
		}
		if r, _, err := ParseRate(it.Rate); err == nil {
			l.Rate = r
		} else {
			warn("rate", it.Rate, err)
		}
		l.Discount, _ = strconv.ParseFloat(strings.TrimSpace(it.Discount), 64)
		a, err := ParseAmount(it.Amount)
		if err != nil {
			warn("line amount", it.Amount, err)
		}
		taxable += -a // stock is debited: negative in Tally
		l.Amount = float64(-a) / 100
		p.Qty += l.Qty
		p.Lines = append(p.Lines, l)
	}
	p.Taxable = float64(taxable) / 100
	p.Other = float64(total-taxable) / 100
	p.Qty = round2(p.Qty)
	return p
}
