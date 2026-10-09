package appapi

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

// Sites and shop locations. Owners create, rename and delete sites (RLS);
// which shops are in a site, shop pins and suggestions change only through
// the database's functions, which check who may.
//
//	GET    /b/{slug}/api/v1/sites[?company=<id>]                 sites (staff: only theirs)
//	POST   /b/{slug}/api/v1/sites                                {"company", "name", "shops": [...]} → {"id"}
//	PATCH  /b/{slug}/api/v1/sites/{id}                           {"name"}
//	DELETE /b/{slug}/api/v1/sites/{id}
//	PUT    /b/{slug}/api/v1/sites/{id}/shops                     {"shops": [...]} (exactly these shops)
//	GET    /b/{slug}/api/v1/sites/{id}/shops                     the site's shops, highest balance first
//	GET    /b/{slug}/api/v1/companies/{id}/site-shops            every shop with its site (site editor)
//	GET    /b/{slug}/api/v1/reports/sites?company=&from=&to=     site_report()
//	GET    /b/{slug}/api/v1/shops/{id}/location                  {"location": row | null}
//	PUT    /b/{slug}/api/v1/shops/{id}/location                  {"latitude", "longitude", "radius_m"}
//	DELETE /b/{slug}/api/v1/shops/{id}/location
//	GET    /b/{slug}/api/v1/location-suggestions                 pending, oldest first
//	POST   /b/{slug}/api/v1/location-suggestions/{id}/review     {"approve", "radius_m"}

func ok() map[string]any { return map[string]any{"ok": true} }

// siteNameError explains the database's refusals of a site name.
func siteNameError(err error) error {
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		switch pg.Code {
		case "23505":
			return fail(http.StatusConflict, "NAME_TAKEN", "There is already a site with this name in this company.")
		case "23514":
			return fail(http.StatusBadRequest, "INVALID_INPUT", "Enter a site name (up to 80 characters).")
		}
	}
	return err
}

func (s *Server) sitesList(r *request) (any, error) {
	where, args := "true", []any{}
	if c := r.URL.Query().Get("company"); c != "" {
		where, args = "company_id = $1::uuid", []any{c}
	}
	rows, err := jsonRows(r, `select id, company_id, name from public.sites where `+where+` order by name, id`, args...)
	if err != nil {
		return nil, err
	}
	return map[string]any{"sites": rows}, nil
}

