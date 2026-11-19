package main

import (
	"context"
	"fmt"
	"net"
	"slices"
	"strings"
	"time"
)

// ingressTarget is where the domain must point: an IP for an A record or a
// load-balancer hostname for a CNAME.
type ingressTarget struct {
	addr     string
	hostname bool
	note     string
}

// findIngressTarget works out the address DNS should point at. On k3s the
// ingress Service only knows the node's private IP (ServiceLB), so the VM's
// public address from the config file is used instead.
func (w *Workflow) findIngressTarget(ctx context.Context) (ingressTarget, error) {
	if w.cfg.Provider == "k3s" && w.cfg.K3s.Host != "" {
		return ingressTarget{addr: w.cfg.K3s.Host, note: "the k3s VM's public address (ServiceLB serves 80/443 on the node)"}, nil
	}
	ns, svc := w.cfg.IngressNamespace, w.cfg.IngressService
	out, err := w.kubectl(ctx, "-n", ns, "get", "svc", svc,
		"-o", `jsonpath={.status.loadBalancer.ingress[0].ip}{" "}{.status.loadBalancer.ingress[0].hostname}`)
	if err != nil {
		return ingressTarget{}, fmt.Errorf("reading Service %s/%s: %w", ns, svc, err)
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		return ingressTarget{}, fmt.Errorf("Service %s/%s has no load-balancer address yet", ns, svc)
	}
	if ip := net.ParseIP(fields[0]); ip != nil {
		t := ingressTarget{addr: fields[0], note: "the ingress load balancer"}
		if ip.IsPrivate() {
			t.note = "a PRIVATE address; on a single VM point DNS at its public IP instead (set cluster.k3s.host)"
		}
		return t, nil
	}
	return ingressTarget{addr: fields[0], hostname: true, note: "the ingress load balancer"}, nil
}

// dnsAdvice compares what the domain resolves to with the target's addresses.
func dnsAdvice(domain string, t ingressTarget, resolved, targetAddrs []string, lookupErr error) (bool, string) {
	record := fmt.Sprintf("an A record %s -> %s", domain, t.addr)
	if t.hostname {
		record = fmt.Sprintf("a CNAME record %s -> %s", domain, t.addr)
	}
	if lookupErr != nil || len(resolved) == 0 {
		return false, fmt.Sprintf("%s does not resolve yet. Ask the DNS admin for %s.", domain, record)
	}
	for _, a := range resolved {
		if slices.Contains(targetAddrs, a) {
			return true, fmt.Sprintf("%s resolves to %s, which is %s.", domain, strings.Join(resolved, ", "), t.note)
		}
	}
	return false, fmt.Sprintf("%s resolves to %s, not to %s (%s). Ask the DNS admin to change it to %s.",
		domain, strings.Join(resolved, ", "), t.addr, t.note, record)
}

// checkDNS reports whether the domain already points at the cluster. It never
// fails the run: DNS is managed outside the cluster, and everything except the
// HTTPS certificate deploys without it.
func (w *Workflow) checkDNS(ctx context.Context) error {
	domain := w.cfg.Host
	w.log.Step("DNS for " + domain)
	t, err := w.findIngressTarget(ctx)
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		w.log.Warnf("Skipping the DNS check: %v", err)
		return nil
	}

	lookupCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	resolved, lookupErr := net.DefaultResolver.LookupHost(lookupCtx, domain)
	targetAddrs := []string{t.addr}
	if t.hostname {
		targetAddrs, _ = net.DefaultResolver.LookupHost(lookupCtx, t.addr)
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}

	ok, msg := dnsAdvice(domain, t, resolved, targetAddrs, lookupErr)
	if ok {
		w.log.Successf("%s", msg)
		return nil
	}
	w.log.Warnf("%s Until then cert-manager cannot issue the HTTPS certificate.", msg)
	return nil
}
