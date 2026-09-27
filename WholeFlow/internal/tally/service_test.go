package tally

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"
)

// fakeTally answers like TallyPrime, choosing a canned body by what the request asks for.
func fakeTally(t *testing.T, handler func(req string) string) (*Service, func()) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		io.WriteString(w, handler(string(b)))
	}))
	return newTestService(t, srv.URL, time.Second), srv.Close
}

func newTestService(t *testing.T, url string, timeout time.Duration) *Service {
	host, portStr, _ := net.SplitHostPort(strings.TrimPrefix(url, "http://"))
	port, _ := strconv.Atoi(portStr)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	c := NewClient(host, port, timeout, log, t.TempDir(), false)
	return NewService(c, log, host, port, []string{"Sundry Debtors"})
}

const companiesXML = `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION>
<COMPANY NAME="Test Co"><GUID>g-1</GUID><BOOKSFROM TYPE="Date">20240401</BOOKSFROM><WFPERIODFROM>20260401</WFPERIODFROM><WFPERIODTO>20270331</WFPERIODTO></COMPANY>
</COLLECTION></DATA></BODY></ENVELOPE>`

const ledgersXML = `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION>
<LEDGER NAME="SHOP ONE -- PALA"><GUID>g-1-01</GUID><PARENT>Sundry Debtors</PARENT>
 <ADDRESS.LIST><ADDRESS>Main Rd</ADDRESS><ADDRESS>PH 9876543210</ADDRESS></ADDRESS.LIST>
 <OPENINGBALANCE>-100.00</OPENINGBALANCE><CLOSINGBALANCE>-45000.00</CLOSINGBALANCE>
 <LEDGSTREGDETAILS.LIST><APPLICABLEFROM>20230401</APPLICABLEFROM><GSTIN>OLD</GSTIN></LEDGSTREGDETAILS.LIST>
 <LEDGSTREGDETAILS.LIST><APPLICABLEFROM>20240401</APPLICABLEFROM><GSTIN>32ABCDE1234F1Z5</GSTIN></LEDGSTREGDETAILS.LIST>
</LEDGER>
<LEDGER NAME="SHOP TWO KUMILY"><GUID>g-1-02</GUID><PARENT>&#4; Sundry Debtors</PARENT><LEDGERPHONE>9447000000</LEDGERPHONE>
 <CLOSINGBALANCE>8200.00</CLOSINGBALANCE></LEDGER>
<LEDGER NAME="SHOP THREE"><GUID>g-1-03</GUID><PARENT>Sundry Debtors</PARENT><CLOSINGBALANCE></CLOSINGBALANCE></LEDGER>
</COLLECTION></DATA></BODY></ENVELOPE>`

func TestGetCustomers(t *testing.T) {
	svc, done := fakeTally(t, func(req string) string {
		if !strings.Contains(req, "<SVCURRENTCOMPANY>Test Co</SVCURRENTCOMPANY>") || !strings.Contains(req, "<WFGROUP>Sundry Debtors</WFGROUP>") {
			t.Errorf("request missing company or group: %s", req)
		}
		return ledgersXML
	})
	defer done()
	cs, err := svc.GetCustomers(context.Background(), "Test Co")
	if err != nil {
		t.Fatal(err)
	}
	if len(cs) != 3 {
		t.Fatalf("got %d customers", len(cs))
	}
	one := cs[0]
	if one.Name != "SHOP ONE -- PALA" || one.Balance != (Balance{45000, "DR"}) || one.Receivable != 45000 ||
		one.OpeningBalance != (Balance{100, "DR"}) || one.Area != "Pala" || one.GSTIN != "32ABCDE1234F1Z5" ||
		len(one.Phones) != 1 || one.PhoneSource != "address" {
		t.Errorf("shop one: %+v", one)
	}
	if cs[1].Name != "SHOP THREE" || cs[1].Balance.Type != "" {
		t.Errorf("shop three: %+v", cs[1])
	}
	two := cs[2]
	if two.Balance != (Balance{8200, "CR"}) || two.PhoneSource != "ledger" || two.Group != "Sundry Debtors" {
		t.Errorf("shop two: %+v", two)
	}
}

func TestResolveCompany(t *testing.T) {
	svc, done := fakeTally(t, func(string) string { return companiesXML })
	defer done()
	ctx := context.Background()
	if c, err := svc.ResolveCompany(ctx, "test co"); err != nil || c.Name != "Test Co" || c.PeriodTo != "2027-03-31" {
		t.Errorf("resolve: %+v %v", c, err)
	}
	assertKind(t, func() error { _, err := svc.ResolveCompany(ctx, "Other"); return err }(), KindCompanyNotFound)
	assertKind(t, func() error { _, err := svc.ResolveCompany(ctx, ""); return err }(), KindNoCompany)
}

func TestErrorResponses(t *testing.T) {
	cases := map[string]struct {
		body string
		kind ErrorKind
	}{
		"unknown request": {`<RESPONSE>Unknown Request, cannot be processed</RESPONSE>`, KindTallyError},
		"status 0":        {`<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>0</STATUS></HEADER><BODY><DATA>DESC not found</DATA></BODY></ENVELOPE>`, KindTallyError},
		"line error":      {`<ENVELOPE><HEADER><STATUS>1</STATUS></HEADER><BODY><DATA><LINEERROR>Could not set 'SVCurrentCompany'</LINEERROR></DATA></BODY></ENVELOPE>`, KindTallyError},
		"invalid xml":     {`<ENVELOPE><BODY><DATA>`, KindInvalidResponse},
		"html":            {`<html><body>proxy</body></html>`, KindInvalidResponse},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			svc, done := fakeTally(t, func(string) string { return tc.body })
			defer done()
			_, err := svc.GetCompanies(context.Background())
			assertKind(t, err, tc.kind)
		})
	}
}

func TestUnreachableAndTimeout(t *testing.T) {
	// A closed port: nothing is listening.
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	addr := l.Addr().String()
	l.Close()
	svc := newTestService(t, "http://"+addr, time.Second)
	_, err := svc.GetCompanies(context.Background())
	assertKind(t, err, KindUnreachable)
	st := svc.TestConnection(context.Background())
	if st.Connected || st.State != "Not Connected" {
		t.Errorf("status: %+v", st)
	}

	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(500 * time.Millisecond)
	}))
	defer slow.Close()
	svc = newTestService(t, slow.URL, 100*time.Millisecond)
	_, err = svc.GetCompanies(context.Background())
	assertKind(t, err, KindTimeout)
}

func assertKind(t *testing.T, err error, want ErrorKind) {
	t.Helper()
	var te *Error
	if !errors.As(err, &te) || te.Kind != want {
		t.Errorf("error = %v; want kind %s", err, want)
	}
}
