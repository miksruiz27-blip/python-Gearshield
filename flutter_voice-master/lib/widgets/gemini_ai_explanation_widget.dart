import 'package:flutter/material.dart';
import '../models/gearshield_result.dart';
import '../services/gemini_forensic_service.dart';
import '../theme/vocalis_theme.dart';

/// Widget interactivo para mostrar el informe forense asistido por Gemini AI.
class GeminiAiExplanationWidget extends StatefulWidget {
  final GearShieldResult result;

  const GeminiAiExplanationWidget({super.key, required this.result});

  @override
  State<GeminiAiExplanationWidget> createState() =>
      _GeminiAiExplanationWidgetState();
}

class _GeminiAiExplanationWidgetState extends State<GeminiAiExplanationWidget> {
  Map<String, dynamic>? _analysisData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForensicAnalysis();
  }

  @override
  void didUpdateWidget(covariant GeminiAiExplanationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _loadForensicAnalysis();
    }
  }

  Future<void> _loadForensicAnalysis() async {
    setState(() => _isLoading = true);
    final data =
        await GeminiForensicService.generateForensicExplanation(widget.result);
    if (mounted) {
      setState(() {
        _analysisData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: VocalisTheme.primary),
            ),
            SizedBox(width: 12),
            Text(
              'Generando dictamen asistido por Gemini AI...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: VocalisTheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    final data = _analysisData!;
    final String status = data['status'] ?? '';
    final Color accentColor = status == 'ALERTA_CRÍTICA'
        ? VocalisTheme.error
        : (status == 'REVISION_SOSPECHOSA'
            ? VocalisTheme.accentAmber
            : VocalisTheme.accentEmerald);

    final List<dynamic> findings = data['findings'] as List<dynamic>? ?? [];

    return Container(
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con distinción Gemini AI
          Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20.0),
                topRight: Radius.circular(20.0),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data['title'] ?? 'Dictamen Gemini AI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    data['badge'] ?? 'IA Forense',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
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
                Text(
                  data['summary'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: VocalisTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hallazgos del Diagnóstico Biofísico:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                ...findings.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.brightness_1_rounded,
                            size: 6, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: VocalisTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),

                // Recomendación de Seguridad
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: VocalisTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VocalisTheme.glassBorderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: accentColor, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recomendación de Seguridad Gemini:',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data['action_recommendation'] ?? '',
                              style: const TextStyle(
                                fontSize: 11,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
