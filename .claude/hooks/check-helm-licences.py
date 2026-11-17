#!/usr/bin/env python3
"""Helm chart licence gate.

Every chart under deploy-as-code/helm/charts and every chart Argo CD pulls from an external Helm repo must be listed
in deploy-as-code/helm/licences.yaml. Third-party entries declare the deployed component's licence and a link to the
licence text, and the link is validated:
  1. pinned    https, allowed host, URL contains `licence_ref`, which is a tag or commit (not a moving branch)
  2. reachable the URL returns the file
  3. matches   the fetched text contains every licence id of the declared SPDX expression
  4. unchanged sha256 of the text equals `licence_sha256`
  5. deployed  the tag at `tag_source` in values.yaml (and env overrides) / the Argo targetRevision equals the entry
Then the declared licence must be Category A or B of the DIGIT 3.0 Licences Review (license-policy.json next to this file).

Modes:
  (stdin hook event)             Claude Code PostToolUse hook: reports violations for the charts the edit touched
  --all [--summary <md>]         CI: whole repo
  --pin <key> [<key> ...]        fetch an entry's licence_url(s), print sha256 and the licences found in the text

Exit codes: 0 pass, 2 violations (fed back to Claude / fails CI), 1 non-blocking problem (e.g. offline in the hook).
"""
import concurrent.futures
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
POLICY_FILE = os.environ.get("LICENSE_POLICY", os.path.join(HERE, "license-policy.json"))
CACHE_DIR = os.path.join(tempfile.gettempdir(), "helm-licence-gate")
FETCH_TIMEOUT = int(os.environ.get("HELM_LICENCE_FETCH_TIMEOUT", "30"))
MAX_BYTES = 2_000_000

CHARTS_DIR = os.path.join("deploy-as-code", "helm", "charts")
ENV_DIR = os.path.join("deploy-as-code", "helm", "environments")
MAP_FILE = os.path.join("deploy-as-code", "helm", "licences.yaml")
ARGO_DIRS = [os.path.join("deploy-as-code", "helm", "charts", "argo-cd"), os.path.join("deploy-as-code", "argocd-apps")]

URL_HOSTS = {"raw.githubusercontent.com", "github.com", "gitlab.com"}
MOVING_REFS = {"main", "master", "develop", "dev", "trunk", "head", "latest", "stable", "lts", "nightly", "edge", ""}
COMMIT = re.compile(r"^[0-9a-f]{40}$")

# Lower rank is better. OR takes the best choice, AND the worst.
RANK = {"A": 0, "A_CONFIRM": 1, "PENDING": 2, "B": 3, "X": 4, "UNKNOWN": 5}
PASSING = {"A", "A_CONFIRM", "B"}

# Licence id -> phrase that identifies it in a licence text (lower-case, whitespace collapsed).
TEXT_SIGNATURES = {
    "Apache-2.0": r"apache license,? (version )?2\.0",
    "MIT": r"permission is hereby granted, free of charge, to any person obtaining a copy",
    "ISC": r"permission to use, copy, modify, and/or distribute this software for any purpose with or without fee "
           r"is hereby granted, provided that the above copyright notice",
    "BSD-3-Clause": r"redistribution and use in source and binary forms(?!.*advertising materials)"
                    r"(?=.*(neither the name|names of its contributors may not be used))",
    "BSD-2-Clause": r"redistribution and use in source and binary forms(?!.*advertising materials)"
                    r"(?!.*(neither the name|names of its contributors may not be used))",
    "PostgreSQL": r"permission to use, copy, modify, and distribute this software and its documentation for any "
                  r"purpose, without fee, and without a written agreement is hereby granted",
    "MPL-2.0": r"mozilla public license,? (version|v\.?) ?2\.0",
    "EPL-2.0": r"eclipse public license - v 2\.0",
    "BUSL-1.1": r"business source license 1\.1",
    "AGPL-3.0": r"gnu affero general public license",
    "GPL-3.0": r"gnu general public license version 3, 29 june 2007",
    "GPL-2.0": r"gnu general public license,? (version 2, june 1991|either version 2)",
    "LGPL-2.1": r"gnu lesser general public license version 2\.1",
    "LGPL-3.0": r"gnu lesser general public license version 3",
    "SSPL-1.0": r"server side public license",
    "Elastic-2.0": r"elastic license 2\.0",
    "LicenseRef-Elastic-License-1.0": r"elastic license(?! 2\.0)(?!,? version 2)",  # pre-2021 Elastic License
    "RSAL-2.0": r"redis source available license",
}
SPDX_ALIASES = {"-only": "", "-or-later": ""}


