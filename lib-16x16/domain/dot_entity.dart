import 'package:hive/hive.dart';

part 'dot_entity.g.dart';

@HiveType(typeId: 0)
class DotEntity extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int createdAt;

  @HiveField(2)
  final int updatedAt;

  @HiveField(3)
  final String payload_v3;

  @HiveField(4)
  final String? title;

  @HiveField(5)
  final int gen;

  @HiveField(6)
  final String? originalId;

  DotEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.payload_v3,
    this.title,
    this.gen = 0,
    this.originalId,
  });

  DotEntity copyWith({
    String? id,
    int? createdAt,
    int? updatedAt,
    String? payload_v3,
    String? title,
    int? gen,
    String? originalId,
  }) {
    return DotEntity(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payload_v3: payload_v3 ?? this.payload_v3,
      title: title ?? this.title,
      gen: gen ?? this.gen,
      originalId: originalId ?? this.originalId,
    );
  }
}
