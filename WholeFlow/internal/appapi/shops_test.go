package appapi

import "testing"

func sp(s string) *string { return &s }

// Same cases as the app's former report tests: sites A–Z (by name, any case),
// shops in no site last, and a site called "No site" kept apart from them.
func TestGroupsOrder(t *testing.T) {
	groups := map[string]*siteGroup{}
	groupFor(groups, sp("p"), sp("Pala")).subtotal = 400
	groupFor(groups, nil, nil).subtotal = 50
	groupFor(groups, sp("k"), sp("kply")).subtotal = 70
	groupFor(groups, sp("x"), sp("No site")).subtotal = 1
	out := groupsJSON(groups)
	var got []string
	for _, g := range out {
		got = append(got, str(g["site_id"].(*string))+"="+g["subtotal"].(string))
	}
	want := []string{"k=0.70", "x=0.01", "p=4.00", "=0.50"}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		eq(t, got[i], want[i], "group order")
	}
}

func TestLikePattern(t *testing.T) {
	eq(t, likePattern("  50%  off_ "), `%50\% off\_%`, "pattern")
}
