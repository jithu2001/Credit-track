package syncer

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strconv"
	"strings"
	gosync "sync"
	"testing"
	"time"

	"wholeflow/internal/tally"
)

// fakeTally imitates TallyPrime's HTTP/XML server closely enough for the
// real internal/tally parser: companies, shop ledgers, voucher types and
// vouchers with the server-side AlterID filter the sync relies on.
type fakeTally struct {
	mu        gosync.Mutex
	companies []*fakeCompany
	down      bool          // refuse connections (simulated by closing the server)
	delay     time.Duration // respond slowly (timeouts)
	requests  map[string]int
	srv       *httptest.Server
	addr      string
}

type fakeCompany struct {
	Name, GUID string
	BooksFrom  string
	Ledgers    []fakeLedger
	Vouchers   []fakeVoucher
	Stock      []fakeStock
}

type fakeLedger struct {
	Name, GUID, Parent string
	Opening, Closing   string
	Phone              string
}

type fakeVoucher struct {
	GUID      string
	AlterID   int64
	Date      string // YYYYMMDD
	Type      string
	Number    string
	Cancelled bool
	Optional  bool
	Entries   []fakeEntry
	Party     string     // purchase vouchers: PARTYLEDGERNAME
	Items     []fakeItem // purchase vouchers: inventory lines
}

type fakeEntry struct {
	Ledger string
	Amount string
}

var (
	reCompany = regexp.MustCompile(`<SVCURRENTCOMPANY>(.*?)</SVCURRENTCOMPANY>`)
	reNewer   = regexp.MustCompile(`\$AlterID &gt; (\d+)`)
)

func newFakeTally(t *testing.T) *fakeTally {
	t.Helper()
	f := &fakeTally{requests: map[string]int{}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.handle))
	f.addr = strings.TrimPrefix(f.srv.URL, "http://")
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeTally) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	req := string(body)
	f.mu.Lock()
	delay := f.delay
	f.mu.Unlock()
	if delay > 0 {
		time.Sleep(delay)
	}
	io.WriteString(w, f.respond(req))
}

