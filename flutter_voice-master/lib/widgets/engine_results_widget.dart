import 'package:flutter/material.dart';
import '../models/gearshield_result.dart';
import '../theme/vocalis_theme.dart';

class EngineResultsWidget extends StatefulWidget {
  final GearShieldResult result;

  const EngineResultsWidget({super.key, required this.result});

  @override
  State<EngineResultsWidget> createState() => _EngineResultsWidgetState();
}

class _EngineResultsWidgetState extends State<EngineResultsWidget> {
  bool _isExplanationExpanded = true;
  bool _isTimelineExpanded = false;

  Color _getRiskColor(String riskZone) {
    switch (riskZone) {
      case 'ZONA_ROJA':
        return VocalisTheme.error;
      case 'ZONA_AMARILLA':
        return VocalisTheme.accentAmber;
      case 'ZONA_VERDE':
      default:
        return VocalisTheme.accentEmerald;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final riskColor = _getRiskColor(result.riskZone);

    return Container(
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de Resultados del Motor
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20.0),
                topRight: Radius.circular(20.0),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics_rounded, color: riskColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'RESULTADOS MOTOR GEARSHIELD 2.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: riskColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: riskColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    result.riskZone.replaceAll('_', ' '),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Diagnóstico Principal
                const Text(
                  'Diagnóstico del Motor:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),

                // Métricas (Riesgo Máximo vs Promedio)
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        'Riesgo Máximo',
                        '${result.maxAiProb.toStringAsFixed(1)}%',
                        Icons.trending_up_rounded,
                        result.maxAiProb >= 60 ? VocalisTheme.error : VocalisTheme.accentEmerald,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        'Promedio Biofísico',
                        '${result.avgAiProb.toStringAsFixed(1)}%',
                        Icons.speed_rounded,
                        VocalisTheme.primaryContainer,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Acción Requerida
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: VocalisTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VocalisTheme.glassBorderSubtle),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: VocalisTheme.textSecondary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Acción Requerida:',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: VocalisTheme.textTertiary),
                            ),
                            Text(
                              result.actionRequired.replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 12,
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

                const Divider(height: 24),

                // Sección Explicación del Motor
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isExplanationExpanded = !_isExplanationExpanded;
                    });
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.lightbulb_outline_rounded, color: VocalisTheme.primary, size: 20),
                          SizedBox(width: 6),
                          Text(
                            'Explicación Forense del Motor',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: VocalisTheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        _isExplanationExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: VocalisTheme.primary,
                      ),
                    ],
                  ),
                ),

                if (_isExplanationExpanded) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: VocalisTheme.surfaceContainerLow.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: VocalisTheme.glassBorderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildExplanationBullet(
                          'Análisis Biofísico 220-D',
                          'El motor GearShield 2.0 analiza 220 micro-características acústicas por ventana temporal.',
                        ),
                        const SizedBox(height: 6),
                        _buildExplanationBullet(
                          'Suavizado Exponencial (EMA)',
                          'Aplica suavizado temporal para prevenir falsos positivos y detectar splicing de síntesis de voz.',
                        ),
                        const SizedBox(height: 6),
                        _buildExplanationBullet(
                          'Evaluación de Riesgo (${result.riskZone})',
                          _getRiskExplanationText(result.riskZone),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Timeline desplegable de Ventanas Temporal
                if (result.timeline.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTimelineExpanded = !_isTimelineExpanded;
                      });
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.timeline_rounded, color: VocalisTheme.accentEmerald, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Línea de Tiempo Temporal (Ventanas)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.accentEmerald,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _isTimelineExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: VocalisTheme.accentEmerald,
                        ),
                      ],
                    ),
                  ),
                  if (_isTimelineExpanded) ...[
                    const SizedBox(height: 8),
                    Column(
                      children: result.timeline.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 85,
                                child: Text(
                                  '${item.startSec.toStringAsFixed(1)}s - ${item.endSec.toStringAsFixed(1)}s',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: VocalisTheme.textSecondary),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: item.probAi / 100.0,
                                    backgroundColor: VocalisTheme.surfaceContainerLow,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      item.isAi ? VocalisTheme.error : VocalisTheme.accentEmerald,
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${item.probAi.toStringAsFixed(1)}%',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: item.isAi ? VocalisTheme.error : VocalisTheme.accentEmerald,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 9, color: VocalisTheme.textSecondary)),
              Text(
                value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationBullet(String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline_rounded, color: VocalisTheme.primary, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11, color: VocalisTheme.textPrimary, height: 1.3),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: VocalisTheme.primary),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getRiskExplanationText(String riskZone) {
    switch (riskZone) {
      case 'ZONA_ROJA':
        return 'Se detectaron inconsistencias biofísicas graves o patrones de clonación neural. Audio marcado como Deepfake Sintético.';
      case 'ZONA_AMARILLA':
        return 'Se detectaron pequeñas variaciones sospechosas en la envolvente espectral o pitch. Se recomienda reconfirmación de voz.';
      case 'ZONA_VERDE':
      default:
        return 'Las características espectrales corresponden a tracto vocal humano orgánico sin huellas de síntesis de IA.';
    }
  }
}
