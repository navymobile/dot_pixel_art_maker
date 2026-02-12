# File Map

## 更新日

- 2026-02-12

## root (lib)

- main.dart
  役割: アプリの初期化と起動
  種別: Utility (Entry Point)
  概要: Hiveの初期化、Adapter登録、MaterialAppの構築を行う。

## domain

- dot_model.dart
  役割: ドット絵データの不変データモデル定義
  種別: Model
  概要: id, pixels, gen等のデータを保持し、copyWith等のメソッドを提供する。

- dot_entity.dart
  役割: Hiveデータベース保存用のデータ定義
  種別: Model (HiveObject)
  概要: Hiveのアノテーション(`@HiveType`)が付与された永続化用クラス。

- gen_logic.dart
  役割: 世代(Gen)管理ロジック
  種別: Service / Utility
  概要: 交換時などに世代をインクリメントするロジックをカプセル化する。

## infra

- dot_storage.dart
  役割: ドット絵データのデータベース操作(CRUD)
  種別: Repository
  概要: Hive Boxを操作し、DotEntityの保存・取得・削除・監視を行う。

- dot_codec.dart
  役割: ピクセルデータのエンコード/デコード
  種別: Utility
  概要: ARGB配列とRGB565 Base64URL文字列の相互変換を行う。

- qr_service.dart
  役割: QRコードのデータ生成と解析
  種別: Service
  概要: PixelデータをQR用バイナリデータへ変換し、読み取りデータの検証を行う。

- storage_service.dart
  役割: 簡易データ(設定/パレット)の永続化
  種別: Service
  概要: SharedPreferencesを使用し、最近使ったパレット色などを保存する。

## ui

- home_screen.dart
  役割: 保存済みドット絵の一覧表示
  種別: Screen
  概要: DotStorageを監視し、保存された作品をグリッド表示する。

- edit_screen.dart
  役割: ドット絵作成・編集画面のコンテナ
  種別: Screen
  概要: DotEditorを表示し、AppBarの表示や画面遷移引数の処理を行う。

### ui/canvas

- dot_editor.dart
  役割: キャンバス描画と編集操作の提供
  種別: Widget
  概要: CustomPaintでの描画、ジェスチャー検知、ツールバー操作、描画状態管理を行う。

### ui/palette

- palette_widget.dart
  役割: カラーパレットの表示と選択
  種別: Widget
  概要: 固定グレースケールと、使用履歴(Recent)に基づく動的パレットを表示する。

### ui/exchange

- exchange_screen.dart
  役割: QRコードによる作品交換画面
  種別: Screen
  概要: 現在の作品のQR表示と、カメラによる他作品のQRスキャンを行う。

### ui/sub

- dot_grid_item.dart
  役割: ホーム画面のグリッドアイテム表示
  種別: Widget
  概要: List<int>からドット絵プレビューを軽量に描画し、タップイベントを処理する。
