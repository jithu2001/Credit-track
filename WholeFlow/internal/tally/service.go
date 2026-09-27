package tally

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Service is the only entry point the rest of the application uses to read
// Tally. It never writes to Tally.
type Service struct {
	client     *Client
	log        *slog.Logger
	shopGroups []string
	host       string
	port       int
}

func NewService(client *Client, log *slog.Logger, host string, port int, shopGroups []string) *Service {
	return &Service{client: client, log: log, host: host, port: port, shopGroups: shopGroups}
}

// Endpoint is the Tally URL requests are sent to.
func (s *Service) Endpoint() string { return s.client.Endpoint }

// ---------------------------------------------------------------- types

type Company struct {
	Name            string `json:"name"`
	GUID            string `json:"guid"`
	Number          string `json:"number,omitempty"`
	FinancialYear   string `json:"financialYearFrom"` // start of the company's FY (STARTINGFROM)
	BooksFrom       string `json:"booksFrom"`
	EndingAt        string `json:"endingAt,omitempty"`
	PeriodFrom      string `json:"currentPeriodFrom,omitempty"`
	PeriodTo        string `json:"currentPeriodTo,omitempty"`
	LastVoucherDate string `json:"lastVoucherDate,omitempty"`
	State           string `json:"state,omitempty"`
}

type Customer struct {
	ID            string   `json:"id"` // Tally GUID of the ledger
	MasterID      int      `json:"masterId,omitempty"`
	AlterID       int64    `json:"-"` // bumped by Tally whenever the ledger is altered
	Name          string   `json:"name"`
	Aliases       []string `json:"aliases,omitempty"`
	Group         string   `json:"group"`
	Address       []string `json:"address,omitempty"`
	Phones        []string `json:"phones,omitempty"`
	PhoneSource   string   `json:"phoneSource,omitempty"` // "ledger" or "address"
	ContactPerson string   `json:"contactPerson,omitempty"`
	Email         string   `json:"email,omitempty"`
	GSTIN         string   `json:"gstin,omitempty"`
	GSTRegType    string   `json:"gstRegistrationType,omitempty"`
	State         string   `json:"state,omitempty"`
	Pincode       string   `json:"pincode,omitempty"`
	Country       string   `json:"country,omitempty"`
	Area          string   `json:"area,omitempty"` // derived from ledger name, not a Tally field

	OpeningBalance Balance `json:"openingBalance"`
	Balance        Balance `json:"currentBalance"`
	// Receivable is the signed amount due (positive = Dr, negative = Cr) for sorting/totals.
	Receivable float64 `json:"receivable"`

	// Signed Tally values in paise, for exact arithmetic inside the app.
	OpeningSigned Amount `json:"-"`
	ClosingSigned Amount `json:"-"`
	// ParseWarnings lists fields Tally returned that we could not interpret.
	ParseWarnings []string `json:"parseWarnings,omitempty"`
}

type LedgerSummary struct {
	Name    string  `json:"name"`
	Group   string  `json:"group"`
	Balance Balance `json:"closingBalance"`
}

type Status struct {
	Connected      bool      `json:"connected"`
	Host           string    `json:"host"`
	Port           int       `json:"port"`
	Endpoint       string    `json:"endpoint"`
	ProcessRunning *bool     `json:"processRunning,omitempty"` // nil when not checkable (remote host)
	ResponseMs     int64     `json:"responseMs,omitempty"`
	Companies      []Company `json:"companies"`
	State          string    `json:"state"` // "Ready", "No company open", "Not Connected"
	Error          *Error    `json:"-"`
	CheckedAt      time.Time `json:"checkedAt"`
}

// ---------------------------------------------------------------- connection

// TestConnection checks the process, reachability, and that Tally answers a
// real request (the company list).
func (s *Service) TestConnection(ctx context.Context) Status {
	st := Status{Host: s.host, Port: s.port, Endpoint: s.client.Endpoint, CheckedAt: time.Now()}
	st.ProcessRunning = s.processRunning(ctx)

	start := time.Now()
	companies, err := s.GetCompanies(ctx)
	st.ResponseMs = time.Since(start).Milliseconds()
	if err != nil {
		st.State, st.Error = "Not Connected", asError(err, "status")
		return st
	}
	st.Connected, st.Companies = true, companies
	st.State = "Ready"
	if len(companies) == 0 {
		st.State = "No company open"
	}
	return st
}

// processRunning uses tasklist, so it only means something for a local Tally.
func (s *Service) processRunning(ctx context.Context) *bool {
	switch strings.ToLower(s.host) {
	case "localhost", "127.0.0.1", "::1":
	default:
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "tasklist", "/FI", "IMAGENAME eq tally.exe", "/FO", "CSV", "/NH").Output()
	if err != nil {
		s.log.Warn("tasklist failed", "error", err.Error())
		return nil
	}
	running := strings.Contains(strings.ToLower(string(out)), `"tally.exe"`)
	return &running
}

