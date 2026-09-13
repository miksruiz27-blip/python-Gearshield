import 'package:hive/hive.dart';

part 'pdf_report_item.g.dart';

@HiveType(typeId: 0)
class PdfReportItem extends HiveObject {
  @HiveField(0)
  final String reportUuid;

  @HiveField(1)
  final String filename;

  @HiveField(2)
  final String localPath;

  @HiveField(3)
  final double overallRiskAi;

  @HiveField(4)
  final DateTime createdAt;

  PdfReportItem({
    required this.reportUuid,
    required this.filename,
    required this.localPath,
    required this.overallRiskAi,
    required this.createdAt,
  });
}
