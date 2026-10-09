package controlclient

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// fakeControl answers like the WholeFlow control service.
func fakeControl(t *testing.T, h http.HandlerFunc) *Client {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	c, err := New(srv.URL, 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestActivateSuccess(t *testing.T) {
	var got ActivateRequest
	c := fakeControl(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/control/activate" || r.Header.Get("Authorization") != "" {
			t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
		}
		json.NewDecoder(r.Body).Decode(&got)
		io.WriteString(w, `{"device_id":"dev-1","business_id":"biz-1","business_name":"Demo Traders","base_url":"https://api.example/b/demo",
			"device_key":"jwt-key","max_companies":2,"subscription_state":"active"}`)
	})
	act, err := c.Activate(context.Background(), ActivateRequest{ReferenceKey: "DEMO-65YC-47X7-QMEZ", ActivationCode: "ABCD-EFGH", Machine: "PC1", WindowsUser: "me", AppVersion: "0.4.0"})
	if err != nil {
		t.Fatal(err)
	}
	if act.BusinessName != "Demo Traders" || act.DeviceKey != "jwt-key" || act.MaxCompanies != 2 || act.BaseURL != "https://api.example/b/demo" {
		t.Fatalf("activation: %+v", act)
	}
	if got.ReferenceKey != "DEMO-65YC-47X7-QMEZ" || got.ActivationCode != "ABCD-EFGH" || got.Machine != "PC1" || got.AppVersion != "0.4.0" {
		t.Fatalf("request body: %+v", got)
	}
}

func TestActivateErrorMessageSurfaced(t *testing.T) {
	c := fakeControl(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		io.WriteString(w, `{"error":{"code":"UNKNOWN_KEY","message":"No business has this reference key."}}`)
	})
	_, err := c.Activate(context.Background(), ActivateRequest{ReferenceKey: "X", ActivationCode: "Y"})
	ce, ok := err.(*Error)
	if !ok || ce.Status != 404 || ce.Code != "UNKNOWN_KEY" || ce.Message != "No business has this reference key." || ce.Unreachable() {
		t.Fatalf("error: %#v", err)
	}
}

func TestUnreachableClassification(t *testing.T) {
	c := fakeControl(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		io.WriteString(w, "<html>bad gateway</html>")
	})
	_, err := c.PCLogin(context.Background(), "a@b.c", "pw")
	if !IsUnreachable(err) || StatusOf(err) != 502 {
		t.Fatalf("5xx must count as unreachable: %v", err)
	}
	// Nothing listening at all.
	srv := httptest.NewServer(http.NotFoundHandler())
	url := srv.URL
	srv.Close()
	dead, _ := New(url, time.Second)
	if _, err := dead.PCLogin(context.Background(), "a@b.c", "pw"); !IsUnreachable(err) || StatusOf(err) != 0 {
		t.Fatalf("connection refused must count as unreachable: %v", err)
	}
}

func TestPCLoginWrongPasswordIsNotUnreachable(t *testing.T) {
	c := fakeControl(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		io.WriteString(w, `{"error":{"code":"BAD_LOGIN","message":"Wrong email or password."}}`)
	})
	_, err := c.PCLogin(context.Background(), "a@b.c", "nope")
	if IsUnreachable(err) || StatusOf(err) != 401 {
		t.Fatalf("401: %v", err)
	}
}

func TestHeartbeatSendsKey(t *testing.T) {
	c := fakeControl(t, func(w http.ResponseWriter, r *http.Request) {
		var body map[string]string
		json.NewDecoder(r.Body).Decode(&body)
		if r.URL.Path != "/control/heartbeat" || r.Header.Get("Authorization") != "Bearer pc-key" || body["app_version"] != "9.9" {
			w.WriteHeader(http.StatusUnauthorized)
			io.WriteString(w, `{"error":{"code":"BAD_KEY","message":"bad key"}}`)
			return
		}
		io.WriteString(w, `{"subscription_state":"grace","max_companies":3,"revoked":false}`)
	})
	hb, err := c.Heartbeat(context.Background(), "pc-key", "9.9")
	if err != nil || hb.SubscriptionState != "grace" || hb.MaxCompanies != 3 {
		t.Fatalf("%+v %v", hb, err)
	}
}

func TestNewRefusesPlainHTTP(t *testing.T) {
	if _, err := New("http://api.example.com", 0); err == nil {
		t.Fatal("plain http to another host must be refused")
	}
	if _, err := New("https://api.jitsuji.xyz/", 0); err != nil {
		t.Fatal(err)
	}
}

func TestOutdated(t *testing.T) {
	for _, c := range []struct {
		cur, latest string
		want        bool
	}{
		{"0.5.1", "0.6.0", true}, {"0.6.0", "0.6.0", false}, {"0.10.0", "0.9.9", false}, {"0.9", "0.10.0", true},
		{"v0.6.0-dev", "0.6.1", true}, {"0.6.0", "", false}, {"dev", "0.6.0", false}, {"0.6", "0.6.0", false},
	} {
		if got := Outdated(c.cur, c.latest); got != c.want {
			t.Errorf("Outdated(%q, %q) = %v", c.cur, c.latest, got)
		}
	}
}
