# AGENTS.md

Project: ドット絵共有アプリ
Platform: Flutter (Prototype)

---

## 1. Project Philosophy

このアプリは「会って受け取り、出自が残る」16×16ドット絵共有アプリである。

### 不変原則

- 16×16固定
- genは劣化ではなく人のつながりの長さ
- 交換は対面（QR）を前提
- SNS機能を導入しない
- 機能を増やしすぎない

---

## 2. Architectural Principles

### Separation of Concerns

- UIとドメインロジックを分離する
- 描画(CustomPainter)はデータに依存するのみ
- ビジネスロジックはdomain層に配置する

### Data Structure Rules

- ドットデータは1次元配列 (List<int>) 256要素
- パレットはインデックス方式
- QR格納用データは軽量化を意識

---

## 3. Coding Constraints

- 不要な抽象化を行わない
- MVPに含まれない機能を実装しない
- UIを過剰に装飾しない
- 状態管理はシンプルに保つ
- **最小差分で実装する**: 変更は必要な箇所のみに限定し、周囲のコードを巻き込んだ書き換えを行わない。既存コードの削除・移動が意図しない副作用を生まないよう、差分を最小に保つこと（**重要**）

---

## 4. Folder Structure

lib/
├─ domain/
│ ├─ dot_model.dart
│ ├─ exchange_model.dart
│ └─ gen_logic.dart
├─ ui/
│ ├─ canvas/
│ ├─ profile/
│ └─ exchange/
└─ infra/
├─ qr_service.dart
└─ storage_service.dart

---

## 5. MVP Definition

MVP成立条件:

1. 16×16ドットを描ける
2. ドットをデータ化できる
3. QRで交換できる
4. genが増加する
5. オリジナル作者に辿れる

---

## 6. Non-Goals

- いいね機能
- タイムライン
- フォロー機能
- ランキング
- 通知システム

---

## 7. AI Instruction Rule

AIは以下を優先すること:

- 思想の純度を守る
- 不要な機能追加を提案しない
- 技術的合理性を優先する
- MVPを逸脱しない
