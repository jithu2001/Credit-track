package appapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// Visit plans, the day's tasks and check-ins. Owners write plans (RLS + a
// trigger checks the staff member and site); tasks come from
// ensure_visit_tasks() and visits only from check_in().
//
//	GET    /b/{slug}/api/v1/visits/tasks?from=&to=[&company=][&staff=]   makes the days' tasks, then lists them
//	GET    /b/{slug}/api/v1/visits/tasks/{id}/failed-attempts            refused check-ins (owner)
//	POST   /b/{slug}/api/v1/visits/tasks/{id}/check-in                   {"latitude", "longitude", "accuracy_m", "is_mocked", "developer_mode", "note"}
//	GET    /b/{slug}/api/v1/visits/plans?company=
//	POST   /b/{slug}/api/v1/visits/plans        {"site", "staff", "date"} or {"site", "staff", "weekdays": [...], "starts_on", "ends_on"}
//	PATCH  /b/{slug}/api/v1/visits/plans/{id}   {"active"}
//	DELETE /b/{slug}/api/v1/visits/plans/{id}
//	GET    /b/{slug}/api/v1/visits/{id}                                  {"visit": row | null}
//	POST   /b/{slug}/api/v1/visits/{id}/note                             {"note"}

func (s *Server) visitTasks(r *request) (any, error) {
	from, err := optDate(r, "from")
	if err != nil {
		return nil, err
	}
	to, err := optDate(r, "to")
	if err != nil {
		return nil, err
	}
	if from == nil || to == nil || from.After(*to) || to.Sub(*from) > 400*24*time.Hour {
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "from and to are required (at most about a year apart).")
	}
	if _, err := r.tx.Exec(r.Context(), `select public.ensure_visit_tasks($1, $2)`, *from, *to); err != nil {
		return nil, err
	}
	where := []string{"visit_date >= $1", "visit_date <= $2"}
	args := []any{*from, *to}
	if v := r.URL.Query().Get("company"); v != "" {
		args = append(args, v)
		where = append(where, "company_id = $3::uuid")
	}
	if v := r.URL.Query().Get("staff"); v != "" {
		args = append(args, v)
		where = append(where, "staff_id = $"+strconv.Itoa(len(args))+"::uuid")
	}
	rows, err := jsonRows(r, `select task_id, company_id, staff_id, staff_name, shop_id, shop_name, site_id, site_name, visit_date, state,
			visit_id, checked_in_at, distance_m, radius_m, accuracy_m, note
		from public.v_visit_tasks where `+strings.Join(where, " and ")+`
		order by visit_date desc, site_name, shop_name, task_id`, args...)
	if err != nil {
		return nil, err
	}
	return map[string]any{"tasks": rows}, nil
}

