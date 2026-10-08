package appapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Shops (owner and staff; row-level security limits staff to their sites):
//
//	GET /b/{slug}/api/v1/shops?company=<id>&q=&balance=all|owes|credit|settled&sites=<id>,no-site&sort=balance_desc|balance_asc|name&page=0
//	GET /b/{slug}/api/v1/shops/{id}
//	GET /b/{slug}/api/v1/reports/outstanding?company=<id>
//	GET /b/{slug}/api/v1/reports/overdue?company=<id>&credit_days=30
//
// Reports group shops by site (A–Z by name, "no site" last) with subtotals.

const shopPageSize = 50

// noSite in ?sites= stands for the shops in no site.
const noSite = "no-site"

func requireCompany(r *request) (string, error) {
	id := r.URL.Query().Get("company")
	if id == "" {
		return "", fail(http.StatusBadRequest, "INVALID_INPUT", "company is required.")
	}
	return id, nil
}

// companyName also checks the caller may see the company (404 otherwise).
func companyName(r *request, companyID string) (string, error) {
	var name string
	err := r.tx.QueryRow(r.Context(), `select company_name from public.tally_companies
		where id = $1::uuid and public.can_see_company(id)`, companyID).Scan(&name)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", fail(http.StatusNotFound, "NOT_FOUND", "No such company.")
	}
	return name, err
}

// likePattern turns a search into an ILIKE "contains" pattern, matching % and _ literally.
func likePattern(q string) string {
	q = strings.Join(strings.Fields(q), " ")
	q = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(q)
	return "%" + q + "%"
}

func (s *Server) shopsPage(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	if page < 0 || page > 10000 {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "page is out of range.")
	}
	where := []string{"s.company_id = $1::uuid", "s.deleted_at is null"}
	args := []any{companyID}
	arg := func(v any) string {
		args = append(args, v)
		return "$" + strconv.Itoa(len(args))
	}
	if search := strings.TrimSpace(q.Get("q")); search != "" {
		p := arg(likePattern(search))
		where = append(where, "(s.name ilike "+p+" or s.phone ilike "+p+" or s.area ilike "+p+")")
	}
	balance := q.Get("balance")
	switch balance {
	case "", "all":
	case "owes":
		where = append(where, "s.receivable > 0")
	case "credit":
		where = append(where, "s.receivable < 0")
	case "settled":
		where = append(where, "s.receivable = 0")
	default:
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "balance must be all, owes, credit or settled.")
	}
	if v := q.Get("sites"); v != "" {
		var ids []string
		withNone := false
		for _, id := range strings.Split(v, ",") {
			if id == noSite {
				withNone = true
			} else if id != "" {
				ids = append(ids, id)
			}
		}
		switch {
		case len(ids) == 0:
			where = append(where, "s.site_id is null")
		case withNone:
			where = append(where, "(s.site_id = any("+arg(ids)+"::uuid[]) or s.site_id is null)")
		default:
			where = append(where, "s.site_id = any("+arg(ids)+"::uuid[])")
		}
	}
	// "High to low" means the biggest amount first; credits are negative, so
	// under the credit filter that is the most negative first.
	order := ""
	switch q.Get("sort") {
	case "", "balance_desc":
		order = "s.receivable desc"
		if balance == "credit" {
			order = "s.receivable asc"
		}
	case "balance_asc":
		order = "s.receivable asc"
		if balance == "credit" {
			order = "s.receivable desc"
		}
	case "name":
	default:
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "sort must be balance_desc, balance_asc or name.")
	}
	if order != "" {
		order += ", "
	}
	order += "s.name, s.id"

	rows, err := r.tx.Query(r.Context(), `select s.id::text, s.name, s.area, s.phone, round(s.receivable * 100)::bigint, s.site_id::text, si.name
		from public.shops s left join public.sites si on si.id = s.site_id
		where `+strings.Join(where, " and ")+` order by `+order+
		` limit `+strconv.Itoa(shopPageSize)+` offset `+strconv.Itoa(page*shopPageSize), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	shops := []map[string]any{}
	for rows.Next() {
		sh, err := scanSummary(rows)
		if err != nil {
			return nil, err
		}
		shops = append(shops, sh.json())
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{"shops": shops, "page": page, "page_size": shopPageSize, "has_more": len(shops) == shopPageSize}, nil
}

type shopSummary struct {
	ID, Name                      string
	Area, Phone, SiteID, SiteName *string
	Receivable                    int64
}

func scanSummary(row pgx.Row) (shopSummary, error) {
	var s shopSummary
	err := row.Scan(&s.ID, &s.Name, &s.Area, &s.Phone, &s.Receivable, &s.SiteID, &s.SiteName)
	return s, err
}

func (s shopSummary) json() map[string]any {
	return map[string]any{"shop_id": s.ID, "name": s.Name, "area": s.Area, "phone": s.Phone,
		"receivable": money(s.Receivable), "site_id": s.SiteID, "site_name": s.SiteName}
}

func (s *Server) shopDetail(r *request) (any, error) {
	var (
		id, companyID, name, obType string
		area, phone, phoneSource    *string
		contact, email, gstin, addr *string
		state, pincode              *string
		siteID, siteName            *string
		phones, addressLines        []string
		ob, receivable              int64
		syncedAt                    *time.Time
	)
	err := r.tx.QueryRow(r.Context(), `select s.id::text, s.company_id::text, s.name, s.area, s.phone, s.phones, s.phone_source,
			s.contact_person, s.email, s.gstin, s.address, s.address_lines, s.state, s.pincode,
			round(s.opening_balance_amount * 100)::bigint, s.opening_balance_type, round(s.receivable * 100)::bigint,
			s.synced_at, s.site_id::text, si.name
		from public.shops s left join public.sites si on si.id = s.site_id
		where s.id = $1::uuid and s.deleted_at is null`, r.PathValue("id")).
		Scan(&id, &companyID, &name, &area, &phone, &phones, &phoneSource, &contact, &email, &gstin, &addr, &addressLines,
			&state, &pincode, &ob, &obType, &receivable, &syncedAt, &siteID, &siteName)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fail(http.StatusNotFound, "NOT_FOUND", "This shop is not available.")
	} else if err != nil {
		return nil, err
	}
	if phones == nil {
		phones = []string{}
	}
	if addressLines == nil {
		addressLines = []string{}
	}
	return map[string]any{
		"id": id, "company_id": companyID, "name": name, "area": area, "phone": phone, "phones": phones,
		"phone_source": phoneSource, "contact_person": contact, "email": email, "gstin": gstin, "address": addr,
		"address_lines": addressLines, "state": state, "pincode": pincode,
		"opening_balance_amount": money(ob), "opening_balance_type": obType, "receivable": money(receivable),
		"synced_at": optTime(syncedAt), "site_id": siteID, "site_name": siteName,
	}, nil
}

