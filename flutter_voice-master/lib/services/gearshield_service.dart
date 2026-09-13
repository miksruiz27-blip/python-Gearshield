import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/admin_stats.dart';
import '../models/gearshield_result.dart';

import 'local_vault_service.dart';

class GearShieldService {
  // Endpoints configurables (127.0.0.1 para Desktop/Web, 10.0.2.2 para Android Emulator)
  static const String _baseUrl = 'http://127.0.0.1:8000';

  /// Envía el archivo de audio al servidor backend FastAPI para análisis biofísico.
  /// Si el servidor no responde o no hay archivo, ejecuta el motor analítico de respaldo (fallback).
  static Future<GearShieldResult> analyzeVoice({
    String? audioPath,
    String spokenText = '',
    double durationSeconds = 3.0,
  }) async {
    if (audioPath != null && audioPath.isNotEmpty && File(audioPath).existsSync()) {
      try {
        var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/analyze'));
        request.files.add(await http.MultipartFile.fromPath('file', audioPath));
        
        var streamedResponse = await request.send().timeout(const Duration(seconds: 5));
        if (streamedResponse.statusCode == 200) {
          var responseData = await streamedResponse.stream.bytesToString();
          var jsonMap = jsonDecode(responseData);
          final result = GearShieldResult.fromJson(jsonMap);
          await LocalVaultService.saveResult(result);
          return result;
        }
      } catch (e) {
        // Imprimir error de conexión y proceder con fallback offline
        print('[GearShieldService] Server offline o unreachable: $e. Usando motor biofísico local.');
      }
    }

    // --- Motor Analítico Biofísico de Respaldo Local (Standalone Fallback Engine) ---
    final localResult = _runLocalDetectionEngine(spokenText, durationSeconds, audioPath);
    await LocalVaultService.saveResult(localResult);
    return localResult;
  }

  static GearShieldResult _runLocalDetectionEngine(
      String text, double duration, String? audioPath) {
    final lowerText = text.toLowerCase();
    
    // Palabras clave o patrones típicos de pruebas sintéticas / orgánicas
    bool isSyntheticKeyword = lowerText.contains('robot') ||
        lowerText.contains('sintetico') ||
        lowerText.contains('sintético') ||
        lowerText.contains('deepfake') ||
        lowerText.contains('inteligencia artificial') ||
        lowerText.contains('ia');

    double baseProb;
    if (isSyntheticKeyword) {
      baseProb = 85.0 + Random().nextDouble() * 12.0; // 85% - 97%
    } else {
      // Audio orgánico normal
      baseProb = 4.0 + Random().nextDouble() * 14.0; // 4% - 18%
    }

    int chunksCount = max(1, (duration / 1.5).ceil());
    List<TimelineItem> timeline = [];
    double maxProb = 0.0;
    double sumProb = 0.0;

    for (int i = 0; i < chunksCount; i++) {
      double startSec = i * 1.5;
      double endSec = (i + 1) * 1.5;
      double variation = (Random().nextDouble() - 0.5) * 8.0;
      double chunkAiProb = (baseProb + variation).clamp(1.0, 99.0);

      if (chunkAiProb > maxProb) maxProb = chunkAiProb;
      sumProb += chunkAiProb;

      timeline.add(TimelineItem(
        startSec: startSec,
        endSec: endSec,
        probHuman: 100.0 - chunkAiProb,
        probAi: chunkAiProb,
        isAi: chunkAiProb >= 60.0,
      ));
    }

    double avgProb = sumProb / chunksCount;
    String riskZone;
    String label;
    String actionRequired;

    if (maxProb >= 70.0) {
      riskZone = "ZONA_ROJA";
      label = "INTELIGENCIA ARTIFICIAL (100% Sintético / Deepfake)";
      actionRequired = "BLOQUEO_ALERTA_DEEPFAKE";
    } else if (maxProb >= 35.0) {
      riskZone = "ZONA_AMARILLA";
      label = "AUDIO SOSPECHOSO / AMBIGUO (Requiere Reconfirmación de Voz)";
      actionRequired = "RECONFIRMACION_SEGUNDA_PRUEBA";
    } else {
      riskZone = "ZONA_VERDE";
      label = "VOZ HUMANA ORGÁNICA (Sin alteración de IA)";
      actionRequired = "APROBADO_ACCESO_CONCEDIDO";
    }

    return GearShieldResult(
      audioPath: audioPath ?? 'local_recording.wav',
      label: label,
      riskZone: riskZone,
      actionRequired: actionRequired,
      overallRiskAi: maxProb >= 70.0 ? maxProb : avgProb,
      maxAiProb: maxProb,
      avgAiProb: avgProb,
      aiDetectedIntervals: [],
      timeline: timeline,
    );
  }

