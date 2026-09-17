#!/usr/bin/env bash
# OPTIONAL local image build for the BUNDLE shapes — the normal path is the
# GitHub Actions images (egovio/*:modulith-<sha>) consumed via DIGIT_TAG, and
# the per-service shape has no local-build path at all (16 per-service images
# come from Actions only). Use this when iterating on bundle code offline:
# regenerates the bundle modules from the manifest, builds every bundle in it
# plus its db-init image from the same tree (Flyway checksums must match),
# side-loads them into the node's containerd, and records the tag for
# 06-deploy.sh.
#
#   ./05-build.sh <path-to-digit3-repo> [manifest (default dev-bundle.package.yaml)]
source "$(dirname "$0")/lib.sh"
load_env
[ $# -ge 1 ] || die "usage: $0 <path-to-digit3-repo> [manifest yaml under src/bundles/]"
DIGIT3="$(cd "$1" && pwd)"
MANIFEST="$DIGIT3/src/bundles/${2:-dev-bundle.package.yaml}"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST (is this the digit3 repo on the modulith branch?)"

note "generating the bundle modules from the manifest"
OUT=$(cd "$DIGIT3" && python3 src/bundles/generate_bundle.py "$MANIFEST")
echo "$OUT" | tail -3
echo "$OUT" | grep -q "no unresolved property conflicts" || die "generate_bundle.py reported property conflicts — fix the manifest before building"

TAG="modulith-$(git -C "$DIGIT3" rev-parse --short HEAD)"
BUNDLES=$(python3 -c "import yaml,sys; print(' '.join(b['outputDir'] for b in yaml.safe_load(open('$MANIFEST'))['bundles']))")
for b in $BUNDLES; do
  note "building egovio/$b:$TAG and egovio/$b-db:$TAG"
  (cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/$b:$TAG" -f "src/bundles/$b/Dockerfile" .)
  (cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/$b-db:$TAG" "src/bundles/$b/src/main/resources/db")
  note "loading egovio/$b images into the node's containerd"
  docker save "egovio/$b:$TAG"    | vm_ssh 'sudo k3s ctr images import -'
  docker save "egovio/$b-db:$TAG" | vm_ssh 'sudo k3s ctr images import -'
done
echo "$TAG" > "$SCRIPT_DIR/.last-build-tag"
note "built and loaded: $TAG (recorded in scripts/.last-build-tag)"
next "./06-deploy.sh $DIGIT3 <dev-bundle|domain-split>"
