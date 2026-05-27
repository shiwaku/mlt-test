#!/bin/bash
# MLT変換パイプライン: SHP/GeoJSON → MVT → MLT
# 実行前提: Java 21, tippecanoe, ogr2ogr が必要
# エンコーダビルド: cd maplibre-tile-spec/java && ./gradlew cli

set -e

BASE="$(cd "$(dirname "$0")" && pwd)"
JAR="$BASE/maplibre-tile-spec/java/mlt-cli/build/libs/encode.jar"

# -------------------------------------------------------
# Step 1: SHP → GeoJSON（未変換のレイヤーのみ）
# -------------------------------------------------------
echo "[Step 1] SHP → GeoJSON"

ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
  "$BASE/input/建物/buildings.geojson" \
  "$BASE/input/建物/DKG-SHP-513351-BldA3d-20231031-0001.shp"

ogr2ogr -f GeoJSON -t_srs EPSG:4326 \
  "$BASE/input/軌道の中心線/railways.geojson" \
  "$BASE/input/軌道の中心線/DKG-SHP-513351-RailTrCL3d-20231031-0001.shp"

# 道路中心線は既存の roads.geojson を使用（SHPと同梱）

# -------------------------------------------------------
# Step 2: GeoJSON → MVT（tippecanoe）
# -------------------------------------------------------
echo "[Step 2] GeoJSON → MVT (ZL14-16)"

rm -rf "$BASE/mvt"
tippecanoe \
  --no-tile-compression \
  -Z14 -z16 \
  -ad \
  -e "$BASE/mvt" \
  -l bldg  "$BASE/input/建物/buildings.geojson" \
  -l rail  "$BASE/input/軌道の中心線/railways.geojson" \
  -l road  "$BASE/input/道路中心線/roads.geojson" \
  --force

echo "  MVT tiles: $(find "$BASE/mvt" -name "*.pbf" | wc -l)"

# -------------------------------------------------------
# Step 3: MVT → MLT（Java encoder）
# -------------------------------------------------------
echo "[Step 3] MVT → MLT"

rm -rf "$BASE/mlt"
SUCCESS=0; FAIL=0
for pbf in $(find "$BASE/mvt" -name "*.pbf" | sort); do
  rel="${pbf#$BASE/mvt/}"
  dir=$(dirname "$BASE/mlt/$rel")
  mkdir -p "$dir"
  if java -jar "$JAR" --mvt "$pbf" --dir "$dir" --outlines ALL 2>/dev/null; then
    SUCCESS=$((SUCCESS+1))
  else
    FAIL=$((FAIL+1))
    echo "  FAIL: $pbf"
  fi
done

echo "  成功: $SUCCESS / 失敗: $FAIL"
echo "  MLT tiles: $(find "$BASE/mlt" -name "*.mlt" | wc -l)"
echo ""
echo "完了。サーバー起動: python3 server.py"
