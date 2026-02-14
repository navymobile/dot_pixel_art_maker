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
  final String payloadV3;

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
    required this.payloadV3,
    this.title,
    this.gen = 0,
    this.originalId,
  });

  DotEntity copyWith({
    String? id,
    int? createdAt,
    int? updatedAt,
    String? payloadV3,
    String? title,
    int? gen,
    String? originalId,
  }) {
    return DotEntity(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payloadV3: payloadV3 ?? this.payloadV3,
      title: title ?? this.title,
      gen: gen ?? this.gen,
      originalId: originalId ?? this.originalId,
    );
  }
}
