// Package tally talks to TallyPrime over its built-in HTTP/XML server.
// All Tally-specific request building, XML parsing and error translation lives
// here; callers only see Go types and *Error values.
package tally

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// ErrorKind classifies failures so the API layer can pick a user-facing message.
type ErrorKind string

const (
	KindUnreachable     ErrorKind = "TALLY_UNREACHABLE"
	KindTimeout         ErrorKind = "TALLY_TIMEOUT"
	KindHTTP            ErrorKind = "TALLY_HTTP_ERROR"
	KindInvalidResponse ErrorKind = "TALLY_INVALID_RESPONSE"
	KindTallyError      ErrorKind = "TALLY_ERROR"
	KindNoCompany       ErrorKind = "NO_COMPANY_SELECTED"
	KindCompanyNotFound ErrorKind = "COMPANY_NOT_FOUND"
	KindNotFound        ErrorKind = "NOT_FOUND"
)

type Error struct {
	Kind ErrorKind
	Op   string // request type, e.g. "companies"
	Msg  string // technical detail, safe to log
	Err  error
}

func (e *Error) Error() string {
	s := fmt.Sprintf("tally %s: %s", e.Op, e.Kind)
	if e.Msg != "" {
		s += ": " + e.Msg
	}
	if e.Err != nil {
		s += ": " + e.Err.Error()
	}
	return s
}

func (e *Error) Unwrap() error { return e.Err }

// Client is a thin, serialised HTTP transport to one Tally server.
// TallyPrime processes requests one at a time, so we never send in parallel.
type Client struct {
	Endpoint string
	http     *http.Client
	log      *slog.Logger
	rawDir   string // where raw responses are written; "" disables debug dumps
	errDir   string // raw responses that failed to parse are always kept here
	mu       sync.Mutex
}

func NewClient(host string, port int, timeout time.Duration, log *slog.Logger, logDir string, debugRaw bool) *Client {
	c := &Client{
		Endpoint: fmt.Sprintf("http://%s", net.JoinHostPort(host, strconv.Itoa(port))),
		http:     &http.Client{Timeout: timeout},
		log:      log,
		errDir:   filepath.Join(logDir, "raw-errors"),
	}
	if debugRaw {
		c.rawDir = filepath.Join(logDir, "raw")
	}
	return c
}

// Post sends an XML envelope and returns the sanitised response body.
func (c *Client) Post(ctx context.Context, op string, body []byte) ([]byte, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	start := time.Now()
	attrs := []any{"op", op, "endpoint", c.Endpoint}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, &Error{Kind: KindHTTP, Op: op, Err: err}
	}
	req.Header.Set("Content-Type", "text/xml; charset=utf-8")

	resp, err := c.http.Do(req)
	if err != nil {
		kind := KindUnreachable
		var ne net.Error
		if errors.Is(err, context.DeadlineExceeded) || (errors.As(err, &ne) && ne.Timeout()) {
			kind = KindTimeout
		}
		c.log.Error("tally request failed", append(attrs, "kind", kind, "error", err.Error(),
			"duration_ms", time.Since(start).Milliseconds())...)
		return nil, &Error{Kind: kind, Op: op, Err: err}
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	attrs = append(attrs, "status", resp.StatusCode, "bytes", len(raw), "duration_ms", time.Since(start).Milliseconds())
	if err != nil {
		kind := KindUnreachable
		if errors.Is(err, context.DeadlineExceeded) {
			kind = KindTimeout
		}
		c.log.Error("tally response read failed", append(attrs, "kind", kind, "error", err.Error())...)
		return nil, &Error{Kind: kind, Op: op, Err: err}
	}
	if c.rawDir != "" {
		c.dump(c.rawDir, op, raw)
	}
	if resp.StatusCode != http.StatusOK {
		c.log.Error("tally returned non-200", attrs...)
		return nil, &Error{Kind: KindHTTP, Op: op, Msg: resp.Status}
	}

	clean := sanitize(raw)
	if err := checkEnvelope(clean); err != nil {
		path := c.dump(c.errDir, op, raw)
		c.log.Error("tally response rejected", append(attrs, "error", err.Error(), "raw_saved_to", path)...)
		err.Op = op
		return nil, err
	}
	c.log.Info("tally request ok", attrs...)
	return clean, nil
}

// Decode unmarshals a sanitised response, keeping the raw body on failure.
func (c *Client) Decode(op string, body []byte, v any) error {
	if err := xml.Unmarshal(body, v); err != nil {
		path := c.dump(c.errDir, op, body)
		c.log.Error("tally XML parse failed", "op", op, "error", err.Error(), "raw_saved_to", path)
		return &Error{Kind: KindInvalidResponse, Op: op, Msg: "could not parse XML", Err: err}
	}
	return nil
}

func (c *Client) dump(dir, op string, raw []byte) string {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		c.log.Warn("cannot create raw dump dir", "dir", dir, "error", err.Error())
		return ""
	}
	name := fmt.Sprintf("%s_%s.xml", time.Now().Format("20060102-150405.000"), op)
	path := filepath.Join(dir, strings.ReplaceAll(name, ":", ""))
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		c.log.Warn("cannot write raw dump", "path", path, "error", err.Error())
		return ""
	}
	return path
}

