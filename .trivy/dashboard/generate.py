#!/usr/bin/env python3
"""Aggregate Trivy JSON (image + Helm/config scans) into a single self-contained
static dashboard (index.html) suitable for publishing to GitHub Pages.

Usage:
    python3 generate.py --images DIR --helm DIR --out site
    python3 generate.py --results DIR --out site   # auto-detect scan type

Every input is a Trivy JSON report (`--format json`). Image reports carry
Vulnerabilities/Secrets; Helm reports (fs/config scan) carry Misconfigurations.
The scan type is detected from the report, so a single --results dir works too.
"""
import argparse, json, os, sys, glob, datetime, re

SEV_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]


def load_reports(paths):
    reports = []
    for p in paths:
        try:
            with open(p) as f:
                data = json.load(f)
        except Exception as e:
            print(f"skip {p}: {e}", file=sys.stderr)
            continue
        reports.append((p, data))
    return reports


def sev_bucket():
    return {s: 0 for s in SEV_ORDER}


def is_image_report(data):
    at = (data.get("ArtifactType") or "").lower()
    if at in ("container_image", "image"):
        return True
    for r in data.get("Results") or []:
        if r.get("Class") in ("os-pkgs", "lang-pkgs") or r.get("Vulnerabilities"):
            return True
    return False


def chart_of(target):
    # Target looks like "urban/pt-services-v2/templates/deployment.yaml"
    for sep in ("/templates/", "/charts/"):
        if sep in target:
            return target.split(sep)[0]
    # fall back to the directory holding the file
    return os.path.dirname(target) or target


