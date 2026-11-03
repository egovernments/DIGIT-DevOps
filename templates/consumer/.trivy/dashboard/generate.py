#!/usr/bin/env python3
"""Aggregate Trivy JSON into the health-campaign-services security dashboard.

Information architecture (published under <gh-pages>/security/trivy/):

  index.html                          landing: one card per service, search
  data/services.json                  list of every service's latest summary
  <service>/index.html                the service dashboard (Code Scan + Image Scan)
  <service>/data/builds/<id>.json     full per-build model (code + image)
  <service>/data/builds/manifest.json last N builds (the run dropdown)
  <service>/summary.json              latest build summary (fuels the home card)

A "build" is one pipeline run (keyed by the GitHub run id). The pipeline calls
this twice per build:

  generate.py scan --service S --kind code  --input fs.json    --build-id R ...
  generate.py scan --service S --kind image --input image.json --build-id R ...

The first call creates the build (image still pending / or code-failed if the
code gate aborted the run); the second adds the image scan. `home` re-renders
the landing from every service summary.

Both the filesystem (code) scan and the image scan are Trivy vulnerability +
secret scans, so they share one aggregation.
"""
import argparse, json, os, sys, datetime, re, shutil

SEV_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
MAX_BUILDS = 5          # the run dropdown shows the last 5 builds
KEEP_BUILDS = 20        # but keep a few more on disk, reachable by ?build=<id>
HERE = os.path.dirname(os.path.abspath(__file__))


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def sev_bucket():
    return {s: 0 for s in SEV_ORDER}


def rank(s):
    return SEV_ORDER.index(s) if s in SEV_ORDER else len(SEV_ORDER)


def iso_ts(t):
    if not t:
        return ""
    s = re.sub(r"\.\d+", "", str(t).strip()).replace(" ", "T")
    if s.endswith("Z") or re.search(r"[+-]\d{2}:?\d{2}$", s):
        return s
    return s + "Z"


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def read_tpl(name):
    with open(os.path.join(HERE, name)) as f:
        return f.read()


def embed(page, model):
    blob = json.dumps(model, ensure_ascii=False)
    blob = blob.replace("&", "\\u0026").replace("<", "\\u003c").replace(">", "\\u003e")
    return page.replace("/*__DATA__*/{}", blob)


def ensure_logo(site):
    """Copy the shield logo to the site root so home.html (logo.svg) and every
    service page (../logo.svg) can reference it."""
    src = os.path.join(HERE, "logo.svg")
    dst = os.path.join(site, "logo.svg")
    try:
        os.makedirs(site, exist_ok=True)
        if os.path.abspath(src) != os.path.abspath(dst):
            shutil.copyfile(src, dst)
    except OSError:
        pass


def load_json(p, default=None):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return default


# --------------------------------------------------------------------------- #
# scoring — vulnerability posture, 0..10 (10 = clean)
# --------------------------------------------------------------------------- #
def vuln_penalty(t):
    return (t.get("CRITICAL", 0) * 8 + t.get("HIGH", 0) * 2 + t.get("MEDIUM", 0) * 0.4
            + t.get("LOW", 0) * 0.1 + t.get("secrets", 0) * 5)


def score_of(t):
    """Severity-weighted score for a single artifact (image or repo)."""
    if vuln_penalty(t) == 0:
        return 10
    K = 12.0  # 0->10, 1 crit->~6, 5 crit->~2, heavy->1
    return max(1, min(10, round(10 / (1 + vuln_penalty(t) / K))))


def combined_score(code_t, image_t):
    """One posture score for the whole service (code + image combined)."""
    p = vuln_penalty(code_t or {}) + vuln_penalty(image_t or {})
    if p == 0:
        return 10
    return max(1, min(10, round(10 / (1 + p / 12.0))))


