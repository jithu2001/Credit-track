// Package export writes tabular reports as CSV or a minimal .xlsx workbook
// (standard library only).
package export

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"encoding/xml"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// Table is a header row plus data rows; cells are string or float64.
type Table struct {
	Sheet   string
	Title   string // optional first line, e.g. company and timestamp
	Headers []string
	Rows    [][]any
}

func WriteCSV(w io.Writer, t Table) error {
	// BOM so Excel opens UTF-8 (₹, Malayalam names) correctly.
	if _, err := w.Write([]byte("\xef\xbb\xbf")); err != nil {
		return err
	}
	cw := csv.NewWriter(w)
	if t.Title != "" {
		cw.Write([]string{t.Title})
	}
	cw.Write(t.Headers)
	for _, r := range t.Rows {
		rec := make([]string, len(r))
		for i, v := range r {
			switch x := v.(type) {
			case float64:
				rec[i] = strconv.FormatFloat(x, 'f', 2, 64)
			case int:
				rec[i] = strconv.Itoa(x)
			default:
				rec[i] = csvText(fmt.Sprint(x))
			}
		}
		cw.Write(rec)
	}
	cw.Flush()
	return cw.Error()
}

func WriteXLSX(w io.Writer, t Table) error {
	sheet := t.Sheet
	if sheet == "" {
		sheet = "Sheet1"
	}
	files := map[string]string{
		"[Content_Types].xml": `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`,
		"_rels/.rels": `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`,
		"xl/workbook.xml": `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="` + esc(sheet) + `" sheetId="1" r:id="rId1"/></sheets></workbook>`,
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`,
		// Style 1 = bold header, style 2 = #,##0.00 (built-in numFmt 4).
		"xl/styles.xml": `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>
</styleSheet>`,
		"xl/worksheets/sheet1.xml": sheetXML(t),
	}

	zw := zip.NewWriter(w)
	for _, name := range []string{"[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
		"xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"} {
		f, err := zw.Create(name)
		if err != nil {
			return err
		}
		if _, err := io.WriteString(f, files[name]); err != nil {
			return err
		}
	}
	return zw.Close()
}

func sheetXML(t Table) string {
	var b bytes.Buffer
	b.WriteString(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` +
		`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)
	row := 0
	writeRow := func(cells []any, style int) {
		row++
		fmt.Fprintf(&b, `<row r="%d">`, row)
		for i, v := range cells {
			ref := colName(i) + strconv.Itoa(row)
			switch x := v.(type) {
			case float64:
				s := style
				if s == 0 {
					s = 2
				}
				fmt.Fprintf(&b, `<c r="%s" s="%d"><v>%s</v></c>`, ref, s, strconv.FormatFloat(x, 'f', -1, 64))
			case int:
				fmt.Fprintf(&b, `<c r="%s" s="%d"><v>%d</v></c>`, ref, style, x)
			default:
				fmt.Fprintf(&b, `<c r="%s" s="%d" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>`,
					ref, style, esc(fmt.Sprint(x)))
			}
		}
		b.WriteString(`</row>`)
	}
	if t.Title != "" {
		writeRow([]any{t.Title}, 1)
	}
	hdr := make([]any, len(t.Headers))
	for i, h := range t.Headers {
		hdr[i] = h
	}
	writeRow(hdr, 1)
	for _, r := range t.Rows {
		writeRow(r, 0)
	}
	b.WriteString(`</sheetData></worksheet>`)
	return b.String()
}

func colName(i int) string {
	s := ""
	for i++; i > 0; i = (i - 1) / 26 {
		s = string(rune('A'+(i-1)%26)) + s
	}
	return s
}

func esc(s string) string {
	var b bytes.Buffer
	xml.EscapeText(&b, []byte(s))
	return b.String()
}

// csvText defuses spreadsheet formula injection: a Tally name or narration
// such as =HYPERLINK(...) or @SUM(...) would otherwise run as a formula when
// the CSV is opened in Excel. A leading apostrophe makes Excel show it as
// text. (XLSX cells are typed inline strings and are safe as they are.)
func csvText(s string) string {
	if s != "" && strings.ContainsRune("=+-@\t\r", rune(s[0])) {
		return "'" + s
	}
	return s
}