def aggregate(image_reports, helm_reports):
    images, charts = [], []
    vuln_index = {}   # (id,pkg) -> record
    rule_index = {}   # id -> record
    secrets = []
    trivy_version = None
    image_created = None
    helm_created = None

    def rank(s):
        return SEV_ORDER.index(s) if s in SEV_ORDER else len(SEV_ORDER)

    def tag_key(t):
        m = re.match(r'v?(\d+)\.(\d+)\.(\d+)', t or "")
        ver = tuple(int(x) for x in m.groups()) if m else (0, 0, 0)
        b = re.search(r'-(\d+)$', t or "")
        return (ver, int(b.group(1)) if b else 0, t or "")

    # ---- images: parse each (repo:tag) report, group by repo ----------------
    repo_map = {}   # repo -> {"repo":..., "tags":[ per-tag record ]}
    for path, data in image_reports:
        trivy_version = trivy_version or (data.get("Trivy") or {}).get("Version")
        image_created = image_created or data.get("CreatedAt")
        name = data.get("ArtifactName") or os.path.basename(path)
        repo, tag = (name.rsplit(":", 1) + ["latest"])[:2] if ":" in name else (name, "latest")
        meta = data.get("Metadata") or {}
        os_name = ""
        if meta.get("OS"):
            os_name = f"{meta['OS'].get('Family','')} {meta['OS'].get('Name','')}".strip()
        counts = sev_bucket(); n_secrets = 0; findings = []; vulns_full = []
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
               "scanned_at": (data.get("CreatedAt") or "")}
        repo_map.setdefault(repo, {"repo": repo, "tags": []})["tags"].append(rec)

    # per repo: sort tags latest->oldest; latest tag is the representative
    for repo, rm in repo_map.items():
        rm["tags"].sort(key=lambda x: tag_key(x["tag"]), reverse=True)
        latest = rm["tags"][0]
        # fleet aggregates come from the latest tag only (no cross-version double count)
        for v in latest["vulns_full"]:
            key = (v["id"], v["pkg"])
            rec = vuln_index.setdefault(key, {
                "id": v["id"], "pkg": v["pkg"], "installed": v["installed"], "fixed": v["fixed"],
                "severity": v["severity"], "title": v["title"], "url": v["url"], "images": set()})
            rec["images"].add(repo)
            if v["fixed"] and not rec["fixed"]:
                rec["fixed"] = v["fixed"]
            # grouped variants keep the highest observed severity
            if rank(v["severity"]) < rank(rec["severity"]):
                rec["severity"] = v["severity"]
        for t in rm["tags"]:
            t.pop("vulns_full", None)
        images.append({"repo": repo, "latest_tag": latest["tag"], "tag_count": len(rm["tags"]),
                       "os": latest["os"], "counts": latest["counts"], "total": latest["total"],
                       "secrets": latest["secrets"], "tags": rm["tags"]})

    # ---- helm / charts ------------------------------------------------------
    chart_map = {}
    for path, data in helm_reports:
        trivy_version = trivy_version or (data.get("Trivy") or {}).get("Version")
        helm_created = helm_created or data.get("CreatedAt")
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
                loc = {"chart": chart, "file": target, "line": line}
                c["findings"].append({"rule": rid, "title": m.get("Title") or "",
                                      "severity": sev, "file": target, "line": line})
                rec = rule_index.setdefault(rid, {
                    "id": rid, "title": m.get("Title") or "", "severity": sev,
                    "resolution": m.get("Resolution") or "", "charts": set(), "locations": []})
                rec["charts"].add(chart)
                if len(rec["locations"]) < 60:
                    rec["locations"].append(loc)
            for s in r.get("Secrets") or []:
                secrets.append({"domain": "helm", "where": target,
                                "rule": s.get("RuleID") or s.get("Category") or "secret",
                                "severity": (s.get("Severity") or "").upper(),
                                "title": s.get("Title") or "",
                                "location": f"line {s.get('StartLine','?')}"})
    for c in chart_map.values():
        top = sorted(c["rules"].items(), key=lambda kv: -kv[1])
        c["top_rule"] = top[0][0] if top else ""
        del c["rules"]
        c["findings"].sort(key=lambda f: rank(f["severity"]))
        c["findings"] = c["findings"][:60]
        charts.append(c)

    # ---- top lists ----------------------------------------------------------
    vulns = []
    for rec in vuln_index.values():
        rec["count"] = len(rec["images"])
        rec["images"] = sorted(rec["images"])
        vulns.append(rec)
    rules = []
    for rec in rule_index.values():
        rec["count"] = len(rec["charts"])
        rec["charts"] = sorted(rec["charts"])
        rules.append(rec)

    def sev_rank(s):
        return SEV_ORDER.index(s) if s in SEV_ORDER else len(SEV_ORDER)

    vulns.sort(key=lambda r: (sev_rank(r["severity"]), -r["count"]))
    rules.sort(key=lambda r: (sev_rank(r["severity"]), -r["count"]))
    images.sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))
    charts.sort(key=lambda r: (-r["counts"]["CRITICAL"], -r["counts"]["HIGH"], -r["total"]))

    def domain_totals(rows, extra_secrets):
        t = sev_bucket()
        for r in rows:
            for s in SEV_ORDER:
                t[s] += r["counts"].get(s, 0)
        t["secrets"] = extra_secrets
        t["total"] = sum(t[s] for s in SEV_ORDER)
        return t

    img_secrets = sum(img["secrets"] for img in images)   # latest tag per repo
    helm_secrets = sum(1 for s in secrets if s["domain"] == "helm")

    def clean_ts(t):
        return (t or "").replace("T", " ").split(".")[0].replace("Z", "") + (" UTC" if t else "")

    meta = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "image_scanned_at": clean_ts(image_created),
        "helm_scanned_at": clean_ts(helm_created),
        "trivy_version": trivy_version or "",
        "images_count": len(images),
        "image_tags_count": sum(i["tag_count"] for i in images),
        "charts_count": len(charts),
    }
    totals = {
        "image": domain_totals(images, img_secrets),
        "helm": domain_totals(charts, helm_secrets),
    }
    overall = sev_bucket()
    for d in ("image", "helm"):
        for s in SEV_ORDER:
            overall[s] += totals[d][s]
    overall["secrets"] = img_secrets + helm_secrets
    overall["total"] = sum(overall[s] for s in SEV_ORDER)
    totals["overall"] = overall

    return {"meta": meta, "totals": totals, "images": images, "charts": charts,
            "vulns": vulns[:50], "rules": rules[:50], "secrets": secrets}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", help="dir of Trivy image JSON")
    ap.add_argument("--helm", help="dir of Trivy Helm/config JSON")
    ap.add_argument("--results", help="dir of mixed Trivy JSON (auto-detect type)")
    ap.add_argument("--out", default="site", help="output dir")
    ap.add_argument("--title", default="DIGIT Container & Chart Security")
    ap.add_argument("--repo-url", default="", help="repo web URL for file hyperlinks (e.g. https://github.com/egovernments/DIGIT-DevOps)")
    ap.add_argument("--ref", default="", help="branch/commit the Helm scan ran on (for blob links)")
    ap.add_argument("--helm-prefix", default="deploy-as-code/helm/charts", help="path prefix of the charts dir within the repo")
    args = ap.parse_args()

    image_reports, helm_reports = [], []
    if args.results:
        for _, data in load_reports(sorted(glob.glob(os.path.join(args.results, "**/*.json"), recursive=True))):
            (image_reports if is_image_report(data) else helm_reports).append(("", data))
    if args.images:
        image_reports += load_reports(sorted(glob.glob(os.path.join(args.images, "*.json"))))
    if args.helm:
        helm_reports += load_reports(sorted(glob.glob(os.path.join(args.helm, "*.json"))))

    model = aggregate(image_reports, helm_reports)
    model["meta"]["title"] = args.title
    model["meta"]["repo"] = {"url": args.repo_url.rstrip("/"), "ref": args.ref,
                             "helm_prefix": args.helm_prefix.strip("/")} if args.repo_url and args.ref else None

    os.makedirs(args.out, exist_ok=True)
    tpl = os.path.join(os.path.dirname(os.path.abspath(__file__)), "template.html")
    with open(tpl) as f:
        page = f.read()
    # escape for an inline <script> context so a scanned string containing
    # </script> or HTML can't break out of the DATA blob (XSS)
    embedded = json.dumps(model, ensure_ascii=False)
    embedded = embedded.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    page = page.replace("/*__DATA__*/{}", embedded)
    out = os.path.join(args.out, "index.html")
    with open(out, "w") as f:
        f.write(page)
    m = model["meta"]; o = model["totals"]["overall"]
    print(f"wrote {out}")
    print(f"  images={m['images_count']} charts={m['charts_count']} "
          f"CRITICAL={o['CRITICAL']} HIGH={o['HIGH']} secrets={o['secrets']}")


if __name__ == "__main__":
    main()
