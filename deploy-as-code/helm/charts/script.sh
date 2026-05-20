# from repo root (or adjust paths)
SRC="hpa.yaml"
BASES="accelerators business-services common-services core-services digit-works health-services ifix monitoring sanitation urban utilities"

# safety check
[ -f "$SRC" ] || { echo "Missing $SRC in current dir"; exit 1; }

# copy into every core-services/<service>/templates/
for base in $BASES; do
  [ -d "$base" ] || continue
  find "$base" -mindepth 2 -maxdepth 3 -type d -name templates -print0 \
  | while IFS= read -r -d '' d; do
      cp -f "$SRC" "$d/hpa.yaml"
      echo "copied -> $d/hpa.yaml"
    done
done
