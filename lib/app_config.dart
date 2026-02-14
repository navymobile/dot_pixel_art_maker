// アプリ全体の設定値を管理するファイル

class AppConfig {
  // ドット数
  static const int dots = 21 * 1;

  // 使用するエンコード（保存形式)
  // rgba5551: v3 e=1 (RGBA5551, 32768色)
  // indexed8: v4 e=2 (Indexed8, 256色) 不採用
  // rgb444:   v5 e=3 (RGB444, 4096色)
  static const String pixelEncoding = 'rgba5551';
}
