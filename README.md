# MLT（MapLibre Tile）変換・表示テスト

3次元地図データ（SHP/GeoJSON）をMLT形式に変換し、MapLibre GL JS v5で表示する検証環境。

## ディレクトリ構成

```
mlt-test/
├── .gitignore
├── README.md
├── convert.sh                    # 変換パイプライン（SHP→GeoJSON→MVT→MLT）
├── server.py                     # ローカル確認用HTTPサーバー（docs/を配信）
├── input/
│   ├── 000276862.pdf             # 3次元地図データ仕様書
│   ├── GeoJSON/
│   │   ├── buildings.geojson     # 建物（BldA3d）GeoJSON ※コミット済み
│   │   ├── railways.geojson      # 軌道の中心線（RailTrCL3d）GeoJSON ※コミット済み
│   │   ├── roads.geojson         # 道路中心線（RdCL3d）GeoJSON ※コミット済み
│   │   ├── bldg.geojson          # tippecanoe用（buildingsのコピー＋標高正規化）
│   │   ├── rail.geojson          # tippecanoe用（railwaysのコピー）
│   │   └── road.geojson          # tippecanoe用（roadsのコピー）
│   └── SHP/583906/
│       ├── BldA3d/               # 建物ポリゴン（BldA3d）SHP ※gitignore
│       ├── RailTrCL3d/           # 軌道の中心線（RailTrCL3d）SHP ※gitignore
│       └── RdCL3d/               # 道路中心線（RdCL3d）SHP ※gitignore
├── maplibre-tile-spec/           # エンコーダリポジトリ（gitignore・要clone）
└── docs/                         # GitHub Pages配信ディレクトリ
    ├── index.html                # MVT vs MLT 比較ページ（3D建物表示）
    ├── pale.json                 # 背景地図スタイル（地理院最適化ベクトルタイル・淡色）
    ├── stats.json                # タイルサイズ統計（事前計算済み）
    ├── mvt/                      # MVTタイル ZL14-16（58タイル）
    │   └── {z}/{x}/{y}.pbf
    └── mlt/                      # MLTタイル ZL14-16（58タイル）
        └── {z}/{x}/{y}.mlt
```

> **データ概要**：国土地理院 3次元地図データ（地図情報レベル2500）メッシュコード 583906（山形県鶴岡市付近）、取得日 2026-03-17

## 前提条件

| ツール | バージョン | 用途 |
|---|---|---|
| Java | 21以上 | MLTエンコーダ実行 |
| tippecanoe | 2.x | GeoJSON → MVT変換 |
| ogr2ogr (GDAL) | 3.x | SHP → GeoJSON変換 |
| Python | 3.x | 標高正規化・ローカルサーバー |

### Ubuntu / WSL2でのインストール

```bash
sudo apt-get install -y openjdk-21-jdk tippecanoe gdal-bin
```

## セットアップ

### 1. リポジトリのクローンとエンコーダのビルド

```bash
git clone --depth=1 https://github.com/maplibre/maplibre-tile-spec.git
cd maplibre-tile-spec/java
chmod +x gradlew
./gradlew cli
cd ../..
```

ビルド成果物: `maplibre-tile-spec/java/mlt-cli/build/libs/encode.jar`

## 変換手順

### 一括実行

```bash
bash convert.sh
```

### 個別実行

#### Step 1: SHP → GeoJSON

```bash
ogr2ogr -f GeoJSON -t_srs EPSG:4326 input/GeoJSON/buildings.geojson input/SHP/583906/BldA3d/*.shp
ogr2ogr -f GeoJSON -t_srs EPSG:4326 input/GeoJSON/railways.geojson  input/SHP/583906/RailTrCL3d/*.shp
ogr2ogr -f GeoJSON -t_srs EPSG:4326 input/GeoJSON/roads.geojson     input/SHP/583906/RdCL3d/*.shp
```

#### Step 1b: tippecanoe用コピー＆標高フィールド正規化

```bash
cp input/GeoJSON/buildings.geojson input/GeoJSON/bldg.geojson
cp input/GeoJSON/railways.geojson  input/GeoJSON/rail.geojson
cp input/GeoJSON/roads.geojson     input/GeoJSON/road.geojson
```

tippecanoeはファイル名をsource-layer名として使用するため、レイヤー名に合わせてコピー。

整数値の標高フィールド（例: `15.0`）にMLTエンコーダがINT/DOUBLE型混在エラーを起こすため、+0.0001のオフセットで全floatに正規化する（表示誤差 < 1mm）。

