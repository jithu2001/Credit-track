package tally

import (
	"reflect"
	"testing"
)

func TestParseAmount(t *testing.T) {
	cases := map[string]Amount{
		"":             0,
		"0.00":         0,
		"-42559.00":    -4255900,
		"154396.56":    15439656,
		" -46.00 ":     -4600,
		"-1,23,980.04": -12398004,
		"1,000.00 Dr":  -100000,
		"250.50 Cr":    25050,
		"₹ -10.25":     -1025,
	}
	for in, want := range cases {
		got, err := ParseAmount(in)
		if err != nil || got != want {
			t.Errorf("ParseAmount(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
	if _, err := ParseAmount("12 USD @ 83"); err == nil {
		t.Error("expected error for foreign-currency amount")
	}
}

func TestAmountDrCr(t *testing.T) {
	if a := Amount(-4255900); a.DrCr() != "DR" || a.Rupees() != 42559 || a.Receivable() != 42559 {
		t.Errorf("debit: %v %v %v", a.DrCr(), a.Rupees(), a.Receivable())
	}
	if a := Amount(300); a.DrCr() != "CR" || a.Receivable() != -3 {
		t.Errorf("credit: %v %v", a.DrCr(), a.Receivable())
	}
	if Amount(0).DrCr() != "" {
		t.Error("zero should have no type")
	}
}

func TestExtractPhones(t *testing.T) {
	got := ExtractPhones("NEDUMKANDAM", "IDUKKI, KERALA, 685552", "PH 8606880090",
		"MOB: 9747351578, 8289944987", "Ph.9745948182", "Mob- 9747190777", "+91 94472 12345", "32COXPR7836E1ZB")
	want := []string{"8606880090", "9747351578", "8289944987", "9745948182", "9747190777", "9447212345"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestDeriveArea(t *testing.T) {
	cases := map[string]string{
		"ABI TYRES--G--Erattayar":                           "Erattayar",
		"PRINCE TYRES -- RAJAKKAD":                          "Rajakkad",
		"KRISHNA AUTOMOBILES-G- Kanjirappally":              "Kanjirappally",
		"ALEXANDER PAUL CO.---THODUPUZHA,":                  "Thodupuzha",
		"KERALA TYRES & LUBRICANTS -- G MACHIPLAVU, IDUKKI": "Machiplavu",
		"HI-Tech Wheel Alignment Centre -- GMuttom":         "Muttom",
		"CLASSIC AUTOMOBILES -- GVANNAPURAM":                "Vannapuram",
		"PUTHIYIDATH BLDG - THODUPUZHA":                     "Thodupuzha",
		"AMAZE TYRES NEDUMKANDAM":                           "Nedumkandam",
		"HI-Tech Wheel Alignment":                           "Alignment",
		"PALA TYRES (2024-2025)---PALA":                     "Pala",
		"Single":                                            "",
	}
	for in, want := range cases {
		if got := DeriveArea(in); got != want {
			t.Errorf("DeriveArea(%q) = %q; want %q", in, got, want)
		}
	}
}

func TestSanitize(t *testing.T) {
	in := []byte("\xef\xbb\xbf<A><P>&#4; Primary</P><Q>a\x01b &#38; &#x1F;c</Q></A>")
	want := "<A><P> Primary</P><Q>ab &#38; c</Q></A>"
	if got := string(sanitize(in)); got != want {
		t.Errorf("got %q want %q", got, want)
	}
}

func TestISODate(t *testing.T) {
	if ISODate("20260408") != "2026-04-08" || ISODate("") != "" || ISODate("2026-04") != "" {
		t.Error("ISODate")
	}
}
