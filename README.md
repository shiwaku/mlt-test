# MLT（MapLibre Tiles）変換・表示テスト

3次元地図データ（SHP/GeoJSON）をMLT形式に変換し、MapLibre GL JS v5で表示する検証環境。

## ディレクトリ構成

```
mlt-test/
├── .gitignore
├── README.md
├── convert.sh                    # 変換パイプライン（SHP→GeoJSON→MVT→MLT）
├── server.py                     # ローカル確認用HTTPサーバー（docs/を配信）
├── input/                        # 入力データ（SHPはgitignore済み）
│   ├── 建物/
│   │   ├── buildings.geojson     # 建物（BldA3d）GeoJSON ※コミット済み
│   │   ├── DKG-SHP-513351-BldA3d-20231031-0001.shp    ※gitignore
│   │   ├── DKG-SHP-513351-BldA3d-20231031-0001.dbf    ※gitignore
│   │   ├── DKG-SHP-513351-BldA3d-20231031-0001.prj    ※gitignore
│   │   └── DKG-SHP-513351-BldA3d-20231031-0001.shx    ※gitignore
│   ├── 軌道の中心線/
│   │   ├── railways.geojson      # 軌道の中心線（RailTrCL3d）GeoJSON ※コミット済み
│   │   ├── DKG-SHP-513351-RailTrCL3d-20231031-0001.shp  ※gitignore
│   │   ├── DKG-SHP-513351-RailTrCL3d-20231031-0001.dbf  ※gitignore
│   │   ├── DKG-SHP-513351-RailTrCL3d-20231031-0001.prj  ※gitignore
│   │   └── DKG-SHP-513351-RailTrCL3d-20231031-0001.shx  ※gitignore
│   └── 道路中心線/
│       ├── roads.geojson         # 道路中心線（RdCL3d）GeoJSON ※コミット済み
│       ├── DKG-SHP-513351-RdCL3d-20231031-0001.shp    ※gitignore
│       ├── DKG-SHP-513351-RdCL3d-20231031-0001.dbf    ※gitignore
│       ├── DKG-SHP-513351-RdCL3d-20231031-0001.prj    ※gitignore
│       └── DKG-SHP-513351-RdCL3d-20231031-0001.shx    ※gitignore
├── maplibre-tile-spec/           # エンコーダリポジトリ（gitignore・要clone）
└── docs/                         # GitHub Pages配信ディレクトリ
    ├── index.html                # MVT vs MLT 比較ページ
    ├── stats.json                # タイルサイズ統計（事前計算済み）
    ├── mvt/                      # MVTタイル ZL14-16（594タイル）
    │   └── {z}/{x}/{y}.pbf
    └── mlt/                      # MLTタイル ZL14-16（594タイル）
        └── {z}/{x}/{y}.mlt
```

> **データ概要**：国土地理院 3次元地図データ（地図情報レベル2500）メッシュコード 513351（広島県西部）、取得日 2023-10-31

## 前提条件

