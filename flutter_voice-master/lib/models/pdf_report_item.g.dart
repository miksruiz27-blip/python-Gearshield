// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_report_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PdfReportItemAdapter extends TypeAdapter<PdfReportItem> {
  @override
  final int typeId = 0;

  @override
  PdfReportItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PdfReportItem(
      reportUuid: fields[0] as String,
      filename: fields[1] as String,
      localPath: fields[2] as String,
      overallRiskAi: fields[3] as double,
      createdAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PdfReportItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.reportUuid)
      ..writeByte(1)
      ..write(obj.filename)
      ..writeByte(2)
      ..write(obj.localPath)
      ..writeByte(3)
      ..write(obj.overallRiskAi)
      ..writeByte(4)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfReportItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
