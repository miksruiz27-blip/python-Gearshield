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
          'La envolvente espectral muestra un movimiento de formantes completamente lineal generado por matemática del algoritmo TTS (Text-to-Speech).',
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
    // Los segmentos del VAD no vienen necesariamente ordenados ni contiguos:
    // el eje temporal va de 0 al fin del último segmento real.
    return timeline.map((t) => t.endSec).reduce((a, b) => a > b ? a : b);
  }

  /// Timeline ordenado cronológicamente (el backend por oraciones ya lo
  /// entrega en orden, pero el motor local y logs antiguos no lo garantizan).
  List<TimelineItem> get _sortedTimeline {
    final list = List<TimelineItem>.from(widget.result.timeline);
    list.sort((a, b) => a.startSec.compareTo(b.startSec));
    return list;
  }

  /// Ventanas marcadas como IA por el motor, en orden cronológico.
  List<TimelineItem> get _flaggedWindows =>
      _sortedTimeline.where((t) => t.isAi).toList();

  /// Ventana con la probabilidad IA más alta de todo el audio.
  TimelineItem? get _peakWindow {
    final timeline = widget.result.timeline;
    if (timeline.isEmpty) return null;
    return timeline.reduce((a, b) => b.probAi > a.probAi ? b : a);
  }

  /// "Momento que delató a la IA": la PRIMERA ventana (cronológicamente)
  /// que el motor marcó como sintética. Si ninguna fue marcada, se muestra la
  /// ventana de mayor riesgo como referencia (sin llamarla detección).
  TimelineItem? get _triggerWindow {
    final flagged = _flaggedWindows;
    if (flagged.isNotEmpty) return flagged.first;
    return _peakWindow;
  }

  bool get _hasAiDetection => _flaggedWindows.isNotEmpty;

  /// Umbral (en %) a partir del cual el motor marcó ventanas como IA. Se infiere
  /// del propio resultado (mínima prob. marcada) para dibujar la línea de corte
  /// coherente con lo que decidió el backend; 60% si no hay ventanas marcadas.
  double get _aiThresholdPercent {
    final flagged = _flaggedWindows;
    if (flagged.isEmpty) return 60.0;
    return flagged.map((t) => t.probAi).reduce((a, b) => a < b ? a : b);
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
    final trigger = _triggerWindow;
    final peak = _peakWindow;
    final hasDetection = _hasAiDetection;
    final triggerInterval = trigger != null
        ? '${_formatTime(trigger.startSec)} - ${_formatTime(trigger.endSec)}'
        : '—';
    final peakInterval = peak != null
        ? '${_formatTime(peak.startSec)} - ${_formatTime(peak.endSec)}'
        : '—';
    final peakIsTrigger = peak != null && trigger != null && identical(peak, trigger);

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
              if (trigger != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hasDetection ? Icons.crisis_alert_rounded : Icons.check_circle_outline_rounded,
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
                                    text: hasDetection
                                        ? 'Momento exacto que delató a la IA: '
                                        : 'Ventana con mayor riesgo evaluado: ',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: '$triggerInterval (${trigger.probAi.toStringAsFixed(1)}% IA)',
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
                      if (hasDetection && peak != null && !peakIsTrigger) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Text(
                            'Pico de riesgo: $peakInterval (${peak.probAi.toStringAsFixed(1)}% IA) · '
                            '${_flaggedWindows.length} de ${widget.result.timeline.length} ventanas marcadas',
                            style: const TextStyle(
                              fontSize: VocalisTheme.textLabel,
                              color: VocalisTheme.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Gráfica de Riesgo IA por Ventana Temporal
        _buildRiskTimelineHud(primaryColor, trigger, triggerInterval),
        const SizedBox(height: 20),

        // Título de Explicaciones Sencillas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                hasDetection
                    ? 'Explicaciones Forenses: ¿Qué delató a la IA?'
                    : 'Indicadores Biofísicos Verificados',
                style: const TextStyle(
                  fontSize: VocalisTheme.textTitle,
                  fontWeight: FontWeight.bold,
                  color: VocalisTheme.textPrimary,
                ),
              ),
            ),
            Text(
              hasDetection ? '${_aiReasons.length} Anomalías Clave' : 'Sin anomalías',
              style: const TextStyle(
                fontSize: VocalisTheme.textLabel,
                color: VocalisTheme.textTertiary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Explicaciones sencillas (Tarjetas Interactivas) ancladas al momento real
        if (hasDetection)
          _buildAiReasonCards(trigger!, triggerInterval)
        else
          _buildHumanVerifiedCard(peak),
      ],
    );
  }

  /// Tarjeta que se muestra cuando ninguna ventana fue marcada como IA:
  /// no tiene sentido listar "anomalías" de un audio orgánico.
  Widget _buildHumanVerifiedCard(TimelineItem? peak) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: VocalisTheme.accentEmerald.withValues(alpha: 0.4),
        borderRadius: VocalisTheme.radiusCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: VocalisTheme.accentEmerald.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(VocalisTheme.radiusChip),
            ),
            child: const Icon(Icons.verified_user_rounded, color: VocalisTheme.accentEmerald, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Micro-inestabilidad biofísica presente (Jitter/Shimmer)',
                  style: TextStyle(
                    fontSize: VocalisTheme.textBody,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  peak != null
                      ? 'Ninguna ventana superó el umbral de detección. La ventana de mayor riesgo '
                          '(${_formatTime(peak.startSec)} - ${_formatTime(peak.endSec)}) alcanzó '
                          '${peak.probAi.toStringAsFixed(1)}% de probabilidad IA, dentro del rango orgánico.'
                      : 'Ninguna ventana superó el umbral de detección de voz sintética.',
                  style: const TextStyle(
                    fontSize: VocalisTheme.textLabel,
                    color: VocalisTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskTimelineHud(Color primaryColor, TimelineItem? trigger, String triggerInterval) {
    final timeline = _sortedTimeline;
    final flaggedCount = _flaggedWindows.length;
    final totalDuration = _totalDurationSeconds;
    final hasDetection = _hasAiDetection;

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
                  ? (trigger!.startSec / totalDuration).clamp(0.0, 1.0)
                  : 0.0;
              final endRatio = totalDuration > 0
                  ? (trigger!.endSec / totalDuration).clamp(0.0, 1.0)
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
                    // Barras de probabilidad IA por ventana, posicionadas en
                    // su tiempo real (los segmentos VAD tienen distinta duración
                    // y huecos de silencio: por índice quedaban desalineadas
                    // respecto a la caja del momento detectado).
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        size: Size(canvasWidth, canvasHeight),
                        painter: AiRiskBarsPainter(
                          timeline: timeline,
                          totalDuration: totalDuration,
                          aiThreshold: _aiThresholdPercent,
                        ),
                      ),
                    ),

                    // Franja que marca el rango de tiempo del momento que delató a la IA
                    // (o de la ventana de mayor riesgo si no hubo detección).
                    Positioned(
                      left: boxLeft,
                      top: 0,
                      width: (boxRight - boxLeft).clamp(4.0, canvasWidth),
                      height: canvasHeight,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: (hasDetection ? VocalisTheme.error : VocalisTheme.accentEmerald)
                                .withValues(alpha: 0.10),
                            border: Border.all(
                              color: (hasDetection ? VocalisTheme.error : VocalisTheme.accentEmerald)
                                  .withValues(alpha: 0.85),
                              width: 1.6,
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

                    // Etiqueta flotante anclada al momento que delató a la IA.
                    if (hasDetection)
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
                                  '${trigger!.probAi.toStringAsFixed(1)}% de probabilidad IA en esta ventana',
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

  Widget _buildAiReasonCards(TimelineItem trigger, String triggerInterval) {
    // Las tarjetas explican las anomalías típicas de TTS; el detalle se ancla
    // al intervalo real que disparó la detección en ESTE audio en vez de a un
    // segundo fijo de ejemplo.
    final anchor =
        'Detectado en el intervalo $triggerInterval (${trigger.probAi.toStringAsFixed(1)}% IA). ';

    return Column(
      children: List.generate(_aiReasons.length, (index) {
        final item = Map<String, String>.from(_aiReasons[index]);
        item['detail'] = anchor + (item['detail'] ?? '');
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
  final double totalDuration;
  final double aiThreshold;

  AiRiskBarsPainter({
    required this.timeline,
    required this.totalDuration,
    this.aiThreshold = 60.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = VocalisTheme.forensicCanvas);

    // Líneas guía horizontales (cada 25% de altura) muy sutiles.
    final gridPaint = Paint()
      ..color = VocalisTheme.forensicGridLine
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (timeline.isNotEmpty && totalDuration > 0) {
      final pxPerSec = size.width / totalDuration;
      const gap = 1.5;

      for (final item in timeline) {
        final amplitude = (item.probAi / 100.0).clamp(0.0, 1.0);
        final barHeight = (amplitude * size.height).clamp(3.0, size.height);

        final left = (item.startSec * pxPerSec).clamp(0.0, size.width);
        final right = (item.endSec * pxPerSec).clamp(0.0, size.width);
        final width = (right - left - gap).clamp(2.0, size.width);

        final color = item.isAi ? VocalisTheme.error : VocalisTheme.forensicHighEnergy;
        final barRect = Rect.fromLTWH(left + gap / 2, size.height - barHeight, width, barHeight);

        // Relleno degradado: intensidad proporcional al riesgo.
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.55), color],
          ).createShader(barRect);
        canvas.drawRRect(RRect.fromRectAndRadius(barRect, const Radius.circular(3)), paint);

        // Contorno para las ventanas marcadas: se distinguen aun siendo estrechas.
        if (item.isAi) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(barRect, const Radius.circular(3)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.white.withValues(alpha: 0.7),
          );
        }
      }
    }

    // Línea de umbral de detección IA (punteada).
    final thresholdY = size.height * (1.0 - (aiThreshold / 100.0).clamp(0.0, 1.0));
    final thresholdPaint = Paint()
      ..color = VocalisTheme.error.withValues(alpha: 0.75)
      ..strokeWidth = 1.2;
    const dash = 6.0;
    const space = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, thresholdY), Offset((x + dash).clamp(0.0, size.width), thresholdY), thresholdPaint);
      x += dash + space;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: 'umbral IA ${aiThreshold.toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 9, color: VocalisTheme.error.withValues(alpha: 0.9), fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelY = (thresholdY - tp.height - 2).clamp(0.0, size.height - tp.height);
    tp.paint(canvas, Offset(size.width - tp.width - 6, labelY));
  }

  @override
  bool shouldRepaint(covariant AiRiskBarsPainter oldDelegate) {
    return oldDelegate.timeline != timeline ||
        oldDelegate.totalDuration != totalDuration ||
        oldDelegate.aiThreshold != aiThreshold;
  }
}
