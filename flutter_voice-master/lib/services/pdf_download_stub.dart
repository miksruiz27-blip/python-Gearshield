import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Implementación para escritorio/móvil: guarda el PDF en el directorio
/// de documentos de la app y devuelve la ruta absoluta.
Future<String?> savePdfBytes(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
