package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync"
	"text/tabwriter"
	"time"
)

type kongService struct {
	Name      string
	K8sSvc    string
	Path      string // context path, without the leading slash
	StripPath bool
	Auth      bool // attach dynamic-jwt + header-enrichment
}

// Custom plugins; they must be built into the Kong image.
var requiredKongPlugins = []string{"dynamic-jwt", "header-enrichment"}

const kongAdminPort = 8001

func authPlugins(keycloakBaseURL string) []kongPlugin {
	return []kongPlugin{
		{Name: "dynamic-jwt", Config: map[string]any{
			"keycloak_base_url": keycloakBaseURL,
			"cache_ttl":         3600,
			"claims_to_verify":  []string{"exp"},
			"header_names":      []string{"authorization"},
			"uri_param_names":   []string{"jwt"},
		}},
		{Name: "header-enrichment", Config: map[string]any{
			"enable_api_headers":    true,
			"enable_jwt_headers":    true,
			"tenant_header_sources": []string{"X-JWT-tenant", "X-JWT-organization", "X-Tenant-ID"},
			"default_tenant":        "default",
		}},
	}
}

// ---------------------------------------------------------------------------
// Admin API client
// ---------------------------------------------------------------------------

type KongClient struct {
	baseURL string
	http    *http.Client
}

func newKongClient(baseURL string) *KongClient {
	return &KongClient{baseURL: strings.TrimRight(baseURL, "/"), http: &http.Client{Timeout: 15 * time.Second}}
}

// KongAPIError is a non-2xx answer from the Admin API.
type KongAPIError struct {
	Method, Path string
	Status       int
	Message      string
}

func (e *KongAPIError) Error() string {
	return fmt.Sprintf("Kong %s %s: HTTP %d: %s", e.Method, e.Path, e.Status, e.Message)
}

type kongInfo struct {
	Version       string `json:"version"`
	Configuration struct {
		Database string `json:"database"`
	} `json:"configuration"`
	Plugins struct {
		// Kong 3.x maps each name to {version, priority}; older releases to
		// true. Only the keys matter here.
		AvailableOnServer map[string]json.RawMessage `json:"available_on_server"`
	} `json:"plugins"`
}

type kongRef struct {
	ID   string `json:"id,omitempty"`
	Name string `json:"name,omitempty"`
}

type kongRoute struct {
	ID        string   `json:"id,omitempty"`
	Name      string   `json:"name"`
	Paths     []string `json:"paths"`
	StripPath bool     `json:"strip_path"`
	Protocols []string `json:"protocols,omitempty"`
	Hosts     []string `json:"hosts,omitempty"`
	Service   *kongRef `json:"service,omitempty"`
}

type kongPlugin struct {
	ID     string         `json:"id,omitempty"`
	Name   string         `json:"name"`
	Config map[string]any `json:"config,omitempty"`
}

func (c *KongClient) do(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return fmt.Errorf("encoding Kong %s %s body: %w", method, path, err)
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, body)
	if err != nil {
		return fmt.Errorf("building Kong %s %s: %w", method, path, err)
	}
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("Kong %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return fmt.Errorf("reading Kong %s %s response: %w", method, path, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &KongAPIError{Method: method, Path: path, Status: resp.StatusCode, Message: kongMessage(data)}
	}
	if out != nil && len(data) > 0 {
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("decoding Kong %s %s response: %w", method, path, err)
		}
	}
	return nil
}

func kongMessage(body []byte) string {
	var m struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(body, &m) == nil && m.Message != "" {
		return m.Message
	}
	if s := strings.TrimSpace(string(body)); s != "" {
		return truncate(s, 300)
	}
	return "(empty body)"
}

func (c *KongClient) Info(ctx context.Context) (*kongInfo, error) {
	var info kongInfo
	if err := c.do(ctx, http.MethodGet, "/", nil, &info); err != nil {
		return nil, err
	}
	return &info, nil
}

// PutService creates or replaces a service by name.
func (c *KongClient) PutService(ctx context.Context, name, backendURL string) error {
	return c.do(ctx, http.MethodPut, "/services/"+url.PathEscape(name),
		map[string]string{"name": name, "url": backendURL}, nil)
}

