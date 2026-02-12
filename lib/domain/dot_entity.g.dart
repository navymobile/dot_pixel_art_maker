// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dot_entity.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DotEntityAdapter extends TypeAdapter<DotEntity> {
  @override
  final int typeId = 0;

  @override
  DotEntity read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DotEntity(
      id: fields[0] as String,
      createdAt: fields[1] as int,
      updatedAt: fields[2] as int,
      payload_v3: fields[3] as String,
      title: fields[4] as String?,
      gen: fields[5] as int,
      originalId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DotEntity obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.updatedAt)
      ..writeByte(3)
      ..write(obj.payload_v3)
      ..writeByte(4)
      ..write(obj.title)
      ..writeByte(5)
      ..write(obj.gen)
      ..writeByte(6)
      ..write(obj.originalId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DotEntityAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
