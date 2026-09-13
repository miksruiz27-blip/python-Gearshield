import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Painter de alta precisión para el pulpo agresivo de GearShield,
/// la animación de onda de agua ascendente y la transición hacia el micrófono.
class GearShieldOctopusPainter extends CustomPainter {
  /// Progreso de aparición de la mascota (0.0 a 1.0)
  final double mascotProgress;

  /// Progreso de revelación del texto "gearshield" (0.0 a 1.0)
  final double textProgress;

  /// Nivel de la onda de agua ascendente (0.0 = abajo, 1.0 = arriba)
  final double waveProgress;

  /// Fase temporal de la onda (para efecto de fluidos en movimiento)
  final double wavePhase;

  /// Progreso de transformación hacia el micrófono (0.0 = pulpo, 1.0 = micrófono)
  final double morphProgress;

  /// Progreso de pulso o intensidad de audio para el micrófono
  final double micPulse;

  /// Imagen del pulpo (silueta con fondo y ojos ya transparentes, ver
  /// `assets/logos/octopus_mask.png`) usada como stencil: se tiñe en tiempo
  /// real vía `BlendMode.srcIn` para conservar el efecto de inversión de
  /// color al cruzar la onda de agua. Puede ser null mientras se carga de
  /// forma asíncrona; en ese caso simplemente no se dibuja el pulpo todavía.
  final ui.Image? octopusImage;

  GearShieldOctopusPainter({
    required this.mascotProgress,
    required this.textProgress,
    required this.waveProgress,
    required this.wavePhase,
    required this.morphProgress,
    this.micPulse = 0.0,
    this.octopusImage,
  });

  /// Extensión local (sin escalar) de la mascota, usada para calcular cuánto
  /// espacio ocupa realmente en pantalla y así poder dimensionar el resto de
  /// la composición a su alrededor (banda de la onda, escala responsiva) en
  /// vez de usar constantes arbitrarias.
  static const double _mascotHalfExtent = 92.0;

  /// Calcula un factor de escala único para toda la composición
  /// (pulpo + texto) de modo que SIEMPRE quepa dentro del ancho real de la
  /// pantalla. Antes el texto "gearshield" se dibujaba a un tamaño fijo de
  /// 52px con un offset fijo, lo que en un teléfono angosto lo hacía salirse
  /// del borde derecho de la pantalla (`CustomPaint` no recorta su propio
  /// canvas). Ahora se mide el ancho natural del logotipo completo y se
  /// escala todo en conjunto para que quepa con margen.
  double _computeFitScale(Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'GearShield',
        style: TextStyle(
          fontSize: 52,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
          letterSpacing: -1.8,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Ancho natural del conjunto: mitad izquierda del pulpo + el desplazamiento
    // que sufre al revelarse el texto + la separación fija + el ancho del texto.
    final naturalWidth = _mascotHalfExtent + 75.0 + 68.0 + textPainter.width;
    final availableWidth = size.width * 0.88;
    return (availableWidth / naturalWidth).clamp(0.35, 1.0);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Altura (en coordenadas de pantalla) de la superficie del agua para un
  /// [waveProgress] dado. A diferencia de un mapeo lineal directo sobre toda
  /// la altura de la pantalla (que hacía que la onda cruzara el pulpo casi
  /// instantáneamente, ya que la mascota ocupa una fracción pequeña de la
  /// altura total), este mapeo dedica el 70% central del progreso a
  /// atravesar lentamente la banda [waveBandTop, waveBandBottom] que rodea
  /// al pulpo y el texto, y usa el 15% inicial/final para el recorrido
  /// rápido desde el borde inferior y hasta el borde superior de la pantalla.
  double _waveHeightFor(Size size, double waveBandTop, double waveBandBottom) {
    if (waveProgress <= 0.0) return size.height;
    if (waveProgress >= 1.0) return 0.0;

    if (waveProgress <= 0.15) {
      final t = waveProgress / 0.15;
      return _lerp(size.height, waveBandBottom, t);
    } else if (waveProgress <= 0.85) {
      final t = (waveProgress - 0.15) / 0.70;
      return _lerp(waveBandBottom, waveBandTop, t);
    } else {
      final t = (waveProgress - 0.85) / 0.15;
      return _lerp(waveBandTop, 0.0, t);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final fitScale = _computeFitScale(size);

    // Desplazamiento del pulpo para dar espacio al texto cuando aparece.
    final octopusShiftX = textProgress * -75.0 * fitScale;
    final octopusCenter = Offset(center.dx + octopusShiftX, center.dy);

    final mascotHalfHeight = _mascotHalfExtent * fitScale;
    final waveBandTop = (octopusCenter.dy - mascotHalfHeight - 140.0).clamp(0.0, size.height);
    final waveBandBottom = (octopusCenter.dy + mascotHalfHeight + 170.0).clamp(0.0, size.height);

    // 1. Dibujar fondo según el nivel de onda de agua.
    _drawBackgroundAndLiquid(canvas, size, waveBandTop, waveBandBottom);

    // 2. Si morphing está muy avanzado, dibujar transición completa a micrófono.
    if (morphProgress > 0.001) {
      _drawMorphingLogoAndMic(canvas, center, fitScale);
    } else {
      // 3. Dibujar Pulpo + Texto con efecto de corte/inversión de color por el agua.
      _drawLogoWithLiquidInversion(canvas, size, octopusCenter, fitScale, waveBandTop, waveBandBottom);
    }
  }

  /// Dibuja el fondo dividido por la onda de agua
  void _drawBackgroundAndLiquid(Canvas canvas, Size size, double waveBandTop, double waveBandBottom) {
    // Fondo base (Gris claro / Off-white premium como en el mockup)
    final lightBgPaint = Paint()..color = const Color(0xFFF1F4F8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), lightBgPaint);

    if (waveProgress <= 0.001) return;

    final waveHeight = _waveHeightFor(size, waveBandTop, waveBandBottom);

    // Path de la superficie del agua (onda sinusoidal dinámica)
    final liquidPath = Path();
    liquidPath.moveTo(0, size.height);
    liquidPath.lineTo(0, waveHeight);

    final waveAmplitude = 12.0 * math.sin(waveProgress * math.pi);
    const waveFrequency = 0.015;

    for (double x = 0; x <= size.width; x += 4) {
      final y = waveHeight +
          math.sin(x * waveFrequency + wavePhase) * waveAmplitude +
          math.cos(x * waveFrequency * 0.5 + wavePhase * 1.3) * (waveAmplitude * 0.4);
      liquidPath.lineTo(x, y);
    }

    liquidPath.lineTo(size.width, size.height);
    liquidPath.close();

    // Pintura del agua negra (Negro Obsidian Profundo)
    final liquidPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF141A26),
          Color(0xFF07090E),
          Color(0xFF030406),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, waveHeight - 20, size.width, size.height - waveHeight + 20));