// PutRoute creates or replaces a route by name and returns it with its id.
func (c *KongClient) PutRoute(ctx context.Context, r kongRoute) (kongRoute, error) {
	var out kongRoute
	err := c.do(ctx, http.MethodPut, "/routes/"+url.PathEscape(r.Name), r, &out)
	return out, err
}

func (c *KongClient) ListRoutes(ctx context.Context) ([]kongRoute, error) {
	var all []kongRoute
	for path := "/routes?size=1000"; path != ""; {
		var page struct {
			Data []kongRoute `json:"data"`
			Next *string     `json:"next"`
		}
		if err := c.do(ctx, http.MethodGet, path, nil, &page); err != nil {
			return nil, err
		}
		all = append(all, page.Data...)
		path = ""
		if page.Next != nil {
			path = *page.Next
		}
	}
	return all, nil
}

func (c *KongClient) RouteExists(ctx context.Context, name string) (bool, error) {
	err := c.do(ctx, http.MethodGet, "/routes/"+url.PathEscape(name), nil, nil)
	var apiErr *KongAPIError
	if errors.As(err, &apiErr) && apiErr.Status == http.StatusNotFound {
		return false, nil
	}
	return err == nil, err
}

// UpsertRoutePlugin attaches p to the route, or updates it in place if the
// route already has a plugin of that name. It reports whether it created one.
func (c *KongClient) UpsertRoutePlugin(ctx context.Context, routeID string, p kongPlugin) (bool, error) {
	var list struct {
		Data []kongPlugin `json:"data"`
	}
	if err := c.do(ctx, http.MethodGet, "/routes/"+url.PathEscape(routeID)+"/plugins", nil, &list); err != nil {
		return false, err
	}
	for _, existing := range list.Data {
		if existing.Name == p.Name {
			return false, c.do(ctx, http.MethodPatch, "/plugins/"+url.PathEscape(existing.ID), p, nil)
		}
	}
	return true, c.do(ctx, http.MethodPost, "/routes/"+url.PathEscape(routeID)+"/plugins", p, nil)
}

