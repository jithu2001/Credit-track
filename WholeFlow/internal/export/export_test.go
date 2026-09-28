package export

import (
	"bytes"
	"strings"
	"testing"
)

func TestCSVDefusesFormulasAndKeepsNumbers(t *testing.T) {
	var b bytes.Buffer
	err := WriteCSV(&b, Table{Headers: []string{"Name", "Bills", "Amount"}, Rows: [][]any{
		{`=HYPERLINK("http://x","Click")`, 3, -12.5},
		{"@SUM(A1)", 0, 0.0},
		{"PRINCE TYRES -- RAJAKKAD", 1, 1.0},
	}})
	if err != nil {
		t.Fatal(err)
	}
	out := b.String()
	for _, want := range []string{`"'=HYPERLINK(""http://x"",""Click"")",3,-12.50`, "'@SUM(A1),0,0.00", "PRINCE TYRES -- RAJAKKAD,1,1.00"} {
		if !strings.Contains(out, want) {
			t.Errorf("CSV lacks %s:\n%s", want, out)
		}
	}
}

func TestXLSXWritesIntsAsNumbers(t *testing.T) {
	if s := sheetXML(Table{Headers: []string{"Bills"}, Rows: [][]any{{7}}}); !strings.Contains(s, "<v>7</v>") {
		t.Fatalf("int not written as a number cell: %s", s)
	}
}