    canvas.drawPath(liquidPath, liquidPaint);

    // Línea de espuma / brillo cibernético en la cresta de la onda
    if (waveProgress > 0.02 && waveProgress < 0.98) {
      final crestPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFE2E8F0).withValues(alpha: 0.1),
            const Color(0xFF94A3B8).withValues(alpha: 0.8),
            const Color(0xFFE2E8F0).withValues(alpha: 1.0),
            const Color(0xFF94A3B8).withValues(alpha: 0.8),
            const Color(0xFFE2E8F0).withValues(alpha: 0.1),
          ],
        ).createShader(Rect.fromLTWH(0, waveHeight - 10, size.width, 20));

      final crestPath = Path();
      crestPath.moveTo(0, waveHeight);
      for (double x = 0; x <= size.width; x += 4) {
        final y = waveHeight +
            math.sin(x * waveFrequency + wavePhase) * waveAmplitude +
            math.cos(x * waveFrequency * 0.5 + wavePhase * 1.3) * (waveAmplitude * 0.4);
        crestPath.lineTo(x, y);
      }
      canvas.drawPath(crestPath, crestPaint);
    }
  }

  /// Dibuja el pulpo y texto invirtiendo colores perfectamente según la onda de agua
  void _drawLogoWithLiquidInversion(
    Canvas canvas,
    Size size,
    Offset octopusCenter,
    double fitScale,
    double waveBandTop,
    double waveBandBottom,
  ) {
    if (mascotProgress <= 0.001) return;

    // Dibuja en la zona SUPERIOR (Sobre el agua -> Color Gris Oscuro / Negro Mockup)
    canvas.save();
    _drawLogoLayer(
      canvas,
      octopusCenter,
      fitScale,
      brandColor: const Color(0xFF0F172A),
    );
    canvas.restore();

    // Si la onda está activa, dibuja la zona SUBMERGIDA (Bajo el agua -> Color Plata Metálica)
    if (waveProgress > 0.001) {
      final waveHeight = _waveHeightFor(size, waveBandTop, waveBandBottom);

      final clipPath = Path();
      clipPath.moveTo(0, size.height);
      clipPath.lineTo(0, waveHeight);

      final waveAmplitude = 12.0 * math.sin(waveProgress * math.pi);
      const waveFrequency = 0.015;

      for (double x = 0; x <= size.width; x += 4) {
        final y = waveHeight +
            math.sin(x * waveFrequency + wavePhase) * waveAmplitude +
            math.cos(x * waveFrequency * 0.5 + wavePhase * 1.3) * (waveAmplitude * 0.4);
        clipPath.lineTo(x, y);
      }
      clipPath.lineTo(size.width, size.height);
      clipPath.close();

      canvas.save();
      canvas.clipPath(clipPath);
      _drawLogoLayer(
        canvas,
        octopusCenter,
        fitScale,
        brandColor: const Color(0xFFE2E8F0),
        isMetallicGlow: true,
      );
      canvas.restore();
    }
  }

  /// Dibuja los elementos del logo (Pulpo + Texto) para una capa de color dada
  void _drawLogoLayer(
    Canvas canvas,
    Offset octopusCenter,
    double fitScale, {
    required Color brandColor,
    bool isMetallicGlow = false,
  }) {
    final scale = (0.85 + (mascotProgress * 0.15)) * fitScale;
    final opacity = mascotProgress.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(octopusCenter.dx, octopusCenter.dy);
    canvas.scale(scale, scale);

    // 1. Dibujar el pulpo a partir de la imagen (assets/logos/octopus_mask.png)
    if (octopusImage != null) {
      _drawOctopusImage(canvas, octopusImage!, brandColor, opacity, isMetallicGlow: isMetallicGlow);
    }

    canvas.restore();

    // 2. Dibujar el texto "gearshield" si textProgress > 0
    if (textProgress > 0.001) {
      _drawGearShieldText(
        canvas,
        octopusCenter,
        textProgress,
        brandColor,
        opacity,
        fitScale,
      );
    }
  }

  /// Dibuja la imagen del pulpo (silueta con fondo y ojos ya transparentes)
  /// tiñéndola con [color] vía `BlendMode.srcIn`, de modo que el alfa de la
  /// imagen actúa como stencil y las zonas transparentes (fondo y ojos)
  /// dejan ver lo que haya debajo (fondo claro u onda de agua), igual que
  /// hacía antes el dibujo vectorial con sus "ojos" de color independiente.
  void _drawOctopusImage(Canvas canvas, ui.Image image, Color color, double opacity, {bool isMetallicGlow = false}) {
    const halfHeight = _mascotHalfExtent;
    final aspect = image.width / image.height;
    final halfWidth = halfHeight * aspect;

    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromCenter(center: Offset.zero, width: halfWidth * 2, height: halfHeight * 2);

    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color.withValues(alpha: opacity), BlendMode.srcIn)
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;

    if (isMetallicGlow) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5);
    }

    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  /// Dibuja el texto "gearshield" con revelación de máscara fluida
  void _drawGearShieldText(
    Canvas canvas,
    Offset octopusCenter,
    double progress,
    Color color,
    double mascotOpacity,
    double fitScale,
  ) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Tipografía idéntica al mockup (GearShield en Sans-Serif Moderno Condensado),
    // escalada por fitScale para que siempre quepa en el ancho real de pantalla.
    final textStyle = TextStyle(
      fontSize: 52 * fitScale,
      fontWeight: FontWeight.w800,
      fontFamily: 'Inter',
      letterSpacing: -1.8 * fitScale,
      height: 1.0,
    );

    final span = TextSpan(
      style: textStyle.copyWith(color: color.withValues(alpha: progress * mascotOpacity)),
      children: const [
        TextSpan(text: 'Gear', style: TextStyle(fontWeight: FontWeight.w900)),
        TextSpan(text: 'Shield', style: TextStyle(fontWeight: FontWeight.w500)),
      ],
    );

    textPainter.text = span;
    textPainter.layout();

    final textX = octopusCenter.dx + 68 * fitScale;
    final textY = octopusCenter.dy - (textPainter.height / 2) - 4;

    // Revelación por máscara de deslizamiento horizontal
    final clipWidth = textPainter.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(textX, textY - 10, clipWidth, textPainter.height + 20));

    textPainter.paint(canvas, Offset(textX, textY));
    canvas.restore();
  }

  /// Transición cinemática y morphing del pulpo hacia el widget de micrófono.
  /// El frame final (morphProgress -> 1.0) reproduce deliberadamente el mismo
  /// lenguaje visual que `GearShieldMicWidget` (anillos finos, muescas,
  /// ojos grabados en la montura, degradado claro y el mismo glifo
  /// `Icons.mic_rounded`) para que el corte hacia la pantalla principal se
  /// sienta como una continuación y no como un widget distinto pegado después.
  void _drawMorphingLogoAndMic(Canvas canvas, Offset center, double fitScale) {
    final rotation = morphProgress * math.pi * 2.0;
    // El giro se desacelera a medida que el pulpo se asienta como micrófono,
    // en vez de terminar la animación a mitad de un giro.
    final settleFactor = (1.0 - morphProgress).clamp(0.0, 1.0);
    final scale = (1.0 - morphProgress * 0.15) * fitScale;

    canvas.save();
    canvas.translate(center.dx, center.dy - (morphProgress * 40 * fitScale));
    canvas.rotate(rotation * 0.4 * settleFactor);
    canvas.scale(scale, scale);

    // Silueta del pulpo desvaneciéndose (misma paleta obsidiana/plata).
    final octopusOpacity = (1.0 - morphProgress).clamp(0.0, 1.0);
    if (octopusOpacity > 0.02 && octopusImage != null) {
      _drawOctopusImage(canvas, octopusImage!, const Color(0xFFE2E8F0), octopusOpacity * 0.9);
    }

    // Anillos finos concéntricos con muescas: evolución de los tentáculos,
    // dimensionados y coloreados para converger en los del widget real.
    const maxRadius = 100.0;
    for (int i = 1; i <= 3; i++) {
      final baseRadius = (maxRadius / 3) * i * morphProgress + micPulse * 6.0 * i;
      final ringColor = Color.lerp(const Color(0xFFE2E8F0), const Color(0xFF475569), morphProgress)!;

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = ringColor.withValues(alpha: ((0.85 - i * 0.15) * morphProgress).clamp(0.0, 1.0));
      canvas.drawCircle(Offset.zero, baseRadius, ringPaint);

      final notchColor = Color.lerp(const Color(0xFFE2E8F0), const Color(0xFF94A3B8), morphProgress)!;
      final notchPaint = Paint()
        ..color = notchColor.withValues(alpha: morphProgress.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      for (int a = 0; a < 6; a++) {
        final angle = (a * math.pi / 3) + rotation * 0.15;
        canvas.drawCircle(
          Offset(baseRadius * math.cos(angle), baseRadius * math.sin(angle)),
          2.5,
          notchPaint,
        );
      }
    }

    // Ojos agresivos heredados, ahora grabados en la montura exterior del mic.
    if (morphProgress > 0.15) {
      final eyeOpacity = ((morphProgress - 0.15) / 0.85).clamp(0.0, 1.0);
      final eyeColor = Color.lerp(const Color(0xFFF1F4F8), const Color(0xFF64748B), morphProgress)!;
      final eyePaint = Paint()
        ..color = eyeColor.withValues(alpha: eyeOpacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(0, -maxRadius * morphProgress + 14 * morphProgress);
      final leftEye = Path()
        ..moveTo(-12, -4)
        ..lineTo(-3, 0)
        ..lineTo(-10, 3)
        ..close();
      final rightEye = Path()
        ..moveTo(12, -4)
        ..lineTo(3, 0)
        ..lineTo(10, 3)
        ..close();
      canvas.drawPath(leftEye, eyePaint);
      canvas.drawPath(rightEye, eyePaint);
      canvas.restore();
    }

    // Núcleo del micrófono: mismo degradado que usa GearShieldMicWidget en reposo.
    final coreRadius = 45.0 * morphProgress;
    if (coreRadius > 0.5) {
      final coreColorA = Color.lerp(const Color(0xFF0F172A), const Color(0xFFF8FAFC), morphProgress)!;
      final coreColorB = Color.lerp(const Color(0xFF090D16), const Color(0xFFCBD5E1), morphProgress)!;
      final corePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [coreColorA, coreColorB],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: coreRadius));
      canvas.drawCircle(Offset.zero, coreRadius, corePaint);
    }

    // Ícono de micrófono: el mismo glifo Material que pinta GearShieldMicWidget,
    // para que el último frame del morphing sea indistinguible del widget real.
    if (morphProgress > 0.45) {
      final iconOpacity = ((morphProgress - 0.45) / 0.55).clamp(0.0, 1.0);
      final iconPainter = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(Icons.mic_rounded.codePoint),
          style: TextStyle(
            fontSize: 30 * morphProgress,
            fontFamily: Icons.mic_rounded.fontFamily,
            package: Icons.mic_rounded.fontPackage,
            color: const Color(0xFF0F172A).withValues(alpha: iconOpacity),
          ),
        )
        ..layout();
      iconPainter.paint(canvas, Offset(-iconPainter.width / 2, -iconPainter.height / 2));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GearShieldOctopusPainter oldDelegate) {
    return oldDelegate.mascotProgress != mascotProgress ||
        oldDelegate.textProgress != textProgress ||
        oldDelegate.waveProgress != waveProgress ||
        oldDelegate.wavePhase != wavePhase ||
        oldDelegate.morphProgress != morphProgress ||
        oldDelegate.micPulse != micPulse ||
        oldDelegate.octopusImage != octopusImage;
  }
}
