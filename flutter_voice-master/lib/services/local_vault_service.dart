import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gearshield_result.dart';

/// Servicio de Bóveda y Persistencia Local Offline (GearShield Vault).
/// Permite almacenar, consultar y gestionar los resultados de auditorías y la
/// configuración del sistema directamente en el almacenamiento local del dispositivo
/// usando SharedPreferences.
class LocalVaultService {
  static const String _vaultKey = 'gearshield_offline_audit_vault';
  static const String _settingsKey = 'gearshield_app_settings';

  /// Guarda una auditoría en la bóveda local persistente
  static Future<void> saveResult(GearShieldResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> currentVault = prefs.getStringList(_vaultKey) ?? [];

      final resultMap = {
        'audio_path': result.audioPath,
        'label': result.label,
        'risk_zone': result.riskZone,
        'action_required': result.actionRequired,
        'overall_risk_ai': result.overallRiskAi,
        'max_ai_prob': result.maxAiProb,
        'avg_ai_prob': result.avgAiProb,
        'timestamp': DateTime.now().toIso8601String(),
      };

      currentVault.insert(0, jsonEncode(resultMap));
      // Conservar los últimos 50 registros en memoria local
      if (currentVault.length > 50) {
        currentVault.removeRange(50, currentVault.length);
      }

      await prefs.setStringList(_vaultKey, currentVault);
    } catch (_) {}
  }

  /// Recupera el historial completo almacenado localmente
  static Future<List<Map<String, dynamic>>> getSavedResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> currentVault = prefs.getStringList(_vaultKey) ?? [];
      return currentVault
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Borra la bóveda local
  static Future<void> clearVault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_vaultKey);
    } catch (_) {}
  }

  /// Guarda la configuración de usuario / offline
  static Future<void> saveSettings({
    required String apiEndpoint,
    required double sensitivityThreshold,
    required bool localFallbackEnabled,
    required bool autoPdfReport,
    required bool realtimeAlerts,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = {
        'api_endpoint': apiEndpoint,
        'sensitivity_threshold': sensitivityThreshold,
        'local_fallback_enabled': localFallbackEnabled,
        'auto_pdf_report': autoPdfReport,
        'realtime_alerts': realtimeAlerts,
      };
      await prefs.setString(_settingsKey, jsonEncode(settings));
    } catch (_) {}
  }

  /// Recupera la configuración guardada
  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString(_settingsKey);
      if (data != null) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  static const String _demoModeKey = 'gearshield_demo_mode_enabled';

  /// Guarda si el Modo Demo (resultados simulados humano/IA en bucle) está activo.
  static Future<void> saveDemoMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_demoModeKey, enabled);
    } catch (_) {}
  }

  static Future<bool> getDemoMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_demoModeKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}