func (f *fakeTally) respond(req string) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var b bytes.Buffer
	b.WriteString(`<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION>`)
	company := ""
	if m := reCompany.FindStringSubmatch(req); m != nil {
		company = unescape(m[1])
	}
	var c *fakeCompany
	for _, x := range f.companies {
		if x.Name == company {
			c = x
		}
	}
	switch {
	case strings.Contains(req, "<TYPE>Company</TYPE>"):
		f.requests["companies"]++
		for _, x := range f.companies {
			fmt.Fprintf(&b, `<COMPANY NAME="%s"><GUID>%s</GUID><STARTINGFROM>%s</STARTINGFROM><BOOKSFROM>%s</BOOKSFROM><ENDINGAT>20270331</ENDINGAT><WFPERIODFROM>20260401</WFPERIODFROM><WFPERIODTO>20270331</WFPERIODTO><WFLASTVCH>20260925</WFLASTVCH></COMPANY>`,
				esc(x.Name), x.GUID, x.BooksFrom, x.BooksFrom)
		}
	case strings.Contains(req, "<TYPE>Ledger</TYPE>"):
		f.requests["ledgers"]++
		if c != nil {
			for _, l := range c.Ledgers {
				if !strings.Contains(req, "<WFGROUP>"+esc(l.Parent)+"</WFGROUP>") {
					continue
				}
				fmt.Fprintf(&b, `<LEDGER NAME="%s"><GUID>%s</GUID><MASTERID>1</MASTERID><ALTERID>5</ALTERID><PARENT>%s</PARENT><OPENINGBALANCE>%s</OPENINGBALANCE><CLOSINGBALANCE>%s</CLOSINGBALANCE><LEDGERPHONE>%s</LEDGERPHONE></LEDGER>`,
					esc(l.Name), l.GUID, esc(l.Parent), l.Opening, l.Closing, l.Phone)
			}
		}
	case strings.Contains(req, "<TYPE>VoucherType</TYPE>"):
		f.requests["voucher-types"]++
		for _, vt := range [][2]string{{"Sales", ""}, {"Receipt", ""}, {"Credit Note", ""}, {"Journal", ""}, {"Payment", ""},
			{"JK RECEIPT", "Receipt"}, {"B2c Gst Sales", "Sales"}, {"Tyre Claim", "Credit Note"}, {"Purchase", ""}, {"Purchase Tcs", "Purchase"}} {
			fmt.Fprintf(&b, `<VOUCHERTYPE NAME="%s"><PARENT>%s</PARENT></VOUCHERTYPE>`, vt[0], vt[1])
		}
	case strings.Contains(req, "<TYPE>StockItem</TYPE>"):
		f.requests["stock-items"]++
		if c != nil {
			for _, s := range c.Stock {
				fmt.Fprintf(&b, `<STOCKITEM NAME="%s"><GUID>%s</GUID><PARENT>%s</PARENT><BASEUNITS>Nos</BASEUNITS><CLOSINGBALANCE>%s</CLOSINGBALANCE><CLOSINGVALUE>%s</CLOSINGVALUE><CLOSINGRATE>%s</CLOSINGRATE></STOCKITEM>`,
					esc(s.Name), s.GUID, esc(s.Group), s.Qty, s.Value, s.Rate)
			}
		}
	case strings.Contains(req, "$$IsPurchase:$VoucherTypeName"):
		f.requests["purchases"]++
		var since int64
		if m := reNewer.FindStringSubmatch(req); m != nil {
			since, _ = strconv.ParseInt(m[1], 10, 64)
		}
		if c != nil {
			for _, v := range c.Vouchers {
				if !isPurchaseType(v.Type) || v.AlterID <= since {
					continue
				}
				fmt.Fprintf(&b, `<VOUCHER><DATE>%s</DATE><GUID>%s</GUID><ALTERID>%d</ALTERID><VOUCHERTYPENAME>%s</VOUCHERTYPENAME><VOUCHERNUMBER>%s</VOUCHERNUMBER><PARTYLEDGERNAME>%s</PARTYLEDGERNAME><ISOPTIONAL>%s</ISOPTIONAL><ISCANCELLED>%s</ISCANCELLED>`,
					v.Date, v.GUID, v.AlterID, esc(v.Type), esc(v.Number), esc(v.Party), yesNo(v.Optional), yesNo(v.Cancelled))
				for _, e := range v.Entries {
					fmt.Fprintf(&b, `<ALLLEDGERENTRIES.LIST><LEDGERNAME>%s</LEDGERNAME><AMOUNT>%s</AMOUNT></ALLLEDGERENTRIES.LIST>`, esc(e.Ledger), e.Amount)
				}
				for _, it := range v.Items {
					fmt.Fprintf(&b, `<ALLINVENTORYENTRIES.LIST><STOCKITEMNAME>%s</STOCKITEMNAME><RATE>%s</RATE><AMOUNT>%s</AMOUNT><ACTUALQTY>%s</ACTUALQTY><BILLEDQTY>%s</BILLEDQTY></ALLINVENTORYENTRIES.LIST>`,
						esc(it.Item), it.Rate, it.Amount, it.Qty, it.Qty)
				}
				b.WriteString(`</VOUCHER>`)
			}
		}
	case strings.Contains(req, "<TYPE>Voucher</TYPE>"):
		full := strings.Contains(req, "ALLLEDGERENTRIES")
		var since int64
		if m := reNewer.FindStringSubmatch(req); m != nil {
			since, _ = strconv.ParseInt(m[1], 10, 64)
		}
		if full {
			f.requests["vouchers"]++
		} else {
			f.requests["voucher-ids"]++
		}
		if c != nil {
			for _, v := range c.Vouchers {
				if v.AlterID <= since {
					continue
				}
				fmt.Fprintf(&b, `<VOUCHER><DATE>%s</DATE><GUID>%s</GUID><MASTERID>%d</MASTERID><ALTERID>%d</ALTERID>`, v.Date, v.GUID, v.AlterID, v.AlterID)
				if full {
					fmt.Fprintf(&b, `<VOUCHERTYPENAME>%s</VOUCHERTYPENAME><VOUCHERNUMBER>%s</VOUCHERNUMBER><NARRATION>n</NARRATION><ISOPTIONAL>%s</ISOPTIONAL><ISCANCELLED>%s</ISCANCELLED><ISPOSTDATED>No</ISPOSTDATED>`,
						esc(v.Type), esc(v.Number), yesNo(v.Optional), yesNo(v.Cancelled))
					for _, e := range v.Entries {
						fmt.Fprintf(&b, `<ALLLEDGERENTRIES.LIST><LEDGERNAME>%s</LEDGERNAME><AMOUNT>%s</AMOUNT></ALLLEDGERENTRIES.LIST>`, esc(e.Ledger), e.Amount)
					}
				}
				b.WriteString(`</VOUCHER>`)
			}
		}
	}
	b.WriteString(`</COLLECTION></DATA></BODY></ENVELOPE>`)
	return b.String()
}

