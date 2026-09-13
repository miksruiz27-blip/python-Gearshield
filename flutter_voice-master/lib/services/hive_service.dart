import 'package:hive/hive.dart';
import '../models/pdf_report_item.dart';

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

  static Future<void> logout() async {
    await _sessionBox.clear();
  }
}
