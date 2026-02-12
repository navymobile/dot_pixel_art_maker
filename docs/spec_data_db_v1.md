---
name: Data & Database Specification v1.2
id: SPEC_DATA_DB_V1
status: draft
version: 1.2
created_at: 2026-02-12
updated_at: 2026-02-12
scope: data_db
depends_on: SPEC_QR_PAYLOAD_V3
---

# Data & Database Specification v1.2

本仕様書は、16×16ドット絵交換アプリにおけるデータの永続化、データモデル、および整合性担保に関する設計を定義する。
本仕様は **QR Payload Specification v3** を前提とし、そのデータ構造と整合性を保つことを最優先とする。

## 1. Scope / Non-goals

### Scope (対象範囲)

- モバイル端末内でのデータ永続化（Flutter/Hive/SQLite等）
- QRコードによる対面交換時のデータフローと整合性
- 個人の所有履歴（Lineage）の保持構造
- 将来的なサーバー同期を見据えた最小限のID戦略と不可分性の担保

### Non-goals (対象外)

- SNS的機能（いいね/コメント/フォロー/タイムライン）
- オンラインでのデータ交換・検索機能
- ユーザー認証・アカウント管理（MVPでは不要）
- 複雑なクエリ要件

## 2. Data Boundary

本システムは **Local First** （端末主導）のアーキテクチャを採用する。

| 領域                  | 責務                                                                                                   | データ寿命 |
| :-------------------- | :----------------------------------------------------------------------------------------------------- | :--------- |
| **Local (端末)**      | **正 (Source of Truth)**<br>作品の生成、保存、所有権の管理、交換履歴の記録。                           | 永続       |
| **Transport (QR)**    | **媒体 (Medium)**<br>端末間でのデータ転送。一時的な状態。                                              | 一時的     |
| **Server (Optional)** | **副 (Backup/Archive)**<br>履歴の保全、統計収集（将来用）。MVPでは存在しないか、最小限のログ収集のみ。 | 永続       |

## 3. Data Model

エンティティ間のリレーションシップ定義。

```mermaid
erDiagram
    Dot ||--o{ DotInstance : "pointed by"
    Dot ||--o{ ActionLog : "logged on"

    Dot {
        string uuid PK
        int gen PK
        blob pixel_data
        blob lineage_data
        int crc32_u32
    }

    DotInstance {
        string uuid PK
        int current_gen FK => Dot.gen
        boolean is_owner
        datetime acquired_at
        datetime deleted_at
    }

    ActionLog {
        string id PK
        string dot_uuid FK => Dot.uuid
        int dot_gen FK => Dot.gen
        enum action_type
        datetime timestamp
    }
```

### エンティティ定義

1.  **Dot (作品実体)**
    - **役割**: ドット絵のバージョンごとの実体（Immutable）。
    - **PK**: `(uuid, gen)` の複合キー。
    - **特徴**: 同一 `uuid` でも `gen` が異なれば別レコードとして追記保存（Append-only）する。

2.  **DotInstance (所持ポインタ)**
    - **役割**: 端末内での「現在の所持状態」を管理するポインタ。
    - **PK**: `uuid`。1つの作品系列につき、端末内では1つの「最新状態」のみを管理する。
    - **特徴**: `current_gen` カラムで、現在保持している `Dot` の世代を指す。

3.  **ActionLog (操作ログ)**
    - **役割**: ドット絵に対するアクションの事実記録。
    - **特徴**: 特定の `Dot(uuid, gen)` に対して発生したイベントを記録する。

## 4. Field Spec

各エンティティのフィールド詳細。

### 4.1 Dot (Immutable Data / Append-Only)

