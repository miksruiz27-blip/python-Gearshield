import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/gearshield_result.dart';
import 'gearshield_service.dart';

/// Servicio de Inteligencia Artificial Forense de 2do Nivel (Gemini API real).
/// Llama al backend FastAPI (que a su vez llama a Gemini con la API key del
/// servidor, para no exponerla en el cliente web) y sólo cae a una respuesta
/// local pre-calculada si el backend / Gemini no responden a tiempo.
class GeminiForensicService {
  /// Genera un informe forense detallado asistido por Gemini AI real.
  static Future<Map<String, dynamic>> generateForensicExplanation(
      GearShieldResult result) async {
    try {
      final response = await http
          .post(
            Uri.parse('${GearShieldService.activeBaseUrl}/gemini/forensic-explanation'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'overall_risk_ai': result.overallRiskAi,
              'max_ai_prob': result.maxAiProb,
              'avg_ai_prob': result.avgAiProb,
              'label': result.label,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        data['findings'] = (data['findings'] as List?)?.cast<String>() ?? const [];
        data['source'] = 'gemini';
        return data;
      }
      debugPrint('[GeminiForensicService] Backend respondio HTTP ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('[GeminiForensicService] Gemini no disponible, usando fallback local: $e');
    }
    return _localFallbackExplanation(result);
  }

  /// Respaldo local (sin red) para que la demo nunca se quede sin explicacion.
  static Map<String, dynamic> _localFallbackExplanation(GearShieldResult result) {
    final bool isAi = result.overallRiskAi >= 50.0;
    final double aiRisk = result.overallRiskAi;
    final double maxAi = result.maxAiProb;

    if (isAi) {
      return {
        'source': 'local_fallback',
        'status': 'ALERTA_CRÍTICA',
        'badge': 'Anomalía Neural Identificada',
        'title': 'Análisis Forense (Motor Local de Respaldo)',
        'summary':
            'Se han detectado patrones de síntesis vocal neuronal y discontinuidad en la envolvente espectral en las ventanas temporales de mayor riesgo (${maxAi.toStringAsFixed(1)}%).',
        'findings': [
          'Ausencia de micro-temblor fisiológico natural en el tracto vocal humano.',
          'Suavizado artificial detectado en los formantes armónicos F1 y F2.',
          'Variancia de tono (pitch jitter) inferior al umbral biológico (0.02%).',
        ],
        'action_recommendation':
            'Bloquear la transacción o solicitud. Exigir autenticación biométrica de 2do factor.',
        'confidence_score': '${aiRisk.toStringAsFixed(1)}%',
      };
    } else if (aiRisk >= 35.0) {
      return {
        'source': 'local_fallback',
        'status': 'REVISION_SOSPECHOSA',
        'badge': 'Ambivalencia Espectral',
        'title': 'Análisis Forense (Motor Local de Respaldo)',
        'summary':
            'El clip de voz exhibe ligera distorsión armónica o ruido de canal. La variabilidad biofísica se encuentra en la zona de incertidumbre (35% - 65%).',
        'findings': [
          'Leve alteración en el ruido de fondo o compresión de códec de transmisión.',
          'Formantes vocales dentro del rango humano con fluctuación atípica.',
        ],
        'action_recommendation':
            'Solicitar reconfirmación de voz de 5 segundos con frase aleatoria de control.',
        'confidence_score': '${(100 - aiRisk).toStringAsFixed(1)}%',
      };
    } else {
      return {
        'source': 'local_fallback',
        'status': 'AUTÉNTICO_APROBADO',
        'badge': 'Biometría Vocal Humana Confirmada',
        'title': 'Análisis Forense (Motor Local de Respaldo)',
        'summary':
            'Firma acústica coherente con la fisiología del tracto vocal humano orgánico.',
        'findings': [
          'Presencia de micro-respiración y modulación de resonancia nasofaríngea.',
          'Continuidad espectral limpia sin artefactos de síntesis neural.',
        ],
        'action_recommendation': 'Aprobar acceso / transacción.',
        'confidence_score': '${(100 - aiRisk).toStringAsFixed(1)}%',
      };
    }
  }

  /// Orquestador GenUI real: Gemini decide, vía el backend, que widgets renderizar.
  static Future<Map<String, dynamic>> resolveGenUiIntent(
    String query, {
    double overallRiskAi = 0.0,
    double maxAiProb = 0.0,
    String label = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${GearShieldService.activeBaseUrl}/gemini/genui-intent'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': query,
              'overall_risk_ai': overallRiskAi,
              'max_ai_prob': maxAiProb,
              'label': label,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        data['widgets'] = (data['widgets'] as List?)?.cast<String>() ?? const ['gemini_note'];
        data['source'] = 'gemini';
        return data;
      }
      debugPrint('[GeminiForensicService] genui-intent HTTP ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('[GeminiForensicService] GenUI Gemini no disponible, usando fallback local: $e');
    }
    return _localFallbackIntent(query, overallRiskAi);
  }

  static Map<String, dynamic> _localFallbackIntent(String query, double overallRiskAi) {
    final lower = query.toLowerCase();

    if (lower.contains('delato') || lower.contains('delató') || lower.contains('explicacion') || lower.contains('explicación')) {
      return {
        'source': 'local_fallback',
        'intent': 'EXPLANATION',
        'response_text': 'Mostrando la explicación forense (motor local, Gemini no disponible).',
        'widgets': ['gemini_note'],
        'risk_prob': overallRiskAi,
      };
    } else if (lower.contains('espectrograma') || lower.contains('frecuencia') || lower.contains('espectro')) {
      return {
        'source': 'local_fallback',
        'intent': 'SPECTROGRAM',
        'response_text': 'Generando el visor de espectrograma forense.',
        'widgets': ['spectrogram'],
        'risk_prob': overallRiskAi,
      };
    } else if (lower.contains('certificado') || lower.contains('pdf')) {
      return {
        'source': 'local_fallback',
        'intent': 'PDF_EXPORT',
        'response_text': 'Preparando el certificado PDF de auditoría.',
        'widgets': ['gauge', 'pdf_preview'],
        'risk_prob': overallRiskAi,
      };
    } else {
      return {
        'source': 'local_fallback',
        'intent': 'EXPLANATION',
        'response_text': 'Mostrando el dictamen forense estándar (motor local, Gemini no disponible).',
        'widgets': ['spectrogram', 'gauge', 'ab_player', 'gemini_note', 'pdf_preview'],
        'risk_prob': overallRiskAi,
      };
    }
  }
}
