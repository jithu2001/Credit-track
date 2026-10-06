package control

import (
	"net/http"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

// Enquiries from the product website's contact form. The form posts to
// /api/contact on wholeflow.jitsuji.xyz, which nginx forwards here with the
// visitor's IP in X-Real-IP; the admin app lists them under Enquiries.

// LeadInput is what the website sends. Website is a honeypot: people never
// see the field, so anything in it means a bot.
type LeadInput struct {
	Name      string `json:"name"`
	Business  string `json:"business"`
	Phone     string `json:"phone"`
	Email     string `json:"email"`
	Companies string `json:"companies"`
	City      string `json:"city"`
	Message   string `json:"message"`
	Website   string `json:"website"`
}

var indianMobile = regexp.MustCompile(`^[6-9][0-9]{9}$`)

var leadCompanies = map[string]bool{"": true, "1": true, "2-3": true, "4-5": true, "6+": true}

// maxLeadsPerIPPerDay stops one sender filling the list.
const maxLeadsPerIPPerDay = 5

// CleanLead validates and normalises a website enquiry. Phone becomes the
// 10-digit Indian mobile number; every field is trimmed and length-capped.
func CleanLead(in LeadInput) (LeadInput, error) {
	trim := func(s string, max int) string {
		s = strings.Join(strings.Fields(s), " ")
		if utf8.RuneCountInString(s) > max {
			s = string([]rune(s)[:max])
		}
		return s
	}
	out := LeadInput{
		Name:      trim(in.Name, 80),
		Business:  trim(in.Business, 120),
		Email:     strings.ToLower(trim(in.Email, 120)),
		Companies: trim(in.Companies, 8),
		City:      trim(in.City, 60),
		Message:   strings.TrimSpace(in.Message),
	}
	if utf8.RuneCountInString(out.Message) > 1000 {
		out.Message = string([]rune(out.Message)[:1000])
	}
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, in.Phone)
	switch {
	case len(digits) == 12 && strings.HasPrefix(digits, "91"):
		digits = digits[2:]
	case len(digits) == 11 && strings.HasPrefix(digits, "0"):
		digits = digits[1:]
	}
	out.Phone = digits
	switch {
	case out.Name == "":
		return out, userErr(http.StatusBadRequest, "INVALID_INPUT", "Please enter your name.")
	case !indianMobile.MatchString(out.Phone):
		return out, userErr(http.StatusBadRequest, "INVALID_INPUT", "Please enter a 10-digit mobile number.")
	case !validEmail(out.Email):
		return out, userErr(http.StatusBadRequest, "INVALID_INPUT", "Please enter a valid email address.")
	case !leadCompanies[out.Companies]:
		return out, userErr(http.StatusBadRequest, "INVALID_INPUT", "Please choose the number of Tally companies.")
	}
	return out, nil
}

func validEmail(s string) bool {
	if s == "" || strings.ContainsAny(s, " <>") {
		return false
	}
	a, err := mail.ParseAddress(s)
	return err == nil && a.Address == s && strings.Contains(s[strings.LastIndex(s, "@"):], ".")
}

func (s *Server) leadRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /control/leads", s.createLead)
	mux.HandleFunc("GET /control/admin/leads", s.admin(s.listLeads))
	mux.HandleFunc("PATCH /control/admin/leads/{id}", s.admin(s.updateLead))
	mux.HandleFunc("DELETE /control/admin/leads/{id}", s.admin(s.deleteLead))
}

func (s *Server) createLead(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if !s.allowIP(ip, 5) {
		writeErr(w, userErr(http.StatusTooManyRequests, "TOO_MANY", "Too many messages. Please try again in a minute."))
		return
	}
	var in LeadInput
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if strings.TrimSpace(in.Website) != "" { // honeypot: answer like a success, store nothing
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		return
	}
	lead, err := CleanLead(in)
	if err != nil {
		writeErr(w, err)
		return
	}
	ctx := r.Context()
	var today int
	_ = s.Svc.Store.DB.QueryRow(ctx, `select count(*) from leads where ip = $1 and created_at > now() - interval '1 day'`, ip).Scan(&today)
	if today >= maxLeadsPerIPPerDay {
		writeErr(w, userErr(http.StatusTooManyRequests, "TOO_MANY", "We already have your message. We'll be in touch soon."))
		return
	}
	if _, err := s.Svc.Store.DB.Exec(ctx, `insert into leads (name, business, phone, email, companies, city, message, ip)
		values ($1, $2, $3, $4, $5, $6, $7, $8)`,
		lead.Name, lead.Business, lead.Phone, lead.Email, lead.Companies, lead.City, lead.Message, ip); err != nil {
		s.fail(w, r, err)
		return
	}
	s.Log.Info("website enquiry")
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type leadRow struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Business  string    `json:"business"`
	Phone     string    `json:"phone"`
	Email     string    `json:"email"`
	Companies string    `json:"companies"`
	City      string    `json:"city"`
	Message   string    `json:"message"`
	Status    string    `json:"status"`
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (s *Server) listLeads(w http.ResponseWriter, r *http.Request) {
	rows, err := s.Svc.Store.DB.Query(r.Context(), `select id, name, business, phone, email, companies, city, message, status, note, created_at, updated_at
		from leads order by created_at desc limit 500`)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []leadRow{}
	for rows.Next() {
		var l leadRow
		if err := rows.Scan(&l.ID, &l.Name, &l.Business, &l.Phone, &l.Email, &l.Companies, &l.City, &l.Message, &l.Status, &l.Note, &l.CreatedAt, &l.UpdatedAt); err != nil {
			s.fail(w, r, err)
			return
		}
		out = append(out, l)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) updateLead(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Status *string `json:"status"`
		Note   *string `json:"note"`
	}
	if err := readJSON(r, &in); err != nil {
		writeErr(w, err)
		return
	}
	if in.Status != nil {
		switch *in.Status {
		case "new", "contacted", "won", "lost":
		default:
			writeErr(w, userErr(http.StatusBadRequest, "INVALID_INPUT", "Unknown status."))
			return
		}
	}
	if in.Note != nil && utf8.RuneCountInString(*in.Note) > 2000 {
		writeErr(w, userErr(http.StatusBadRequest, "INVALID_INPUT", "The note is too long."))
		return
	}
	tag, err := s.Svc.Store.DB.Exec(r.Context(), `update leads set status = coalesce($2, status), note = coalesce($3, note), updated_at = now()
		where id::text = $1`, r.PathValue("id"), in.Status, in.Note)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, userErr(http.StatusNotFound, "NOT_FOUND", "No such enquiry."))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) deleteLead(w http.ResponseWriter, r *http.Request) {
	tag, err := s.Svc.Store.DB.Exec(r.Context(), `delete from leads where id::text = $1`, r.PathValue("id"))
	if err != nil {
		s.fail(w, r, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, userErr(http.StatusNotFound, "NOT_FOUND", "No such enquiry."))
		return
	}
	a := adminOf(r)
	s.Svc.Store.Audit(r.Context(), &a.ID, nil, "lead.delete", nil)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
