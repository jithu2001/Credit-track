package syncer

// The demo business for Google Play reviewers and testers: an invented
// TallyPrime company, "Demo Distributors" (32 shops in fictional towns,
// about 440 bills and payments from April to October 2026, 20 stock items,
// 3 suppliers with purchase bills), served by the fake Tally until the stop
// file disappears. Every name is made up and there are no phone numbers.
// Skipped unless WF_DEMO_TALLY is set.
//
// Run it, then point a Tally PC app at it and connect that PC to the demo
// business (README "Demo business for Play reviewers"):
//
//	touch /tmp/demo.stop
//	WF_DEMO_TALLY=127.0.0.1:19000 WF_DEMO_TALLY_STOP=/tmp/demo.stop go test ./internal/syncer -run TestDemoTally -timeout 12h -v
//
// Stop it with rm /tmp/demo.stop. The data is the same on every run (fixed seed).

import (
	"fmt"
	"math/rand"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

func money(paise int64) string {
	sign := ""
	if paise < 0 {
		sign, paise = "-", -paise
	}
	return fmt.Sprintf("%s%d.%02d", sign, paise/100, paise%100)
}

func demoCompany() *fakeCompany {
	r := rand.New(rand.NewSource(20261009))
	const guid = "demo-distributors-2026"
	c := &fakeCompany{Name: "Demo Distributors", GUID: guid, BooksFrom: "20260401"}
	names := []string{"Sunrise Auto Spares", "Bluewave Batteries", "Northstar Tyres", "Evergreen Motors", "Bright Star Electricals",
		"Metro Auto Care", "Royal Wheels", "City Battery House", "Prime Auto Parts", "Golden Gear Garage", "Speedline Motors",
		"Unity Auto Works", "Classic Car Care", "Highway Service Station", "Ace Electricals", "Crystal Auto Hub", "Pioneer Tyre Point",
		"Galaxy Auto Spares", "Swift Garage", "Victory Batteries", "Zenith Auto Centre", "Orbit Car Accessories", "Lotus Motor Works",
		"Summit Tyres", "Rapid Auto Electric", "Harbor Auto Parts", "Trident Motors", "Comet Battery World", "Nova Auto Mart", "Falcon Service Centre"}
	towns := []string{"Riverbend", "Hillview", "Lakeside", "Greenfield", "Palm Grove", "Maple Junction", "Coral Bay", "Silver Oak"}

	start := time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC)
	end := time.Date(2026, 10, 8, 0, 0, 0, 0, time.UTC)
	days := int(end.Sub(start).Hours() / 24)
	alter := int64(100)
	billNo, rcptNo := 1, 1
	for i, n := range names {
		shop := fmt.Sprintf("%s -- %s", n, towns[i%len(towns)])
		lg := fmt.Sprintf("%s-S%02d", guid, i+1)
		opening := -int64(r.Intn(4)) * int64(5000+r.Intn(20000)) * 100 // debit (owes) or 0
		bal := opening
		// How this shop pays: some promptly, some late, some barely.
		payShare := []float64{0.95, 0.8, 0.6, 0.3}[i%4]
		var owed int64
		bills := 5 + r.Intn(9)
		for b := 0; b < bills; b++ {
			d := start.AddDate(0, 0, r.Intn(days))
			amt := int64(2000+r.Intn(58000)) * 100
			alter++
			c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: fmt.Sprintf("%s-V%d", guid, alter), AlterID: alter, Date: d.Format("20060102"),
				Type: "Sales", Number: fmt.Sprintf("DD/26-27/%03d", billNo),
				Entries: []fakeEntry{{shop, "-" + money(amt)}, {"Sales Accounts GST", money(amt)}}})
			billNo++
			bal -= amt
			owed += amt
			// A payment some weeks later, for part of what is owed.
			pd := d.AddDate(0, 0, 10+r.Intn(70))
			if pd.Before(end) && r.Float64() < payShare {
				pay := int64(float64(owed)*payShare) / 100000 * 100000
				if pay > 0 {
					alter++
					c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: fmt.Sprintf("%s-V%d", guid, alter), AlterID: alter, Date: pd.Format("20060102"),
						Type: "Receipt", Number: fmt.Sprintf("R/%03d", rcptNo),
						Entries: []fakeEntry{{shop, money(pay)}, {"Bank Account", "-" + money(pay)}}})
					rcptNo++
					bal += pay
					owed -= pay
				}
			}
		}
		c.Ledgers = append(c.Ledgers, fakeLedger{Name: shop, GUID: lg, Parent: "Sundry Debtors", Opening: money(opening), Closing: money(bal)})
	}
	// Two shops with nothing due (settled), for the "settled" filter.
	for i, n := range []string{"Starlight Motors -- Riverbend", "Meadow Auto Parts -- Lakeside"} {
		c.Ledgers = append(c.Ledgers, fakeLedger{Name: n, GUID: fmt.Sprintf("%s-Z%d", guid, i), Parent: "Sundry Debtors"})
	}
	c.Ledgers = append(c.Ledgers,
		fakeLedger{Name: "Sales Accounts GST", GUID: guid + "-SA", Parent: "Sales Accounts"},
		fakeLedger{Name: "Bank Account", GUID: guid + "-BK", Parent: "Bank Accounts"},
		fakeLedger{Name: "Purchase Accounts GST", GUID: guid + "-PA", Parent: "Purchase Accounts"})

	// Stock: an invented brand. Some low, some out of stock.
	type item struct {
		name, group string
		rate        int64
	}
	items := []item{
		{"DP-35 Car Battery 35Ah", "Car Batteries", 5200}, {"DP-45 Car Battery 45Ah", "Car Batteries", 6400},
		{"DP-65 Car Battery 65Ah", "Car Batteries", 8900}, {"DP-80 SUV Battery 80Ah", "Car Batteries", 11200},
		{"DP-5L Bike Battery 5Ah", "Two Wheeler Batteries", 1350}, {"DP-7L Bike Battery 7Ah", "Two Wheeler Batteries", 1650},
		{"DP-9L Bike Battery 9Ah", "Two Wheeler Batteries", 1950}, {"DP-150 Inverter Battery 150Ah", "Inverter Batteries", 13800},
		{"DP-200 Inverter Battery 200Ah", "Inverter Batteries", 17600}, {"DP-100 Tubular 100Ah", "Inverter Batteries", 10500},
		{"Roadline 145/80 R12 Tyre", "Tyres", 2850}, {"Roadline 155/70 R13 Tyre", "Tyres", 3300},
		{"Roadline 175/65 R14 Tyre", "Tyres", 3950}, {"Roadline 185/65 R15 Tyre", "Tyres", 4600},
		{"Roadline 90/90-17 Bike Tyre", "Tyres", 1450}, {"Roadline 100/90-18 Bike Tyre", "Tyres", 1750},
		{"ClearFlow Distilled Water 1L", "Accessories", 45}, {"PowerClip Battery Terminal", "Accessories", 120},
		{"GripMax Wiper Blade 20in", "Accessories", 380}, {"ShineOn Car Polish 500ml", "Accessories", 290},
	}
	for i, it := range items {
		qty := []int{0, 2, 4, 7, 12, 18, 25, 40}[r.Intn(8)]
		if i == 0 || i == 7 {
			qty = 0 // out of stock
		}
		c.Stock = append(c.Stock, fakeStock{Name: it.name, GUID: fmt.Sprintf("%s-I%02d", guid, i+1), Group: it.group,
			Qty: fmt.Sprintf(" %d Nos", qty), Value: "-" + money(int64(qty)*it.rate*100), Rate: money(it.rate*100) + "/Nos"})
	}

	// Suppliers and purchase bills.
	suppliers := []string{"Northwind Power Supplies", "Bluehill Tyre Distributors", "Starline Accessories Co"}
	var owe [3]int64
	for p := 0; p < 9; p++ {
		s := p % 3
		d := start.AddDate(0, 0, 7+p*20)
		var lines []fakeItem
		var total int64
		for k := 0; k < 2+r.Intn(3); k++ {
			it := items[[]int{r.Intn(10), 10 + r.Intn(6), 16 + r.Intn(4)}[s]]
			q := int64(5 + r.Intn(20))
			cost := it.rate * 85 // 85% of the selling rate, in paise
			amt := q * cost
			total += amt
			lines = append(lines, fakeItem{Item: it.name, Qty: fmt.Sprintf(" %d Nos", q), Rate: money(cost) + "/Nos", Amount: "-" + money(amt)})
		}
		alter++
		c.Vouchers = append(c.Vouchers, fakeVoucher{GUID: fmt.Sprintf("%s-P%d", guid, alter), AlterID: alter, Date: d.Format("20060102"),
			Type: "Purchase", Number: fmt.Sprintf("PB/%03d", p+1), Party: suppliers[s], Items: lines,
			Entries: []fakeEntry{{suppliers[s], money(total)}, {"Purchase Accounts GST", "-" + money(total)}}})
		owe[s] += total
	}
	for s, n := range suppliers {
		paid := owe[s] / 2 / 100 * 100
		c.Ledgers = append(c.Ledgers, fakeLedger{Name: n, GUID: fmt.Sprintf("%s-SUP%d", guid, s), Parent: "Sundry Creditors",
			Closing: money(owe[s] - paid)})
	}
	return c
}

func TestDemoTally(t *testing.T) {
	addr, stop := os.Getenv("WF_DEMO_TALLY"), os.Getenv("WF_DEMO_TALLY_STOP")
	if addr == "" || stop == "" {
		t.Skip("demo data only")
	}
	c := demoCompany()
	f := &fakeTally{requests: map[string]int{}, companies: []*fakeCompany{c}}
	l, err := net.Listen("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	f.srv = httptest.NewUnstartedServer(http.HandlerFunc(f.handle))
	f.srv.Listener.Close()
	f.srv.Listener = l
	f.srv.Start()
	defer f.srv.Close()
	t.Logf("demo Tally on %s: %d ledgers, %d vouchers, %d stock items", addr, len(c.Ledgers), len(c.Vouchers), len(c.Stock))
	for {
		if _, err := os.Stat(stop); err != nil {
			t.Logf("requests: %v", f.requests)
			return
		}
		time.Sleep(time.Second)
	}
}