func (s *Server) createSite(r *request) (any, error) {
	var in struct {
		Company string   `json:"company"`
		Name    string   `json:"name"`
		Shops   []string `json:"shops"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	var id string
	if err := r.tx.QueryRow(r.Context(), `insert into public.sites (company_id, name) values ($1::uuid, $2) returning id::text`,
		in.Company, strings.TrimSpace(in.Name)).Scan(&id); err != nil {
		return nil, siteNameError(err)
	}
	if err := setSiteShops(r, id, in.Shops); err != nil {
		return nil, err
	}
	return map[string]any{"id": id}, nil
}

func setSiteShops(r *request, siteID string, shops []string) error {
	if shops == nil {
		shops = []string{}
	}
	_, err := r.tx.Exec(r.Context(), `select public.set_site_shops($1::uuid, $2::uuid[])`, siteID, shops)
	return err
}

// affected fails with 404 when an update or delete matched no row the caller may change.
func affected(tag pgconn.CommandTag, what string) error {
	if tag.RowsAffected() == 0 {
		return fail(http.StatusNotFound, "NOT_FOUND", fmt.Sprintf("This %s is not available.", what))
	}
	return nil
}

func (s *Server) renameSite(r *request) (any, error) {
	var in struct {
		Name string `json:"name"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	tag, err := r.tx.Exec(r.Context(), `update public.sites set name = $2 where id = $1::uuid`, r.PathValue("id"), strings.TrimSpace(in.Name))
	if err != nil {
		return nil, siteNameError(err)
	}
	return ok(), affected(tag, "site")
}

func (s *Server) deleteSite(r *request) (any, error) {
	tag, err := r.tx.Exec(r.Context(), `delete from public.sites where id = $1::uuid`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return ok(), affected(tag, "site")
}

func (s *Server) putSiteShops(r *request) (any, error) {
	var in struct {
		Shops []string `json:"shops"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	if err := setSiteShops(r, r.PathValue("id"), in.Shops); err != nil {
		return nil, err
	}
	return ok(), nil
}

func (s *Server) siteShops(r *request) (any, error) {
	rows, err := r.tx.Query(r.Context(), `select s.id::text, s.name, s.area, s.phone, round(s.receivable * 100)::bigint, s.site_id::text, si.name
		from public.shops s join public.sites si on si.id = s.site_id
		where s.site_id = $1::uuid and s.deleted_at is null order by s.receivable desc, s.id`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		sh, err := scanSummary(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, sh.json())
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return map[string]any{"shops": out}, nil
}

func (s *Server) companySiteShops(r *request) (any, error) {
	rows, err := jsonRows(r, `select id, name, area, site_id, receivable from public.shops
		where company_id = $1::uuid and deleted_at is null order by name, id`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return map[string]any{"shops": rows}, nil
}

func (s *Server) siteReport(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	from, err := optDate(r, "from")
	if err != nil {
		return nil, err
	}
	to, err := optDate(r, "to")
	if err != nil {
		return nil, err
	}
	if from == nil || to == nil {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "from and to are required.")
	}
	rows, err := jsonRows(r, `select * from public.site_report($1::uuid, $2, $3)`, companyID, *from, *to)
	if err != nil {
		return nil, err
	}
	return map[string]any{"rows": rows}, nil
}

// ---------------------------------------------------------------- shop locations

func (s *Server) shopLocation(r *request) (any, error) {
	row, err := jsonRow(r, `select shop_id, latitude, longitude, radius_m, source, set_at
		from public.shop_locations where shop_id = $1::uuid`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return map[string]any{"location": row}, nil
}

func (s *Server) setShopLocation(r *request) (any, error) {
	var in struct {
		Latitude  float64 `json:"latitude"`
		Longitude float64 `json:"longitude"`
		RadiusM   int     `json:"radius_m"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	_, err := r.tx.Exec(r.Context(), `select public.set_shop_location($1::uuid, $2, $3, $4)`,
		r.PathValue("id"), in.Latitude, in.Longitude, in.RadiusM)
	var pg *pgconn.PgError
	if errors.As(err, &pg) && pg.Code == "23514" {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT",
			fmt.Sprintf("The server does not accept a %d m radius. Choose 20 m or more.", in.RadiusM))
	}
	if err != nil {
		return nil, err
	}
	return ok(), nil
}

func (s *Server) clearShopLocation(r *request) (any, error) {
	if _, err := r.tx.Exec(r.Context(), `select public.clear_shop_location($1::uuid)`, r.PathValue("id")); err != nil {
		return nil, err
	}
	return ok(), nil
}

func (s *Server) locationSuggestions(r *request) (any, error) {
	rows, err := jsonRows(r, `select g.id, g.shop_id, g.latitude, g.longitude, g.accuracy_m, g.created_at,
			json_build_object('name', sh.name) as shops, json_build_object('name', u.name) as users
		from public.shop_location_suggestions g
		left join public.shops sh on sh.id = g.shop_id
		left join public.users u on u.id = g.suggested_by
		where g.status = 'pending' order by g.created_at, g.id`)
	if err != nil {
		return nil, err
	}
	return map[string]any{"suggestions": rows}, nil
}

func (s *Server) reviewSuggestion(r *request) (any, error) {
	var in struct {
		Approve bool `json:"approve"`
		RadiusM *int `json:"radius_m"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	radius := 100
	if in.RadiusM != nil {
		radius = *in.RadiusM
	}
	if _, err := r.tx.Exec(r.Context(), `select public.review_location_suggestion($1::uuid, $2, $3)`,
		r.PathValue("id"), in.Approve, radius); err != nil {
		return nil, err
	}
	return ok(), nil
}
