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

- user_storage.dart
  役割: ユーザー設定・プロファイル情報の永続化
  種別: Repository
  概要: Hiveを使用し、ユーザーアイコン（選択されたドット絵）などを保存する。

## ui

- home_screen.dart
  役割: 保存済みドット絵の一覧表示
  種別: Screen
  概要: DotStorageを監視し、保存された作品をグリッド表示する。

- edit_screen.dart
  役割: ドット絵作成・編集画面のコンテナ
  種別: Screen
  概要: DotEditorを表示し、AppBarの表示や画面遷移引数の処理を行う。

- detail_screen.dart
  役割: ドット絵の詳細表示・管理画面
  種別: Screen
  概要: ドット絵のプレビュー、削除、編集画面への遷移、エクスポート画面への遷移を行う。

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

- qr_display_screen.dart
  役割: 作品QRコード表示画面
  種別: Screen
  概要: 現在の作品（ドット絵＋パレット）をエンコードしてQRコードを表示する。

- qr_scan_screen.dart
  役割: QRコードスキャン画面
  種別: Screen
  概要: カメラでQRコードを読み取り、デコードしてドット絵データを取り込む。

### ui/profile

- profile_screen.dart
  役割: ユーザープロファイル画面
  種別: Screen
  概要: ユーザーアイコンの表示・変更、アプリバージョンの表示を行う。

- dot_selection_screen.dart
  役割: アイコン用ドット絵選択画面
  種別: Screen
  概要: ユーザーが作成したドット絵一覧を表示し、プロファイルアイコンとして選択可能にする。

### ui/export

- export_screen.dart
  役割: 画像エクスポート画面
  種別: Screen
  概要: ドット絵をLINEスタンプ用や汎用サイズ（S/M/L）の透過PNGとして書き出す。

### ui/sub

- dot_grid_item.dart
  役割: ホーム画面のグリッドアイテム表示
  種別: Widget
  概要: List<int>からドット絵プレビューを軽量に描画し、タップイベントを処理する。

- dot_grid_body.dart
  役割: ドット絵グリッド表示の共通コンポーネント
  種別: Widget
  概要: HomeScreenやDotSelectionScreenで使用される、ドット絵一覧のグリッド表示部分。

- import_photo_sheet.dart
  役割: 写真取り込み用ボトムシート
  種別: Widget
  概要: カメラ/ライブラリから画像を選択し、ドット絵に変換してインポートするUI。

## docs

- spec_dot_codec_v4.md
  役割: DotCodec v4 仕様書
  種別: Specification
  概要: RGBA5551とIndexed8をサポートするデータ構造(v4)と、v3後方互換戦略を定義。

- spec_dot_codec_v5.md
  役割: DotCodec v5 仕様書
  種別: Specification
  概要: v4をベースにRGB444(4096色+0予約透明)を追加。可変長ヘッダ[v,e,w,h]、12bitビットパック、v5→v4→v3フォールバック戦略を定義。

- export_spec.md
  役割: 画像エクスポート機能仕様書
  種別: Specification
  概要: LINEスタンプ用（370x320px、余白あり）および汎用エクスポート（正方形、Nearest Neighbor拡大）の仕様定義。