# --------------------------------------------------------------------------- #
# aggregation — one Trivy report (fs scan OR image scan) -> a vuln model
# --------------------------------------------------------------------------- #
def aggregate_vuln(data, kind):
    trivy_version = (data.get("Trivy") or {}).get("Version") or ""
    created = data.get("CreatedAt") or ""
    artifact = data.get("ArtifactName") or ""
    meta = data.get("Metadata") or {}
    os_name = ""
    if meta.get("OS"):
        os_name = f"{meta['OS'].get('Family','')} {meta['OS'].get('Name','')}".strip()

    counts = sev_bucket()
    findings, secrets = [], []
    seen = {}
    for r in data.get("Results") or []:
        cls = r.get("Class") or ""
        target = r.get("Target") or ""
        for v in r.get("Vulnerabilities") or []:
            sev = (v.get("Severity") or "UNKNOWN").upper()
            vid = v.get("VulnerabilityID")
            key = (vid, v.get("PkgName"), v.get("InstalledVersion"))
            if key in seen:
                continue
            seen[key] = 1
            counts[sev] = counts.get(sev, 0) + 1
            findings.append({
                "id": vid, "pkg": v.get("PkgName"),
                "installed": v.get("InstalledVersion"),
                "fixed": v.get("FixedVersion") or "",
                "severity": sev, "cls": cls, "target": target,
                "title": v.get("Title") or (v.get("Description") or "")[:140],
                "url": v.get("PrimaryURL") or "",
            })
        for s in r.get("Secrets") or []:
            secrets.append({
                "rule": s.get("RuleID") or s.get("Category") or "secret",
                "severity": (s.get("Severity") or "").upper(),
                "title": s.get("Title") or "",
                "where": target, "line": s.get("StartLine", ""),
            })
    findings.sort(key=lambda f: (rank(f["severity"]), f.get("pkg") or ""))
    totals = dict(counts)
    totals["secrets"] = len(secrets)
    totals["total"] = sum(counts.values())
    return {
        "kind": kind,
        "artifact": artifact,
        "os": os_name,
        "counts": counts,
        "totals": totals,
        "findings": findings[:4000],
        "secrets": secrets,
        "trivy_version": trivy_version,
        "scanned_at": iso_ts(created) or now_iso(),
        "score": score_of(totals),
    }


# --------------------------------------------------------------------------- #
# build record + manifest
# --------------------------------------------------------------------------- #
def kind_summary(m):
    if not m:
        return None
    t = m["totals"]
    return {"critical": t["CRITICAL"], "high": t["HIGH"], "medium": t["MEDIUM"],
            "total": t["total"], "secrets": t["secrets"], "score": m["score"],
            "gate": m.get("gate", "pass")}


def manifest_entry(build):
    return {"id": build["build_id"], "scanned_at": build["meta"]["scanned_at"],
            "commit": build["meta"].get("commit", ""), "branch": build["meta"].get("branch", ""),
            "actor": build["meta"].get("actor", ""), "status": build["status"],
            "score": build["score"],
            "code": kind_summary(build.get("code")),
            "image": kind_summary(build.get("image"))}


def update_manifest(builds_dir, entry):
    mpath = os.path.join(builds_dir, "manifest.json")
    runs = (load_json(mpath, {}) or {}).get("builds", [])
    runs = [r for r in runs if r.get("id") != entry["id"]]
    runs.append(entry)
    runs.sort(key=lambda r: r.get("scanned_at") or "", reverse=True)
    keep, drop = runs[:KEEP_BUILDS], runs[KEEP_BUILDS:]
    for r in drop:
        try:
            os.remove(os.path.join(builds_dir, r["id"] + ".json"))
        except OSError:
            pass
    json.dump({"builds": keep}, open(mpath, "w"), ensure_ascii=False)
    return keep


def recompute(build):
    code_t = (build.get("code") or {}).get("totals")
    image_t = (build.get("image") or {}).get("totals")
    build["score"] = combined_score(code_t, image_t)


STATUS = {
    # (has_code, code_gate, has_image, image_gate) is resolved in code below
}


def resolve_status(build):
    code, image = build.get("code"), build.get("image")
    if code and code.get("gate") == "fail":
        return "code-failed"          # pipeline aborted before image build
    if image and image.get("gate") == "fail":
        return "image-failed"         # image scan aborted the push
    if code and image:
        return "complete"
    if code and not image:
        return "image-pending"        # code passed; image not scanned (yet)
    return "pending"


# --------------------------------------------------------------------------- #
# render a service page
# --------------------------------------------------------------------------- #
def write_service_page(site, service, builds, current_id):
    svc_dir = os.path.join(site, service)
    os.makedirs(svc_dir, exist_ok=True)
    cur = load_json(os.path.join(svc_dir, "data", "builds", current_id + ".json"))
    # Embed the current build's full model so the page renders on first paint
    # (and works over file://); other builds are fetched lazily over http.
    boot = {"service": service, "builds": builds, "current": current_id,
            "meta": cur["meta"] if cur else {}, "current_model": cur,
            "generated_at": now_iso()}
    page = embed(read_tpl("service.html"), boot)
    open(os.path.join(svc_dir, "index.html"), "w").write(page)


