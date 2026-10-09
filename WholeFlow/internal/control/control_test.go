package control

import (
	"strings"
	"testing"
	"time"
)

func d(s string) time.Time {
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		panic(err)
	}
	return t
}

func TestPaymentPeriod(t *testing.T) {
	cases := []struct {
		name              string
		paidUntil, paidOn string
		months            int
		wantFrom, wantTo  string
	}{
		{"renew early: continues from paid_until", "2026-10-31", "2026-10-20", 1, "2026-11-01", "2026-11-30"},
		{"paid after it ran out: starts on the payment day", "2026-10-31", "2026-11-03", 1, "2026-11-03", "2026-12-02"},
		{"three months", "2026-10-31", "2026-10-31", 3, "2026-11-01", "2027-01-31"},
		{"month end clamps", "2027-01-30", "2027-01-30", 1, "2027-01-31", "2027-02-27"},
		{"a year", "2026-03-31", "2026-03-15", 12, "2026-04-01", "2027-03-31"},
	}
	for _, c := range cases {
		p := PaymentPeriod(d(c.paidUntil), d(c.paidOn), c.months)
		if got := p.From.Format("2006-01-02"); got != c.wantFrom {
			t.Errorf("%s: from %s, want %s", c.name, got, c.wantFrom)
		}
		if got := p.To.Format("2006-01-02"); got != c.wantTo {
			t.Errorf("%s: to %s, want %s", c.name, got, c.wantTo)
		}
	}
}

func TestAccessState(t *testing.T) {
	paid := d("2026-10-31")
	cases := map[string]string{
		"2026-10-20": StateActive,
		"2026-10-24": StateRenewalDue, // 7 days before
		"2026-10-31": StateRenewalDue,
		"2026-11-01": StateGrace,
		"2026-11-07": StateGrace, // last grace day
		"2026-11-08": StateEnded,
	}
	for day, want := range cases {
		if got := AccessState("active", paid, 7, 7, d(day)); got != want {
			t.Errorf("%s: %s, want %s", day, got, want)
		}
	}
	if got := AccessState("suspended", paid, 7, 7, d("2026-10-01")); got != StateEnded {
		t.Errorf("suspended: %s", got)
	}
}

func TestTodayUsesIndianClock(t *testing.T) {
	// 20:00 UTC on 5 Oct is 01:30 on 6 Oct in India.
	now := time.Date(2026, 10, 5, 20, 0, 0, 0, time.UTC)
	if got := Today(now).Format("2006-01-02"); got != "2026-10-06" {
		t.Errorf("Today = %s", got)
	}
}

func TestSealer(t *testing.T) {
	s, err := NewSealer(strings.Repeat("ab", 32))
	if err != nil {
		t.Fatal(err)
	}
	sealed, _ := s.Seal("service-key")
	if strings.Contains(sealed, "service-key") {
		t.Fatal("sealed value leaks the secret")
	}
	if got, err := s.Open(sealed); err != nil || got != "service-key" {
		t.Fatalf("open: %q %v", got, err)
	}
	other, _ := NewSealer(strings.Repeat("cd", 32))
	if _, err := other.Open(sealed); err == nil {
		t.Fatal("opened with the wrong master key")
	}
	if _, err := NewSealer("short"); err == nil {
		t.Fatal("accepted a short master key")
	}
}

func TestJWT(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	tok, err := DeviceKey("secret-a", "jmj", "dev-1", now)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := VerifyJWT("secret-a", tok, now)
	if err != nil {
		t.Fatal(err)
	}
	if claims["role"] != "service_role" || claims["device_id"] != "dev-1" || claims["ref"] != "jmj" {
		t.Fatalf("claims %v", claims)
	}
	if _, err := VerifyJWT("secret-b", tok, now); err == nil {
		t.Fatal("verified with another business's secret")
	}
	if _, err := VerifyJWT("secret-a", tok, now.AddDate(6, 0, 0)); err == nil {
		t.Fatal("expired key verified")
	}
	noExp, _ := SignJWT("secret-a", map[string]any{"role": "service_role", "device_id": "dev-1"})
	if _, err := VerifyJWT("secret-a", noExp, now); err == nil {
		t.Fatal("token without exp verified")
	}
	if c, _ := ParseJWTUnverified(tok); c["ref"] != "jmj" {
		t.Fatal("unverified parse")
	}
}

func TestKeysAndCodes(t *testing.T) {
	k, _ := NewReferenceKey("jmjmarketing")
	if !strings.HasPrefix(k, "JMJM-") || len(k) != len("JMJM-AAAA-AAAA-AAAA") {
		t.Fatalf("reference key %q", k)
	}
	if strings.ContainsAny(k, "01OIL") {
		t.Fatalf("ambiguous characters in %q", k)
	}
	if NormalizeKey(" jmjm-abcd -efgh ") != "JMJM-ABCD-EFGH" {
		t.Fatal("normalize")
	}
	c, _ := NewActivationCode()
	if len(c) != 9 || c[4] != '-' {
		t.Fatalf("code %q", c)
	}
	if HashCode(strings.ToLower(c)) != HashCode(c) {
		t.Fatal("hash must ignore case")
	}
}

func TestRenewMessage(t *testing.T) {
	got := RenewMessage("Pay ₹{price} per month for the {plan} plan.", "Standard", 800)
	if got != "Pay ₹800 per month for the Standard plan." {
		t.Fatal(got)
	}
}

func TestCleanLead(t *testing.T) {
	good := LeadInput{Name: "  Biju   Thomas ", Business: "Periyar Traders", Phone: "+91 98470-12345", Email: "Biju@Example.in", Companies: "2-3", City: "Kumily", Message: "Call after 5"}
	l, err := CleanLead(good)
	if err != nil {
		t.Fatal(err)
	}
	if l.Name != "Biju Thomas" || l.Phone != "9847012345" || l.Email != "biju@example.in" {
		t.Fatalf("cleaned: %+v", l)
	}
	for _, phone := range []string{"09847012345", "919847012345", "98470 12345"} {
		if l, err := CleanLead(LeadInput{Name: "A", Phone: phone, Email: "a@b.in"}); err != nil || l.Phone != "9847012345" {
			t.Fatalf("phone %q: %v %q", phone, err, l.Phone)
		}
	}
	bad := []LeadInput{
		{Phone: "9847012345", Email: "a@b.in"},                               // no name
		{Name: "A", Phone: "12345", Email: "a@b.in"},                         // short phone
		{Name: "A", Phone: "5847012345", Email: "a@b.in"},                    // not a mobile number
		{Name: "A", Phone: "9847012345", Email: "not-an-email"},              // email
		{Name: "A", Phone: "9847012345", Email: "a@b"},                       // email without a dot in the domain
		{Name: "A", Phone: "9847012345", Email: "a@b.in", Companies: "lots"}, // unknown company count
	}
	for i, in := range bad {
		if _, err := CleanLead(in); err == nil {
			t.Fatalf("bad %d accepted: %+v", i, in)
		}
	}
	long, _ := CleanLead(LeadInput{Name: strings.Repeat("x", 300), Phone: "9847012345", Email: "a@b.in", Message: strings.Repeat("m", 5000)})
	if len([]rune(long.Name)) != 80 || len([]rune(long.Message)) != 1000 {
		t.Fatalf("not capped: %d %d", len(long.Name), len(long.Message))
	}
}
