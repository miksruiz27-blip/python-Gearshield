import 'package:hive/hive.dart';
import '../models/pdf_report_item.dart';
import 'local_vault_service.dart';

class HiveService {
  static final Box<PdfReportItem> _pdfBox = Hive.box<PdfReportItem>('pdf_reports_box');
  static final Box _sessionBox = Hive.box('user_session_box');

  // --- MÉTODOS DE REPORTES PDF ---
  static Future<void> savePdfReport(PdfReportItem report) async {
    await _pdfBox.put(report.reportUuid, report);
  }

  static List<PdfReportItem> getAllPdfReports() {
    return _pdfBox.values.toList();
  }

  // --- MÉTODOS DE SESIÓN DE USUARIO ---
  static Future<void> saveUserSession(String token, String username) async {
    await _sessionBox.put('token', token);
    await _sessionBox.put('username', username);
  }

  static String? getToken() => _sessionBox.get('token');
  static String? getUsername() => _sessionBox.get('username');
  static String? getEmail() => _sessionBox.get('email');

  /// Un usuario es "invitado" si nunca inició sesión ni se registró
  /// (no hay token guardado en la bóveda local).
  static bool isGuest() => getToken() == null;

  static Future<void> saveUserSessionFull(String token, String username, String email) async {
    await _sessionBox.put('token', token);
    await _sessionBox.put('username', username);
    await _sessionBox.put('email', email);
  }

  static Future<void> updateUserData(String username) async {
    await _sessionBox.put('username', username);
  }

  static Future<void> logout() async {
    await _sessionBox.clear();
  }

  static Future<void> deleteAccount() async {
    await _sessionBox.clear();
    await _pdfBox.clear();
    await LocalVaultService.clearVault();
  }
}
