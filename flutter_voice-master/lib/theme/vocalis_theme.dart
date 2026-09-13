import 'package:flutter/material.dart';

class VocalisTheme {
  static const Color surface = Color(0xFFF8F9FF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color primary = Color(0xFF3525CD);
  static const Color primaryContainer = Color(0xFF4F46E5);
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentAmberContainer = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color glassBorder = Color(0x99FFFFFF);
  static const Color glassBorderSubtle = Color(0xCCE2E8F0);
  static const Color meshIce = Color(0xFFD6E4FF);
  static const Color meshLilac = Color(0xFFEDE9FE);

  // Paleta exclusiva del panel forense (espectrograma): deriva del mismo
  // eje indigo del resto de la UI en vez de tonos neón sueltos (cian/teal),
  // para que el widget "oscuro" se sienta parte de la misma familia visual.
  static const Color forensicCanvas = Color(0xFF11132B);
  static const Color forensicCanvasAlt = Color(0xFF1B1E3F);
  static const Color forensicGridLine = Color(0x14FFFFFF);
  static const Color forensicLowEnergy = Color(0xFF1B1E3F);
  static const Color forensicMidEnergy = Color(0xFF4F46E5);
  static const Color forensicHighEnergy = Color(0xFFA78BFA);
  static const Color forensicTextMuted = Color(0x8AE2E8F0);

  /// Tipografía compartida (evita el mosaico de 9/10/11/12/13/15/16/22px
  /// repartido a mano por todos los widgets del módulo admin).
  static const double textMicro = 9.5;
  static const double textLabel = 11.0;
  static const double textBody = 12.5;
  static const double textTitle = 14.5;
  static const double textHeadline = 18.0;
  static const double textDisplay = 24.0;

  /// Escala de radios: chip/pill, tarjeta interior, tarjeta contenedora.
  static const double radiusChip = 10.0;
  static const double radiusCard = 16.0;
  static const double radiusHero = 20.0;

  static BoxDecoration glassCardDecoration({
    Color borderColor = glassBorderSubtle,
    Color bg = const Color(0xEEFFFFFF),
    double borderRadius = 16.0,
  }) {
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 18,
          offset: Offset(0, 4),
        ),
      ],
    );
  }
}