| Field Name      | Type          | Key | Null | Constraints | Description                          |
| :-------------- | :------------ | :-- | :--- | :---------- | :----------------------------------- |
| `uuid`          | String (UUID) | PK  | No   | v4形式      | 作品の固有ID。QRの `<uuid>` と一致。 |
| `gen`           | Integer       | PK  | No   | `>= 0`      | 世代数。QRの `<gen>` と一致。        |
| `pixel_data`    | Blob (512B)   | -   | No   | RGBA5551    | ピクセルデータ。                     |
| `lineage_data`  | Blob (16B\*N) | -   | No   | Max N=20    | 系譜データ（不可分BLOB）。           |
| `lineage_count` | Integer       | -   | No   | `0..20`     | 系譜の数 N。                         |
| `crc32_u32`     | Integer (4B)  | -   | No   | Unsigned    | 計算済みのCRC32値（比較用）。        |
| `created_at`    | Timestamp     | -   | Yes  | -           | データ生成・取得日時。               |

### 4.2 DotInstance (Mutable Pointer)

| Field Name    | Type          | Key | Null | Constraints   | Description                                     |
| :------------ | :------------ | :-- | :--- | :------------ | :---------------------------------------------- |
| `uuid`        | String (UUID) | PK  | No   | Ref Dot       | 作品ID。このテーブルの主キー。                  |
| `current_gen` | Integer       | FK  | No   | Ref Dot       | 現在保持している世代。                          |
| `is_owner`    | Boolean       | -   | No   | -             | 自分が作成・編集したか(true)、他者作か(false)。 |
| `acquired_at` | Timestamp     | -   | No   | -             | 最新版の取得日時。                              |
| `deleted_at`  | Timestamp     | -   | Yes  | **Tombstone** | 削除日時。Nullなら有効。値があれば論理削除。    |
| `title`       | String        | -   | Yes  | Max 64chars   | ユーザーが付けたタイトル。                      |

### 4.3 ActionLog (Fact Log)

| Field Name    | Type          | Key | Null | Constraints              | Description                                |
| :------------ | :------------ | :-- | :--- | :----------------------- | :----------------------------------------- |
| `id`          | String (UUID) | PK  | No   | -                        | ログID。                                   |
| `dot_uuid`    | String (UUID) | FK  | No   | Ref Dot                  | 対象作品ID。                               |
| `dot_gen`     | Integer       | FK  | No   | Ref Dot                  | 対象作品世代。                             |
| `action_type` | Enum          | -   | No   | `QR_SHOWN`, `QR_SCANNED` | `SHOWN`=表示した, `SCANNED`=スキャンした。 |
| `timestamp`   | Timestamp     | -   | No   | -                        | 発生日時。                                 |

## 5. ID Strategy

- **(uuid, gen) Uniqueness**:
  - システム全体で「作品ID」と「世代」のペアを一意の識別子とする。
  - Wire Format (`v3|<uuid>|<gen>|...`) と完全に整合させる。
- **UUID継承ポリシー (編集時)**:
  - 既存の `Dot(uuid, gen)` を編集して保存する場合:
    - -> 新しいレコード `Dot(uuid, gen + 1)` を作成 (INSERT)。
    - -> `uuid` は継承される。
  - 新規作成（Clear状態から）の場合:
    - -> 新しいレコード `Dot(new_uuid, 0)` を作成 (INSERT)。

## 6. Persistence Spec

端末ローカル永続化の仕様。

- **Store Strategy**:
  - **Dots**: **Append-only**。一度書かれた `(uuid, gen)` のレコードは不変であり、物理削除しない。
  - **Instances**: **Mutable**。`uuid` をキーとして `current_gen` を更新する（Upsert）。
- **Index**:
  - `dots`: `(uuid, gen)` 複合PK。
  - `instances`: `uuid` (PK), `deleted_at` (フィルタ用), `acquired_at` (ソート用)。

## 7. Consistency & Idempotency

- **同一 (uuid, gen) の受信**:
  - **Payload完全一致**: 既にDBにあるデータと完全に一致する場合、保存処理はスキップ（冪等）。ログ `QR_SCANNED` は記録する。
  - **Payload不一致（競合）**: 同一 `(uuid, gen)` なのに中身（Pixel/Lineage/CRC）が異なる場合。
    - -> **Reject (Error)**: データ破損または改ざんとみなし、保存しない。`FormatException` として処理する。