def load_policy():
    with open(POLICY_FILE, encoding="utf-8") as f:
        policy = json.load(f)
    index = {}
    for category, spec in policy["categories"].items():
        for key in spec["licences"]:
            index[key.lower()] = (key, category)
    policy["_index"] = index
    return policy


def classify_expression(policy, expr):
    """SPDX expression with AND / OR / parentheses -> (key, category)."""
    tokens = re.findall(r"\(|\)|[^\s()]+", expr)
    pos = 0

    def peek():
        return tokens[pos].upper() if pos < len(tokens) else None

    def factor():
        nonlocal pos
        if peek() == "(":
            pos += 1
            result = disjunction()
            pos += 1  # ")"
            return result
        base = tokens[pos]
        pos += 1
        return policy["_index"].get(base.lower(), (base, "UNKNOWN"))

    def conjunction():
        nonlocal pos
        parts = [factor()]
        while peek() == "AND":
            pos += 1
            parts.append(factor())
        return max(parts, key=lambda p: RANK[p[1]])

    def disjunction():
        nonlocal pos
        parts = [conjunction()]
        while peek() == "OR":
            pos += 1
            parts.append(conjunction())
        return min(parts, key=lambda p: RANK[p[1]])

    try:
        return disjunction()
    except IndexError:
        return expr, "UNKNOWN"


def licence_ids(expr):
    return [t for t in re.findall(r"[^\s()]+", expr) if t.upper() not in ("AND", "OR", "WITH")]


def signature_id(licence_id):
    base = licence_id
    for suffix, repl in SPDX_ALIASES.items():
        if base.endswith(suffix):
            base = base[: -len(suffix)] + repl
    return base


def detect_licences(text):
    norm = re.sub(r"\s+", " ", text).lower()
    return {key for key, pattern in TEXT_SIGNATURES.items() if re.search(pattern, norm)}


def raw_url(url):
    """github.com/<o>/<r>/blob/<ref>/<path> -> raw.githubusercontent.com/<o>/<r>/<ref>/<path>."""
    m = re.match(r"https://github\.com/([^/]+)/([^/]+)/blob/(.+)$", url)
    return f"https://raw.githubusercontent.com/{m.group(1)}/{m.group(2)}/{m.group(3)}" if m else url


