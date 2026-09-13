class AdminStats {
  final int totalCalls;
  final int aiCallsDetected;
  final int humanCallsDetected;
  final int deepfakesCount;
  final int reportedFalsePositives;
  final double aiPercentage;
  final String lastUpdated;

  AdminStats({
    required this.totalCalls,
    required this.aiCallsDetected,
    required this.humanCallsDetected,
    required this.deepfakesCount,
    required this.reportedFalsePositives,
    required this.aiPercentage,
    required this.lastUpdated,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalCalls: json['total_calls'] ?? 0,
      aiCallsDetected: json['ai_calls_detected'] ?? 0,
      humanCallsDetected: json['human_calls_detected'] ?? 0,
      deepfakesCount: json['deepfakes_count'] ?? 0,
      reportedFalsePositives: json['reported_false_positives'] ?? 0,
      aiPercentage: (json['ai_percentage'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: json['last_updated'] ?? DateTime.now().toIso8601String(),
    );
  }

  factory AdminStats.fallback() {
    return AdminStats(
      totalCalls: 128,
      aiCallsDetected: 34,
      humanCallsDetected: 94,
      deepfakesCount: 18,
      reportedFalsePositives: 3,
      aiPercentage: 26.5,
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}

class DetectionLogEntry {
  final String id;
  final String timestamp;
  final String filename;
  final String label;
  final double overallRiskAi;
  final double maxAiProb;
  final double avgAiProb;
  final bool isSynthetic;
  final bool isFalsePositive;
  final String? falsePositiveReason;
  final String location;
  final String channel;

  DetectionLogEntry({
    required this.id,
    required this.timestamp,
    required this.filename,
    required this.label,
    required this.overallRiskAi,
    required this.maxAiProb,
    required this.avgAiProb,
    required this.isSynthetic,
    required this.isFalsePositive,
    this.falsePositiveReason,
    required this.location,
    required this.channel,
  });

  factory DetectionLogEntry.fromJson(Map<String, dynamic> json) {
    return DetectionLogEntry(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      filename: json['filename'] ?? 'Audio_Clip.wav',
      label: json['label'] ?? 'Voz Analizada',
      overallRiskAi: (json['overall_risk_ai'] as num?)?.toDouble() ?? 0.0,
      maxAiProb: (json['max_ai_prob'] as num?)?.toDouble() ?? 0.0,
      avgAiProb: (json['avg_ai_prob'] as num?)?.toDouble() ?? 0.0,
      isSynthetic: json['is_synthetic'] ?? false,
      isFalsePositive: json['is_false_positive'] ?? false,
      falsePositiveReason: json['false_positive_reason'],
      location: json['location'] ?? 'Nodo Local',
      channel: json['channel'] ?? 'Canal Estándar',
    );
  }
}
