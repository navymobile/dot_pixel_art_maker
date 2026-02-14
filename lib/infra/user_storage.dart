import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class UserStorage {
  static const String _boxName = 'user_box';
  static const String _iconKey = 'user_icon_pixels';

  static final UserStorage _instance = UserStorage._internal();
  factory UserStorage() => _instance;
  UserStorage._internal();

  Box? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox(_boxName);
  }

  Future<void> saveUserIcon(List<int> pixels) async {
    if (_box == null) await init();
    await _box!.put(_iconKey, pixels);
  }

  List<int>? getUserIcon() {
    if (_box == null) return null;
    final dynamic data = _box!.get(_iconKey);
    if (data is List) {
      return data.cast<int>();
    }
    return null;
  }

  Future<void> deleteUserIcon() async {
    if (_box == null) await init();
    await _box!.delete(_iconKey);
  }

  ValueListenable<Box> listen() {
    if (_box == null) throw Exception('Box not initialized');
    return _box!.listenable(keys: [_iconKey]);
  }
}