#### Step 2: GeoJSON → MVT（tippecanoe）

```bash
tippecanoe \
  --no-tile-compression \
  -Z14 -z16 \
  -ad \
  -e docs/mvt \
  input/GeoJSON/bldg.geojson \
  input/GeoJSON/rail.geojson \
  input/GeoJSON/road.geojson \
  --force
```

- `--no-tile-compression`: MLTエンコーダが非圧縮PBFを要求するため必須
- `-ad`: タイルサイズ超過時に地物を間引く（高密度データ対応）
- **`-l` フラグ不使用**: tippecanoe 2.xの `-l name` はGLOBAL指定（全入力ファイルに適用）のため、ファイル名でsource-layer名を設定する
- source-layer名: `bldg` / `rail` / `road`（ファイル名から自動設定）

#### Step 3: MVT → MLT（Java encoder）

```bash
JAR=maplibre-tile-spec/java/mlt-cli/build/libs/encode.jar
for pbf in $(find docs/mvt -name "*.pbf"); do
  dir=$(dirname "docs/mlt/${pbf#docs/mvt/}")
  mkdir -p "$dir"
  java -jar "$JAR" --mvt "$pbf" --dir "$dir" --outlines ALL
done
```

## 表示確認

```bash
python3 server.py
```

ブラウザで `http://localhost:8765/index.html` を開く（WSL2の場合は`http://<WSL2-IP>:8765/`）。

MapLibre GL JS v5（`"encoding": "mlt"` 対応）でMLTタイルを読み込み、建物3D・道路・軌道を表示する。背景地図は地理院最適化ベクトルタイル（淡色、`pale.json`）を使用。

## 検証結果メモ

### ファイルサイズ比較（テストデータ：地図情報レベル2500、メッシュ583906）

データ：3次元地図（建物・道路中心線・軌道の中心線）、ZL14〜16、58タイル

#### 全体サマリー

| 指標 | MVT（非圧縮） | MLT | 比率 |
|---|---:|---:|---|
| 合計サイズ | 4,503 KB | 3,058 KB | **67.9%（▼32.1%）** |
| 平均タイルサイズ | 79,506 B | 54,000 B | 67.9% |
| 最大タイルサイズ | 370 KB | 257 KB | 69.5% |

#### ズームレベル別

| ZL | タイル数 | MVT合計 | MLT合計 | 削減率 |
|---|---:|---:|---:|---|
| 14 | 4 | ※ | ※ | ※ |
| 15 | 12 | ※ | ※ | ※ |
| 16 | 42 | ※ | ※ | ※ |

※ 詳細はdocs/stats.jsonを参照

#### gzip圧縮MVTとの比較

| 形式 | サイズ | MVT非圧縮比 |
|---|---:|---|
| MVT（非圧縮） | 4.50 MB | 基準 |
| **MLT** | **3.06 MB** | **67.9%（▼32.1%）** |
| MVT（gzip圧縮） | 参考値 | 〜33% |

> **注意**: MLTはgzip等の汎用圧縮ではなく、カラム指向レイアウト＋型別軽量エンコーディング（RLE / Delta / FastPFOR / FSST / Dictionary等）を形式内に組み込んでサイズを削減している。gzip圧縮済みMVTと比べるとMLTは大きくなる可能性がある。MLTエンコーダが非圧縮MVTを入力とする制約上、「非圧縮MVT vs MLT」が唯一成立する比較条件。

### 技術的な注意点

- tippecanoeの `--no-tile-compression` が必須（圧縮PBFはエンコーダがエラー）
- **tippecanoe 2.x の `-l name` はGLOBALフラグ**（全ファイルに適用）。複数レイヤーはファイル名でsource-layer名を制御する
- 整数値の標高フィールドがMVT内でINT/DOUBLE混在 → MLTエンコーダが型エラー。GeoJSON側で+0.0001オフセットを追加して回避
- Java 21以上が必須（Java 17ではビルド不可）

## 参考

- [MapLibre Tile Spec](https://maplibre.org/maplibre-tile-spec/)
- [maplibre/maplibre-tile-spec (GitHub)](https://github.com/maplibre/maplibre-tile-spec)
- [MapLibre Tile(MLT)を触ってみた - Qiita](https://qiita.com/sleepy__keita/items/32e87b8bf6f5dcfe9fa2)
- [plateau-lod2-mvtをMLTに変換してmaplibre-gl-jsで表示してみた - Qiita](https://qiita.com/frogcat/items/0287ab9f931a98088b0a)
