package control

import (
	"strconv"
	"strings"
	"time"
)

// Access states, as the business database's access_state() computes them.
const (
	StateActive     = "active"
	StateRenewalDue = "renewal_due"
	StateGrace      = "grace"
	StateEnded      = "ended"
)

// Day is a calendar date at midnight UTC (dates only; the business clock
// decides which day "today" is).
func Day(t time.Time) time.Time { return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC) }

// India is the business clock for every hosted business today.
var India = time.FixedZone("IST", 5*3600+30*60)

// Today in the business clock.
func Today(now time.Time) time.Time { return Day(now.In(India)) }

// Period is what a payment covers.
type Period struct{ From, To time.Time }

// PaymentPeriod: a payment of n months starts the day after the current
// paid_until, or on the payment day when the subscription had already run
// out (no back-dating over a gap), and ends the day before the same date n
// months later. The new paid_until is To.
func PaymentPeriod(paidUntil, paidOn time.Time, months int) Period {
	from := Day(paidUntil).AddDate(0, 0, 1)
	if on := Day(paidOn); on.After(from) {
		from = on
	}
	return Period{From: from, To: addMonths(from, months).AddDate(0, 0, -1)}
}

// addMonths keeps month-end dates sensible: 31 Jan + 1 month = 28/29 Feb.
func addMonths(d time.Time, n int) time.Time {
	y, m, day := d.Date()
	first := time.Date(y, m, 1, 0, 0, 0, 0, time.UTC).AddDate(0, n, 0)
	last := first.AddDate(0, 1, -1).Day()
	if day > last {
		day = last
	}
	return time.Date(first.Year(), first.Month(), day, 0, 0, 0, 0, time.UTC)
}

// StatusDates: the app keeps working until grace_until; owners see the
// reminder from remind_from.
func StatusDates(paidUntil time.Time, graceDays, remindDays int) (graceUntil, remindFrom time.Time) {
	p := Day(paidUntil)
	return p.AddDate(0, 0, graceDays), p.AddDate(0, 0, -remindDays)
}

// AccessState mirrors public.access_state() for the admin app and the PC.
func AccessState(status string, paidUntil time.Time, graceDays, remindDays int, today time.Time) string {
	if status != "active" {
		return StateEnded
	}
	grace, remind := StatusDates(paidUntil, graceDays, remindDays)
	t := Day(today)
	switch {
	case t.After(grace):
		return StateEnded
	case t.After(Day(paidUntil)):
		return StateGrace
	case !t.Before(remind):
		return StateRenewalDue
	default:
		return StateActive
	}
}

// RenewMessage fills {plan} and {price} in the owner-facing template.
func RenewMessage(template, planName string, price float64) string {
	p := strconv.FormatFloat(price, 'f', -1, 64)
	return strings.NewReplacer("{plan}", planName, "{price}", p).Replace(template)
}
