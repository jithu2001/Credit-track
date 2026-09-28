package tally

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
)

// WholeFlow never writes to Tally. Every request body passes through
// checkReadOnly before it leaves the process (see Client.post), which accepts
// only the one shape this package produces: a TDL collection *Export*.
//
// The check is an allow-list, not a block-list: the envelope header is fixed
// (TALLYREQUEST=Export, TYPE=Collection), only known elements may appear, and
// formulas may call only the read-only $$ functions listed below. Anything
// else — an Import, a TALLYMESSAGE with vouchers or masters, an ACTION, a
// report or function definition, an unknown $$ function — is refused and
// never sent. User input (company, ledger and item names, ids) only ever
// appears as escaped text inside static variables, so it cannot add elements.

// KindWriteBlocked is returned when a request fails the read-only check.
const KindWriteBlocked ErrorKind = "TALLY_WRITE_BLOCKED"

var (
	// Children allowed under each element, by path. "" = text only.
	allowedChildren = map[string]map[string]bool{
		"ENVELOPE":                                     set("HEADER", "BODY"),
		"ENVELOPE/HEADER":                              set("VERSION", "TALLYREQUEST", "TYPE", "ID"),
		"ENVELOPE/BODY":                                set("DESC"),
		"ENVELOPE/BODY/DESC":                           set("STATICVARIABLES", "TDL"),
		"ENVELOPE/BODY/DESC/TDL":                       set("TDLMESSAGE"),
		"ENVELOPE/BODY/DESC/TDL/TDLMESSAGE":            set("COLLECTION", "SYSTEM", "VARIABLE"),
		"ENVELOPE/BODY/DESC/TDL/TDLMESSAGE/COLLECTION": set("TYPE", "FETCH", "FILTER", "CHILDOF", "BELONGSTO", "COMPUTE"),
		"ENVELOPE/BODY/DESC/TDL/TDLMESSAGE/VARIABLE":   set("TYPE"),
	}
	// Fixed header values: this is what makes the request an export.
	requiredHeader = map[string]string{
		"VERSION": "1", "TALLYREQUEST": "Export", "TYPE": "Collection", "ID": "WFC",
	}
	// Static variables: Tally's own SV* inputs and this app's WF* variables.
	staticVarRe = regexp.MustCompile(`^(SVEXPORTFORMAT|SVCURRENTCOMPANY|SVFROMDATE|SVTODATE|WF[A-Z0-9]+)$`)
	// Attributes allowed per element name.
	allowedAttrs = map[string]map[string]bool{
		"COLLECTION": set("NAME"),
		"SYSTEM":     set("TYPE", "NAME"),
		"VARIABLE":   set("NAME"),
	}
	// Read-only TDL functions the formulas use.
	allowedFunctions = set("SysName", "IsPurchase", "FilterCount", "SystemPeriodFrom", "SystemPeriodTo")
	functionRe       = regexp.MustCompile(`\$\$([A-Za-z_][A-Za-z0-9_]*)`)
)

func set(xs ...string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}

// checkReadOnly returns nil only for a well-formed collection export built
// from the allowed vocabulary.
func checkReadOnly(body []byte) error {
	dec := xml.NewDecoder(bytes.NewReader(body))
	dec.Strict = true
	var path []string
	var text strings.Builder
	seenRoot := false
	header := map[string]string{}
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("request is not well-formed XML: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			name := t.Name.Local
			if t.Name.Space != "" {
				return fmt.Errorf("namespaced element <%s:%s> not allowed", t.Name.Space, name)
			}
			parent := strings.Join(path, "/")
			switch {
			case len(path) == 0:
				if seenRoot || name != "ENVELOPE" {
					return fmt.Errorf("root element must be a single <ENVELOPE>, got <%s>", name)
				}
				seenRoot = true
			case parent == "ENVELOPE/BODY/DESC/STATICVARIABLES":
				if !staticVarRe.MatchString(name) {
					return fmt.Errorf("static variable <%s> not allowed", name)
				}
			default:
				kids, known := allowedChildren[parent]
				if !known || !kids[name] {
					return fmt.Errorf("element <%s> not allowed inside <%s>", name, parent)
				}
			}
			for _, a := range t.Attr {
				if !allowedAttrs[name][a.Name.Local] || a.Name.Space != "" {
					return fmt.Errorf("attribute %s on <%s> not allowed", a.Name.Local, name)
				}
				if name == "SYSTEM" && a.Name.Local == "TYPE" && a.Value != "Formulae" {
					return fmt.Errorf(`<SYSTEM TYPE=%q> not allowed (only "Formulae")`, a.Value)
				}
				if err := checkFunctions(a.Value); err != nil {
					return err
				}
			}
			path = append(path, name)
			text.Reset()
		case xml.EndElement:
			if len(path) == 2 && path[0] == "ENVELOPE" && path[1] != "BODY" && path[1] != "HEADER" {
				return fmt.Errorf("unexpected <%s>", path[1])
			}
			if len(path) == 3 && path[1] == "HEADER" {
				header[path[2]] = strings.TrimSpace(text.String())
			}
			path = path[:len(path)-1]
			text.Reset()
		case xml.CharData:
			text.Write(t)
			if err := checkFunctions(string(t)); err != nil {
				return err
			}
		case xml.ProcInst, xml.Directive:
			return errors.New("processing instructions and directives not allowed")
		}
	}
	if !seenRoot {
		return errors.New("empty request")
	}
	for k, want := range requiredHeader {
		if header[k] != want {
			return fmt.Errorf("header %s must be %q, got %q", k, want, header[k])
		}
	}
	return nil
}

func checkFunctions(s string) error {
	for _, m := range functionRe.FindAllStringSubmatch(s, -1) {
		if !allowedFunctions[m[1]] {
			return fmt.Errorf("TDL function $$%s not allowed", m[1])
		}
	}
	return nil
}
