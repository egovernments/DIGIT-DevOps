#!/usr/bin/env python3
"""Aggregate Trivy JSON into the DIGIT security dashboards.

Two separate dashboards are produced under the same site:
  - docker/index.html : container-image vulnerabilities (from `trivy image`)
  - helm/index.html   : Helm-chart misconfigurations (from `trivy fs/config`)
plus a landing index.html that links to both.

Each scan run is archived under data/<domain>/runs/ (a compact per-run model +
a manifest), so the Helm dashboard can offer a branch picker and a run/timestamp
picker ("recent runs"), and both dashboards can show run history.

Modes:
  generate.py domain --domain docker --data DIR --site SITE [run metadata...]
  generate.py landing --site SITE
"""
import argparse, json, os, sys, glob, datetime, re, hashlib

SEV_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
# history kept per domain (docker reports are large, so keep fewer)
MAX_RUNS = {"docker": 8, "helm": 30}


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def sev_bucket():
    return {s: 0 for s in SEV_ORDER}


def rank(s):
    return SEV_ORDER.index(s) if s in SEV_ORDER else len(SEV_ORDER)


def iso_ts(t):
    """Normalize any Trivy timestamp to an ISO-8601 UTC string the browser can
    parse and render in the viewer's own timezone."""
    if not t:
        return ""
    s = re.sub(r"\.\d+", "", str(t).strip()).replace(" ", "T")
    if s.endswith("Z") or re.search(r"[+-]\d{2}:?\d{2}$", s):
        return s
    return s + "Z"


def load_reports(paths):
    out = []
    for p in paths:
        try:
            with open(p) as f:
                out.append((p, json.load(f)))
        except Exception as e:
            print(f"skip {p}: {e}", file=sys.stderr)
    return out


def chart_of(target):
    for sep in ("/templates/", "/charts/"):
        if sep in target:
            return target.split(sep)[0]
    return os.path.dirname(target) or target


def tag_key(t):
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", t or "")
    ver = tuple(int(x) for x in m.groups()) if m else (0, 0, 0)
    b = re.search(r"-(\d+)$", t or "")
    return (ver, int(b.group(1)) if b else 0, t or "")


def domain_totals(rows, extra_secrets):
    t = sev_bucket()
    for r in rows:
        for s in SEV_ORDER:
            t[s] += r["counts"].get(s, 0)
    t["secrets"] = extra_secrets
    t["total"] = sum(t[s] for s in SEV_ORDER)
    return t