| ツール | バージョン | 用途 |
|---|---|---|
| Java | 21以上 | MLTエンコーダ実行 |
| tippecanoe | 2.x | GeoJSON → MVT変換 |
| ogr2ogr (GDAL) | 3.x | SHP → GeoJSON変換 |
| Python | 3.x | ローカルサーバー |

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
ogr2ogr -f GeoJSON -t_srs EPSG:4326 input/建物/buildings.geojson input/建物/*.shp
ogr2ogr -f GeoJSON -t_srs EPSG:4326 input/軌道の中心線/railways.geojson input/軌道の中心線/*.shp
# 道路中心線は roads.geojson として配置済み
```

#### Step 2: GeoJSON → MVT（tippecanoe）

```bash
tippecanoe \
  --no-tile-compression \
  -Z14 -z16 \
  -ad \
  -e mvt \
  -l bldg  input/建物/buildings.geojson \
  -l rail  input/軌道の中心線/railways.geojson \
  -l road  input/道路中心線/roads.geojson \
  --force
```

- `--no-tile-compression`: MLTエンコーダが圧縮PBFを扱えないため必須
- `-ad`: タイルサイズ超過時に地物を間引く（高密度データ対応）
- レイヤー名: `bldg` / `rail` / `road`

#### Step 3: MVT → MLT（Java encoder）

```bash
JAR=maplibre-tile-spec/java/mlt-cli/build/libs/encode.jar
for pbf in $(find mvt -name "*.pbf"); do
  dir=$(dirname "mlt/${pbf#mvt/}")
  mkdir -p "$dir"
  java -jar "$JAR" --mvt "$pbf" --dir "$dir" --outlines ALL
done
```

## 表示確認

```bash
python3 server.py
```

ブラウザで `http://localhost:8765/index.html` を開く。

MapLibre GL JS v5（`"encoding": "mlt"` 対応）でMLTタイルを読み込み、建物・道路・軌道を表示する。

## 検証結果メモ

### ファイルサイズ比較（テストデータ：地図情報レベル2500、メッシュ513351）

データ：3次元地図（建物・道路中心線・軌道の中心線）、ZL14〜16、594タイル

#### 全体サマリー

| 指標 | MVT（非圧縮） | MLT | 比率 |
|---|---:|---:|---|
| 合計サイズ | 18,849 KB | 10,413 KB | **55.2%（▼44.8%）** |
| 平均タイルサイズ | 32,494 B | 17,952 B | 55.2% |
| 最大タイルサイズ | 383,756 B | 206,223 B | 53.7% |

#### ズームレベル別

| ZL | タイル数 | MVT合計 | MLT合計 | 削減率 |
|---|---:|---:|---:|---|
| 14 | 35 | 6,547 KB | 3,477 KB | ▼46.9% |
| 15 | 120 | 7,235 KB | 4,062 KB | ▼43.8% |
| 16 | 439 | 5,067 KB | 2,874 KB | ▼43.3% |

#### gzip圧縮MVTとの比較

| 形式 | サイズ | MVT非圧縮比 |
|---|---:|---|
| MVT（非圧縮） | 18.41 MB | 基準 |
| **MLT** | **10.17 MB** | **55.2%（▼44.8%）** |
| MVT（gzip圧縮） | 6.17 MB | 33.5% |

> **注意**: gzip圧縮済みMVTと比べるとMLTは約1.65倍大きい。MLTエンコーダが非圧縮MVTを入力とする制約上、「非圧縮MVT vs MLT」が唯一成立する比較条件。公称「最大6倍の圧縮率向上」との乖離は、比較条件・データ種別・圧縮設定の違いによるものと考えられる。

#### タイル個別サンプル（ZL16）

| タイル | MVT | MLT | 増減 |
|---|---:|---:|---|
| 地物多（例） | 14,763 B | 8,527 B | **▼42%** |
| 地物中（例） | 3,392 B | 2,632 B | ▼22% |
| 地物少（例） | 432 B | 636 B | ▲47% |

小タイル（地物数が少ない）はMLTのヘッダーオーバーヘッドで逆に増加する傾向あり。

### 技術的な注意点

- tippecanoeの `--no-tile-compression` が必須（圧縮PBFはエンコーダがエラー）
- プロパティの型が地物間で混在する場合、MLTエンコーダがエラーになる（事前確認推奨）
- Java 21以上が必須（Java 17ではビルド不可）

## 参考

- [MapLibre Tile Spec](https://maplibre.org/maplibre-tile-spec/)
- [maplibre/maplibre-tile-spec (GitHub)](https://github.com/maplibre/maplibre-tile-spec)
- [MapLibre Tiles(MLT)を触ってみた - Qiita](https://qiita.com/sleepy__keita/items/32e87b8bf6f5dcfe9fa2)
- [plateau-lod2-mvtをMLTに変換してmaplibre-gl-jsで表示してみた - Qiita](https://qiita.com/frogcat/items/0287ab9f931a98088b0a)
