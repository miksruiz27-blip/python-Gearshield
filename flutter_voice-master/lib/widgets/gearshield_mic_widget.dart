import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget de Micrófono Principal de GearShield.
/// Representa la evolución natural de la mascota del pulpo en la UI activa:
/// Mantiene la estética minimalista, tecnológica y agresiva en paleta Negro Obsidian + Gris Claro.
class GearShieldMicWidget extends StatefulWidget {
  final bool isListening;
  final bool isAnalyzing;
  final VoidCallback onTap;
  final double size;

  const GearShieldMicWidget({
    super.key,
    required this.isListening,
    required this.isAnalyzing,
    required this.onTap,
    this.size = 220.0,
  });

  @override
  State<GearShieldMicWidget> createState() => _GearShieldMicWidgetState();
}

class _GearShieldMicWidgetState extends State<GearShieldMicWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onTap: widget.isAnalyzing ? null : widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pulseController,
            _rotationController,
            _waveController,
          ]),
          builder: (context, child) {
            return CustomPaint(
              painter: _MicWidgetPainter(
                isListening: widget.isListening,
                isAnalyzing: widget.isAnalyzing,
                pulseValue: _pulseController.value,
                rotationAngle: _rotationController.value * math.pi * 2,
                wavePhase: _waveController.value * math.pi * 2,
              ),
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.isListening
                          ? const [Color(0xFFE11D48), Color(0xFF9F1239)]
                          : (widget.isAnalyzing
                              ? const [Color(0xFF6366F1), Color(0xFF4338CA)]
                              : const [Color(0xFFF8FAFC), Color(0xFFCBD5E1)]),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isListening
                            ? const Color(0xFFE11D48).withValues(alpha: 0.5)
                            : (widget.isAnalyzing
                                ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                                : const Color(0xFFE2E8F0).withValues(alpha: 0.25)),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isListening
                        ? Icons.stop_rounded
                        : (widget.isAnalyzing
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded),
                    size: 42,
                    color: (widget.isListening || widget.isAnalyzing)
                        ? Colors.white
                        : const Color(0xFF0F172A),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MicWidgetPainter extends CustomPainter {
  final bool isListening;
  final bool isAnalyzing;
  final double pulseValue;
  final double rotationAngle;
  final double wavePhase;

  _MicWidgetPainter({
    required this.isListening,
    required this.isAnalyzing,
    required this.pulseValue,
    required this.rotationAngle,
    required this.wavePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 10;

    // 1. Dibujar Anillos Cibernéticos Concéntricos (Evolución de los tentáculos)
    const ringCount = 3;
    for (int i = 1; i <= ringCount; i++) {
      final baseRadius = (maxRadius / ringCount) * i;
      final pulseOffset = isListening
          ? (pulseValue * 12.0 * i)
          : (isAnalyzing ? (math.sin(wavePhase + i) * 6.0) : (pulseValue * 4.0));

      final radius = (baseRadius + pulseOffset).clamp(0.0, maxRadius);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isListening ? 2.5 : 1.8
        ..color = isListening
            ? const Color(0xFFF43F5E).withValues(alpha: 0.8 - (i * 0.2))
            : (isAnalyzing
                ? const Color(0xFF818CF8).withValues(alpha: 0.8 - (i * 0.2))
                : const Color(0xFF475569).withValues(alpha: 0.4 - (i * 0.1)));

      canvas.drawCircle(center, radius, ringPaint);

      // Dibujar crestas geométricas angulares en los anillos (estética del pulpo)
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((i % 2 == 0 ? 1 : -1) * rotationAngle * 0.5);

      final notchPaint = Paint()
        ..color = isListening
            ? const Color(0xFFFB7185)
            : (isAnalyzing ? const Color(0xFFA5B4FC) : const Color(0xFF94A3B8))
        ..style = PaintingStyle.fill;

      for (int a = 0; a < 6; a++) {
        final angle = (a * math.pi / 3);
        final notchX = radius * math.cos(angle);
        final notchY = radius * math.sin(angle);
        canvas.drawCircle(Offset(notchX, notchY), 2.5, notchPaint);
      }

      canvas.restore();
    }

    // 2. Dibujar Ojos Agresivos diminutos grabados en la montura exterior
    canvas.save();
    canvas.translate(center.dx, center.dy - maxRadius + 14);
    final eyePaint = Paint()
      ..color = isListening
          ? const Color(0xFFF43F5E)
          : (isAnalyzing ? const Color(0xFF818CF8) : const Color(0xFF64748B))
      ..style = PaintingStyle.fill;

    // Ojo Izq
    final leftEye = Path()
      ..moveTo(-12, -4)
      ..lineTo(-3, 0)
      ..lineTo(-10, 3)
      ..close();
    canvas.drawPath(leftEye, eyePaint);

    // Ojo Der
    final rightEye = Path()
      ..moveTo(12, -4)
      ..lineTo(3, 0)
      ..lineTo(10, 3)
      ..close();
    canvas.drawPath(rightEye, eyePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MicWidgetPainter oldDelegate) {
    return oldDelegate.isListening != isListening ||
        oldDelegate.isAnalyzing != isAnalyzing ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.wavePhase != wavePhase;
  }
}