# --------------------------------------------------------------------------- #
# aggregation
# --------------------------------------------------------------------------- #
def aggregate_images(reports):
    repo_map, vuln_index = {}, {}
    trivy_version, created = None, None
    for path, data in reports:
        trivy_version = trivy_version or (data.get("Trivy") or {}).get("Version")
        created = created or data.get("CreatedAt")
        name = data.get("ArtifactName") or os.path.basename(path)
        repo, tag = (name.rsplit(":", 1) + ["latest"])[:2] if ":" in name else (name, "latest")
        meta = data.get("Metadata") or {}
        os_name = ""
        if meta.get("OS"):
            os_name = f"{meta['OS'].get('Family','')} {meta['OS'].get('Name','')}".strip()
        counts, n_secrets, findings, vulns_full = sev_bucket(), 0, [], []
        for r in data.get("Results") or []:
            for v in r.get("Vulnerabilities") or []:
                sev = (v.get("Severity") or "UNKNOWN").upper()
                counts[sev] = counts.get(sev, 0) + 1
                rowd = {"id": v.get("VulnerabilityID"), "pkg": v.get("PkgName"),
                        "installed": v.get("InstalledVersion"), "fixed": v.get("FixedVersion") or "",
                        "severity": sev, "cls": r.get("Class") or "",
                        "title": v.get("Title") or (v.get("Description") or "")[:140],
                        "url": v.get("PrimaryURL") or ""}
                findings.append(rowd); vulns_full.append(rowd)
            n_secrets += len(r.get("Secrets") or [])
        findings.sort(key=lambda f: rank(f["severity"]))
        rec = {"tag": tag, "os": os_name, "counts": counts, "total": sum(counts.values()),
               "secrets": n_secrets, "findings": findings[:40], "vulns_full": vulns_full,
               "scanned_at": iso_ts(data.get("CreatedAt") or "")}
        repo_map.setdefault(repo, {"repo": repo, "tags": []})["tags"].append(rec)

    images = []
    for repo, rm in repo_map.items():
        rm["tags"].sort(key=lambda x: tag_key(x["tag"]), reverse=True)
        latest = rm["tags"][0]
        for v in latest["vulns_full"]:
            key = (v["id"], v["pkg"])
            r = vuln_index.setdefault(key, {"id": v["id"], "pkg": v["pkg"],
                "installed": v["installed"], "fixed": v["fixed"], "severity": v["severity"],
                "title": v["title"], "url": v["url"], "images": set()})
            r["images"].add(repo)
            if v["fixed"] and not r["fixed"]:
                r["fixed"] = v["fixed"]
            if rank(v["severity"]) < rank(r["severity"]):
                r["severity"] = v["severity"]
        for t in rm["tags"]:
            t.pop("vulns_full", None)
        images.append({"repo": repo, "latest_tag": latest["tag"], "tag_count": len(rm["tags"]),
                       "os": latest["os"], "counts": latest["counts"], "total": latest["total"],
                       "secrets": latest["secrets"], "tags": rm["tags"]})

    vulns = []
    for r in vuln_index.values():
        r["count"] = len(r["images"]); r["images"] = sorted(r["images"]); vulns.append(r)
    vulns.sort(key=lambda r: (rank(r["severity"]), -r["count"]))
    images.sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))

    img_secrets = sum(i["secrets"] for i in images)
    totals = domain_totals(images, img_secrets)
    return {
        "domain": "docker",
        "images": images,
        "vulns": vulns[:80],
        "totals": totals,
        "asset_count": len(images),
        "tag_count": sum(i["tag_count"] for i in images),
        "trivy_version": trivy_version or "",
        "scanned_at": iso_ts(created or ""),
    }


def aggregate_helm(reports):
    chart_map, rule_index, secrets = {}, {}, []
    trivy_version, created = None, None
    for path, data in reports:
        trivy_version = trivy_version or (data.get("Trivy") or {}).get("Version")
        created = created or data.get("CreatedAt")
        for r in data.get("Results") or []:
            target = r.get("Target") or ""
            for m in r.get("Misconfigurations") or []:
                if (m.get("Status") or "FAIL").upper() != "FAIL":
                    continue
                chart = chart_of(target)
                c = chart_map.setdefault(chart, {"name": chart, "counts": sev_bucket(),
                    "total": 0, "rules": {}, "findings": []})
                sev = (m.get("Severity") or "UNKNOWN").upper()
                c["counts"][sev] = c["counts"].get(sev, 0) + 1
                c["total"] += 1
                rid = m.get("ID") or m.get("AVDID") or "?"
                c["rules"][rid] = c["rules"].get(rid, 0) + 1
                line = ((m.get("CauseMetadata") or {}).get("StartLine")) or ""
                c["findings"].append({"rule": rid, "title": m.get("Title") or "",
                    "severity": sev, "file": target, "line": line})
                rec = rule_index.setdefault(rid, {"id": rid, "title": m.get("Title") or "",
                    "severity": sev, "resolution": m.get("Resolution") or "",
                    "charts": set(), "locations": []})
                rec["charts"].add(chart)
                if len(rec["locations"]) < 60:
                    rec["locations"].append({"chart": chart, "file": target, "line": line})
            for s in r.get("Secrets") or []:
                secrets.append({"domain": "helm", "where": target,
                    "rule": s.get("RuleID") or s.get("Category") or "secret",
                    "severity": (s.get("Severity") or "").upper(),
                    "title": s.get("Title") or "", "location": f"line {s.get('StartLine','?')}"})
    charts = []
    for c in chart_map.values():
        top = sorted(c["rules"].items(), key=lambda kv: -kv[1])
        c["top_rule"] = top[0][0] if top else ""
        del c["rules"]
        c["findings"].sort(key=lambda f: rank(f["severity"]))
        # keep (almost) all findings so the Excel export is complete; the UI only
        # renders a slice anyway. A high cap still guards against a pathological chart.
        c["findings"] = c["findings"][:1000]
        charts.append(c)
    rules = []
    for r in rule_index.values():
        r["count"] = len(r["charts"]); r["charts"] = sorted(r["charts"]); rules.append(r)
    rules.sort(key=lambda r: (rank(r["severity"]), -r["count"]))
    charts.sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))

    totals = domain_totals(charts, len(secrets))
    return {
        "domain": "helm",
        "charts": charts,
        "rules": rules[:80],
        "secrets": secrets,
        "totals": totals,
        "asset_count": len(charts),
        "trivy_version": trivy_version or "",
        "scanned_at": iso_ts(created or ""),
    }