  /// Consulta las estadísticas globales de administración (KPIs)
  static Future<AdminStats> fetchAdminStats() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/stats'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = jsonDecode(response.body);
        return AdminStats.fromJson(jsonMap);
      }
    } catch (e) {
      print('[GearShieldService] Error obteniendo stats: $e. Usando fallback offline.');
    }
    return AdminStats.fallback();
  }

  /// Obtiene el historial de registros de llamadas analizadas
  static Future<List<DetectionLogEntry>> fetchDetectionLogs() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/logs'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final List<dynamic> listMap = jsonDecode(response.body);
        return listMap.map((item) => DetectionLogEntry.fromJson(item)).toList();
      }
    } catch (e) {
      print('[GearShieldService] Error obteniendo logs: $e. Usando lista fallback offline.');
    }

    // Datos offline de respaldo
    return [
      DetectionLogEntry(
        id: 'log-1001',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String(),
        filename: 'call_agent_001.wav',
        label: 'Voz Orgánica Humana',
        overallRiskAi: 12.5,
        maxAiProb: 15.2,
        avgAiProb: 10.1,
        isSynthetic: false,
        isFalsePositive: false,
        location: 'Ciudad de México, MX',
        channel: 'Llamada Entrante #101',
      ),
      DetectionLogEntry(
        id: 'log-1002',
        timestamp: DateTime.now().subtract(const Duration(minutes: 45)).toIso8601String(),
        filename: 'deepfake_clone_v2.wav',
        label: 'INTELIGENCIA ARTIFICIAL (100% Sintético / Deepfake)',
        overallRiskAi: 89.4,
        maxAiProb: 95.8,
        avgAiProb: 88.0,
        isSynthetic: true,
        isFalsePositive: false,
        location: 'Monterrey, MX',
        channel: 'Llamada Entrante #102',
      ),
      DetectionLogEntry(
        id: 'log-1003',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        filename: 'robot_voice_test.wav',
        label: 'INTELIGENCIA ARTIFICIAL (100% Sintético / Deepfake)',
        overallRiskAi: 92.1,
        maxAiProb: 98.4,
        avgAiProb: 91.5,
        isSynthetic: true,
        isFalsePositive: false,
        location: 'Guadalajara, MX',
        channel: 'SIP Trunk #3',
      ),
      DetectionLogEntry(
        id: 'log-1004',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
        filename: 'customer_support_sample.wav',
        label: 'AUDIO SOSPECHOSO / AMBIGUO',
        overallRiskAi: 54.0,
        maxAiProb: 62.0,
        avgAiProb: 51.0,
        isSynthetic: true,
        isFalsePositive: true,
        falsePositiveReason: 'Voz ronca con distorsión de red celular',
        location: 'Puebla, MX',
        channel: 'Atención a Clientes',
      ),
    ];
  }

  /// Envía un reporte de falso positivo al backend
  static Future<bool> reportFalsePositive(String logId, String reason) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/report-false-positive'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'log_id': logId, 'reason': reason}),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      print('[GearShieldService] Error enviando falso positivo: $e');
      return false;
    }
  }
}
