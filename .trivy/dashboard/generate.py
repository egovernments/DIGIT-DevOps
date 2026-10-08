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
        "vulns": vulns[:5000],   # high cap: full set for the Excel export (UI filters)
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
        "rules": rules[:2000],   # high cap: full set for the Excel export (UI filters)
        "secrets": secrets,
        "totals": totals,
        "asset_count": len(charts),
        "trivy_version": trivy_version or "",
        "scanned_at": iso_ts(created or ""),
    }


# --------------------------------------------------------------------------- #
# terraform (IaC misconfig) — same Trivy "Misconfigurations" shape as helm, but
# grouped by terraform module and split per cloud (aws/azure/gcp). Produces one
# helm-shaped model per cloud plus a combined "all clouds" model whose assets are
# prefixed with the cloud, so the Excel "by directory" export yields one
# worksheet per cloud automatically.
# --------------------------------------------------------------------------- #
TF_CLOUDS = ["aws", "azure", "gcp"]
TF_CLOUD_LABEL = {"aws": "AWS", "azure": "Azure", "gcp": "GCP"}


def tf_module_of(target):
    """Human-readable terraform module name for a scanned file target."""
    t = re.sub(r"^(\.\./)+", "", target or "")
    d = os.path.dirname(t)
    return d or "root"


def tf_repo_path(cloud, target, root="infra-as-code/terraform"):
    """Resolve a Trivy target (relative to the cloud dir) to a repo path, or ""
    when it points outside the repo (e.g. a downloaded registry module)."""
    t = target or ""
    if t.startswith("terraform-aws-modules/") or t.startswith(".terraform/") or "/.terraform/" in t:
        return ""
    base = f"{root}/{cloud}"
    parts = (base + "/" + t).split("/")
    out = []
    for p in parts:
        if p in ("", "."):
            continue
        if p == "..":
            if out:
                out.pop()
        else:
            out.append(p)
    rp = "/".join(out)
    return rp if rp.startswith(root + "/") else ""


def aggregate_tf(reports, cloud, prefix=False):
    """Build a helm-shaped model (charts=modules, rules) from one cloud's Trivy
    misconfig JSON. With prefix=True the module (asset) names are prefixed with
    the cloud for the combined overview."""
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
                mod = tf_module_of(target)
                name = f"{cloud}/{mod}" if prefix else mod
                c = chart_map.setdefault(name, {"name": name, "counts": sev_bucket(),
                    "total": 0, "rules": {}, "findings": []})
                sev = (m.get("Severity") or "UNKNOWN").upper()
                c["counts"][sev] = c["counts"].get(sev, 0) + 1
                c["total"] += 1
                rid = m.get("ID") or m.get("AVDID") or "?"
                c["rules"][rid] = c["rules"].get(rid, 0) + 1
                line = ((m.get("CauseMetadata") or {}).get("StartLine")) or ""
                fpath = tf_repo_path(cloud, target)
                c["findings"].append({"rule": rid, "title": m.get("Title") or "",
                    "severity": sev, "file": fpath or target, "line": line})
                rec = rule_index.setdefault(rid, {"id": rid, "title": m.get("Title") or "",
                    "severity": sev, "resolution": m.get("Resolution") or "",
                    "charts": set(), "locations": []})
                rec["charts"].add(name)
                if len(rec["locations"]) < 60:
                    rec["locations"].append({"chart": name, "file": fpath or target, "line": line})
            for s in r.get("Secrets") or []:
                secrets.append({"domain": "terraform", "where": tf_repo_path(cloud, target) or target,
                    "rule": s.get("RuleID") or s.get("Category") or "secret",
                    "severity": (s.get("Severity") or "").upper(),
                    "title": s.get("Title") or "", "location": f"line {s.get('StartLine','?')}"})
    charts = []
    for c in chart_map.values():
        top = sorted(c["rules"].items(), key=lambda kv: -kv[1])
        c["top_rule"] = top[0][0] if top else ""
        del c["rules"]
        c["findings"].sort(key=lambda f: rank(f["severity"]))
        c["findings"] = c["findings"][:1000]
        charts.append(c)
    rules = []
    for r in rule_index.values():
        r["count"] = len(r["charts"]); r["charts"] = sorted(r["charts"]); rules.append(r)
    rules.sort(key=lambda r: (rank(r["severity"]), -r["count"]))
    charts.sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))
    totals = domain_totals(charts, len(secrets))
    return {"domain": "terraform", "charts": charts, "rules": rules[:2000],
            "secrets": secrets, "totals": totals, "asset_count": len(charts),
            "trivy_version": trivy_version or "", "scanned_at": iso_ts(created or "")}


