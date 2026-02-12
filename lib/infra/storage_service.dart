import 'package:shared_preferences/shared_preferences.dart';
import '../domain/dot_model.dart';

class StorageService {
  static const String keyCurrentDot = 'current_dot';

  // Save the current dot
  Future<void> saveDot(DotModel dot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCurrentDot, dot.toJson());
  }

  // Palette Persistence
  static const String _paletteKey = 'recent_palette_v1';

  Future<List<int>> loadRecentPalette() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? hexList = prefs.getStringList(_paletteKey);
    if (hexList == null) return [];

    return hexList.map((hex) => int.parse(hex)).toList();
  }

  Future<void> saveRecentPalette(List<int> colors) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> hexList = colors.map((c) => c.toString()).toList();
    await prefs.setStringList(_paletteKey, hexList);
  }

  // Load the current dot. If none exists, create a new one.
  Future<DotModel> loadDot() async {
    final prefs = await SharedPreferences.getInstance();
    final String? dotJson = prefs.getString(keyCurrentDot);

    if (dotJson != null) {
      try {
        return DotModel.fromJson(dotJson);
      } catch (e) {
        // Fallback if data is corrupted
        return DotModel.create();
      }
    } else {
      // First time launch
      return DotModel.create();
    }
  }

  // Clear data (for debug or reset)
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyCurrentDot);
  }
}
