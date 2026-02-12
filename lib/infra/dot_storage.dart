import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../domain/dot_entity.dart';
import '../domain/dot_model.dart';
import 'dot_codec.dart';

class DotStorage {
  static const String _boxName = 'dot_box';

  static final DotStorage _instance = DotStorage._internal();
  factory DotStorage() => _instance;
  DotStorage._internal();

  Box<DotEntity>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;

    // Hive init must be done in main()
    // Register adapter must be done in main()

    _box = await Hive.openBox<DotEntity>(_boxName);
  }

  // Save (Create or Update)
  Future<void> saveDot(DotModel dot, {String? title}) async {
    if (_box == null) await init();

    final payloadV3 = DotCodec.encodeV3(dot.pixels, dot.lineage);

    final entity = DotEntity(
      id: dot.id,
      createdAt: dot.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      payload_v3: payloadV3,
      title: title ?? dot.title,
      gen: dot.gen,
      originalId: dot.originalId,
    );

    await _box!.put(dot.id, entity);
  }

  // Get
  DotModel? getDot(String id) {
    if (_box == null) return null; // Or throw
    final entity = _box!.get(id);
    if (entity == null) return null;

    return _toModel(entity);
  }

  // List (Sorted by updatedAt desc)
  List<DotModel> listDots() {
    if (_box == null) return [];

    final entities = _box!.values.toList();
    entities.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Descending

    return entities.map((e) => _toModel(e)).toList();
  }

  // Delete
  Future<void> deleteDot(String id) async {
    if (_box == null) return; // Or init
    await _box!.delete(id);
  }

  // Listen for changes
  ValueListenable<Box<DotEntity>> listen() {
    if (_box == null) throw Exception('Box not initialized');
    return _box!.listenable();
  }

  // Helper
  DotModel _toModel(DotEntity entity) {
    try {
      final result = DotCodec.decodeV3(entity.payload_v3);

      return DotModel(
        id: entity.id,
        pixels: result.pixels,
        gen: entity.gen,
        originalId: entity.originalId,
        title: entity.title,
        createdAt: entity.createdAt,
        updatedAt: entity.updatedAt,
        lineage: result.lineage,
      );
    } catch (e) {
      // Fallback for corrupted/legacy data in pre-release
      // Return a blank or error dot, or maybe rethrow?
      // Since we can't easily recover v2 data (code removed),
      // we'll return a blank dot to prevent crash.
      return DotModel.create(id: entity.id);
    }
  }
}