func (s *Server) failedAttempts(r *request) (any, error) {
	rows, err := jsonRows(r, `select attempted_at, reason, distance_m, radius_m, accuracy_m
		from public.visit_failed_attempts where task_id = $1::uuid order by attempted_at desc`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return map[string]any{"attempts": rows}, nil
}

func (s *Server) checkIn(r *request) (any, error) {
	var in struct {
		Latitude      float64  `json:"latitude"`
		Longitude     float64  `json:"longitude"`
		AccuracyM     *float64 `json:"accuracy_m"`
		IsMocked      bool     `json:"is_mocked"`
		DeveloperMode bool     `json:"developer_mode"`
		Note          *string  `json:"note"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	var raw []byte
	err := r.tx.QueryRow(r.Context(), `select public.check_in($1::uuid, $2, $3, $4, $5, $6, $7)`,
		r.PathValue("id"), in.Latitude, in.Longitude, in.AccuracyM, in.IsMocked, in.DeveloperMode, in.Note).Scan(&raw)
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		switch {
		case pg.Code == "23505":
			return nil, fail(http.StatusConflict, "ALREADY_CHECKED_IN", "You have already checked in at this shop today.")
		case pg.Code == "22023" && strings.Contains(pg.Message, "not for today"):
			return nil, fail(http.StatusBadRequest, "NOT_TODAY", "This visit is not for today, so you cannot check in.")
		case pg.Code == "42501":
			return nil, fail(http.StatusForbidden, "NO_SHOP", "You no longer have this shop. Ask your owner.")
		}
	}
	if err != nil {
		return nil, err
	}
	return json.RawMessage(raw), nil
}

func (s *Server) visitPlans(r *request) (any, error) {
	companyID, err := requireCompany(r)
	if err != nil {
		return nil, err
	}
	rows, err := jsonRows(r, `select p.id, p.site_id, p.staff_id, p.active, p.plan_date, p.weekday, p.starts_on, p.ends_on,
			json_build_object('name', si.name) as sites, json_build_object('name', u.name) as users
		from public.visit_plans p
		left join public.sites si on si.id = p.site_id
		left join public.users u on u.id = p.staff_id
		where p.company_id = $1::uuid order by p.active desc, p.created_at desc, p.id`, companyID)
	if err != nil {
		return nil, err
	}
	return map[string]any{"plans": rows}, nil
}

// planError explains the plan trigger's refusals.
func planError(err error) error {
	var pg *pgconn.PgError
	if errors.As(err, &pg) && pg.Code == "23514" {
		switch {
		case strings.Contains(pg.Message, "check-in"):
			return fail(http.StatusBadRequest, "INVALID_INPUT",
				`Turn on "Must check in at shops" for this staff member first (Settings → Staff).`)
		case strings.Contains(pg.Message, "does not have this site"):
			return fail(http.StatusBadRequest, "INVALID_INPUT", "This staff member does not have this site. Give it to them first.")
		}
	}
	return err
}

func (s *Server) createPlans(r *request) (any, error) {
	var in struct {
		Site     string  `json:"site"`
		Staff    string  `json:"staff"`
		DateStr  *string `json:"date"`
		Weekdays []int   `json:"weekdays"`
		StartsOn *string `json:"starts_on"`
		EndsOn   *string `json:"ends_on"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	insert := func(day *string, weekday *int, starts, ends *string) error {
		_, err := r.tx.Exec(r.Context(), `insert into public.visit_plans (site_id, staff_id, plan_date, weekday, starts_on, ends_on)
			values ($1::uuid, $2::uuid, $3::date, $4, $5::date, $6::date)`, in.Site, in.Staff, day, weekday, starts, ends)
		return planError(err)
	}
	switch {
	case in.DateStr != nil:
		if err := insert(in.DateStr, nil, nil, nil); err != nil {
			return nil, err
		}
	case len(in.Weekdays) > 0:
		if in.StartsOn == nil {
			today := date(r.today) // weekly plans start today (India) unless told otherwise
			in.StartsOn = &today
		}
		for _, w := range in.Weekdays {
			w := w
			if err := insert(nil, &w, in.StartsOn, in.EndsOn); err != nil {
				return nil, err
			}
		}
	default:
		return nil, fail(http.StatusBadRequest, "INVALID_INPUT", "Choose a date or weekdays.")
	}
	return ok(), nil
}

func (s *Server) setPlanActive(r *request) (any, error) {
	var in struct {
		Active bool `json:"active"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	tag, err := r.tx.Exec(r.Context(), `update public.visit_plans set active = $2 where id = $1::uuid`, r.PathValue("id"), in.Active)
	if err != nil {
		return nil, planError(err)
	}
	return ok(), affected(tag, "plan")
}

func (s *Server) deletePlan(r *request) (any, error) {
	tag, err := r.tx.Exec(r.Context(), `delete from public.visit_plans where id = $1::uuid`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return ok(), affected(tag, "plan")
}

func (s *Server) visitDetail(r *request) (any, error) {
	row, err := jsonRow(r, `select id, checked_in_at, device_lat, device_lng, accuracy_m, status, shop_lat, shop_lng, radius_m,
			distance_m, note from public.shop_visits where id = $1::uuid`, r.PathValue("id"))
	if err != nil {
		return nil, err
	}
	return map[string]any{"visit": row}, nil
}

func (s *Server) addVisitNote(r *request) (any, error) {
	var in struct {
		Note string `json:"note"`
	}
	if err := readBody(r, &in); err != nil {
		return nil, err
	}
	if _, err := r.tx.Exec(r.Context(), `select public.add_visit_note($1::uuid, $2)`, r.PathValue("id"), in.Note); err != nil {
		return nil, err
	}
	return ok(), nil
}