// ---------------------------------------------------------------- companies

const companyTDL = `<COLLECTION NAME="WFC"><TYPE>Company</TYPE>` +
	`<FETCH>NAME,GUID,COMPANYNUMBER,STARTINGFROM,BOOKSFROM,ENDINGAT,STATENAME</FETCH>` +
	`<COMPUTE>WFPERIODFROM: $$SystemPeriodFrom</COMPUTE>` +
	`<COMPUTE>WFPERIODTO: $$SystemPeriodTo</COMPUTE>` +
	`<COMPUTE>WFLASTVCH: $LastVoucherDate</COMPUTE>` +
	`</COLLECTION>`

type xmlCompany struct {
	Name       string `xml:"NAME,attr"`
	GUID       string `xml:"GUID"`
	Number     string `xml:"COMPANYNUMBER"`
	Starting   string `xml:"STARTINGFROM"`
	BooksFrom  string `xml:"BOOKSFROM"`
	EndingAt   string `xml:"ENDINGAT"`
	State      string `xml:"STATENAME"`
	PeriodFrom string `xml:"WFPERIODFROM"`
	PeriodTo   string `xml:"WFPERIODTO"`
	LastVch    string `xml:"WFLASTVCH"`
}

// GetCompanies lists the companies currently open in TallyPrime.
func (s *Service) GetCompanies(ctx context.Context) ([]Company, error) {
	const op = "companies"
	body, err := s.client.Post(ctx, op, Request{TDL: companyTDL}.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlCompany `xml:"BODY>DATA>COLLECTION>COMPANY"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]Company, 0, len(env.Items))
	for _, c := range env.Items {
		out = append(out, Company{
			Name: clean(c.Name), GUID: clean(c.GUID), Number: clean(c.Number),
			FinancialYear: ISODate(c.Starting), BooksFrom: ISODate(c.BooksFrom), EndingAt: ISODate(c.EndingAt),
			PeriodFrom: ISODate(c.PeriodFrom), PeriodTo: ISODate(c.PeriodTo),
			LastVoucherDate: ISODate(c.LastVch), State: clean(c.State),
		})
	}
	return out, nil
}

// ResolveCompany confirms the company is open in Tally. This matters because
// Tally silently answers with the *active* company when SVCURRENTCOMPANY names
// a company that is not loaded.
func (s *Service) ResolveCompany(ctx context.Context, name string) (*Company, error) {
	if strings.TrimSpace(name) == "" {
		return nil, &Error{Kind: KindNoCompany, Op: "company", Msg: "no company selected"}
	}
	companies, err := s.GetCompanies(ctx)
	if err != nil {
		return nil, err
	}
	for i := range companies {
		if strings.EqualFold(companies[i].Name, name) || companies[i].GUID == name {
			return &companies[i], nil
		}
	}
	return nil, &Error{Kind: KindCompanyNotFound, Op: "company", Msg: fmt.Sprintf("company %q is not open in TallyPrime", name)}
}

// ---------------------------------------------------------------- ledgers

// GetLedgers returns every ledger with its group, for inspecting how the
// company's chart of accounts is organised.
func (s *Service) GetLedgers(ctx context.Context, company string) ([]LedgerSummary, error) {
	const op = "ledgers"
	tdl := `<COLLECTION NAME="WFC"><TYPE>Ledger</TYPE><FETCH>NAME,PARENT,CLOSINGBALANCE</FETCH></COLLECTION>`
	body, err := s.client.Post(ctx, op, Request{Company: company, TDL: tdl}.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []struct {
			Name    string `xml:"NAME,attr"`
			Parent  string `xml:"PARENT"`
			Closing string `xml:"CLOSINGBALANCE"`
		} `xml:"BODY>DATA>COLLECTION>LEDGER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]LedgerSummary, 0, len(env.Items))
	for _, l := range env.Items {
		amt, err := ParseAmount(l.Closing)
		if err != nil {
			s.log.Warn("ledger balance unparsed", "ledger", l.Name, "error", err.Error())
		}
		out = append(out, LedgerSummary{Name: clean(l.Name), Group: clean(l.Parent), Balance: amt.Balance()})
	}
	return out, nil
}

// ---------------------------------------------------------------- customers

const customerFetch = `NAME,GUID,MASTERID,ALTERID,PARENT,OPENINGBALANCE,CLOSINGBALANCE,ADDRESS,LEDGERPHONE,` +
	`LEDGERMOBILE,LEDGERCONTACT,EMAIL,PARTYGSTIN,GSTREGISTRATIONTYPE,LEDSTATENAME,PINCODE,COUNTRYNAME,` +
	`LANGUAGENAME,LEDGSTREGDETAILS,LEDMAILINGDETAILS`

type xmlLedger struct {
	Name       string   `xml:"NAME,attr"`
	GUID       string   `xml:"GUID"`
	MasterID   string   `xml:"MASTERID"`
	AlterID    string   `xml:"ALTERID"`
	Parent     string   `xml:"PARENT"`
	Opening    string   `xml:"OPENINGBALANCE"`
	Closing    string   `xml:"CLOSINGBALANCE"`
	Address    []string `xml:"ADDRESS.LIST>ADDRESS"`
	Phone      string   `xml:"LEDGERPHONE"`
	Mobile     string   `xml:"LEDGERMOBILE"`
	Contact    string   `xml:"LEDGERCONTACT"`
	Email      string   `xml:"EMAIL"`
	GSTIN      string   `xml:"PARTYGSTIN"`
	GSTRegType string   `xml:"GSTREGISTRATIONTYPE"`
	State      string   `xml:"LEDSTATENAME"`
	Pincode    string   `xml:"PINCODE"`
	Country    string   `xml:"COUNTRYNAME"`
	Names      []string `xml:"LANGUAGENAME.LIST>NAME.LIST>NAME"`
	// Newer TallyPrime releases keep date-wise GST and mailing details.
	GSTDetails []struct {
		From    string `xml:"APPLICABLEFROM"`
		GSTIN   string `xml:"GSTIN"`
		RegType string `xml:"GSTREGISTRATIONTYPE"`
		State   string `xml:"STATE"`
	} `xml:"LEDGSTREGDETAILS.LIST"`
	Mailing []struct {
		From    string   `xml:"APPLICABLEFROM"`
		Address []string `xml:"ADDRESS.LIST>ADDRESS"`
		Pincode string   `xml:"PINCODE"`
		State   string   `xml:"STATE"`
		Country string   `xml:"COUNTRY"`
	} `xml:"LEDMAILINGDETAILS.LIST"`
}

// GetCustomers returns every ledger under the configured shop groups
// (default: Sundry Debtors, including its sub-groups).
func (s *Service) GetCustomers(ctx context.Context, company string) ([]Customer, error) {
	byID := map[string]bool{}
	var out []Customer
	for _, group := range s.shopGroups {
		tdl := `<COLLECTION NAME="WFC"><TYPE>Ledger</TYPE><CHILDOF>##WFGROUP</CHILDOF><BELONGSTO>Yes</BELONGSTO>` +
			`<FETCH>` + customerFetch + `</FETCH></COLLECTION>`
		items, err := s.fetchLedgers(ctx, "customers", Request{Company: company, Vars: map[string]string{"WFGROUP": group}, TDL: tdl})
		if err != nil {
			return nil, err
		}
		if len(items) == 0 {
			s.log.Warn("shop group returned no ledgers", "group", group, "company", company)
		}
		for _, c := range items {
			if !byID[c.ID] {
				byID[c.ID] = true
				out = append(out, c)
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name) })
	return out, nil
}

// GetCustomer fetches one shop ledger live from Tally by GUID.
func (s *Service) GetCustomer(ctx context.Context, company, id string) (*Customer, error) {
	tdl := `<COLLECTION NAME="WFC"><TYPE>Ledger</TYPE><FETCH>` + customerFetch + `</FETCH><FILTER>WFBYID</FILTER></COLLECTION>` +
		`<SYSTEM TYPE="Formulae" NAME="WFBYID">$GUID = ##WFID</SYSTEM>`
	items, err := s.fetchLedgers(ctx, "customer", Request{Company: company, Vars: map[string]string{"WFID": id}, TDL: tdl})
	if err != nil {
		return nil, err
	}
	if len(items) == 0 {
		return nil, &Error{Kind: KindNotFound, Op: "customer", Msg: "no ledger with id " + id}
	}
	c := items[0]
	if !s.isShopGroupMember(ctx, company, c) {
		return nil, &Error{Kind: KindNotFound, Op: "customer", Msg: "ledger " + c.Name + " is not in a shop group"}
	}
	return &c, nil
}

// GetCustomerBalance returns just the live balance of one shop.
func (s *Service) GetCustomerBalance(ctx context.Context, company, id string) (*Customer, error) {
	return s.GetCustomer(ctx, company, id)
}

// GetCustomerBalances returns the balances of all shops (same fetch as GetCustomers).
func (s *Service) GetCustomerBalances(ctx context.Context, company string) ([]Customer, error) {
	return s.GetCustomers(ctx, company)
}

// isShopGroupMember guards GetCustomer against returning, say, a bank ledger.
func (s *Service) isShopGroupMember(ctx context.Context, company string, c Customer) bool {
	for _, g := range s.shopGroups {
		if strings.EqualFold(c.Group, g) {
			return true
		}
	}
	// Sub-group of a shop group: ask Tally.
	customers, err := s.GetCustomers(ctx, company)
	if err != nil {
		return false
	}
	for _, x := range customers {
		if x.ID == c.ID {
			return true
		}
	}
	return false
}

func (s *Service) fetchLedgers(ctx context.Context, op string, req Request) ([]Customer, error) {
	body, err := s.client.Post(ctx, op, req.Envelope())
	if err != nil {
		return nil, err
	}
	var env struct {
		Items []xmlLedger `xml:"BODY>DATA>COLLECTION>LEDGER"`
	}
	if err := s.client.Decode(op, body, &env); err != nil {
		return nil, err
	}
	out := make([]Customer, 0, len(env.Items))
	for _, l := range env.Items {
		out = append(out, s.toCustomer(l))
	}
	return out, nil
}

func (s *Service) toCustomer(l xmlLedger) Customer {
	c := Customer{
		ID: clean(l.GUID), Name: clean(l.Name), Group: clean(l.Parent),
		ContactPerson: clean(l.Contact), Email: clean(l.Email), GSTIN: clean(l.GSTIN),
		GSTRegType: clean(l.GSTRegType), State: clean(l.State), Pincode: clean(l.Pincode), Country: clean(l.Country),
	}
	c.MasterID, _ = strconv.Atoi(clean(l.MasterID))
	c.AlterID, _ = strconv.ParseInt(clean(l.AlterID), 10, 64)
	for _, n := range l.Names {
		if n = clean(n); n != "" && n != c.Name {
			c.Aliases = append(c.Aliases, n)
		}
	}
	for _, a := range l.Address {
		if a = clean(a); a != "" {
			c.Address = append(c.Address, a)
		}
	}

	// Fall back to the latest date-wise mailing / GST details when the legacy fields are empty.
	if m := latest(len(l.Mailing), func(i int) string { return l.Mailing[i].From }); m >= 0 {
		md := l.Mailing[m]
		if len(c.Address) == 0 {
			for _, a := range md.Address {
				if a = clean(a); a != "" {
					c.Address = append(c.Address, a)
				}
			}
		}
		c.Pincode = firstNonEmpty(c.Pincode, md.Pincode)
		c.State = firstNonEmpty(c.State, md.State)
		c.Country = firstNonEmpty(c.Country, md.Country)
	}
	if g := latest(len(l.GSTDetails), func(i int) string { return l.GSTDetails[i].From }); g >= 0 {
		gd := l.GSTDetails[g]
		c.GSTIN = firstNonEmpty(c.GSTIN, gd.GSTIN)
		c.GSTRegType = firstNonEmpty(c.GSTRegType, gd.RegType)
		c.State = firstNonEmpty(c.State, gd.State)
	}

	if p := ExtractPhones(l.Mobile, l.Phone); len(p) > 0 {
		c.Phones, c.PhoneSource = p, "ledger"
	} else if p := ExtractPhones(c.Address...); len(p) > 0 {
		c.Phones, c.PhoneSource = p, "address"
	}
	c.Area = DeriveArea(c.Name)

	var err error
	if c.OpeningSigned, err = ParseAmount(l.Opening); err != nil {
		c.ParseWarnings = append(c.ParseWarnings, "opening balance: "+err.Error())
		s.log.Warn("unparsed amount", "ledger", c.Name, "field", "OPENINGBALANCE", "error", err.Error())
	}
	if c.ClosingSigned, err = ParseAmount(l.Closing); err != nil {
		c.ParseWarnings = append(c.ParseWarnings, "current balance: "+err.Error())
		s.log.Warn("unparsed amount", "ledger", c.Name, "field", "CLOSINGBALANCE", "error", err.Error())
	}
	c.OpeningBalance = c.OpeningSigned.Balance()
	c.Balance = c.ClosingSigned.Balance()
	c.Receivable = c.ClosingSigned.Receivable()
	return c
}

func latest(n int, date func(int) string) int {
	best := -1
	for i := 0; i < n; i++ {
		if best < 0 || date(i) >= date(best) {
			best = i
		}
	}
	return best
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v = clean(v); v != "" {
			return v
		}
	}
	return ""
}

func asError(err error, op string) *Error {
	if te, ok := err.(*Error); ok {
		return te
	}
	return &Error{Kind: KindInvalidResponse, Op: op, Err: err}
}