def score_of(t):
    ch, hi, se = t["CRITICAL"], t["HIGH"], t.get("secrets", 0)
    if ch > 50: return 1
    if ch > 20: return 2
    if ch > 10: return 3
    if ch > 0:  return 4
    if hi > 50: return 5
    if hi > 20: return 6
    if hi > 5:  return 7
    if hi > 0:  return 8
    if se > 0:  return 9
    return 10


# --------------------------------------------------------------------------- #
# run archive
# --------------------------------------------------------------------------- #
def run_id(branch, ts):
    slug = re.sub(r"[^A-Za-z0-9]+", "-", (branch or "scan")).strip("-").lower() or "scan"
    stamp = re.sub(r"[^0-9]", "", (ts or "")) or hashlib.sha1(os.urandom(8)).hexdigest()[:12]
    return f"{slug}-{stamp}"[:80]


def update_manifest(runs_dir, entry, max_runs):
    os.makedirs(runs_dir, exist_ok=True)
    mpath = os.path.join(runs_dir, "manifest.json")
    runs = []
    if os.path.exists(mpath):
        try:
            runs = json.load(open(mpath)).get("runs", [])
        except Exception:
            runs = []
    runs = [r for r in runs if r.get("id") != entry["id"]]
    runs.append(entry)
    # newest first by scan time
    runs.sort(key=lambda r: r.get("scanned_at") or "", reverse=True)
    # trim, deleting archived files that fall off the list
    keep, drop = runs[:max_runs], runs[max_runs:]
    for r in drop:
        try:
            os.remove(os.path.join(runs_dir, r["id"] + ".json"))
        except OSError:
            pass
    json.dump({"runs": keep}, open(mpath, "w"), ensure_ascii=False)
    return keep


# --------------------------------------------------------------------------- #
# rendering
# --------------------------------------------------------------------------- #
def embed(page, model):
    blob = json.dumps(model, ensure_ascii=False)
    blob = blob.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    return page.replace("/*__DATA__*/{}", blob)


def read_tpl(name):
    return open(os.path.join(os.path.dirname(os.path.abspath(__file__)), name)).read()


