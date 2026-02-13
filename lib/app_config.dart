// アプリ全体の設定値を管理するファイル

class AppConfig {
  // ドット数
  static const int dots = 21;

  // 使用するエンコード
  // rgba5551: encodeV3 を使用
  // indexed8: encodeIndex8 を使用
  // rgb444: encodeRgb444 を使用
  static const String pixelEncoding = 'rgb444';
}
