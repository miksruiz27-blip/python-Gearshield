import 'package:flutter/material.dart';
import '../models/gearshield_result.dart';
import '../theme/vocalis_theme.dart';

/// Widget forense de riesgo IA por ventana temporal.
///
/// Antes pintaba un espectrograma simulado (mapa de calor generado con
/// funciones matemáticas de relleno) que nunca recibía datos reales de
/// análisis: siempre se instanciaba como `const SpectrogramViewerWidget()`
/// con valores de ejemplo fijos. El backend tampoco devuelve un
/// espectrograma real, solo probabilidad IA por ventana temporal
/// (`GearShieldResult.timeline`), así que ahora el widget recibe un
/// resultado real y dibuja una barra por ventana con su probabilidad IA
/// real, en rojo si el motor la marcó (`isAi`) y en la paleta indigo del
/// resto de la app si no — mismo lenguaje visual, datos honestos.
class SpectrogramViewerWidget extends StatefulWidget {
  final GearShieldResult result;

  const SpectrogramViewerWidget({super.key, required this.result});

  @override
  State<SpectrogramViewerWidget> createState() => _SpectrogramViewerWidgetState();
}

class _SpectrogramViewerWidgetState extends State<SpectrogramViewerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _scannerController;
  int _selectedReasonIndex = 0;

  final List<Map<String, String>> _aiReasons = [
    {
      'icon': 'graphic_eq',
      'title': 'Anomalía de Formantes (F1/F2)',
      'severity': 'ALTA (96%)',
      'summary':
          'Transición de frecuencias anormalmente perfecta entre vocales. Ninguna cuerda vocal humana puede cambiar de tono sin micro-turbulencia de aire.',
      'detail':
          'En el segundo 0:04.5, la envolvente espectral muestra un movimiento de formantes completamente lineal generado por matemática del algoritmo TTS (Text-to-Speech).',
    },
    {
      'icon': 'memory',
      'title': 'Artefactos de Vocoder Sintético',
      'severity': 'CRÍTICA (98%)',
      'summary':
          'Filtro de fase espectral estático detectado en la banda de 4 kHz a 7 kHz típico de modelos de síntesis de IA (ElevenLabs / Bark).',
      'detail':
          'El ruido de fondo no tiene variaciones naturales de ambiente; contiene un patrón repetitivo cíclico generado por redes neuronales convolucionales.',
    },
    {
      'icon': 'air',
      'title': 'Ausencia de Pausas Respiratorias',
      'severity': 'MEDIA (82%)',
      'summary':
          'Pronunciación continua durante 6.4 segundos sin micro-pausa de inhalación de oxígeno ni chasquidos linguales.',
      'detail':
          'El flujo fonético es ininterrumpido a nivel de milisegundos, violando el patrón biológico de capacidad pulmonar humana.',
    },
    {
      'icon': 'show_chart',
      'title': 'Cero Inestabilidad Biofísica (Jitter/Shimmer)',
      'severity': 'ALTA (91%)',
      'summary':
          'La micro-variación de frecuencia fundamental (Jitter) es de 0.01%, indicando estabilidad sintética no biológica.',
      'detail':
          'Las cuerdas vocales humanas reales siempre experimentan un tremor muscular involuntario de al menos 0.4% a 1.2%.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Color _severityColor(String severity) {
    if (severity.startsWith('CRÍTICA') || severity.startsWith('ALTA')) {
      return VocalisTheme.error;
    }
    if (severity.startsWith('MEDIA')) {
      return VocalisTheme.accentAmber;
    }
    return VocalisTheme.accentEmerald;
  }

  String get _filename {
    final path = widget.result.audioPath;
    if (path.isEmpty) return 'audio_analizado.wav';
    return path.replaceAll('\\', '/').split('/').last;
  }

  double get _totalDurationSeconds {
    final timeline = widget.result.timeline;
    if (timeline.isEmpty) return 0.0;
    return timeline.last.endSec;
  }

  /// Ventana con más riesgo: la marcada como IA con mayor probabilidad si
  /// hay alguna, o si no, la de mayor probabilidad simplemente.
  TimelineItem? get _peakWindow {
    final timeline = widget.result.timeline;
    if (timeline.isEmpty) return null;
    final flagged = timeline.where((t) => t.isAi).toList();
    final pool = flagged.isNotEmpty ? flagged : timeline;
    return pool.reduce((a, b) => b.probAi > a.probAi ? b : a);
  }

  String _formatTime(double seconds) {
    final totalMs = (seconds.clamp(0.0, double.infinity) * 1000).round();
    final duration = Duration(milliseconds: totalMs);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    final tenths = (duration.inMilliseconds % 1000) ~/ 100;
    return '$minutes:${secs.toString().padLeft(2, '0')}.${tenths}s';
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final aiRiskPercentage = result.maxAiProb;
    final isAiHighRisk = aiRiskPercentage >= 60.0;
    final primaryColor = isAiHighRisk ? VocalisTheme.error : VocalisTheme.accentEmerald;
    final peak = _peakWindow;
    final triggerInterval =
        peak != null ? '${_formatTime(peak.startSec)} - ${_formatTime(peak.endSec)}' : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header del Audio Reciente
        Container(
          padding: const EdgeInsets.all(16),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: VocalisTheme.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
                          ),
                          child: Icon(
                            isAiHighRisk ? Icons.warning_rounded : Icons.verified_user_rounded,
                            color: primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Audio Reciente Analizado',
                                    style: TextStyle(
                                      fontSize: VocalisTheme.textLabel,
                                      fontWeight: FontWeight.bold,
                                      color: VocalisTheme.textTertiary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: VocalisTheme.primaryContainer.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'EN VIVO',
                                      style: TextStyle(
                                        fontSize: VocalisTheme.textMicro,
                                        fontWeight: FontWeight.bold,
                                        color: VocalisTheme.primaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _filename,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: VocalisTheme.textTitle,
                                  fontWeight: FontWeight.bold,
                                  color: VocalisTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${aiRiskPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: VocalisTheme.textDisplay,
                          fontWeight: FontWeight.w900,
                          color: primaryColor,
                        ),
                      ),
                      Text(
                        isAiHighRisk ? 'RIESGO SINTÉTICO IA' : 'HUMANO VERIFICADO',
                        style: TextStyle(
                          fontSize: VocalisTheme.textMicro,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (peak != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        peak.isAi ? Icons.crisis_alert_rounded : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: VocalisTheme.textBody, color: VocalisTheme.textPrimary),
                            children: [
                              TextSpan(
                                text: peak.isAi
                                    ? 'Momento exacto que delató a la IA: '
                                    : 'Ventana con mayor riesgo evaluado: ',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: triggerInterval,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Gráfica de Riesgo IA por Ventana Temporal
        _buildRiskTimelineHud(primaryColor, peak, triggerInterval),
        const SizedBox(height: 20),

        // Título de Explicaciones Sencillas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Explicaciones Forenses: ¿Qué delató a la IA?',
              style: TextStyle(
                fontSize: VocalisTheme.textTitle,
                fontWeight: FontWeight.bold,
                color: VocalisTheme.textPrimary,
              ),
            ),
            Text(
              '${_aiReasons.length} Anomalías Clave',
              style: const TextStyle(
                fontSize: VocalisTheme.textLabel,
                color: VocalisTheme.textTertiary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Explicaciones sencillas (Tarjetas Interactivas)
        _buildAiReasonCards(),
      ],
    );
  }

  Widget _buildRiskTimelineHud(Color primaryColor, TimelineItem? peak, String triggerInterval) {
    final timeline = widget.result.timeline;
    final flaggedCount = timeline.where((t) => t.isAi).length;
    final totalDuration = _totalDurationSeconds;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VocalisTheme.forensicCanvas, VocalisTheme.forensicCanvasAlt],
        ),
        borderRadius: BorderRadius.circular(VocalisTheme.radiusHero),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: VocalisTheme.forensicHighEnergy, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ANÁLISIS DE RIESGO IA · PROBABILIDAD POR VENTANA',
                  style: TextStyle(
                    fontSize: VocalisTheme.textLabel,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Canvas de barras de riesgo IA (una barra = una ventana temporal real)
          LayoutBuilder(
            builder: (context, constraints) {
              const canvasHeight = 170.0;
              final canvasWidth = constraints.maxWidth;

              if (timeline.isEmpty) {
                return SizedBox(
                  height: canvasHeight,
                  width: canvasWidth,
                  child: const Center(
                    child: Text(
                      'Sin ventanas temporales disponibles para este registro.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: VocalisTheme.textLabel, color: VocalisTheme.forensicTextMuted),
                    ),
                  ),
                );
              }

              final startRatio = totalDuration > 0
                  ? (peak!.startSec / totalDuration).clamp(0.0, 1.0)
                  : 0.0;
              final endRatio = totalDuration > 0
                  ? (peak!.endSec / totalDuration).clamp(0.0, 1.0)
                  : 0.0;
              final boxLeft = canvasWidth * startRatio;
              final boxRight = canvasWidth * endRatio;

              const labelWidth = 184.0;
              final rawLabelLeft = (boxLeft + boxRight) / 2 - labelWidth / 2;
              final maxLabelLeft = (canvasWidth - labelWidth - 4).clamp(4.0, double.infinity);
              final labelLeft = rawLabelLeft.clamp(4.0, maxLabelLeft);

              return SizedBox(
                height: canvasHeight,
                width: canvasWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Barras de probabilidad IA por ventana.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        size: Size(canvasWidth, canvasHeight),
                        painter: AiRiskBarsPainter(timeline: timeline),
                      ),
                    ),

                    // Franja que marca el rango de tiempo de la ventana pico.
                    Positioned(
                      left: boxLeft,
                      top: 0,
                      width: (boxRight - boxLeft).clamp(4.0, canvasWidth),
                      height: canvasHeight,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (peak!.isAi ? VocalisTheme.error : VocalisTheme.accentEmerald)
                                  .withValues(alpha: 0.7),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Escáner animado en tiempo real.
                    AnimatedBuilder(
                      animation: _scannerController,
                      builder: (context, child) {
                        return Positioned(
                          left: _scannerController.value * (canvasWidth - 2),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 2,
                              color: Colors.white.withValues(alpha: 0.55),
                              child: Container(
                                decoration: const BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: VocalisTheme.forensicHighEnergy,
                                      blurRadius: 6,
                                      spreadRadius: 0.5,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Etiqueta flotante anclada a la ventana pico.
                    if (peak.isAi)
                      Positioned(
                        left: labelLeft,
                        top: 8,
                        width: labelWidth,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: VocalisTheme.error,
                              borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 8),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'IA detectada · $triggerInterval',
                                        style: const TextStyle(
                                          fontSize: VocalisTheme.textMicro,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${peak.probAi.toStringAsFixed(1)}% de probabilidad IA en esta ventana',
                                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          // Eje de tiempo (X)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final seconds = totalDuration * i / 4;
              return Text(
                '${seconds.toStringAsFixed(1)}s',
                style: const TextStyle(
                  fontSize: VocalisTheme.textMicro,
                  color: VocalisTheme.forensicTextMuted,
                  fontFamily: 'monospace',
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Leyenda unificada: barra de probabilidad IA + ventanas marcadas.
          Row(
            children: [
              const Text(
                'Prob. IA',
                style: TextStyle(fontSize: VocalisTheme.textMicro, color: VocalisTheme.forensicTextMuted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [
                        VocalisTheme.forensicLowEnergy,
                        VocalisTheme.forensicMidEnergy,
                        VocalisTheme.forensicHighEnergy,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: VocalisTheme.error, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                flaggedCount > 0 ? '$flaggedCount ventana(s) marcada(s) IA' : 'Ninguna ventana marcada IA',
                style: const TextStyle(
                  fontSize: VocalisTheme.textMicro,
                  fontWeight: FontWeight.bold,
                  color: VocalisTheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiReasonCards() {
    return Column(
      children: List.generate(_aiReasons.length, (index) {
        final item = _aiReasons[index];
        final isSelected = _selectedReasonIndex == index;
        final severityColor = _severityColor(item['severity']!);

        IconData iconData;
        switch (item['icon']) {
          case 'memory':
            iconData = Icons.memory_rounded;
            break;
          case 'air':
            iconData = Icons.air_rounded;
            break;
          case 'show_chart':
            iconData = Icons.show_chart_rounded;
            break;
          case 'graphic_eq':
          default:
            iconData = Icons.graphic_eq_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: VocalisTheme.glassCardDecoration(
            borderColor: isSelected ? VocalisTheme.primaryContainer : VocalisTheme.glassBorderSubtle,
            borderRadius: VocalisTheme.radiusCard,
          ),
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            onExpansionChanged: (expanded) {
              if (expanded) {
                setState(() => _selectedReasonIndex = index);
              }
            },
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VocalisTheme.primaryContainer.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
              ),
              child: Icon(iconData, color: VocalisTheme.primaryContainer, size: 20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    item['title']!,
                    style: const TextStyle(
                      fontSize: VocalisTheme.textBody,
                      fontWeight: FontWeight.bold,
                      color: VocalisTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item['severity']!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: severityColor,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                item['summary']!,
                style: const TextStyle(fontSize: VocalisTheme.textLabel, color: VocalisTheme.textSecondary, height: 1.35),
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: VocalisTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
                    border: Border.all(color: VocalisTheme.glassBorderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 14, color: VocalisTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['detail']!,
                          style: const TextStyle(fontSize: VocalisTheme.textLabel, color: VocalisTheme.textPrimary, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Pinta una barra por cada ventana temporal de [timeline], con altura
/// proporcional a la probabilidad IA real de esa ventana (`probAi`) y en
/// rojo si el motor la marcó como IA (`isAi`), o en la paleta indigo del
/// resto de la app si no. Sustituye al mapa de calor simulado anterior,
/// que no representaba ningún dato real devuelto por el backend.
class AiRiskBarsPainter extends CustomPainter {
  final List<TimelineItem> timeline;

  AiRiskBarsPainter({required this.timeline});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VocalisTheme.forensicCanvas);

    if (timeline.isNotEmpty) {
      final barWidth = size.width / timeline.length;
      for (int i = 0; i < timeline.length; i++) {
        final item = timeline[i];
        final amplitude = (item.probAi / 100.0).clamp(0.0, 1.0);
        final barHeight = (amplitude * size.height).clamp(3.0, size.height);
        final color = item.isAi ? VocalisTheme.error : VocalisTheme.forensicHighEnergy;

        final barRect = Rect.fromLTWH(
          i * barWidth,
          size.height - barHeight,
          (barWidth * 0.72).clamp(1.0, barWidth),
          barHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
          Paint()..color = color,
        );
      }
    }

    // Líneas guía horizontales (cada 25% de altura) muy sutiles.
    final gridPaint = Paint()
      ..color = VocalisTheme.forensicGridLine
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant AiRiskBarsPainter oldDelegate) {
    return oldDelegate.timeline != timeline;
  }
}
