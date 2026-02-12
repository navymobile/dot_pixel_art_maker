# 色データライフサイクル (Color Data Lifecycle) - RGBA5551

16x16ドット絵アプリにおける色データの取り扱い、変換、保存形式についての仕様書。
**透明情報を保持するため、保存・交換形式を RGBA5551 に変更する。**

---

## 1. キャンバス描画時の色データ形式 (In-Memory)

編集中およびアプリ動作中にメモリ上で保持される形式。

- **型**: `List<int>` (長さ 256)
- **データ構造**: 32bit int (ARGB形式: `0xAARRGGBB`)
- **Bit数**: 各チャンネル 8bit (計 32bit)
- **Alphaの扱い**:
  - **通常色**: 不透明 (`0xFF......`)。カラーピッカーでAlpha値は選択不可。
  - **消しゴム**: 完全透明 (`0x00000000`) として扱われる。

---

## 2. 内部保持形式 (Model)

`DotModel` クラスが保持するデータ。

- **型**: `List<int>`
- **内容**: キャンバス描画時と同一の ARGB int 配列。

---

## 3. 保存形式 (Storage) & QR交換形式 (Exchange)

Hive (ローカルDB) および QRコードで使用される形式。
共通のロジック (`DotCodec` / `QrService`) で統一する。

- **データ構造**: `Uint16` (Big Endian) 256個 -> `String` (Base64URL Encoded)
- **量子化**: **RGBA5551 (16bit)**
  - **R**: 5bit
  - **G**: 5bit
  - **B**: 5bit
  - **A**: 1bit (0=Transparent, 1=Opaque)

### 変換ロジック (Encode: ARGB32 -> RGBA5551)

**実装の原則**:

- 変換ロジックは `DotCodec` に集約し、`QrService` はそれを呼び出す構成とする（ロジック重複の禁止）。
- ビット演算時は符号拡張事故を防ぐため `>>>` (unsigned shift) を使用する。

```dart
// 1. ARGB32 -> RGBA5551 (Uint16)
int argb32ToRgba5551(int argb) {
  // 符号なしシフト (>>>) を使用
  final a = (argb >>> 24) & 0xFF;
  if (a == 0) return 0x0000; // 完全透明 (RGB無視, A=0)

  final r = (argb >>> 16) & 0xFF;
  final g = (argb >>> 8) & 0xFF;
  final b = argb & 0xFF;

  final r5 = (r >>> 3) & 0x1F;
  final g5 = (g >>> 3) & 0x1F;
  final b5 = (b >>> 3) & 0x1F;

  // A=1 (0x1) を付与
  return (r5 << 11) | (g5 << 6) | (b5 << 1) | 1;
}
```

### 復元ロジック (Decode: RGBA5551 -> ARGB32)

```dart
// 2. RGBA5551 (Uint16) -> ARGB32
int rgba5551ToArgb32(int v) {
  final a1 = v & 1;
  if (a1 == 0) return 0x00000000; // 完全透明

  // 読み出しも念のため >>>
  final r5 = (v >>> 11) & 0x1F;
  final g5 = (v >>> 6) & 0x1F;
  final b5 = (v >>> 1) & 0x1F;

  // 5bit -> 8bit Scaling (High bits replication)
  final r8 = (r5 << 3) | (r5 >>> 2);
  final g8 = (g5 << 3) | (g5 >>> 2);
  final b8 = (b5 << 3) | (b5 >>> 2);

  return (0xFF << 24) | (r8 << 16) | (g8 << 8) | b8;
}
```

### Pack / Unpack (List<int> <-> Base64URL)

- `ByteData` を使用し、**Big Endian** で `Uint16` として書き込む/読み込むこと。
- Base64URLエンコード時はパディング(`=`)を除去し、デコード時は不足分を付与すること。
- **デコード時に長さ検証を行うこと (256px \* 2byte = 512byte 固定)**。

```dart
if (bytes.lengthInBytes != 512) {
  throw FormatException('Invalid pixel payload length: ${bytes.lengthInBytes}');
}
```

---

## 4. 変更による影響

- **データサイズ**: 変更なし (16bit維持)。
- **透明度**: **保持される** (消しゴムで消した箇所が透明のまま保存・復元される)。
- **画質**:
  - Greenの階調が 6bit(64階調) から 5bit(32階調) に減少。
  - ただし、ドット絵においては視覚的な差は極めて小さい。
- **後方互換性**:
  - 既存の RGB565 データは互換性なし。**アプリ開発中のため、互換性は切り捨てる (Wipe推奨)**。

---

## 5. 実装タスク & 実機確認項目

1.  **DotCodec 修正**: 上記ロジックで実装。
2.  **QrService 修正**: 独自の変換ロジックを削除し、`DotCodec` を利用するように変更。
3.  **実機確認**:
    - [ ] **透明維持確認**: 消しゴムで消した箇所が、保存→再読み込み後も「透明」であること（白にならないこと）。
    - [ ] **データ一致**: 同じドット絵を「DB保存→読込」と「QR生成→読込」した際、ピクセルデータが完全一致すること。
    - [ ] **黒色維持**: 「黒 (#000000)」が透明扱いされず、正しく「黒」として復元されること。