def score_of(t, assets=0):
    """Severity-weighted posture score, 0-10 (10 = clean).

    A density of weighted findings per asset, so it reflects the whole posture
    (including Medium findings and volume) rather than only the single worst
    severity - clearing many findings visibly improves the score. Critical still
    dominates via its weight. Mapped with score = 10 / (1 + penalty/K).
    """
    total = (t["CRITICAL"] + t["HIGH"] + t["MEDIUM"]
             + t.get("LOW", 0) + t.get("UNKNOWN", 0) + t.get("secrets", 0))
    if total == 0:
        return 10
    n = assets or 1
    penalty = (t["CRITICAL"] * 10 + t["HIGH"] * 3 + t["MEDIUM"] * 1
               + t.get("LOW", 0) * 0.5 + t.get("UNKNOWN", 0) * 0.5
               + t.get("secrets", 0) * 5) / n
    K = 14.0  # calibration: clean=10; ~7/chart -> 7; ~20/chart -> 4; very high -> 1
    return max(1, min(10, round(10 / (1 + penalty / K))))


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
             "assets": model["asset_count"], "score": score_of(t, model["asset_count"])}

    repo = None
    if args.repo_url and (args.ref or branch):
        repo = {"url": args.repo_url.rstrip("/"), "ref": (args.ref or branch),
                "helm_prefix": args.helm_prefix.strip("/") if args.domain == "helm" else ""}

    meta = {"domain": args.domain, "generated_at":
            datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
            "scanned_at": scanned_at, "branch": branch, "actor": args.actor or "",
            "trivy_version": model["trivy_version"], "asset_count": model["asset_count"],
            "tag_count": model.get("tag_count", 0), "score": score_of(t, model["asset_count"]), "repo": repo}
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
               "actor": args.actor or "", "score": score_of(t, model["asset_count"]), "totals": t,
               "asset_count": model["asset_count"], "tag_count": model.get("tag_count", 0),
               "run_count": len(runs)},
              open(os.path.join(site_domain, "summary.json"), "w"), ensure_ascii=False)

    print(f"wrote {out}  ({args.domain}: assets={model['asset_count']} "
          f"CRIT={t['CRITICAL']} HIGH={t['HIGH']} score={score_of(t, model['asset_count'])}/10 runs={len(runs)})")


def _render_page(site_sub, domain, model, meta, repo, labels, root, scanned_at,
                 actor, branch, max_runs=20):
    """Archive one run and render a dash.html page for a (terraform) sub-site."""
    t = model["totals"]
    rid = run_id(branch or domain, scanned_at)
    entry = {"id": rid, "branch": branch, "scanned_at": scanned_at, "actor": actor or "",
             "occ": t["total"], "critical": t["CRITICAL"], "high": t["HIGH"],
             "assets": model["asset_count"], "score": score_of(t, model["asset_count"])}
    model["meta"] = meta
    runs_dir = os.path.join(site_sub, "data", "runs")
    os.makedirs(runs_dir, exist_ok=True)
    json.dump({**model, "meta": meta, "run": entry},
              open(os.path.join(runs_dir, rid + ".json"), "w"), ensure_ascii=False)
    runs = update_manifest(runs_dir, entry, max_runs)
    for r in runs:
        r["latest"] = (r["id"] == runs[0]["id"])
    boot = {"domain": domain, "kind": "terraform", "labels": labels, "root": root,
            "meta": meta, "repo": repo, "runs": runs, "current": rid}
    os.makedirs(site_sub, exist_ok=True)
    open(os.path.join(site_sub, "index.html"), "w").write(embed(read_tpl("dash.html"), boot))
    json.dump({"domain": domain, "scanned_at": scanned_at, "branch": branch,
               "actor": actor or "", "score": score_of(t, model["asset_count"]),
               "totals": t, "asset_count": model["asset_count"], "run_count": len(runs)},
              open(os.path.join(site_sub, "summary.json"), "w"), ensure_ascii=False)
    return entry


