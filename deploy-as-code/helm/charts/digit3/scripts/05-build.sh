#!/usr/bin/env bash
# 05 — generate the bundle module, build both images from the same tree, load
# them into the node's containerd (INSTALL.md §4.1). No registry needed.
# Usage: ./05-build.sh <path-to-digit3-repo>
source "$(dirname "$0")/lib.sh"
load_env

[ $# -eq 1 ] || die "usage: $0 <path-to-digit3-repo>"
DIGIT3="$(cd "$1" && pwd)"
MANIFEST="$DIGIT3/src/bundles/dev-bundle.package.yaml"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST (is this the digit3 repo on the modulith branch?)"

note "generating the bundle module from the manifest"
OUT=$(cd "$DIGIT3" && python3 src/bundles/generate_bundle.py src/bundles/dev-bundle.package.yaml)
echo "$OUT" | tail -3
echo "$OUT" | grep -q "no unresolved property conflicts" || die "generate_bundle.py reported property conflicts — fix the manifest before building"

TAG="modulith-$(git -C "$DIGIT3" rev-parse --short HEAD)"
note "building egovio/dev-bundle:$TAG and egovio/dev-bundle-db:$TAG (same tree — Flyway checksums must match)"
(cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/dev-bundle:$TAG" -f src/bundles/dev-bundle/Dockerfile .)
(cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/dev-bundle-db:$TAG" src/bundles/dev-bundle/src/main/resources/db)

note "loading both images into the node's containerd"
docker save "egovio/dev-bundle:$TAG"    | vm_ssh 'sudo k3s ctr images import -'
docker save "egovio/dev-bundle-db:$TAG" | vm_ssh 'sudo k3s ctr images import -'

echo "$TAG" > "$SCRIPT_DIR/.last-build-tag"
note "built and loaded: $TAG (recorded in scripts/.last-build-tag)"
next "./06-deploy.sh $DIGIT3"
