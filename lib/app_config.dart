// アプリ全体の設定値を管理するファイル

class AppConfig {
  // ドット数
  static const int dots = 21 * 2;

  // 使用するエンコード (v5 形式で保存)
  // rgba5551: v5 e=1 (RGBA5551, 32768色)
  // indexed8: v5 e=2 (Indexed8, 256色)
  // rgb444:   v5 e=3 (RGB444, 4096色)
  static const String pixelEncoding = 'rgba5551';
}
