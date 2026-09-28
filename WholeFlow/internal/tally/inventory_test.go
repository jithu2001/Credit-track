package tally

import (
	"context"
	"strings"
	"testing"
)

func TestParseQuantityAndRate(t *testing.T) {
	for in, want := range map[string]Quantity{
		" 17 Nos": {17, "Nos"}, "-3 pc": {-3, "pc"}, "": {}, "1,250.5 Kg": {1250.5, "Kg"}, "6 Nos = 1 Box": {6, "Nos"},
	} {
		got, err := ParseQuantity(in)
		if err != nil || got != want {
			t.Errorf("ParseQuantity(%q) = %v, %v; want %v", in, got, err, want)
		}
	}
	if _, err := ParseQuantity("lots"); err == nil {
		t.Error("ParseQuantity accepted garbage")
	}
	if r, u, err := ParseRate("844.15/Nos"); err != nil || r != 844.15 || u != "Nos" {
		t.Errorf("ParseRate = %v %q %v", r, u, err)
	}
	if r, _, err := ParseRate(""); err != nil || r != 0 {
		t.Errorf("empty rate = %v %v", r, err)
	}
}

const stockXML = `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION>
<STOCKITEM NAME="TYRE B"><GUID>s-2</GUID><PARENT>Scooter</PARENT><CATEGORY>&#4; Not Applicable</CATEGORY><BASEUNITS>Nos</BASEUNITS>
 <CLOSINGBALANCE> 6 Nos</CLOSINGBALANCE><CLOSINGVALUE>-6053.63</CLOSINGVALUE><CLOSINGRATE>1008.94/Nos</CLOSINGRATE>
 <REORDERBASE> 10 Nos</REORDERBASE><LANGUAGENAME.LIST><NAME.LIST><NAME>TYRE B</NAME><NAME>114821</NAME></NAME.LIST></LANGUAGENAME.LIST></STOCKITEM>
<STOCKITEM NAME="tyre a"><GUID>s-1</GUID><PARENT>Car</PARENT><BASEUNITS>Nos</BASEUNITS><CLOSINGBALANCE>-2 Nos</CLOSINGBALANCE><CLOSINGVALUE>1500.00</CLOSINGVALUE></STOCKITEM>
<STOCKITEM NAME="TYRE C"><GUID>s-3</GUID><PARENT>Car</PARENT><CLOSINGBALANCE></CLOSINGBALANCE></STOCKITEM>
</COLLECTION></DATA></BODY></ENVELOPE>`

func TestGetStockItems(t *testing.T) {
	svc, done := fakeTally(t, func(req string) string {
		if !strings.Contains(req, "<TYPE>StockItem</TYPE>") {
			t.Errorf("not a stock item request: %s", req)
		}
		return stockXML
	})
	defer done()
	items, err := svc.GetStockItems(context.Background(), "Test Co")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 3 || items[0].Name != "tyre a" || items[1].Name != "TYRE B" {
		t.Fatalf("want 3 items sorted by name, got %+v", items)
	}
	a, b, c := items[0], items[1], items[2]
	if a.Status != "negative" || a.ClosingQty != -2 || a.ClosingValue != -1500 {
		t.Errorf("negative item: %+v", a)
	}
	if b.Status != "low" || b.ClosingValue != 6053.63 || b.ClosingRate != 1008.94 || b.Category != "" ||
		len(b.Aliases) != 1 || b.Aliases[0] != "114821" {
		t.Errorf("low item: %+v", b)
	}
	if c.Status != "zero" || c.ClosingQty != 0 {
		t.Errorf("zero item: %+v", c)
	}
}

const purchasesXML = `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION>
<VOUCHER><GUID>v-1</GUID><DATE>20260404</DATE><VOUCHERTYPENAME>Purchase Tcs</VOUCHERTYPENAME><VOUCHERNUMBER>93585</VOUCHERNUMBER>
 <PARTYLEDGERNAME>CEAT LIMITED</PARTYLEDGERNAME><ISCANCELLED>No</ISCANCELLED>
 <ALLLEDGERENTRIES.LIST><LEDGERNAME>CEAT LIMITED</LEDGERNAME><AMOUNT>1180.00</AMOUNT></ALLLEDGERENTRIES.LIST>
 <ALLLEDGERENTRIES.LIST><LEDGERNAME>Purchase@18%</LEDGERNAME><AMOUNT>-1000.00</AMOUNT></ALLLEDGERENTRIES.LIST>
 <ALLLEDGERENTRIES.LIST><LEDGERNAME>IGST</LEDGERNAME><AMOUNT>-180.00</AMOUNT></ALLLEDGERENTRIES.LIST>
 <ALLINVENTORYENTRIES.LIST><STOCKITEMNAME>TYRE A</STOCKITEMNAME><GODOWNNAME>Main Location</GODOWNNAME><RATE>100.00/Nos</RATE>
  <AMOUNT>-600.00</AMOUNT><ACTUALQTY> 6 Nos</ACTUALQTY><BILLEDQTY> 6 Nos</BILLEDQTY></ALLINVENTORYENTRIES.LIST>
 <ALLINVENTORYENTRIES.LIST><STOCKITEMNAME>TYRE B</STOCKITEMNAME><RATE>100.00/Nos</RATE>
  <AMOUNT>-400.00</AMOUNT><ACTUALQTY> 4 Nos</ACTUALQTY><BILLEDQTY> 4 Nos</BILLEDQTY></ALLINVENTORYENTRIES.LIST>
</VOUCHER>
<VOUCHER><GUID>v-2</GUID><DATE>20260405</DATE><VOUCHERTYPENAME>Purchase</VOUCHERTYPENAME><ISCANCELLED>Yes</ISCANCELLED></VOUCHER>
</COLLECTION></DATA></BODY></ENVELOPE>`

func TestGetPurchases(t *testing.T) {
	svc, done := fakeTally(t, func(req string) string {
		if !strings.Contains(req, "$$IsPurchase:$VoucherTypeName") {
			t.Errorf("purchase filter missing: %s", req)
		}
		return purchasesXML
	})
	defer done()
	list, err := svc.GetPurchases(context.Background(), &Company{Name: "Test Co", BooksFrom: "2026-04-01"})
	if err != nil {
		t.Fatal(err)
	}
	if list.Cancelled != 1 || len(list.Purchases) != 1 {
		t.Fatalf("want 1 bill + 1 cancelled, got %+v", list)
	}
	p := list.Purchases[0]
	if p.Supplier != "CEAT LIMITED" || p.Total != 1180 || p.Taxable != 1000 || p.Other != 180 || p.Qty != 10 || p.Date != "2026-04-04" {
		t.Errorf("bill: %+v", p)
	}
	if len(p.Lines) != 2 || p.Lines[0] != (PurchaseLine{Item: "TYRE A", Godown: "Main Location", Qty: 6, ActualQt: 6, Unit: "Nos", Rate: 100, Amount: 600}) {
		t.Errorf("lines: %+v", p.Lines)
	}
	if len(p.Ledgers) != 2 || p.Ledgers[1].Ledger != "IGST" || p.Ledgers[1].Amount != (Balance{180, "DR"}) {
		t.Errorf("ledgers (party must be excluded): %+v", p.Ledgers)
	}
}