- **同一 uuid, 別 gen の受信**:
  - 当該 uuid の Instance が保持する `current_gen` と比較。
    - 受信 `gen` > `current_gen`: **Update**。Instanceの `current_gen` を更新し、Dotsに新レコード追加。
    - 受信 `gen` < `current_gen`: **Ignore**。古い世代への巻き戻しは行わない。Dotsへの追加は任意（履歴補完としては可）。

## 8. Lineage Handling

- **BLOB保持**:
  - `lineage_log` (16B \* N) はバイナリBLOBとして `Dot` テーブルに格納。不可分性を優先。

## 9. Tombstone Policy

- **削除操作**:
  - `DotInstance` の `deleted_at` を更新するのみ。
  - `Dot` テーブルの実データは削除しない（系譜保護のため）。

## 10. DDL案 (Conceptual SQL)

```sql
-- 作品実体（履歴含むすべて）
CREATE TABLE dots (
    uuid            TEXT NOT NULL,
    gen             INTEGER NOT NULL,
    pixel_data      BLOB NOT NULL,
    lineage_data    BLOB NOT NULL,
    lineage_count   INTEGER NOT NULL,
    crc32_u32       INTEGER NOT NULL,
    created_at      INTEGER NOT NULL,
    PRIMARY KEY (uuid, gen)
);

-- 所持状態（ユーザーに見える最新状態へのポインタ）
CREATE TABLE dot_instances (
    uuid            TEXT PRIMARY KEY,       -- 作品UUID
    current_gen     INTEGER NOT NULL,       -- 最新世代
    is_owner        BOOLEAN NOT NULL,
    title           TEXT,
    acquired_at     INTEGER NOT NULL,
    deleted_at      INTEGER,                -- Nullable
    FOREIGN KEY (uuid, current_gen) REFERENCES dots(uuid, gen)
);

-- イベントログ
CREATE TABLE action_logs (
    id              TEXT PRIMARY KEY,
    dot_uuid        TEXT NOT NULL,
    dot_gen         INTEGER NOT NULL,
    action_type     TEXT NOT NULL CHECK(action_type IN ('QR_SHOWN', 'QR_SCANNED')),
    timestamp       INTEGER NOT NULL,
    FOREIGN KEY (dot_uuid, dot_gen) REFERENCES dots(uuid, gen)
);
```

## 11. Concrete Scenarios

| シナリオ   | Action     | dots (Append)        | instances (Upsert)      | logs (Insert)                 |
| :--------- | :--------- | :------------------- | :---------------------- | :---------------------------- |
| **New**    | 新規作成   | INSERT (uuidA, gen0) | INSERT (uuidA, gen0)    | -                             |
| **Edit**   | 編集保存   | INSERT (uuidA, gen1) | UPDATE (gen=1)          | -                             |
| **Scan**   | 受取(新規) | INSERT (uuidB, gen5) | INSERT (uuidB, gen5)    | INSERT (SCANNED, uuidB, gen5) |
| **Scan**   | 受取(更新) | INSERT (uuidB, gen6) | UPDATE (gen=6)          | INSERT (SCANNED, uuidB, gen6) |
| **Scan**   | 受取(既存) | - (Skip)             | - (Skip/Update At)      | INSERT (SCANNED, uuidB, gen5) |
| **Scan**   | 受取(競合) | - (Reject)           | -                       | -                             |
| **Show**   | QR表示     | -                    | -                       | INSERT (SHOWN, uuidA, gen1)   |
| **Delete** | 削除       | -                    | UPDATE (deleted_at=Now) | -                             |

## 12. Decision Needed

1.  **過去世代ログの保持期間**
    - 端末容量節約のため、履歴（Dotsテーブル）をどこまで保持するか。
    - **Decision**: MVPでは無制限（テキスト/小画像データのみのため容量懸念は低い）。将来的にVacuum機能を検討。