def build_domain(args):
    reports = load_reports(sorted(glob.glob(os.path.join(args.data, "*.json"))))
    model = aggregate_images(reports) if args.domain == "docker" else aggregate_helm(reports)

    scanned_at = iso_ts(args.scanned_at) or model["scanned_at"] \
        or datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    branch = args.branch or ("master" if args.domain == "docker" else "")
    rid = run_id(branch, scanned_at)
    t = model["totals"]
    entry = {"id": rid, "branch": branch, "scanned_at": scanned_at,
             "actor": args.actor or "", "occ": t["total"],
             "critical": t["CRITICAL"], "high": t["HIGH"],
             "assets": model["asset_count"], "score": score_of(t)}

    repo = None
    if args.repo_url and (args.ref or branch):
        repo = {"url": args.repo_url.rstrip("/"), "ref": (args.ref or branch),
                "helm_prefix": args.helm_prefix.strip("/") if args.domain == "helm" else ""}

    meta = {"domain": args.domain, "generated_at":
            datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
            "scanned_at": scanned_at, "branch": branch, "actor": args.actor or "",
            "trivy_version": model["trivy_version"], "asset_count": model["asset_count"],
            "tag_count": model.get("tag_count", 0), "score": score_of(t), "repo": repo}
    model["meta"] = meta

    # archive this run (full model) + refresh manifest
    site_domain = os.path.join(args.site, args.domain)
    runs_dir = os.path.join(site_domain, "data", "runs")
    os.makedirs(runs_dir, exist_ok=True)
    json.dump({**model, "meta": meta, "run": entry},
              open(os.path.join(runs_dir, rid + ".json"), "w"), ensure_ascii=False)
    runs = update_manifest(runs_dir, entry, MAX_RUNS.get(args.domain, 12))
    for r in runs:
        r["latest"] = (r["id"] == runs[0]["id"])

    # The page embeds only a light bootstrap (meta + run list); the heavy per-run
    # model is fetched from data/runs/<id>.json on load and on run switch. This
    # keeps index.html small and avoids duplicating the data both inline and in
    # the archive.
    boot = {"domain": args.domain, "meta": meta, "repo": repo,
            "runs": runs, "current": rid}
    os.makedirs(site_domain, exist_ok=True)
    page = embed(read_tpl("dash.html"), boot)
    out = os.path.join(site_domain, "index.html")
    open(out, "w").write(page)

    # a compact per-domain summary the landing page reads
    json.dump({"domain": args.domain, "scanned_at": scanned_at, "branch": branch,
               "actor": args.actor or "", "score": score_of(t), "totals": t,
               "asset_count": model["asset_count"], "tag_count": model.get("tag_count", 0),
               "run_count": len(runs)},
              open(os.path.join(site_domain, "summary.json"), "w"), ensure_ascii=False)

    print(f"wrote {out}  ({args.domain}: assets={model['asset_count']} "
          f"CRIT={t['CRITICAL']} HIGH={t['HIGH']} score={score_of(t)}/10 runs={len(runs)})")


def build_landing(args):
    def load_summary(dom):
        p = os.path.join(args.site, dom, "summary.json")
        if os.path.exists(p):
            try:
                return json.load(open(p))
            except Exception:
                return None
        return None
    model = {"generated_at":
             datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
             "docker": load_summary("docker"), "helm": load_summary("helm")}
    page = embed(read_tpl("landing.html"), model)
    open(os.path.join(args.site, "index.html"), "w").write(page)
    print(f"wrote {os.path.join(args.site, 'index.html')} (landing)")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)

    d = sub.add_parser("domain")
    d.add_argument("--domain", required=True, choices=["docker", "helm"])
    d.add_argument("--data", required=True, help="dir of raw Trivy JSON for this domain")
    d.add_argument("--site", required=True, help="site root (…/security/trivy)")
    d.add_argument("--branch", default="")
    d.add_argument("--actor", default="")
    d.add_argument("--scanned-at", default="", dest="scanned_at")
    d.add_argument("--repo-url", default="", dest="repo_url")
    d.add_argument("--ref", default="")
    d.add_argument("--helm-prefix", default="deploy-as-code/helm/charts", dest="helm_prefix")

    l = sub.add_parser("landing")
    l.add_argument("--site", required=True)

    args = ap.parse_args()
    if args.mode == "domain":
        build_domain(args)
    else:
        build_landing(args)


if __name__ == "__main__":
    main()
