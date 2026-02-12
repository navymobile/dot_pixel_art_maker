---
name: Variable Grid Size Data Specification
id: SPEC_DATA_VARIABLE_GRID
status: draft
version: 1.0
created_at: 2026-02-13
scope: data_db
depends_on: SPEC_QR_PAYLOAD_V3
---

# Variable Grid Size Data Specification

本ドキュメントは、アプリ設定 `AppConfig.dots` によりグリッドサイズを可変としたことに伴う、データ構造および検証ロジックの変更点を定義する。
本仕様は **QR Payload Specification v3** をベースとし、その「固定サイズ（16x16）」制約を緩和・拡張するものである。

## 1. 変更の背景

- **Before**: グリッドサイズは `16x16` (256px) 固定。
- **After**: グリッドサイズは `AppConfig.dots` (例: 21, 24, 32) により可変。ビルド時に決定される。

## 2. Payload構造の変更 (Dynamic Payload)

Payload の構造自体（Header, Body, Footer）は維持するが、**Pixel Data 領域のサイズ** が可変となる。

### 2.1 サイズ定義

| パラメータ          | 定義                      | 旧仕様 (16x16) | 新仕様 (Variable)                |
| :------------------ | :------------------------ | :------------- | :------------------------------- |
| **Grid Size**       | `N`                       | `16`           | **`AppConfig.dots`**             |
| **Pixel Count**     | `N * N`                   | `256`          | **`AppConfig.dots^2`**           |
| **Pixel Data Size** | `Pixel Count * 2` (bytes) | `512` bytes    | **`AppConfig.dots^2 * 2`** bytes |

### 2.2 Payload レイアウト

| オフセット |       サイズ (Bytes)       | 項目          | 内容                  |
| :--------: | :------------------------: | :------------ | :-------------------- |
|     0      | **`AppConfig.dots^2 * 2`** | Pixel Data    | RGBA5551 (Big-endian) |
|    ...     |             1              | Lineage Count | 変更なし              |
|    ...     |        16 \* Count         | Lineage Log   | 変更なし              |
|    ...     |             4              | CRC32         | 変更なし              |

### 2.3 検証ロジック (Validation)

デコード時のペイロード長検証ロジックを以下のように変更する。

- **旧ロジック**: `totalLen < 517` (512 + 1 + 4) ならエラー。
- **新ロジック**: `totalLen < (PixelDataSize + 5)` ならエラー。

$$
\text{MinLength} = (\text{AppConfig.dots}^2 \times 2) + 1 + 4
$$

例: `dots=21` の場合、最小長は `(441 * 2) + 5 = 887` bytes。

## 3. 互換性とリスク

### 3.1 互換性の喪失 (Breaking Change)

- **異なる `AppConfig.dots` 設定でビルドされたアプリ間では、QRコードや保存データの互換性がない。**
  - 例: 21x21版アプリで生成したデータを、16x16版アプリで読み込むと「Payload too short / CRC mismatch」となり失敗する。
  - 逆も同様に失敗する（サイズ不一致）。

### 3.2 運用上の注意

- 将来的に単一アプリ内で「複数のサイズ」をサポートする場合、Payload内に `Grid Size` ヘッダを含めるか、Payload長からサイズを逆算するロジックが必要となる。
- 現状の実装は `AppConfig.dots` という定数に依存しているため、**設定値を変更した際は過去のデータが読み込めなくなる** ことを許容する必要がある。
