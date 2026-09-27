package tally

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// Amount is a signed Tally amount in paise, using Tally's own sign convention:
// negative = Debit, positive = Credit. For a Sundry Debtor a debit balance is
// money the shop owes us (receivable); a credit balance is an advance/excess
// we owe back.
type Amount int64

// ParseAmount accepts what Tally puts in TYPE="Amount" elements: "-42559.00",
// "" (zero), and tolerates grouping commas, a currency symbol and Dr/Cr suffixes.
func ParseAmount(s string) (Amount, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	orig := s
	sign := 1.0
	low := strings.ToLower(s)
	switch {
	case strings.HasSuffix(low, "dr"):
		sign, s = -1, s[:len(s)-2]
	case strings.HasSuffix(low, "cr"):
		s = s[:len(s)-2]
	}
	s = strings.Map(func(r rune) rune {
		if r == ',' || r == '₹' || unicode.IsSpace(r) {
			return -1
		}
		return r
	}, s)
	s = strings.TrimPrefix(s, "Rs.")
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("unrecognised amount %q", orig)
	}
	return Amount(math.Round(sign * f * 100)), nil
}

// Rupees returns the absolute value in rupees.
func (a Amount) Rupees() float64 {
	return math.Abs(float64(a)) / 100
}

// DrCr returns "DR", "CR" or "" (zero) using Tally's sign convention.
func (a Amount) DrCr() string {
	switch {
	case a < 0:
		return "DR"
	case a > 0:
		return "CR"
	}
	return ""
}

// Receivable is the amount due from the party: positive for Dr, negative for Cr.
func (a Amount) Receivable() float64 { return -float64(a) / 100 }

// Balance is the JSON shape used for every Dr/Cr figure.
type Balance struct {
	Amount float64 `json:"amount"`
	Type   string  `json:"type"` // "DR", "CR" or "" when zero
}

func (a Amount) Balance() Balance { return Balance{Amount: a.Rupees(), Type: a.DrCr()} }

// ISODate converts Tally's YYYYMMDD to YYYY-MM-DD; returns "" for anything else.
func ISODate(s string) string {
	s = strings.TrimSpace(s)
	if len(s) != 8 {
		return ""
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return ""
		}
	}
	return s[:4] + "-" + s[4:6] + "-" + s[6:]
}

var phoneRe = regexp.MustCompile(`\+?\d[\d \-]{7,15}\d`)

// ExtractPhones pulls 10–12 digit phone numbers out of free text such as
// "PH 8606880090" or "MOB: 9747351578, 8289944987". Pincodes (6 digits) and
// GSTINs (contain letters) are not matched.
func ExtractPhones(texts ...string) []string {
	var out []string
	seen := map[string]bool{}
	for _, t := range texts {
		for _, m := range phoneRe.FindAllString(t, -1) {
			d := strings.Map(func(r rune) rune {
				if r >= '0' && r <= '9' {
					return r
				}
				return -1
			}, m)
			if len(d) == 12 && strings.HasPrefix(d, "91") {
				d = d[2:]
			} else if len(d) == 11 && strings.HasPrefix(d, "0") && d[1] >= '6' {
				d = d[1:]
			}
			if len(d) < 10 || len(d) > 12 || seen[d] {
				continue
			}
			seen[d] = true
			out = append(out, d)
		}
	}
	return out
}

var (
	// Explicit separators used in this business's ledger names:
	// "ABI TYRES--G--Erattayar", "PRINCE TYRES -- RAJAKKAD", "BLDG - THODUPUZHA".
	areaSepRe = regexp.MustCompile(`-{2,}|\s-\s|-G-`)
	// A "G" marker is often glued to the town: "-- G MACHIPLAVU", "-- GMuttom",
	// "-- GVANNAPURAM". Strip it when followed by a space, by Upper+lower, or by
	// a consonant+vowel pair (no Kerala town starts "Gv", "Gm", ...).
	leadingGRe   = regexp.MustCompile(`^G(?:\s+|([A-Z][a-z])|([BCDFJKMNPSTVZbcdfjkmnpstvz][AEIOUaeiou]))`)
	trimPunctSet = " \t,.;:-/()"
)

// DeriveArea guesses the shop's area/town. Tally has no "area" field; in this
// data the town is the suffix of the ledger name. Returns "" if unsure.
func DeriveArea(name string) string {
	name = strings.TrimSpace(name)
	var part string
	if loc := areaSepRe.FindAllStringIndex(name, -1); len(loc) > 0 {
		part = name[loc[len(loc)-1][1]:]
		part = leadingGRe.ReplaceAllString(strings.TrimSpace(part), "${1}${2}")
		part, _, _ = strings.Cut(part, ",")
	} else {
		fields := strings.Fields(name)
		if len(fields) < 2 {
			return ""
		}
		part = fields[len(fields)-1]
	}
	part = strings.Trim(part, trimPunctSet)
	if len([]rune(part)) < 3 || strings.IndexFunc(part, unicode.IsLetter) < 0 {
		return ""
	}
	return titleCase(part)
}

func titleCase(s string) string {
	words := strings.Fields(strings.ToLower(s))
	for i, w := range words {
		r := []rune(w)
		r[0] = unicode.ToUpper(r[0])
		words[i] = string(r)
	}
	return strings.Join(words, " ")
}

func clean(s string) string { return strings.TrimSpace(s) }
