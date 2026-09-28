package tally

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// Every request shape this package sends must pass the read-only check.
func TestReadOnlyAllowsEveryRealRequest(t *testing.T) {
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		seen = append(seen, string(b))
		io.WriteString(w, `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION></COLLECTION></DATA></BODY></ENVELOPE>`)
	}))
	defer srv.Close()
	svc := newTestService(t, srv.URL, 5*time.Second)
	ctx := context.Background()
	co := &Company{Name: "Test & Co <1>", GUID: "g", BooksFrom: "2024-04-01", PeriodTo: "2027-03-31"}
	// Names with XML specials and TDL-looking text must stay inert text.
	evil := `X</WFLEDGER><TALLYMESSAGE><VOUCHER ACTION="Delete"/></TALLYMESSAGE><WFLEDGER>&amp;`
	calls := map[string]func() error{
		"companies": func() error { _, err := svc.GetCompanies(ctx); return err },
		"ledgers":   func() error { _, err := svc.GetLedgers(ctx, co.Name); return err },
		"customers": func() error { _, err := svc.GetCustomers(ctx, co.Name); return err },
		"suppliers": func() error { _, err := svc.GetSuppliers(ctx, co.Name); return err },
		"customer":  func() error { _, err := svc.GetCustomer(ctx, co.Name, evil); return notFoundOK(err) },
		"supplier":  func() error { _, err := svc.GetSupplier(ctx, co.Name, evil); return notFoundOK(err) },
		"shop txns": func() error {
			_, err := svc.GetCustomerTransactions(ctx, co, &Customer{Name: evil})
			return err
		},
		"supplier txns": func() error {
			_, err := svc.GetSupplierTransactions(ctx, co, &Customer{Name: evil})
			return err
		},
		"vouchers":            func() error { _, err := svc.GetVouchers(ctx, co, 0); return err },
		"vouchers since":      func() error { _, err := svc.GetVouchers(ctx, co, 61159); return err },
		"voucher ids":         func() error { _, err := svc.GetVoucherIDs(ctx, co); return err },
		"purchases":           func() error { _, err := svc.GetPurchases(ctx, co); return err },
		"purchases since":     func() error { _, err := svc.GetPurchasesSince(ctx, co, 60000); return err },
		"stock items":         func() error { _, err := svc.GetStockItems(ctx, co.Name); return err },
		"connection (status)": func() error { svc.TestConnection(ctx); return nil },
	}
	for name, call := range calls {
		before := len(seen)
		if err := call(); err != nil {
			var te *Error
			if errors.As(err, &te) && te.Kind == KindWriteBlocked {
				t.Errorf("%s: real request was blocked: %v", name, err)
			}
		}
		if len(seen) == before {
			t.Errorf("%s: no request reached Tally", name)
		}
	}
	for _, body := range seen {
		if strings.Contains(body, "<TALLYMESSAGE") || strings.Contains(body, `ACTION="Delete"`) {
			t.Fatalf("user text leaked into the request as markup:\n%s", body)
		}
		if !strings.Contains(body, "<TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE>") {
			t.Fatalf("request is not a collection export:\n%s", body)
		}
	}
}

func notFoundOK(err error) error {
	var te *Error
	if errors.As(err, &te) && te.Kind == KindNotFound {
		return nil
	}
	return err
}

const exportHead = `<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST><TYPE>Collection</TYPE><ID>WFC</ID></HEADER>` +
	`<BODY><DESC><STATICVARIABLES><SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT></STATICVARIABLES><TDL><TDLMESSAGE>`
const exportTail = `</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>`

