import 'admin_stats.dart';

class TimelineItem {
  final double startSec;
  final double endSec;
  final double probHuman;
  final double probAi;
  final bool isAi;

  TimelineItem({
    required this.startSec,
    required this.endSec,
    required this.probHuman,
    required this.probAi,
    required this.isAi,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    return TimelineItem(
      startSec: (json['start_sec'] as num).toDouble(),
      endSec: (json['end_sec'] as num).toDouble(),
      probHuman: (json['prob_human'] as num).toDouble(),
      probAi: (json['prob_ai'] as num).toDouble(),
      isAi: json['is_ai'] as bool? ?? false,
    );
  }
}

class GearShieldResult {
  final String audioPath;
  final String label;
  final String riskZone;
  final String actionRequired;
  final double overallRiskAi;
  final double maxAiProb;
  final double avgAiProb;
  final List<dynamic> aiDetectedIntervals;
  final List<TimelineItem> timeline;

  GearShieldResult({
    required this.audioPath,
    required this.label,
    required this.riskZone,
    required this.actionRequired,
    required this.overallRiskAi,
    required this.maxAiProb,
    required this.avgAiProb,
    required this.aiDetectedIntervals,
    required this.timeline,
  });

  factory GearShieldResult.fromJson(Map<String, dynamic> json) {
    var rawTimeline = json['timeline'] as List? ?? [];
    List<TimelineItem> timelineItems =
        rawTimeline.map((item) => TimelineItem.fromJson(item)).toList();

    return GearShieldResult(
      audioPath: json['audio_path'] as String? ?? '',
      label: json['label'] as String? ?? 'Desconocido',
      riskZone: json['risk_zone'] as String? ?? 'ZONA_VERDE',
      actionRequired: json['action_required'] as String? ?? 'NINGUNA',
      overallRiskAi: (json['overall_risk_ai'] as num?)?.toDouble() ?? 0.0,
      maxAiProb: (json['max_ai_prob'] as num?)?.toDouble() ?? 0.0,
      avgAiProb: (json['avg_ai_prob'] as num?)?.toDouble() ?? 0.0,
      aiDetectedIntervals: json['ai_detected_intervals'] as List? ?? [],
      timeline: timelineItems,
    );
  }

  /// Construye un resultado a partir de un registro de historial
  /// (`DetectionLogEntry`), que solo trae agregados (max/avg/overall) y no
  /// el desglose por ventana temporal — por eso `timeline` queda vacío en
  /// vez de inventar ventanas que el backend nunca devolvió para ese log.
  factory GearShieldResult.fromLogEntry(DetectionLogEntry log) {
    return GearShieldResult(
      audioPath: log.filename,
      label: log.label,
      riskZone: log.isSynthetic ? 'ZONA_ROJA' : 'ZONA_VERDE',
      actionRequired: log.isSynthetic ? 'BLOQUEO_ALERTA_DEEPFAKE' : 'APROBADO_ACCESO_CONCEDIDO',
      overallRiskAi: log.overallRiskAi,
      maxAiProb: log.maxAiProb,
      avgAiProb: log.avgAiProb,
      aiDetectedIntervals: const [],
      timeline: const [],
    );
  }
}