def build_terraform(args):
    """Scan JSON lives per cloud at <data>/<cloud>.json. Builds a per-cloud
    dashboard at terraform/<cloud>/ and a combined overview at terraform/."""
    site_tf = os.path.join(args.site, "terraform")
    scanned_at = iso_ts(args.scanned_at) or \
        datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    gen_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    branch = args.branch or "master"

    def repo_for(prefix):
        if not args.repo_url:
            return None
        return {"url": args.repo_url.rstrip("/"), "ref": (args.ref or branch), "helm_prefix": prefix}

    cloud_reports, per_cloud = {}, {}
    for cloud in TF_CLOUDS:
        p = os.path.join(args.data, cloud + ".json")
        cloud_reports[cloud] = load_reports([p]) if os.path.exists(p) else []

    # ---- per-cloud dashboards ----
    for cloud in TF_CLOUDS:
        model = aggregate_tf(cloud_reports[cloud], cloud, prefix=False)
        t = model["totals"]
        meta = {"domain": "terraform-" + cloud, "generated_at": gen_at, "scanned_at": scanned_at,
                "branch": branch, "actor": args.actor or "", "trivy_version": model["trivy_version"],
                "asset_count": model["asset_count"], "tag_count": 0,
                "score": score_of(t, model["asset_count"]), "repo": repo_for("")}
        labels = {"tag": TF_CLOUD_LABEL[cloud], "title": TF_CLOUD_LABEL[cloud] + " Terraform ",
                  "brandSub": TF_CLOUD_LABEL[cloud] + " Terraform · Trivy",
                  "doc": TF_CLOUD_LABEL[cloud] + " Terraform · Trivy · DIGIT", "cloud": cloud}
        _render_page(os.path.join(site_tf, cloud), "terraform-" + cloud, model, meta,
                     repo_for(""), labels, "../../", scanned_at, args.actor or "", branch)
        per_cloud[cloud] = {"cloud": cloud, "label": TF_CLOUD_LABEL[cloud],
                            "totals": t, "asset_count": model["asset_count"],
                            "score": score_of(t, model["asset_count"])}
        print(f"  terraform/{cloud}: modules={model['asset_count']} "
              f"CRIT={t['CRITICAL']} HIGH={t['HIGH']} total={t['total']}")

    # ---- combined overview (assets prefixed by cloud -> Excel per-cloud sheets) ----
    all_reports = [(cloud, data) for cloud in TF_CLOUDS for _, data in cloud_reports[cloud]]
    ov = {"domain": "terraform", "charts": [], "rules": [], "secrets": [],
          "totals": sev_bucket(), "asset_count": 0, "trivy_version": "", "scanned_at": scanned_at}
    merged = {"charts": [], "rule_index": {}, "secrets": []}
    for cloud in TF_CLOUDS:
        cm = aggregate_tf(cloud_reports[cloud], cloud, prefix=True)
        ov["trivy_version"] = ov["trivy_version"] or cm["trivy_version"]
        merged["charts"].extend(cm["charts"])
        merged["secrets"].extend(cm["secrets"])
        for r in cm["rules"]:
            ex = merged["rule_index"].get(r["id"])
            if not ex:
                merged["rule_index"][r["id"]] = {**r, "charts": list(r["charts"])}
            else:
                ex["count"] += r["count"]
                ex["charts"] = sorted(set(ex["charts"]) | set(r["charts"]))
                ex["locations"] = (ex.get("locations") or []) + (r.get("locations") or [])
    merged["charts"].sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))
    rules = sorted(merged["rule_index"].values(), key=lambda r: (rank(r["severity"]), -r["count"]))
    ov.update({"charts": merged["charts"], "rules": rules, "secrets": merged["secrets"],
               "asset_count": len(merged["charts"]),
               "totals": domain_totals(merged["charts"], len(merged["secrets"]))})
    t = ov["totals"]
    meta = {"domain": "terraform", "generated_at": gen_at, "scanned_at": scanned_at,
            "branch": branch, "actor": args.actor or "", "trivy_version": ov["trivy_version"],
            "asset_count": ov["asset_count"], "tag_count": 0,
            "score": score_of(t, ov["asset_count"]), "repo": repo_for(""),
            "clouds": [per_cloud[c] for c in TF_CLOUDS]}
    labels = {"tag": "Terraform", "title": "Terraform ", "brandSub": "Terraform IaC · Trivy",
              "doc": "Terraform · Trivy · DIGIT", "cloud": ""}
    _render_page(site_tf, "terraform", ov, meta, repo_for(""), labels, "../",
                 scanned_at, args.actor or "", branch)
    print(f"  terraform (all): modules={ov['asset_count']} "
          f"CRIT={t['CRITICAL']} HIGH={t['HIGH']} total={t['total']} score={meta['score']}/10")


def build_landing(args):
    def load_summary(dom):
        p = os.path.join(args.site, dom, "summary.json")
        if os.path.exists(p):
            try:
                return json.load(open(p))
            except Exception:
                return None
        return None
    tf = load_summary("terraform")
    if tf:
        tf_clouds = []
        for c in TF_CLOUDS:
            s = load_summary(os.path.join("terraform", c))
            if s:
                s["cloud"] = c
                s["label"] = TF_CLOUD_LABEL[c]
                tf_clouds.append(s)
        tf["clouds"] = tf_clouds
    model = {"generated_at":
             datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
             "docker": load_summary("docker"), "helm": load_summary("helm"), "terraform": tf}
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

    tf = sub.add_parser("terraform")
    tf.add_argument("--data", required=True, help="dir with <cloud>.json (aws/azure/gcp)")
    tf.add_argument("--site", required=True, help="site root (…/security/trivy)")
    tf.add_argument("--branch", default="")
    tf.add_argument("--actor", default="")
    tf.add_argument("--scanned-at", default="", dest="scanned_at")
    tf.add_argument("--repo-url", default="", dest="repo_url")
    tf.add_argument("--ref", default="")

    l = sub.add_parser("landing")
    l.add_argument("--site", required=True)

    args = ap.parse_args()
    if args.mode == "domain":
        build_domain(args)
    elif args.mode == "terraform":
        build_terraform(args)
    else:
        build_landing(args)


if __name__ == "__main__":
    main()
