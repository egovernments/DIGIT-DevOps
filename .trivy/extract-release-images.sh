#!/usr/bin/env bash
# Resolve the last N distinct RELEASE versions for every repo in a Docker Hub org
# and write .trivy/release-images.yaml (repo -> [tags]). The registry scan reads
# that manifest (registries.yaml: from_manifest) to scan every release build.
#
# A "release" tag matches ^v<major>.<minor>.<patch>  (DIGIT's release convention,
# e.g. v1.2.8-9fde481c92-2). Branch/dev/Dockerfile tags and third-party mirror
# tags (17-jdk, 3.5.0, ...) don't match, so they drop out automatically.
# For each version only the newest build is kept, and the newest N versions taken.
#
# Usage:   .trivy/extract-release-images.sh [output.yaml]
# Env:     DOCKER_ORG (default egovio), RELEASE_TAGS_PER_REPO (default 5),
#          DOCKERHUB_USERNAME + DOCKERHUB_TOKEN (else falls back to ~/.docker/config.json)
# Needs:   curl, jq, python3
set -euo pipefail
OUT="${1:-$(cd "$(dirname "$0")" && pwd)/release-images.yaml}"
ORG="${DOCKER_ORG:-egovio}"
N="${RELEASE_TAGS_PER_REPO:-5}"

if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
  U="$DOCKERHUB_USERNAME"; P="$DOCKERHUB_TOKEN"
else
  creds=$(python3 -c "import json,os,base64;a=json.load(open(os.path.expanduser('~/.docker/config.json')))['auths']['https://index.docker.io/v1/']['auth'];print(base64.b64decode(a).decode())")
  U="${creds%%:*}"; P="${creds#*:}"
fi
tok=$(curl -fsSL -H 'Content-Type: application/json' -d "{\"username\":\"$U\",\"password\":\"$P\"}" https://hub.docker.com/v2/users/login/ | jq -r '.token')
[ -n "$tok" ] && [ "$tok" != "null" ] || { echo "Docker Hub login failed" >&2; exit 1; }
export tok ORG
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

echo "Enumerating $ORG repositories..." >&2
url="https://hub.docker.com/v2/repositories/${ORG}/?page_size=100"; : > "$tmp/repos.txt"
while [ -n "$url" ] && [ "$url" != "null" ]; do
  page=$(curl -fsSL -H "Authorization: JWT $tok" "$url")
  echo "$page" | jq -r '.results[].name' >> "$tmp/repos.txt"
  url=$(echo "$page" | jq -r '.next')
done
echo "  $(wc -l < "$tmp/repos.txt") repos" >&2

mkdir -p "$tmp/tags"; export tmp
fetch() {
  local r="$1"; : > "$tmp/tags/$r.txt"
  for p in 1 2 3 4 5; do
    n=$(curl -fsSL -H "Authorization: JWT $tok" "https://hub.docker.com/v2/repositories/${ORG}/$r/tags/?page_size=100&page=$p&ordering=last_updated" 2>/dev/null | jq -r '.results[].name' 2>/dev/null)
    [ -z "$n" ] && break
    printf '%s\n' "$n" >> "$tmp/tags/$r.txt"
    [ "$(printf '%s' "$n" | wc -l)" -lt 100 ] && break
  done
}
export -f fetch
echo "Listing tags..." >&2
xargs -P 12 -I{} bash -c 'fetch "$@"' _ {} < "$tmp/repos.txt" 2>/dev/null

python3 - "$tmp/tags" "$OUT" "$N" <<'PY'
import re, glob, os, sys, collections
d, out, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
verrx = re.compile(r'^(v\d+\.\d+\.\d+(?:-beta)?)')
m = {}
for f in glob.glob(os.path.join(d, '*.txt')):
    repo = os.path.basename(f)[:-4]
    seen = collections.OrderedDict()          # version -> newest build tag
    for line in open(f):
        t = line.strip(); mm = verrx.match(t)
        if not mm: continue
        v = mm.group(1)
        if v not in seen: seen[v] = t          # first seen (newest pushed) build of this version
        if len(seen) >= N: break
    if seen: m[repo] = list(seen.values())
L = [f"# Auto-generated: last {N} distinct release versions (^v<maj>.<min>.<patch> tags)",
     "# per egovio repo on Docker Hub. Regenerate: .trivy/extract-release-images.sh",
     "# Consumed by the registry scan via registries.yaml (from_manifest).", "images:"]
for r in sorted(m):
    L.append(f"  {r}:")
    for t in m[r]: L.append(f"    - {t}")
open(out, "w").write("\n".join(L) + "\n")
print(f"  wrote {out}: {len(m)} repos, {sum(len(v) for v in m.values())} tags", file=sys.stderr)
PY
echo "Done." >&2