// ---------------------------------------------------------------- reports

// siteGroup is one site's shops in a report.
type siteGroup struct {
	id, name *string
	shops    []map[string]any
	subtotal int64
}

func siteLabel(name *string) string {
	if name == nil || strings.TrimSpace(*name) == "" {
		return "No site"
	}
	return strings.TrimSpace(*name)
}

// groupsJSON orders groups by site name (A–Z), "no site" last, and writes them.
func groupsJSON(groups map[string]*siteGroup) []map[string]any {
	list := make([]*siteGroup, 0, len(groups))
	for _, g := range groups {
		list = append(list, g)
	}
	sort.Slice(list, func(i, j int) bool {
		a, b := list[i], list[j]
		if (a.id == nil) != (b.id == nil) {
			return b.id == nil
		}
		la, lb := strings.ToLower(siteLabel(a.name)), strings.ToLower(siteLabel(b.name))
		if la != lb {
			return la < lb
		}
		return str(a.id) < str(b.id)
	})
	out := make([]map[string]any, 0, len(list))
	for _, g := range list {
		out = append(out, map[string]any{"site_id": g.id, "site_name": g.name, "subtotal": money(g.subtotal), "shops": g.shops})
	}
	return out
}

func groupFor(groups map[string]*siteGroup, id, name *string) *siteGroup {
	key := str(id)
	g := groups[key]
	if g == nil {
		g = &siteGroup{id: id, name: name}
		groups[key] = g
	}
	return g
}

func (s *Server) outstandingReport(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	name, err := companyName(r, companyID)
	if err != nil {
		return nil, err
	}
	rows, err := r.tx.Query(r.Context(), `select shop_id::text, name, area, phone, round(receivable * 100)::bigint, site_id::text, site_name
		from public.v_shop_outstanding where company_id = $1::uuid and receivable > 0
		order by receivable desc, name, shop_id`, companyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	groups := map[string]*siteGroup{}
	var total int64
	count := 0
	for rows.Next() {
		sh, err := scanSummary(rows)
		if err != nil {
			return nil, err
		}
		g := groupFor(groups, sh.SiteID, sh.SiteName)
		g.shops = append(g.shops, sh.json())
		g.subtotal += sh.Receivable
		total += sh.Receivable
		count++
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{
		"company_id": companyID, "company_name": name, "generated_at": s.Now().UTC().Format(time.RFC3339),
		"total": money(total), "shop_count": count, "groups": groupsJSON(groups),
	}, nil
}

func (s *Server) overdueReport(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	days, err := creditDays(r)
	if err != nil {
		return nil, err
	}
	name, err := companyName(r, companyID)
	if err != nil {
		return nil, err
	}
	// Ageing (FIFO) runs in the database: overdue_shops() limits shops to the
	// caller's sites and leaves bills out for staff who may not see transactions.
	rows, err := r.tx.Query(r.Context(), `select shop_id::text, name, area, phone, round(receivable * 100)::bigint,
			round(overdue * 100)::bigint, max_days_overdue, overdue_bills, bills_visible, bills, site_id::text, site_name
		from public.overdue_shops($1::uuid, $2, $3) where overdue > 0
		order by overdue desc, max_days_overdue desc, shop_id`, companyID, days, r.today)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	groups := map[string]*siteGroup{}
	var total int64
	count := 0
	for rows.Next() {
		var id, shopName string
		var area, phone, siteID, siteName *string
		var receivable, overdue int64
		var maxDays, bills int
		var visible bool
		var billJSON []byte
		if err := rows.Scan(&id, &shopName, &area, &phone, &receivable, &overdue, &maxDays, &bills, &visible, &billJSON,
			&siteID, &siteName); err != nil {
			return nil, err
		}
		var billList any
		if visible && len(billJSON) > 0 {
			billList = json.RawMessage(billJSON)
		}
		g := groupFor(groups, siteID, siteName)
		g.shops = append(g.shops, map[string]any{
			"shop_id": id, "name": shopName, "area": area, "phone": phone, "receivable": money(receivable),
			"overdue": money(overdue), "max_days_overdue": maxDays, "overdue_bills": bills,
			"bills_visible": visible, "bills": billList, "site_id": siteID, "site_name": siteName,
		})
		g.subtotal += overdue
		total += overdue
		count++
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{
		"company_id": companyID, "company_name": name, "credit_days": days, "today": date(r.today),
		"generated_at": s.Now().UTC().Format(time.RFC3339), "total": money(total), "shop_count": count,
		"groups": groupsJSON(groups),
	}, nil
}
