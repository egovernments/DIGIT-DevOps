#!/usr/bin/env bash
# 05 — ensure the shape's images are available, Docker-Hub-first (INSTALL.md
# §4.1). Published egovio images exist for every shape at the tag pinned in
# the environment file, so out of the box this script verifies and exits —
# nothing is built. Only when a tag is missing from the hub (e.g. you want to
# run your own digit3 HEAD) does it build from source and import into the
# node's containerd.
#
# Usage: ./05-build.sh [--shape single-container|domain-bundles|per-service] <digit3-path> [TAG]
#   TAG default: the published tag pinned in the env file (modulith-39f619d).
#   A local build always tags modulith-<digit3 short HEAD> — app and db images
#   must come from ONE tree (Flyway checksums), so foreign tags are refused.
source "$(dirname "$0")/lib.sh"
load_env

parse_args "$@"
SHAPE="${SHAPE_FLAG:-$(current_shape)}"
shape_helmfile "$SHAPE" >/dev/null   # validates the name

[ ${#POSARGS[@]} -ge 1 ] || die "usage: $0 [--shape <shape>] <digit3-path> [TAG]"
DIGIT3="$(cd "${POSARGS[0]}" && pwd)"
TAG="${POSARGS[1]:-$PUBLISHED_TAG}"
MANIFEST="$(shape_manifest "$DIGIT3" "$SHAPE")"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

if [ "$SHAPE" = "per-service" ]; then
  # Per-service images are pinned per block in the env file (mixed registries
  # and tags from the reference deployment) — verify they exist, don't build.
  note "shape: per-service — verifying the images pinned in azure-k3s.yaml"
  FAIL=0
  while read -r block ref; do
    if hub_has "$ref"; then echo "    hub: $ref  ($block)"; else echo "    MISSING: $ref  ($block)"; FAIL=1; fi
  done < <(per_service_images)
  [ "$FAIL" -eq 0 ] || die "some pinned per-service images are missing — fix the pins in azure-k3s.yaml (these are published reference builds, not locally buildable tags)"
  note "all per-service images published — nothing to build (k3s pulls on deploy)"
  next "./06-deploy.sh --shape per-service $DIGIT3"
  exit 0
fi

note "shape: $SHAPE — checking Docker Hub for egovio images at :$TAG"
MISSING=()
for repo in $(shape_bundles "$SHAPE"); do
  for r in "$repo" "$repo-db"; do
    if hub_has "$r:$TAG"; then echo "    hub: egovio/$r:$TAG"; else echo "    MISSING: egovio/$r:$TAG"; MISSING+=("$r"); fi
  done
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "$TAG" > "$SCRIPT_DIR/.last-build-tag"
  note "all images published — nothing to build (k3s pulls on deploy)"
  next "./06-deploy.sh --shape $SHAPE $DIGIT3"
  exit 0
fi

BUILT_TAG="modulith-$(git -C "$DIGIT3" rev-parse --short HEAD)"
if [ "$TAG" != "$PUBLISHED_TAG" ] && [ "$TAG" != "$BUILT_TAG" ]; then
  die "tag $TAG is not on the hub and doesn't match this digit3 tree ($BUILT_TAG) — a local build must come from one tree"
fi
note "building missing images from $DIGIT3 at :$BUILT_TAG"

note "generating bundle modules from the manifest"
OUT=$(cd "$DIGIT3" && python3 src/bundles/generate_bundle.py "$MANIFEST")
echo "$OUT" | tail -2
echo "$OUT" | grep -q "no unresolved property conflicts" || die "generate_bundle.py reported property conflicts"
for b in $(shape_bundles "$SHAPE"); do
  (cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/$b:$BUILT_TAG" -f "src/bundles/$b/Dockerfile" .)
  (cd "$DIGIT3" && docker buildx build --platform linux/amd64 --load -t "egovio/$b-db:$BUILT_TAG" "src/bundles/$b/src/main/resources/db")
  docker save "egovio/$b:$BUILT_TAG"    | vm_ssh 'sudo k3s ctr images import -'
  docker save "egovio/$b-db:$BUILT_TAG" | vm_ssh 'sudo k3s ctr images import -'
done

echo "$BUILT_TAG" > "$SCRIPT_DIR/.last-build-tag"
note "built and loaded :$BUILT_TAG (recorded in scripts/.last-build-tag)"
next "./06-deploy.sh --shape $SHAPE $DIGIT3"
