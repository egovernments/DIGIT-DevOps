package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// fakeKong is an in-memory Kong Admin API covering the calls the workflow makes.
type fakeKong struct {
	mu           sync.Mutex
	database     string
	plugins      []string
	services     map[string]string
	routes       map[string]kongRoute
	routePlugins map[string][]kongPlugin
	posts        int
	patches      int
	failService  string
}

func newFakeKong(t *testing.T) (*fakeKong, *KongClient) {
	f := &fakeKong{
		database:     "postgres",
		plugins:      []string{"dynamic-jwt", "header-enrichment", "cors"},
		services:     map[string]string{},
		routes:       map[string]kongRoute{},
		routePlugins: map[string][]kongPlugin{},
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		avail := map[string]any{}
		for _, p := range f.plugins {
			avail[p] = map[string]string{"version": "1.0"}
		}
		writeJSON(w, 200, map[string]any{
			"version":       "3.5.0",
			"configuration": map[string]string{"database": f.database},
			"plugins":       map[string]any{"available_on_server": avail},
		})
	})
	mux.HandleFunc("PUT /services/{name}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		if r.PathValue("name") == f.failService {
			writeJSON(w, 400, map[string]string{"message": "schema violation (url: invalid)"})
			return
		}
		var body map[string]string
		json.NewDecoder(r.Body).Decode(&body)
		f.services[r.PathValue("name")] = body["url"]
		writeJSON(w, 200, body)
	})
	mux.HandleFunc("PUT /routes/{name}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		var route kongRoute
		json.NewDecoder(r.Body).Decode(&route)
		route.ID = "id-" + r.PathValue("name")
		f.routes[route.Name] = route
		writeJSON(w, 200, route)
	})
	mux.HandleFunc("GET /routes", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		var data []kongRoute
		for _, rt := range f.routes {
			data = append(data, rt)
		}
		writeJSON(w, 200, map[string]any{"data": data, "next": nil})
	})
	mux.HandleFunc("GET /routes/{name}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		rt, ok := f.routes[r.PathValue("name")]
		if !ok {
			writeJSON(w, 404, map[string]string{"message": "Not found"})
			return
		}
		writeJSON(w, 200, rt)
	})
	mux.HandleFunc("GET /routes/{id}/plugins", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		writeJSON(w, 200, map[string]any{"data": f.routePlugins[r.PathValue("id")]})
	})
	mux.HandleFunc("POST /routes/{id}/plugins", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		var p kongPlugin
		json.NewDecoder(r.Body).Decode(&p)
		p.ID = r.PathValue("id") + "-" + p.Name
		f.routePlugins[r.PathValue("id")] = append(f.routePlugins[r.PathValue("id")], p)
		f.posts++
		writeJSON(w, 201, p)
	})
	mux.HandleFunc("PATCH /plugins/{id}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.patches++
		writeJSON(w, 200, map[string]string{"id": r.PathValue("id")})
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return f, newKongClient(srv.URL)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func testWorkflow() *Workflow {
	return &Workflow{
		cfg: &Config{Namespace: "egov", Host: "k3s.example.org", KeycloakBaseURL: "http://kc"},
		log: &Logger{out: io.Discard, errOut: io.Discard},
	}
}

var testServices = []kongService{
	{Name: "pdf-v3", K8sSvc: "pdf-v3", Path: "pdf-v3", Auth: true},
	{Name: "metabase", K8sSvc: "metabase", Path: "metabase", StripPath: true},
}

func TestCheckKongCapabilities(t *testing.T) {
	f, c := newFakeKong(t)
	ctx := context.Background()

	info, err := c.Info(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := checkKongCapabilities(info, testServices); err != nil {
		t.Errorf("capable Kong rejected: %v", err)
	}

	f.plugins = []string{"cors"}
	info, _ = c.Info(ctx)
	err = checkKongCapabilities(info, testServices)
	if err == nil || !strings.Contains(err.Error(), "dynamic-jwt, header-enrichment") {
		t.Errorf("missing plugins: err = %v", err)
	}
	if err := checkKongCapabilities(info, []kongService{{Name: "metabase"}}); err != nil {
		t.Errorf("services without auth should not need plugins: %v", err)
	}

	f.database = "off"
	info, _ = c.Info(ctx)
	if err := checkKongCapabilities(info, testServices); err == nil || !strings.Contains(err.Error(), "DB-less") {
		t.Errorf("DB-less: err = %v", err)
	}
}

func TestConfigureKongServiceIsIdempotent(t *testing.T) {
	f, c := newFakeKong(t)
	w := testWorkflow()
	ctx := context.Background()
	svc := kongService{Name: "pdf-v3", K8sSvc: "pdf-v3", Path: "pdf-v3", Auth: true}

	for run := 1; run <= 2; run++ {
		if err := w.configureKongService(ctx, c, svc, nil); err != nil {
			t.Fatalf("run %d: %v", run, err)
		}
	}
	if f.posts != 2 || f.patches != 2 {
		t.Errorf("posts=%d patches=%d, want 2 created then 2 updated", f.posts, f.patches)
	}
	if got := f.services["pdf-v3"]; got != "http://pdf-v3.egov.svc.cluster.local:8080" {
		t.Errorf("backend = %q", got)
	}
	rt := f.routes["pdf-v3-route"]
	if strings.Join(rt.Paths, ",") != "/pdf-v3" || strings.Join(rt.Hosts, ",") != "k3s.example.org" || rt.Service.Name != "pdf-v3" {
		t.Errorf("route = %+v", rt)
	}
}

func TestConfigureKongServiceWithoutAuth(t *testing.T) {
	f, c := newFakeKong(t)
	err := testWorkflow().configureKongService(context.Background(), c,
		kongService{Name: "metabase", K8sSvc: "metabase", Path: "metabase", StripPath: true}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if f.posts != 0 {
		t.Errorf("plugins attached to a no-auth service: %d", f.posts)
	}
	if !f.routes["metabase-route"].StripPath {
		t.Error("strip_path not sent")
	}
}

func TestKongAPIErrorCarriesMessage(t *testing.T) {
	f, c := newFakeKong(t)
	f.failService = "vc"
	err := testWorkflow().configureKongService(context.Background(), c,
		kongService{Name: "vc", K8sSvc: "vc", Path: "credential", Auth: true}, nil)

	var apiErr *KongAPIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("err = %v, want a *KongAPIError", err)
	}
	if apiErr.Status != 400 || apiErr.Message != "schema violation (url: invalid)" {
		t.Errorf("apiErr = %+v", apiErr)
	}
	if _, ok := f.routes["vc-route"]; ok {
		t.Error("route created although the service failed")
	}
}

func TestRouteExists(t *testing.T) {
	f, c := newFakeKong(t)
	ctx := context.Background()
	if ok, err := c.RouteExists(ctx, "nope-route"); ok || err != nil {
		t.Errorf("missing route: ok=%v err=%v", ok, err)
	}
	f.routes["a-route"] = kongRoute{ID: "1", Name: "a-route"}
	if ok, err := c.RouteExists(ctx, "a-route"); !ok || err != nil {
		t.Errorf("existing route: ok=%v err=%v", ok, err)
	}
}

func TestOverlaps(t *testing.T) {
	existing := []kongRoute{
		{Name: "pdf-v3-route", Paths: []string{"/pdf-v3"}},
		{Name: "legacy-pdf", Paths: []string{"/pdf-v3/old"}},
		{Name: "other", Paths: []string{"/other"}},
	}
	got := overlaps(existing, kongService{Name: "pdf-v3", Path: "pdf-v3"})
	if len(got) != 1 || !strings.HasPrefix(got[0], "legacy-pdf") {
		t.Errorf("got %v", got)
	}
}
