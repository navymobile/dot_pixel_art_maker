import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

class DotModel {
  final String id; // DNA
  final List<int> pixels; // 256 length, ARGB int. 0 = transparent.
  final int gen;
  final String? originalId;
  final String? title;
  final int createdAt;
  final int updatedAt;
  final List<Uint8List> lineage;

  DotModel({
    required this.id,
    required this.pixels,
    this.gen = 0,
    this.originalId,
    this.title,
    int? createdAt,
    int? updatedAt,
    this.lineage = const [],
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
       updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  factory DotModel.create({String? id, List<int>? pixels}) {
    return DotModel(
      id: id ?? const Uuid().v4(),
      pixels: pixels ?? List.filled(256, 0), // 0 is transparent
      gen: 0,
      originalId: null, // Self is original
      title: null,
      lineage: const [],
    );
  }

  // Creating a new generation from an existing dot (Exchange)
  factory DotModel.fromExchange(DotModel other) {
    return DotModel(
      id: const Uuid().v4(), // New identity
      pixels: List.from(other.pixels), // Copy pixels
      gen: other.gen + 1, // Increment generation
      originalId: other.originalId ?? other.id, // Trace back to original
      title: other.title,
      lineage: List.from(other.lineage), // Copy lineage
    );
  }

  DotModel copyWith({
    String? id,
    List<int>? pixels,
    int? gen,
    String? originalId,
    String? title,
    List<Uint8List>? lineage,
  }) {
    return DotModel(
      id: id ?? this.id,
      pixels: pixels ?? this.pixels,
      gen: gen ?? this.gen,
      originalId: originalId ?? this.originalId,
      title: title ?? this.title,
      createdAt: this.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      lineage: lineage ?? this.lineage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pixels': pixels,
      'gen': gen,
      'originalId': originalId,
      'title': title,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory DotModel.fromMap(Map<String, dynamic> map) {
    return DotModel(
      id: map['id'] ?? '',
      pixels: List<int>.from(map['pixels']),
      gen: map['gen']?.toInt() ?? 0,
      originalId: map['originalId'],
      title: map['title'],
      createdAt: map['createdAt']?.toInt(),
      updatedAt: map['updatedAt']?.toInt(),
    );
  }

  String toJson() => json.encode(toMap());

  factory DotModel.fromJson(String source) =>
      DotModel.fromMap(json.decode(source));
}
