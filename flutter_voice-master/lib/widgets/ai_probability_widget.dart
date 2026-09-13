import 'package:flutter/material.dart';
import '../models/gearshield_result.dart';
import '../theme/vocalis_theme.dart';

class AiProbabilityWidget extends StatelessWidget {
  final GearShieldResult result;

  const AiProbabilityWidget({super.key, required this.result});

  /// Determina la zona de riesgo según la probabilidad de IA y el resultado.
  String _determineZone(double aiPercentage) {
    if (result.riskZone == 'ZONA_ROJA' || aiPercentage >= 65.0) {
      return 'ZONA_ROJA';
    } else if (result.riskZone == 'ZONA_AMARILLA' ||
        (aiPercentage >= 35.0 && aiPercentage <= 65.0)) {
      return 'ZONA_AMARILLA';
    } else {
      return 'ZONA_VERDE';
    }
  }

  Color _getRiskColor(String zone) {
    switch (zone) {
      case 'ZONA_ROJA':
        return VocalisTheme.error;
      case 'ZONA_AMARILLA':
        return VocalisTheme.accentAmber;
      case 'ZONA_VERDE':
      default:
        return VocalisTheme.accentEmerald;
    }
  }

  IconData _getRiskIcon(String zone) {
    switch (zone) {
      case 'ZONA_ROJA':
        return Icons.warning_rounded;
      case 'ZONA_AMARILLA':
        return Icons.gpp_maybe_rounded;
      case 'ZONA_VERDE':
      default:
        return Icons.verified_user_rounded;
    }
  }

  String _getHeaderTitle(String zone) {
    switch (zone) {
      case 'ZONA_ROJA':
        return '¡PELIGRO: DEEPFAKE / IA DETECTADA!';
      case 'ZONA_AMARILLA':
        return 'REVALIDACIÓN REQUERIDA (SOSPECHOSO)';
      case 'ZONA_VERDE':
      default:
        return 'PROBABILIDAD: VOZ ORGÁNICA';
    }
  }

  String _getCircleLabel(String zone) {
    switch (zone) {
      case 'ZONA_ROJA':
        return 'PELIGRO IA';
      case 'ZONA_AMARILLA':
        return 'REVALIDACIÓN';
      case 'ZONA_VERDE':
      default:
        return 'ORGÁNICO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double aiPercentage = result.overallRiskAi;
    final double humanPercentage = (100.0 - aiPercentage).clamp(0.0, 100.0);
    final String zone = _determineZone(aiPercentage);
    final Color riskColor = _getRiskColor(zone);

    // Seleccionar la probabilidad relevante a mostrar en el círculo principal ("la probabilidad de lo que es")
    double displayedPercentage;
    if (zone == 'ZONA_VERDE') {
      displayedPercentage = humanPercentage;
    } else if (zone == 'ZONA_ROJA') {
      displayedPercentage = aiPercentage;
    } else {
      // Zona Amarilla (Revalidación / Ambivalente): Mostrar la probabilidad dominante
      displayedPercentage = aiPercentage >= 50.0 ? aiPercentage : humanPercentage;
    }

    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: riskColor.withValues(alpha: 0.3),
        borderRadius: 20.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_getRiskIcon(zone), color: riskColor, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _getHeaderTitle(zone),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: riskColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: CircularProgressIndicator(
                  value: (displayedPercentage / 100.0).clamp(0.0, 1.0),
                  strokeWidth: 10,
                  backgroundColor: VocalisTheme.surfaceContainerLow,
                  valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${displayedPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: riskColor,
                    ),
                  ),
                  Text(
                    _getCircleLabel(zone),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: riskColor.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Barra de comparación Humano vs IA
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: humanPercentage.round().clamp(1, 100),
                    child: Container(color: VocalisTheme.accentEmerald),
                  ),
                  Expanded(
                    flex: aiPercentage.round().clamp(0, 100),
                    child: Container(color: VocalisTheme.error),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Voz Orgánica: ${humanPercentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: VocalisTheme.accentEmerald,
                ),
              ),
              Text(
                'Riesgo IA: ${aiPercentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: VocalisTheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