def write_service_summary(site, service, build, build_count):
    svc_dir = os.path.join(site, service)
    s = {"service": service, "build_id": build["build_id"],
         "scanned_at": build["meta"]["scanned_at"], "branch": build["meta"].get("branch", ""),
         "commit": build["meta"].get("commit", ""), "actor": build["meta"].get("actor", ""),
         "status": build["status"], "score": build["score"],
         "code": kind_summary(build.get("code")), "image": kind_summary(build.get("image")),
         "build_count": build_count}
    json.dump(s, open(os.path.join(svc_dir, "summary.json"), "w"), ensure_ascii=False)
    return s


def cmd_scan(args):
    data = load_json(args.input)
    if data is None:
        print(f"ERROR: cannot read {args.input}", file=sys.stderr)
        sys.exit(1)
    model = aggregate_vuln(data, args.kind)
    model["gate"] = "fail" if args.gate == "fail" else "pass"

    svc_dir = os.path.join(args.site, args.service)
    builds_dir = os.path.join(svc_dir, "data", "builds")
    os.makedirs(builds_dir, exist_ok=True)
    bpath = os.path.join(builds_dir, args.build_id + ".json")

    build = load_json(bpath) or {
        "build_id": args.build_id, "service": args.service,
        "meta": {"service": args.service, "build_id": args.build_id},
        "code": None, "image": None}
    build[args.kind] = model
    m = build["meta"]
    m.update({"service": args.service, "build_id": args.build_id,
              "commit": args.commit or m.get("commit", ""),
              "branch": args.branch or m.get("branch", ""),
              "actor": args.actor or m.get("actor", ""),
              "repo_url": args.repo_url or m.get("repo_url", ""),
              "run_url": args.run_url or m.get("run_url", ""),
              "trivy_version": model["trivy_version"] or m.get("trivy_version", ""),
              "scanned_at": model["scanned_at"], "generated_at": now_iso()})
    build["status"] = resolve_status(build)
    recompute(build)
    json.dump(build, open(bpath, "w"), ensure_ascii=False)

    builds = update_manifest(builds_dir, manifest_entry(build))
    for r in builds:
        r["latest"] = (r["id"] == builds[0]["id"])
    ensure_logo(args.site)
    write_service_page(args.site, args.service, builds[:MAX_BUILDS], args.build_id)
    write_service_summary(args.site, args.service, build, len(builds))
    cs, ims = build.get("code"), build.get("image")
    print(f"scan {args.service} [{args.kind}] build={args.build_id} status={build['status']} "
          f"score={build['score']}/10 "
          f"code={(cs['totals']['CRITICAL'] if cs else '-')}C/{cs['totals']['HIGH'] if cs else '-'}H "
          f"image={(ims['totals']['CRITICAL'] if ims else '-')}C/{ims['totals']['HIGH'] if ims else '-'}H")


def cmd_home(args):
    services = []
    for name in sorted(os.listdir(args.site)):
        p = os.path.join(args.site, name, "summary.json")
        s = load_json(p)
        if s:
            services.append(s)
    services.sort(key=lambda s: (s.get("score", 10),
                                 -((s.get("code") or {}).get("critical", 0)
                                   + (s.get("image") or {}).get("critical", 0)),
                                 s["service"]))
    model = {"generated_at": now_iso(), "services": services}
    ensure_logo(args.site)
    json.dump(model, open(os.path.join(args.site, "data_services.json"), "w"), ensure_ascii=False)
    page = embed(read_tpl("home.html"), model)
    open(os.path.join(args.site, "index.html"), "w").write(page)
    print(f"home: {len(services)} services -> {os.path.join(args.site, 'index.html')}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="mode", required=True)

    s = sub.add_parser("scan", help="ingest one code or image Trivy report for a build")
    s.add_argument("--service", required=True)
    s.add_argument("--kind", required=True, choices=["code", "image"])
    s.add_argument("--input", required=True, help="raw Trivy JSON (fs or image scan)")
    s.add_argument("--site", required=True, help="site root (…/security/trivy)")
    s.add_argument("--build-id", required=True, dest="build_id")
    s.add_argument("--commit", default="")
    s.add_argument("--branch", default="")
    s.add_argument("--actor", default="")
    s.add_argument("--repo-url", default="", dest="repo_url")
    s.add_argument("--run-url", default="", dest="run_url")
    s.add_argument("--gate", default="pass", choices=["pass", "fail"],
                   help="fail = this scan found a blocking critical and aborted the run")

    h = sub.add_parser("home", help="rebuild the landing page from all service summaries")
    h.add_argument("--site", required=True)

    args = ap.parse_args()
    {"scan": cmd_scan, "home": cmd_home}[args.mode](args)


if __name__ == "__main__":
    main()
