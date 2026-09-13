import 'dart:typed_data';

import 'pdf_download_stub.dart'
    if (dart.library.html) 'pdf_download_web.dart' as impl;

/// Guarda/descarga bytes de PDF de forma multiplataforma.
/// En Web dispara una descarga real del navegador; en escritorio/móvil
/// guarda el archivo en el directorio de documentos de la app y devuelve
/// la ruta resultante (o null en Web, donde no aplica).
Future<String?> savePdfBytes(Uint8List bytes, String filename) {
  return impl.savePdfBytes(bytes, filename);
}