// checkKongCapabilities fails before any change if this Kong cannot accept the
// configuration: DB-less Kong rejects Admin API writes, and the auth routes
// need the custom plugins loaded.
func checkKongCapabilities(info *kongInfo, services []kongService) error {
	if strings.EqualFold(info.Configuration.Database, "off") {
		return errors.New("Kong runs DB-less (database=off), so its Admin API rejects writes and services/routes cannot be created; Kong must run with a Postgres database")
	}
	needAuth := false
	for _, s := range services {
		needAuth = needAuth || s.Auth
	}
	if !needAuth {
		return nil
	}
	var missing []string
	for _, p := range requiredKongPlugins {
		if _, ok := info.Plugins.AvailableOnServer[p]; !ok {
			missing = append(missing, p)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("Kong plugins not available on this Kong: %s (they must be built into the Kong image)", strings.Join(missing, ", "))
	}
	return nil
}

// overlaps lists other routes whose paths start with this service's path.
func overlaps(existing []kongRoute, svc kongService) []string {
	prefix := "/" + svc.Path
	var out []string
	for _, r := range existing {
		if r.Name == svc.Name+"-route" {
			continue
		}
		for _, p := range r.Paths {
			if strings.HasPrefix(p, prefix) {
				out = append(out, fmt.Sprintf("%s (paths: %s)", r.Name, strings.Join(r.Paths, ",")))
				break
			}
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Port-forward
// ---------------------------------------------------------------------------

type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

type portForward struct {
	cmd    *exec.Cmd
	done   chan struct{}
	err    error // valid once done is closed
	stderr *syncBuffer
}

// Stop ends the port-forward, politely first.
func (pf *portForward) Stop() {
	select {
	case <-pf.done:
		return
	default:
	}
	_ = pf.cmd.Process.Signal(os.Interrupt)
	select {
	case <-pf.done:
	case <-time.After(5 * time.Second):
		_ = pf.cmd.Process.Kill()
		<-pf.done
	}
}

// openKongTunnel always starts its own port-forward on a dedicated local port
// and never reuses one already listening: an existing localhost:8001 may lead
// to a different cluster's Kong, and configuring that one would be silent and
// wrong.
func (w *Workflow) openKongTunnel(ctx context.Context) (*KongClient, error) {
	ns, svc, port := w.cfg.Namespace, w.cfg.KongAdminSvc, w.cfg.KongLocalPort
	w.log.Step(fmt.Sprintf("Opening port-forward to %s/svc/%s", ns, svc))

	if _, err := w.kubectl(ctx, "-n", ns, "get", "svc", svc); err != nil {
		if isNotFound(err) {
			return nil, stepErr("kong",
				"Argo CD deploys Kong from the platform appset: run `all` (or `argocd`) first, then check the gateway-kong app",
				fmt.Errorf("Service %s/%s not found", ns, svc))
		}
		return nil, stepErr("kong", "", err)
	}

	if out, err := w.kubectl(ctx, "auth", "can-i", "create", "pods/portforward", "-n", ns); err != nil || strings.TrimSpace(string(out)) != "yes" {
		return nil, stepErr("kong", "this identity needs permission to port-forward in namespace "+ns,
			fmt.Errorf("not allowed to create pods/portforward in %s", ns))
	}

	addr := fmt.Sprintf("127.0.0.1:%d", port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, stepErr("kong", fmt.Sprintf("free it (lsof -i :%d) or set KONG_LOCAL_PORT", port),
			fmt.Errorf("local port %d is in use: %w", port, err))
	}
	ln.Close()

	cmd := w.run.command(ctx, "", "kubectl", "-n", ns, "port-forward", "--address", "127.0.0.1",
		"svc/"+svc, fmt.Sprintf("%d:%d", port, kongAdminPort))
	pf := &portForward{cmd: cmd, done: make(chan struct{}), stderr: &syncBuffer{}}
	cmd.Stdout = io.Discard
	cmd.Stderr = pf.stderr
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("starting kubectl port-forward: %w", err)
	}
	go func() {
		pf.err = cmd.Wait()
		close(pf.done)
	}()
	w.tunnel = pf

	client := newKongClient("http://" + addr)
	deadline := time.NewTimer(20 * time.Second)
	defer deadline.Stop()
	tick := time.NewTicker(500 * time.Millisecond)
	defer tick.Stop()
	for {
		probeCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
		err := client.do(probeCtx, http.MethodGet, "/status", nil, nil)
		cancel()
		if err == nil {
			w.log.Successf("Kong Admin API reachable at %s.", client.baseURL)
			return client, nil
		}
		select {
		case <-pf.done:
			return nil, stepErr("kong", fmt.Sprintf("kubectl -n %s get pods | grep -i kong", ns),
				fmt.Errorf("kubectl port-forward exited (%v):\n%s", pf.err, indent(strings.TrimSpace(pf.stderr.String()), "    ")))
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-deadline.C:
			return nil, stepErr("kong", fmt.Sprintf("kubectl -n %s get pods | grep -i kong", ns),
				fmt.Errorf("Kong Admin API not reachable at %s after 20s: %w", client.baseURL, err))
		case <-tick.C:
		}
	}
}

// ---------------------------------------------------------------------------
// Workflow steps
// ---------------------------------------------------------------------------

func (w *Workflow) configureKong(ctx context.Context) error {
	w.log.Banner("KONG SERVICES & ROUTES -> " + w.cfg.Host)
	client, err := w.openKongTunnel(ctx)
	if err != nil {
		return err
	}

	w.log.Step("Checking Kong mode and plugins")
	info, err := client.Info(ctx)
	if err != nil {
		return stepErr("kong", "", fmt.Errorf("reading Kong node info: %w", err))
	}
	w.log.Infof("Kong %s, database mode: %s", orDash(info.Version), w.log.Bold(orDash(info.Configuration.Database)))
	services := w.cfg.KongServices
	if err := checkKongCapabilities(info, services); err != nil {
		return stepErr("kong", "see README: Kong", err)
	}
	w.log.Successf("Kong accepts Admin API writes and has the required plugins.")

	if err := w.prompt.Confirm(ctx, fmt.Sprintf("Create/update %d Kong services and routes for host %q?",
		len(services), w.cfg.Host)); err != nil {
		return err
	}

	existing, err := client.ListRoutes(ctx)
	if err != nil {
		w.log.Warnf("Could not list routes, skipping the path-overlap check: %v", err)
	}
	var errs []error
	for _, svc := range w.cfg.KongServices {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := w.configureKongService(ctx, client, svc, existing); err != nil {
			w.log.Errorf("%s: %v", svc.Name, err)
			errs = append(errs, fmt.Errorf("%s: %w", svc.Name, err))
		}
	}

	w.printKongSummary(ctx, client)
	if len(errs) > 0 {
		return stepErr("kong", "fix the cause and rerun the kong command; every call is an upsert, so it is safe to repeat",
			fmt.Errorf("%d of %d services failed:\n%w", len(errs), len(services), errors.Join(errs...)))
	}
	w.log.Successf("All Kong services configured.")
	return nil
}

func (w *Workflow) configureKongService(ctx context.Context, c *KongClient, svc kongService, existing []kongRoute) error {
	routeName := svc.Name + "-route"
	backend := fmt.Sprintf("http://%s.%s.svc.cluster.local:8080", svc.K8sSvc, w.cfg.Namespace)
	w.log.Step(fmt.Sprintf("Kong service %s  (/%s -> %s, strip_path=%t, auth=%t)",
		w.log.Bold(svc.Name), svc.Path, backend, svc.StripPath, svc.Auth))

	if o := overlaps(existing, svc); len(o) > 0 {
		w.log.Warnf("Possible path overlap with existing route(s):\n%s", indent(strings.Join(o, "\n"), "    - "))
	}

	if err := c.PutService(ctx, svc.Name, backend); err != nil {
		return fmt.Errorf("service: %w", err)
	}
	w.log.Successf("Service %q ready.", svc.Name)

	route, err := c.PutRoute(ctx, kongRoute{
		Name:      routeName,
		Paths:     []string{"/" + svc.Path},
		StripPath: svc.StripPath,
		Protocols: []string{"http", "https"},
		Hosts:     []string{w.cfg.Host},
		Service:   &kongRef{Name: svc.Name},
	})
	if err != nil {
		return fmt.Errorf("route: %w", err)
	}
	if route.ID == "" {
		return fmt.Errorf("route: Kong returned no id for %q", routeName)
	}
	w.log.Successf("Route %q ready (%s).", routeName, route.ID)

	if !svc.Auth {
		w.log.Infof("No auth plugins for %q (it has its own login).", svc.Name)
		return nil
	}
	for _, p := range authPlugins(w.cfg.KeycloakBaseURL) {
		created, err := c.UpsertRoutePlugin(ctx, route.ID, p)
		if err != nil {
			return fmt.Errorf("plugin %s: %w", p.Name, err)
		}
		if created {
			w.log.Successf("Plugin %q attached.", p.Name)
		} else {
			w.log.Successf("Plugin %q updated.", p.Name)
		}
	}
	return nil
}

func (w *Workflow) printKongSummary(ctx context.Context, c *KongClient) {
	w.log.Step("Kong routes for host " + w.log.Bold(w.cfg.Host))
	var buf bytes.Buffer
	tw := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "SERVICE\tCONTEXT PATH\tSTRIP PATH\tAUTH\tSTATUS")
	for _, svc := range w.cfg.KongServices {
		status := "ACTIVE"
		ok, err := c.RouteExists(ctx, svc.Name+"-route")
		switch {
		case err != nil:
			status = "ERROR: " + truncate(err.Error(), 60)
		case !ok:
			status = "MISSING"
		}
		auth := "none"
		if svc.Auth {
			auth = "jwt + enrich"
		}
		fmt.Fprintf(tw, "%s\t/%s\t%t\t%s\t%s\n", svc.Name, svc.Path, svc.StripPath, auth, status)
	}
	tw.Flush()
	w.log.Block(buf.String())
}