def fetch(url, use_cache=True):
    """Returns (bytes, error_text)."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    cached = os.path.join(CACHE_DIR, hashlib.sha256(url.encode()).hexdigest())
    if use_cache and os.path.isfile(cached):
        with open(cached, "rb") as f:
            return f.read(), None
    request = urllib.request.Request(raw_url(url), headers={"User-Agent": "helm-licence-gate"})
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:
            body = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}"
    except (urllib.error.URLError, OSError) as e:
        return None, f"unreachable ({getattr(e, 'reason', e)})"
    if len(body) > MAX_BYTES:
        return None, f"larger than {MAX_BYTES} bytes"
    with open(cached + ".part", "wb") as f:
        f.write(body)
    os.replace(cached + ".part", cached)
    return body, None


def prefetch(urls):
    """Fill the cache in parallel; check_link then reads from it."""
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        list(pool.map(fetch, sorted(u for u in urls if isinstance(u, str) and u.startswith("https://"))))


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def dig(node, path):
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except (OSError, yaml.YAMLError):
        return {}


def chart_dirs(repo):
    found = []
    base = os.path.join(repo, CHARTS_DIR)
    for root, _dirs, files in os.walk(base):
        if "Chart.yaml" in files:
            found.append(os.path.relpath(root, base))
    return sorted(found)


def env_files(repo):
    base = os.path.join(repo, ENV_DIR)
    if not os.path.isdir(base):
        return []
    return sorted(os.path.join(base, f) for f in os.listdir(base)
                  if f.endswith((".yaml", ".yml")) and "secret" not in f)


def external_charts(repo):
    """{key: (targetRevision, file)} for Argo CD sources that pull a chart from a Helm repository."""
    found = {}

    def walk(node, path):
        if isinstance(node, dict):
            url, chart = node.get("repoURL"), node.get("chart")
            if isinstance(url, str) and isinstance(chart, str) and url.startswith("http") \
                    and "{{" not in url + chart and not url.endswith(".git"):
                found[f"{url.rstrip('/')}#{chart}"] = (str(node.get("targetRevision", "")), path)
            for value in node.values():
                walk(value, path)
        elif isinstance(node, list):
            for value in node:
                walk(value, path)

    for argo_dir in ARGO_DIRS:
        for root, _dirs, files in os.walk(os.path.join(repo, argo_dir)):
            if os.sep + "templates" in root:
                continue
            for name in files:
                if not name.endswith((".yaml", ".yml")):
                    continue
                path = os.path.join(root, name)
                try:
                    with open(path, encoding="utf-8") as f:
                        docs = list(yaml.safe_load_all(f))
                except (OSError, yaml.YAMLError):
                    continue
                for doc in docs:
                    walk(doc, os.path.relpath(path, repo))
    return found


def deployed_tag(repo, chart, tag_source):
    """Tag the chart deploys by default: Chart.yaml appVersion, or a dotted path in values.yaml
    (or in another values file of the chart: `<file>:<path>`)."""
    chart_dir = os.path.join(repo, CHARTS_DIR, chart)
    if tag_source == "appVersion":
        value = load_yaml(os.path.join(chart_dir, "Chart.yaml")).get("appVersion")
    else:
        values_file, _, path = tag_source.rpartition(":")
        value = dig(load_yaml(os.path.join(chart_dir, values_file or "values.yaml")), path)
    return tag_value(value)


def tag_value(value):
    if value is None:
        return None
    value = str(value).strip()
    if "/" in value or (":" in value and not value.startswith("RELEASE.")):
        value = value.rsplit(":", 1)[-1] if ":" in value else ""  # "repo:tag" string
    return value


def check_link(policy_hosts, key, entry, fetch_ok, problems):
    """The five link checks for one entry. Appends (key, message) to problems; returns fetch errors (offline)."""
    offline = []
    urls = as_list(entry.get("licence_url"))
    hashes = [str(h) for h in as_list(entry.get("licence_sha256"))]
    ref = str(entry.get("licence_ref") or "")
    declared = str(entry.get("licence") or "")
    if not urls or not declared or declared == "NOASSERTION":
        problems.append((key, "incomplete entry: needs licence, licence_url, licence_ref and licence_sha256"
                         + (f" ({entry['todo']})" if entry.get("todo") else "")))
        return offline
    if ref.lower() in MOVING_REFS or not (COMMIT.match(ref) or re.search(r"\d", ref)):
        problems.append((key, f"licence_ref '{ref}' is not a release tag or commit SHA"))
    if len(hashes) != len(urls):
        problems.append((key, "licence_sha256 needs one hash per licence_url (run --pin)"))
    found = set()
    for i, url in enumerate(urls):
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.hostname not in policy_hosts:
            problems.append((key, f"licence_url must be https on {', '.join(sorted(policy_hosts))}: {url}"))
            continue
        if ref and f"/{ref}/" not in parsed.path:
            problems.append((key, f"licence_url is not pinned to licence_ref '{ref}': {url}"))
        if not fetch_ok:
            continue
        body, error = fetch(url)
        if error:
            if error.startswith("unreachable"):
                offline.append(f"{url}: {error}")
            problems.append((key, f"licence_url {error}: {url}"))
            continue
        digest = hashlib.sha256(body).hexdigest()
        if i < len(hashes) and hashes[i] != digest:
            problems.append((key, f"licence text changed: sha256 {digest} != {hashes[i]} for {url}"))
        found |= detect_licences(body.decode("utf-8", errors="replace"))
    if fetch_ok and urls and not any(p[0] == key and "licence_url" in p[1] and "pinned" not in p[1]
                                     for p in problems):
        missing = [i for i in licence_ids(declared) if signature_id(i) not in found]
        if missing:
            problems.append((key, f"declared licence {declared} not found in the linked text "
                                  f"(missing {', '.join(missing)}; text looks like "
                                  f"{', '.join(sorted(found)) or 'nothing recognised'})"))
    return offline


def check_category(policy, key, entry, problems, notes):
    declared = str(entry.get("licence") or "")
    if not declared or declared == "NOASSERTION":
        return
    licence, category = classify_expression(policy, declared)
    if category in PASSING:
        if category == "B":
            notes.append((key, f"{declared} -> {policy['categories']['B'].get('description', '')}"))
        elif category != "A":
            notes.append((key, f"{declared} passes with a note: {policy.get('notes', {}).get(licence, '')}"))
        return
    exception = next((e for e in policy.get("exceptions", []) if e.get("key") == key), None)
    if exception:
        notes.append((key, f"{declared} ({category}) allowed by exception: {exception.get('reason', '')} "
                           f"(approved by {exception.get('approved_by', '?')})"))
        return
    problems.append((key, f"{entry.get('component', key)} is {declared} -> {category} ({licence}); only "
                          "Categories A and B may be deployed without a licence-owner exception"))


def check_versions(repo, envs, chart, entry, problems):
    source = entry.get("tag_source")
    allowed = [str(t) for t in as_list(entry.get("tag"))]
    if not source or not allowed:
        problems.append((chart, "entry needs tag and tag_source to tie the licence to the deployed version"))
        return
    tag = deployed_tag(repo, chart, source)
    where = "Chart.yaml appVersion" if source == "appVersion" else f"values.yaml {source}"
    if tag is None or tag.lower() in MOVING_REFS:
        problems.append((chart, f"{where} is '{tag or ''}': pin the image tag so its licence can be checked"))
    elif tag not in allowed:
        problems.append((chart, f"{where} deploys '{tag}' but licences.yaml lists {allowed}: update the entry "
                                "(version, licence_ref, licence_url, sha) after checking the new version's licence"))
    if source == "appVersion" or ":" in source:
        return
    release = os.path.basename(chart)
    for env in envs:
        override = tag_value(dig(load_yaml(env).get(release) or {}, source))
        if override and override not in allowed:
            problems.append((chart, f"{os.path.relpath(env, repo)} overrides {release}.{source} to '{override}', "
                                    f"not in {allowed}", ))


def evaluate(repo, fetch_ok=True, only=None):
    """Returns (problems, notes, offline, counts). `only`: set of keys to report on (None = all)."""
    policy = load_policy()
    licence_map = load_yaml(os.path.join(repo, MAP_FILE))
    first_party = set(licence_map.get("first_party") or [])
    third_party = licence_map.get("third_party") or {}
    external = licence_map.get("external_charts") or {}
    problems, notes, offline = [], [], []

    charts = chart_dirs(repo)
    for chart in charts:
        if only is not None and chart not in only:
            continue
        listed = (chart in first_party) + (chart in third_party)
        if listed == 0:
            problems.append((chart, f"chart is not in {MAP_FILE}: add it to first_party (DIGIT's own code) or "
                                    "third_party (with licence and pinned licence_url)"))
        elif listed == 2:
            problems.append((chart, f"chart is listed in both first_party and third_party of {MAP_FILE}"))
    for key in sorted(first_party | set(third_party)):
        if key not in charts and (only is None or key in only):
            problems.append((key, f"{MAP_FILE} lists '{key}' but there is no such chart: remove the entry"))

    if fetch_ok:
        wanted = [*third_party.items(), *external.items()]
        prefetch({url for key, entry in wanted if only is None or key in only
                  for url in as_list(entry.get("licence_url"))})

    envs = env_files(repo)
    for chart, entry in sorted(third_party.items()):
        if (only is not None and chart not in only) or chart not in charts:
            continue
        offline += check_link(URL_HOSTS, chart, entry, fetch_ok, problems)
        check_versions(repo, envs, chart, entry, problems)
        check_category(policy, chart, entry, problems, notes)

    found = external_charts(repo)
    for key, (revision, path) in sorted(found.items()):
        if only is not None and key not in only and path not in only:
            continue
        entry = external.get(key)
        if not entry:
            problems.append((key, f"{path} deploys external chart {key} {revision}, not in {MAP_FILE} "
                                  "external_charts"))
            continue
        if str(entry.get("version")) != revision:
            problems.append((key, f"{path} deploys {key} {revision} but {MAP_FILE} lists {entry.get('version')}"))
        offline += check_link(URL_HOSTS, key, entry, fetch_ok, problems)
        check_category(policy, key, entry, problems, notes)
    for key in sorted(set(external) - set(found)):
        if only is None:
            problems.append((key, f"{MAP_FILE} external_charts lists '{key}' but no Argo CD app deploys it"))

    counts = {"charts": len(charts), "first_party": len(first_party), "third_party": len(third_party),
              "external": len(found)}
    return problems, notes, offline, counts


def report_text(problems, notes, counts):
    lines = [f"Helm licence gate: {counts['charts']} charts ({counts['first_party']} first-party, "
             f"{counts['third_party']} third-party), {counts['external']} external charts. "
             f"{len(problems)} violation(s)."]
    by_key = {}
    for key, message in problems:
        by_key.setdefault(key, []).append(message)
    for key in sorted(by_key):
        lines.append(f"FAIL  {key}")
        lines += [f"      - {m}" for m in by_key[key]]
    for key, message in notes:
        lines.append(f"NOTE  {key}: {message}")
    return "\n".join(lines)


def write_summary(path, problems, notes, counts):
    lines = ["## Helm licence gate", "",
             f"**{counts['charts']}** charts ({counts['first_party']} first-party, {counts['third_party']} "
             f"third-party), **{counts['external']}** external charts, **{len(problems)}** violation(s).", ""]
    if problems:
        lines += ["| Chart | Problem |", "|---|---|"]
        lines += [f"| `{k}` | {m.replace('|', '/')} |" for k, m in problems]
    if notes:
        lines += ["", "| Chart | Note |", "|---|---|"] + [f"| `{k}` | {m} |" for k, m in notes]
    with open(path, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n\n")


def repo_root():
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return out.stdout.strip() or os.getcwd()


def affected_keys(repo, path):
    """Map keys an edit can affect: the chart containing the file, an env file, an Argo file, or changed map keys."""
    rel = os.path.relpath(os.path.abspath(path), repo)
    if rel == MAP_FILE:
        try:
            before = yaml.safe_load(subprocess.run(["git", "-C", repo, "show", f"HEAD:{MAP_FILE}"],
                                                   capture_output=True, text=True).stdout) or {}
        except yaml.YAMLError:
            before = {}
        after = load_yaml(os.path.join(repo, MAP_FILE))
        keys = set()
        for section in ("third_party", "external_charts"):
            old, new = before.get(section) or {}, after.get(section) or {}
            keys |= {k for k in set(old) | set(new) if old.get(k) != new.get(k)}
        keys |= set(before.get("first_party") or []) ^ set(after.get("first_party") or [])
        return keys or None
    if rel.startswith(ENV_DIR + os.sep):
        env = load_yaml(path)
        return set(c for c in chart_dirs(repo) if os.path.basename(c) in env)
    if any(rel.startswith(d + os.sep) for d in ARGO_DIRS) and "templates" not in rel.split(os.sep):
        return {rel}
    if rel.startswith(CHARTS_DIR + os.sep):
        directory = os.path.dirname(os.path.join(repo, rel))
        base = os.path.join(repo, CHARTS_DIR)
        while directory.startswith(base) and directory != base:
            if os.path.isfile(os.path.join(directory, "Chart.yaml")):
                return {os.path.relpath(directory, base)}
            directory = os.path.dirname(directory)
    return set()


def run_hook_mode():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    path = (event.get("tool_input") or {}).get("file_path", "")
    if not path.endswith((".yaml", ".yml")):
        return 0
    repo = os.environ.get("CLAUDE_PROJECT_DIR") or repo_root()
    keys = affected_keys(repo, path)
    if keys is not None and not keys:
        return 0
    problems, notes, offline, counts = evaluate(repo, only=keys)
    if offline and all("unreachable" in m for _k, m in problems if "licence_url" in m):
        print("Helm licence gate could not reach the licence links (offline?); CI still checks.\n"
              + "\n".join(offline), file=sys.stderr)
        return 1
    if problems:
        print(report_text(problems, notes, counts)
              + f"\n\nFix the chart or its entry in {MAP_FILE}. For a new third-party chart add component, tag, "
                "tag_source, licence, licence_url (pinned to licence_ref) and licence_sha256 "
                "(`python3 .claude/hooks/check-helm-licences.py --pin <chart>`). If the licence is not Category A or B, "
                "tell the user: it needs a licence-owner exception in .claude/hooks/license-policy.json, which you "
                "must not edit.", file=sys.stderr)
        return 2
    if notes:
        context = "Helm licence gate passed with notes (tell the user):\n" + "\n".join(f"- {k}: {m}" for k, m in notes)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": context}}))
    return 0


def run_pin(repo, keys):
    licence_map = load_yaml(os.path.join(repo, MAP_FILE))
    entries = {**(licence_map.get("third_party") or {}), **(licence_map.get("external_charts") or {})}
    status = 0
    for key in keys:
        entry = entries.get(key)
        if not entry:
            print(f"{key}: no such entry in {MAP_FILE}", file=sys.stderr)
            status = 2
            continue
        print(f"{key}:")
        for url in as_list(entry.get("licence_url")):
            body, error = fetch(url, use_cache=False)
            if error:
                print(f"  {url}: {error}")
                status = 2
                continue
            found = sorted(detect_licences(body.decode("utf-8", errors="replace")))
            print(f"  {url}\n    sha256 {hashlib.sha256(body).hexdigest()}\n    text  {', '.join(found) or '?'}")
    return status


def main(argv):
    repo = os.environ.get("CLAUDE_PROJECT_DIR") or repo_root()
    if not argv:
        return run_hook_mode()
    if argv[0] == "--pin":
        return run_pin(repo, argv[1:])
    if argv[0] == "--all":
        problems, notes, _offline, counts = evaluate(repo)
        print(report_text(problems, notes, counts))
        if len(argv) == 3 and argv[1] == "--summary":
            write_summary(argv[2], problems, notes, counts)
        return 2 if problems else 0
    print("usage: check-helm-licences.py [--all [--summary <md>] | --pin <key> ...]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