func yesNo(b bool) string {
	if b {
		return "Yes"
	}
	return "No"
}

func esc(s string) string {
	var b bytes.Buffer
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

func unescape(s string) string {
	r := strings.NewReplacer("&amp;", "&", "&lt;", "<", "&gt;", ">", "&#39;", "'", "&#34;", `"`)
	return r.Replace(s)
}

// count returns how many requests of the given kind the fake has served.
func (f *fakeTally) count(kind string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.requests[kind]
}

func (f *fakeTally) company(guid string) *fakeCompany {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, c := range f.companies {
		if c.GUID == guid {
			return c
		}
	}
	return nil
}

// edit mutates the fake under its lock.
func (f *fakeTally) edit(fn func()) {
	f.mu.Lock()
	defer f.mu.Unlock()
	fn()
}

// service builds a real tally.Service pointing at the fake (or a dead address).
func (f *fakeTally) service(t *testing.T, timeout time.Duration) *tally.Service {
	t.Helper()
	return tallyServiceFor(t, f.addr, timeout)
}

func tallyServiceFor(t *testing.T, addr string, timeout time.Duration) *tally.Service {
	t.Helper()
	host, portStr, _ := net.SplitHostPort(addr)
	port, _ := strconv.Atoi(portStr)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	c := tally.NewClient(host, port, timeout, log, t.TempDir(), false)
	return tally.NewService(c, log, host, port, []string{"Sundry Debtors"})
}

// deadAddr returns an address nothing listens on.
func deadAddr(t *testing.T) string {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := l.Addr().String()
	l.Close()
	return addr
}

// ---------------------------------------------------------------- sample data

func sampleCompany(guid, name string) *fakeCompany {
	return &fakeCompany{Name: name, GUID: guid, BooksFrom: "20240401",
		Ledgers: []fakeLedger{
			{Name: "SHOP ONE -- PALA", GUID: guid + "-L1", Parent: "Sundry Debtors", Opening: "-100.00", Closing: "-45000.00", Phone: "9876543210"},
			{Name: "SHOP TWO KUMILY", GUID: guid + "-L2", Parent: "Sundry Debtors", Closing: "8200.00"},
			{Name: "SHOP THREE", GUID: guid + "-L3", Parent: "Sundry Debtors"},
			{Name: "Sales@18%", GUID: guid + "-S1", Parent: "Sales Accounts", Closing: "500000.00"},
			{Name: "Cash", GUID: guid + "-C1", Parent: "Cash-in-Hand"},
		},
		Vouchers: []fakeVoucher{
			{GUID: guid + "-V1", AlterID: 101, Date: "20260401", Type: "B2c Gst Sales", Number: "CB/1",
				Entries: []fakeEntry{{"SHOP ONE -- PALA", "-6724.00"}, {"Sales@18%", "6724.00"}}},
			{GUID: guid + "-V2", AlterID: 102, Date: "20260402", Type: "JK RECEIPT", Number: "R/1",
				Entries: []fakeEntry{{"SHOP ONE -- PALA", "5000.00"}, {"Cash", "-5000.00"}}},
			{GUID: guid + "-V3", AlterID: 103, Date: "20260403", Type: "Tyre Claim", Number: "CN/1",
				Entries: []fakeEntry{{"SHOP TWO KUMILY", "1200.00"}, {"Sales@18%", "-1200.00"}}},
			{GUID: guid + "-V4", AlterID: 104, Date: "20260404", Type: "Journal", Number: "J/1",
				Entries: []fakeEntry{{"SHOP ONE -- PALA", "-300.00"}, {"SHOP TWO KUMILY", "300.00"}}},
			{GUID: guid + "-V5", AlterID: 105, Date: "20260405", Type: "B2c Gst Sales", Number: "CB/2", Cancelled: true,
				Entries: []fakeEntry{{"SHOP THREE", "-999.00"}, {"Sales@18%", "999.00"}}},
		}}
}

type fakeStock struct {
	Name, GUID, Group string
	Qty, Value, Rate  string // " 6 Nos", "-6053.63", "1008.94/Nos"
}

type fakeItem struct {
	Item, Qty, Rate, Amount string // "TYRE A", " 6 Nos", "100.00/Nos", "-600.00"
}

func isPurchaseType(t string) bool { return strings.HasPrefix(t, "Purchase") }
