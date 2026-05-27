#!/bin/bash
# MLT変換パイプライン: SHP → GeoJSON → MVT → MLT
# 前提: Java 21+, tippecanoe 2.x, ogr2ogr (GDAL 3.x) が必要
# エンコーダビルド: cd maplibre-tile-spec/java && ./gradlew cli

set -e

BASE="$(cd "$(dirname "$0")" && pwd)"
JAR="$BASE/maplibre-tile-spec/java/mlt-cli/build/libs/encode.jar"

# -------------------------------------------------------
# Step 1: SHP → GeoJSON
# -------------------------------------------------------
echo "[Step 1] SHP → GeoJSON"

ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
  "$BASE/input/GeoJSON/buildings.geojson" \
  "$BASE/input/SHP/583906/BldA3d/"*.shp

ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
  "$BASE/input/GeoJSON/railways.geojson" \
  "$BASE/input/SHP/583906/RailTrCL3d/"*.shp

ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
  "$BASE/input/GeoJSON/roads.geojson" \
  "$BASE/input/SHP/583906/RdCL3d/"*.shp

# -------------------------------------------------------
# Step 1b: レイヤー名をファイル名から取得するためコピー
#          （tippecanoeはファイル名をsource-layer名に使用）
# -------------------------------------------------------
cp "$BASE/input/GeoJSON/buildings.geojson" "$BASE/input/GeoJSON/bldg.geojson"
cp "$BASE/input/GeoJSON/railways.geojson"  "$BASE/input/GeoJSON/rail.geojson"
cp "$BASE/input/GeoJSON/roads.geojson"     "$BASE/input/GeoJSON/road.geojson"

# Step 1c: MLTエンコーダの型混在エラー回避のため
#          整数値の標高フィールドを非整数floatに正規化
python3 - <<'PYEOF'
import json

ELEV_FIELDS = ["medElv", "grElv", "maxElv", "upQrtElv", "loQrtElv"]
import os, sys
src = os.path.join(os.environ.get("BASE", "."), "input/GeoJSON/bldg.geojson")
with open(src) as f:
    gj = json.load(f)
fixed = 0
for feat in gj["features"]:
    props = feat.get("properties") or {}
    for field in ELEV_FIELDS:
        v = props.get(field)
        if isinstance(v, float) and v == int(v):
            props[field] = v + 0.0001
            fixed += 1
with open(src, "w") as f:
    json.dump(gj, f, ensure_ascii=False, separators=(",", ":"))
print(f"  elevation int→float: {fixed} values normalized")
PYEOF

# -------------------------------------------------------
# Step 2: GeoJSON → MVT（tippecanoe）
# -------------------------------------------------------
echo "[Step 2] GeoJSON → MVT (ZL14-16)"

rm -rf "$BASE/docs/mvt"
tippecanoe \
  --no-tile-compression \
  -Z14 -z16 \
  -ad \
  -e "$BASE/docs/mvt" \
  "$BASE/input/GeoJSON/bldg.geojson" \
  "$BASE/input/GeoJSON/rail.geojson" \
  "$BASE/input/GeoJSON/road.geojson" \
  --force

echo "  MVT tiles: $(find "$BASE/docs/mvt" -name "*.pbf" | wc -l)"

# -------------------------------------------------------
# Step 3: MVT → MLT（Java encoder）
# -------------------------------------------------------
echo "[Step 3] MVT → MLT"

rm -rf "$BASE/docs/mlt"
SUCCESS=0; FAIL=0
for pbf in $(find "$BASE/docs/mvt" -name "*.pbf" | sort); do
  rel="${pbf#$BASE/docs/mvt/}"
  dir=$(dirname "$BASE/docs/mlt/$rel")
  mkdir -p "$dir"
  if java -jar "$JAR" --mvt "$pbf" --dir "$dir" --outlines ALL 2>/dev/null; then
    SUCCESS=$((SUCCESS+1))
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $pbf"
  fi
done

echo "  成功: $SUCCESS / 失敗: $FAIL"
echo "  MLT tiles: $(find "$BASE/docs/mlt" -name "*.mlt" | wc -l)"
echo ""
echo "完了。サーバー起動: python3 server.py"