// Anything that could create, alter, delete or run something in Tally is refused.
func TestReadOnlyBlocksWrites(t *testing.T) {
	blocked := map[string]string{
		"import voucher": `<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA><REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME></REQUESTDESC>` +
			`<REQUESTDATA><TALLYMESSAGE><VOUCHER ACTION="Create"/></TALLYMESSAGE></REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>`,
		"import via Export header": `<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Import</TALLYREQUEST><TYPE>Data</TYPE><ID>Vouchers</ID></HEADER><BODY/></ENVELOPE>`,
		"export of a report":       strings.Replace(exportHead, "<TYPE>Collection</TYPE>", "<TYPE>Data</TYPE>", 1) + exportTail,
		"execute request":          strings.Replace(exportHead, "<TALLYREQUEST>Export</TALLYREQUEST>", "<TALLYREQUEST>Execute</TALLYREQUEST>", 1) + exportTail,
		"tallymessage in export":   exportHead + exportTail[:0] + `</TDLMESSAGE></TDL></DESC><DATA><TALLYMESSAGE><LEDGER ACTION="Delete" NAME="X"/></TALLYMESSAGE></DATA></BODY></ENVELOPE>`,
		"action in TDL":            exportHead + `<ACTION NAME="WFA">Delete Object</ACTION>` + exportTail,
		"function definition":      exportHead + `<SYSTEM TYPE="Functions" NAME="F">x</SYSTEM>` + exportTail,
		"object in collection":     exportHead + `<COLLECTION NAME="WFC"><TYPE>Voucher</TYPE><OBJECT>x</OBJECT></COLLECTION>` + exportTail,
		"unknown $$ function":      exportHead + `<SYSTEM TYPE="Formulae" NAME="F">$$ExecuteAction:Delete</SYSTEM>` + exportTail,
		"$$ function in attribute": exportHead + `<COLLECTION NAME="$$Delete"><TYPE>Ledger</TYPE></COLLECTION>` + exportTail,
		"unknown attribute":        exportHead + `<COLLECTION NAME="WFC" ACTION="Alter"><TYPE>Ledger</TYPE></COLLECTION>` + exportTail,
		"unknown static variable":  strings.Replace(exportHead, "</STATICVARIABLES>", "<SVIMPORTFORMAT>x</SVIMPORTFORMAT></STATICVARIABLES>", 1) + exportTail,
		"second root":              exportHead + exportTail + `<ENVELOPE/>`,
		"doctype":                  `<!DOCTYPE x [<!ENTITY e "y">]>` + exportHead + exportTail,
		"missing header":           `<ENVELOPE><BODY><DESC><TDL><TDLMESSAGE/></TDL></DESC></BODY></ENVELOPE>`,
		"not XML":                  `<ENVELOPE><HEADER>`,
		"empty":                    ``,
	}
	for name, body := range blocked {
		if err := checkReadOnly([]byte(body)); err == nil {
			t.Errorf("%s: accepted, must be blocked:\n%s", name, body)
		}
	}
	if err := checkReadOnly([]byte(exportHead + `<COLLECTION NAME="WFC"><TYPE>Ledger</TYPE><FETCH>NAME</FETCH></COLLECTION>` + exportTail)); err != nil {
		t.Fatalf("minimal export refused: %v", err)
	}
}

// A blocked request never reaches the Tally port.
func TestBlockedRequestIsNeverSent(t *testing.T) {
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { atomic.AddInt32(&hits, 1) }))
	defer srv.Close()
	svc := newTestService(t, srv.URL, time.Second)
	_, err := svc.client.post(context.Background(), "test", []byte(`<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER></ENVELOPE>`))
	var te *Error
	if !errors.As(err, &te) || te.Kind != KindWriteBlocked {
		t.Fatalf("want TALLY_WRITE_BLOCKED, got %v", err)
	}
	if atomic.LoadInt32(&hits) != 0 {
		t.Fatal("blocked request was sent to Tally")
	}
}

// Static variable values can be formulas in Tally ($$SysName:XML is one), so
// a name carrying an unknown $$ function fails closed: refused, not sent.
func TestReadOnlyFailsClosedOnFunctionInName(t *testing.T) {
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		io.WriteString(w, `<ENVELOPE><HEADER><VERSION>1</VERSION><STATUS>1</STATUS></HEADER><BODY><DATA><COLLECTION></COLLECTION></DATA></BODY></ENVELOPE>`)
	}))
	defer srv.Close()
	svc := newTestService(t, srv.URL, time.Second)
	_, err := svc.GetCustomerTransactions(context.Background(), &Company{Name: "Co", BooksFrom: "2024-04-01"}, &Customer{Name: "A $$ExecuteAction:x"})
	var te *Error
	// The voucher-type lookup goes first and is harmless; the ledger request must be refused.
	if !errors.As(err, &te) || te.Kind != KindWriteBlocked {
		t.Fatalf("want TALLY_WRITE_BLOCKED, got %v", err)
	}
}