var (
	// Tally emits character references such as &#4; (e.g. before "Primary")
	// that are illegal in XML 1.0 and make strict parsers fail.
	charRefRe = regexp.MustCompile(`&#(x[0-9a-fA-F]+|[0-9]+);`)
)

func sanitize(b []byte) []byte {
	b = bytes.TrimPrefix(b, []byte("\xef\xbb\xbf"))
	if !utf8.Valid(b) {
		b = bytes.ToValidUTF8(b, []byte("�"))
	}
	b = charRefRe.ReplaceAllFunc(b, func(m []byte) []byte {
		s := string(m[2 : len(m)-1])
		var n int64
		var err error
		if s[0] == 'x' || s[0] == 'X' {
			n, err = strconv.ParseInt(s[1:], 16, 32)
		} else {
			n, err = strconv.ParseInt(s, 10, 32)
		}
		if err != nil || !validXMLChar(rune(n)) {
			return nil
		}
		return m
	})
	return bytes.Map(func(r rune) rune {
		if validXMLChar(r) {
			return r
		}
		return -1
	}, b)
}

func validXMLChar(r rune) bool {
	return r == 0x9 || r == 0xA || r == 0xD ||
		(r >= 0x20 && r <= 0xD7FF) || (r >= 0xE000 && r <= 0xFFFD) || (r >= 0x10000 && r <= 0x10FFFF)
}

// checkEnvelope recognises Tally's error shapes:
//
//	<RESPONSE>Unknown Request, cannot be processed</RESPONSE>
//	<ENVELOPE><HEADER><STATUS>0</STATUS></HEADER><BODY><DATA>DESC not found</DATA></BODY></ENVELOPE>
//	<ENVELOPE>...<LINEERROR>Could not find ...</LINEERROR>...</ENVELOPE>
func checkEnvelope(b []byte) *Error {
	var probe struct {
		XMLName xml.Name
		Status  string `xml:"HEADER>STATUS"`
		Data    struct {
			Text      string `xml:",chardata"`
			LineError string `xml:"LINEERROR"`
		} `xml:"BODY>DATA"`
		Text string `xml:",chardata"`
	}
	if err := xml.Unmarshal(b, &probe); err != nil {
		return &Error{Kind: KindInvalidResponse, Msg: "response is not valid XML", Err: err}
	}
	switch {
	case probe.XMLName.Local == "RESPONSE":
		return &Error{Kind: KindTallyError, Msg: strings.TrimSpace(probe.Text)}
	case probe.XMLName.Local != "ENVELOPE":
		return &Error{Kind: KindInvalidResponse, Msg: "unexpected root element <" + probe.XMLName.Local + ">"}
	case strings.TrimSpace(probe.Data.LineError) != "":
		return &Error{Kind: KindTallyError, Msg: strings.TrimSpace(probe.Data.LineError)}
	case strings.TrimSpace(probe.Status) == "0":
		return &Error{Kind: KindTallyError, Msg: strings.TrimSpace(probe.Data.Text)}
	}
	return nil
}

// Request describes one TDL collection export.
type Request struct {
	Company  string            // SVCURRENTCOMPANY; empty = Tally's active company
	FromDate string            // YYYYMMDD, optional
	ToDate   string            // YYYYMMDD, optional
	Vars     map[string]string // extra static variables (declared as String in the TDL)
	TDL      string            // inner TDLMESSAGE XML; must define collection "WFC"
}

func (r Request) Envelope() []byte {
	var b bytes.Buffer
	b.WriteString(`<ENVELOPE><HEADER><VERSION>1</VERSION><TALLYREQUEST>Export</TALLYREQUEST>`)
	b.WriteString(`<TYPE>Collection</TYPE><ID>WFC</ID></HEADER><BODY><DESC><STATICVARIABLES>`)
	b.WriteString(`<SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>`)
	tag := func(name, val string) {
		b.WriteString("<" + name + ">")
		xml.EscapeText(&b, []byte(val))
		b.WriteString("</" + name + ">")
	}
	if r.Company != "" {
		tag("SVCURRENTCOMPANY", r.Company)
	}
	if r.FromDate != "" {
		tag("SVFROMDATE", r.FromDate)
	}
	if r.ToDate != "" {
		tag("SVTODATE", r.ToDate)
	}
	for k, v := range r.Vars {
		tag(k, v)
	}
	b.WriteString(`</STATICVARIABLES><TDL><TDLMESSAGE>`)
	for k := range r.Vars {
		b.WriteString(`<VARIABLE NAME="` + k + `"><TYPE>String</TYPE></VARIABLE>`)
	}
	b.WriteString(r.TDL)
	b.WriteString(`</TDLMESSAGE></TDL></DESC></BODY></ENVELOPE>`)
	return b.Bytes()
}
