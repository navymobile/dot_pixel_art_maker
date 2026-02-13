# DotCodec v4 Specification

## 概要

`DotCodec v4` は、可変長および異なるエンコーディング形式をサポートするための新しいペイロード仕様である。
従来の `v3` (RGBA5551 固定) との互換性を考慮し、まず `v4` としてデコードを試み、失敗した場合に `v3` としてフォールバックする戦略を採用する。

## データ構造

### 1. ヘッダ (2 bytes)

先頭の2バイトはバージョンとエンコーディングタイプを識別するために使用する。

| Offset | Len | Type  | Description                                        |
| :----- | :-- | :---- | :------------------------------------------------- |
| 0      | 1   | uint8 | **Version (v)**: `4` 固定                          |
| 1      | 1   | uint8 | **Encoding (e)**: `1` (RGBA5551) or `2` (Indexed8) |

### 2. ペイロードボディ (Variable Length)

エンコーディングタイプ (`e`) によってサイズと内容が異なるピクセルデータ、および共通の系統情報（Lineage）が含まれる。

#### Type 1: RGBA5551 (Legacy Compatible)

- **Pixels**: 512 bytes (2 bytes \* 256 pixels)
- **Pixels**: 512 bytes (2 bytes \* 256 pixels)
  - 16-bit integer (RGBA 5-5-5-1) Big Endian
- **Count**: 1 byte (Lineage count `N`, max 255)
- **Lineage**: 16 \* `N` bytes (16 bytes per entry)

#### Type 2: Indexed8 (New, High Compression)

- **Pixels**: 256 bytes (1 byte \* 256 pixels)
  - 8-bit integer (Index)
  - `0`: Transparent (Alpha = 0)
  - `1..255`: RGB332 Quantized Color
    - Calculate: `1 + (R3<<5 | G3<<2 | B2)`
    - **Important**: `ColorValue` must be `0..254` (Index `1..255`). If the calculated index exceeds 255 (which is theoretically 256 for pure white if logic is simpler), it must be clamped to 255.
  - パレットデータはペイロードに含まない（固定ロジックで復元）。

* **Count**: 1 byte (Lineage count `N`, max 255)
* **Lineage**: 16 \* `N` bytes (16 bytes per entry)

### 3. チェックサム (4 bytes)

データの整合性を検証するための CRC32。

| Offset | Len | Type   | Description                                    |
| :----- | :-- | :----- | :--------------------------------------------- |
| End-4  | 4   | uint32 | **CRC32**: Big Endian of Header + Payload Body |

- **計算対象**: ヘッダ(2 bytes) + ペイロードボディの全データ（`data[0 .. totalLayoutLength - 4]`）。
- **除外対象**: 自分自身（末尾のCRC32フィールド）。

## 全体レイアウト

```
[ v (1) ][ e (1) ][ Pixels (Var) ][ Count (1) ][ Lineage (16*N) ][ CRC32 (4) ]
```

## エンコーディング / デコーディング フロー

### Encoding (v4)

1.  `v`=4 をセット。
2.  指定された `e` (1 or 2) をセット。
3.  ピクセルデータをエンコードして追加。
4.  Lineageデータを追加。
5.  ここまでのバイト列に対して CRC32 を計算し、末尾に付与。
6.  Base64URL (paddingなし) でエンコード。

### Decoding (Strategy)

前方互換性（既存の v3 データの読み込み）を維持するため、以下の手順でデコードを行う。

1.  **Try v4 Decode:**
    - Base64URLデコードを行う。
    - データ長が最小要件（Header + MinPixels + Count + CRC）を満たすか確認。
      - `e=1 (RGBA5551)`: 2 + 512 + 1 + 4 = **519 bytes**
      - `e=2 (Indexed8)`: 2 + 256 + 1 + 4 = **263 bytes**
    - 先頭バイトが `4` であるか確認。
    - 末尾の CRC32 を検証（計算対象: 末尾4バイトを除く全データ）。
    - **CRC一致**: `v4` として確定。`e` の値に従ってピクセルを展開。
    - **CRC不一致 / 形式不正**: 手順2へ。

2.  **Fallback to v3 (Legacy) Decode:**
    - 既存の `v3` ロジック（Headerなし、固定512bytesピクセル + ... + CRC）で検証を行う。
    - CRC一致なら `v3` として確定。
    - 不一致なら `FormatException` をスロー（データ破損）。

## 補足: インデックス化ロジック (RGB332 conversion)

- **Encode (ARGB -> Index):**
  - Alpha == 0 -> `0`
  - Alpha != 0 ->
    - R (8bit) -> R3 (3bit) : `(r * 7 + 127) ~/ 255`
    - G (8bit) -> G3 (3bit) : `(g * 7 + 127) ~/ 255`
    - B (8bit) -> B2 (2bit) : `(b * 3 + 127) ~/ 255`
    - ColorValue (8bit) : `(R3 << 5) | (G3 << 2) | B2`
    - Index : `min(ColorValue + 1, 255)` (Clamp to 1..255)

- **Decode (Index -> ARGB):**
  - Index == 0 -> `0x00000000` (Transparent)
  - Index != 0 ->
    - ColorValue : `Index - 1`
    - R3 : `(ColorValue >> 5) & 0x07`
    - G3 : `(ColorValue >> 2) & 0x07`
    - B2 : `ColorValue & 0x03`
    - **Logic (Fixed Scaling)**:
      - R8 : `(R3 * 255) ~/ 7`
      - G8 : `(G3 * 255) ~/ 7`
      - B8 : `(B2 * 255) ~/ 3`
    - ARGB : `0xFF000000 | (R8 << 16) | (G8 << 8) | B8`

**注意:** RGB332の復元時、ビットシフトだけでは最大値（255）に戻らない場合があるため、スケーリング計算 `(val * 255) / max` を使用することを推奨する。

**Note on Fallback Strategy:**
もし v4 decode 処理中にエラー（CRC不一致、データ長不足、ヘッダ不正、`version != 4` など）が発生した場合、例外はすべて `FormatException` として上位へ伝播させる。
呼び出し元はこれをキャッチし、**必ず `v3 (legacy)` ロジックでのデコードを試みる**こと。
