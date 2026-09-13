import 'package:flutter/material.dart';
import '../../models/admin_stats.dart';
import '../../models/gearshield_result.dart';
import '../../services/gearshield_service.dart';
import '../../theme/vocalis_theme.dart';
import '../../widgets/spectrogram_viewer_widget.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<AdminStats> _statsFuture;
  late Future<List<DetectionLogEntry>> _logsFuture;
  bool _isLoading = false;

  // 0 = Módulo 1: Análisis Audio Reciente (Espectrograma & Explicaciones IA)
  // 1 = Módulo 2: Dashboard Auditoría Global (Falsos Positivos & Negativos)
  int _activeModuleTab = 0;
  int _activeFilterIndex = 0;

  // Mockup Data de Falsos Positivos y Negativos para Auditoría
  final List<Map<String, dynamic>> _falsePositivesAndNegatives = [
    {
      'id': 'FP-201',
      'type': 'FALSO POSITIVO',
      'typeColor': VocalisTheme.accentAmber,
      'filename': 'call_agent_ronco_009.wav',
      'speaker': 'Carlos Mendoza (Agente Venta)',
      'initialLabel': 'Marcado IA por error (74.0%)',
      'realNature': 'Voz Humana Orgánica',
      'reason': 'Distorsión de micrófono antiguo analógico + voz grave ronca.',
      'status': 'Exonerado / Corregido en Modelo',
      'timestamp': 'Hace 25 min',
    },
    {
      'id': 'FP-202',
      'type': 'FALSO POSITIVO',
      'typeColor': VocalisTheme.accentAmber,
      'filename': 'customer_hoarse_laryngitis.wav',
      'speaker': 'María Fernández (Cliente)',
      'initialLabel': 'Marcado IA por error (68.5%)',
      'realNature': 'Voz Humana Orgánica',
      'reason': 'Laringitis severa que alteró el ritmo natural de articulación.',
      'status': 'Pendiente Firma de Auditoría',
      'timestamp': 'Hace 1 hora',
    },
    {
      'id': 'FN-301',
      'type': 'FALSO NEGATIVO',
      'typeColor': VocalisTheme.error,
      'filename': 'stealth_deepfake_clone_v2.wav',
      'speaker': 'Desconocido (Intento de Fraude)',
      'initialLabel': 'Pasó como Humano (12.0% IA)',
      'realNature': 'Deepfake Sintético Avanzado',
      'reason': 'Superposición de ruido de lluvia sintético para camuflar el vocoder.',
      'status': 'REVELADO EN AUDITORÍA POSTERIOR',
      'timestamp': 'Hace 3 horas',
    },
  ];

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _statsFuture = GearShieldService.fetchAdminStats();
      _logsFuture = GearShieldService.fetchDetectionLogs();
    });
  }

  void _showReportDialog(DetectionLogEntry log) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.flag_outlined, color: VocalisTheme.accentAmber),
            SizedBox(width: 8),
            Text('Reportar Falso Positivo / Negativo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reg. ID: ${log.id} (${log.filename})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: VocalisTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo de la Discrepancia',
                hintText: 'Ej. Voz ronca, ruido de red, deepfake camuflado, etc.',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: VocalisTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: VocalisTheme.accentAmber,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final reason = reasonController.text.trim();
              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              final success = await GearShieldService.reportFalsePositive(
                log.id,
                reason.isEmpty ? 'Reportado en Auditoría' : reason,
              );

              if (mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Registro actualizado en auditoría.'
                          : 'Registrado localmente.',
                    ),
                    backgroundColor:
                        success ? VocalisTheme.accentEmerald : VocalisTheme.accentAmber,
                  ),
                );
                _refreshData();
              }
            },
            child: const Text('Confirmar Reporte',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VocalisTheme.surface,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: VocalisTheme.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAdminAppBar(),
                    const SizedBox(height: 16),

                    // Selector de Módulos (Tab Switcher de Módulos)
                    _buildModuleTabSelector(),
                    const SizedBox(height: 20),

                    // RENDERIZADO DEL MÓDULO SELECCIONADO
                    if (_activeModuleTab == 0) ...[
                      // MÓDULO 1: Análisis Audio Reciente (Riesgo IA & Explicaciones)
                      FutureBuilder<List<DetectionLogEntry>>(
                        future: _logsFuture,
                        builder: (context, snapshot) {
                          final logs = snapshot.data ?? const <DetectionLogEntry>[];
                          if (logs.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
                              child: const Center(
                                child: Text(
                                  'Aún no hay audio analizado para mostrar.',
                                  style: TextStyle(fontSize: 12, color: VocalisTheme.textSecondary),
                                ),
                              ),
                            );
                          }
                          return SpectrogramViewerWidget(
                            result: GearShieldResult.fromLogEntry(logs.first),
                          );
                        },
                      ),
                    ] else ...[
                      // MÓDULO 2: Dashboard Auditoría Global & Falsos Positivos/Negativos
                      _buildGlobalAuditDashboard(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAdminAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: VocalisTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Vocalis / GearShield',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: VocalisTheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: VocalisTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: VocalisTheme.accentEmerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'PANEL DE ADMINISTRACIÓN Y AUDITORÍA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: VocalisTheme.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: VocalisTheme.textSecondary),
            tooltip: 'Actualizar Estadísticas',
            onPressed: _refreshData,
          ),
        ],
      ),
    );
  }

  Widget _buildModuleTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: VocalisTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VocalisTheme.glassBorderSubtle),
      ),
      child: Row(
        children: [
          // Mód 1 Tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeModuleTab = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeModuleTab == 0
                      ? VocalisTheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeModuleTab == 0
                      ? const [
                          BoxShadow(
                            color: Color(0x1A4F46E5),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 16,
                      color: _activeModuleTab == 0
                          ? Colors.white
                          : VocalisTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Análisis Audio Reciente',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _activeModuleTab == 0
                            ? Colors.white
                            : VocalisTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Mód 2 Tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeModuleTab = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _activeModuleTab == 1
                      ? VocalisTheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _activeModuleTab == 1
                      ? const [
                          BoxShadow(
                            color: Color(0x1A4F46E5),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 16,
                      color: _activeModuleTab == 1
                          ? Colors.white
                          : VocalisTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Dashboard Auditoría Global',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _activeModuleTab == 1
                            ? Colors.white
                            : VocalisTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MÓDULO 2: DASHBOARD AUDITORÍA GLOBAL ---
  Widget _buildGlobalAuditDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKpiSection(),
        const SizedBox(height: 20),

        // SECCIÓN DESTACADA DE FALSOS POSITIVOS Y NEGATIVOS
        _buildFalsePositivesAndNegativesSection(),
        const SizedBox(height: 24),

        _buildFilterTabs(),
        const SizedBox(height: 16),
        _buildQueueHeader(),
        const SizedBox(height: 12),
        _buildPriorityCardsQueue(),
        const SizedBox(height: 24),
        _buildDynamicLogsSection(),
      ],
    );
  }

  Widget _buildKpiSection() {
    return FutureBuilder<AdminStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final stats = snapshot.data ?? AdminStats.fallback();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONTINUOUS AI VERIFICATION STREAM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: VocalisTheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.smart_toy_outlined,
                          size: 12, color: VocalisTheme.primary),
                      SizedBox(width: 4),
                      Text(
                        'Live Engine 4.2',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: VocalisTheme.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 16) / 3;
                return Row(
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildKpiCard(
                        title: 'Authenticity',
                        icon: Icons.verified_user_rounded,
                        iconColor: VocalisTheme.accentEmerald,
                        value:
                            '${(100.0 - stats.aiPercentage).toStringAsFixed(1)}%',
                        subtitle: 'Verified Voice',
                        detail:
                            '${stats.aiPercentage.toStringAsFixed(1)}% synthetic',
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: cardWidth,
                      child: _buildKpiCard(
                        title: 'Auto-Parsed',
                        icon: Icons.auto_awesome,
                        iconColor: VocalisTheme.primaryContainer,
                        value:
                            '\$${(stats.totalCalls * 42.5).toStringAsFixed(0)}',
                        subtitle: 'Pending Sign',
                        detail: '${stats.totalCalls} vocal logs',
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: cardWidth,
                      child: _buildKpiCard(
                        title: 'AI Flagged',
                        icon: Icons.warning_rounded,
                        iconColor: VocalisTheme.error,
                        value: '${stats.deepfakesCount} Alerts',
                        subtitle: 'Urgent Review',
                        detail: 'Deepfake Risk',
                        isErrorBg: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required String subtitle,
    required String detail,
    bool isErrorBg = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: isErrorBg
            ? VocalisTheme.error.withValues(alpha: 0.25)
            : VocalisTheme.glassBorderSubtle,
        bg: isErrorBg
            ? VocalisTheme.errorContainer.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isErrorBg
                        ? VocalisTheme.error
                        : VocalisTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isErrorBg ? VocalisTheme.error : VocalisTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color:
                  isErrorBg ? VocalisTheme.error : VocalisTheme.accentEmerald,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: isErrorBg ? VocalisTheme.error : VocalisTheme.textTertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFalsePositivesAndNegativesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: VocalisTheme.accentAmber.withValues(alpha: 0.3),
        borderRadius: VocalisTheme.radiusCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.rule_folder_rounded, color: VocalisTheme.accentAmber, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Modulo de Discrepancias: Falsos Positivos y Negativos',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: VocalisTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: VocalisTheme.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '3 CASOS AUDITADOS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.accentAmber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tarjetas de Discrepancias (Falsos Positivos & Falsos Negativos)
          Column(
            children: _falsePositivesAndNegatives.map((item) {
              final Color badgeColor = item['typeColor'] as Color;
              final bool isNegative = item['type'] == 'FALSO NEGATIVO';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VocalisTheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item['type']!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item['filename']!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          item['timestamp']!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: VocalisTheme.textTertiary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Diagnóstico Inicial:',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: VocalisTheme.textTertiary),
                              ),
                              Text(
                                item['initialLabel']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isNegative
                                      ? VocalisTheme.accentEmerald
                                      : VocalisTheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Naturaleza Real Auditada:',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: VocalisTheme.textTertiary),
                              ),
                              Text(
                                item['realNature']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isNegative
                                      ? VocalisTheme.error
                                      : VocalisTheme.accentEmerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: VocalisTheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: badgeColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Motivo: ${item['reason']}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: VocalisTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = [
      'All Submissions',
      'Needs Approval',
      'AI Flagged',
      'Verified Human',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (index) {
          final isSelected = _activeFilterIndex == index;
          final isFlaggedTab = index == 2;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFlaggedTab) ...[
                    const Icon(Icons.flag_rounded,
                        size: 14, color: VocalisTheme.error),
                    const SizedBox(width: 4),
                  ],
                  Text(filters[index]),
                  if (index == 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: VocalisTheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('8',
                          style: TextStyle(
                              fontSize: 10,
                              color: VocalisTheme.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                  if (isFlaggedTab) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: VocalisTheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('2',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              selectedColor: isFlaggedTab
                  ? VocalisTheme.errorContainer
                  : VocalisTheme.primary,
              backgroundColor: isFlaggedTab
                  ? VocalisTheme.errorContainer.withValues(alpha: 0.3)
                  : Colors.white,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? (isFlaggedTab ? VocalisTheme.error : Colors.white)
                    : (isFlaggedTab
                        ? VocalisTheme.error
                        : VocalisTheme.textSecondary),
              ),
              onSelected: (val) {
                setState(() => _activeFilterIndex = index);
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildQueueHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Text(
              'Voice Audio Audit Queue',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: VocalisTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: VocalisTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const Text(
          'Priority Sorting',
          style: TextStyle(
            fontSize: 11,
            color: VocalisTheme.textTertiary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityCardsQueue() {
    return Column(
      children: [
        // CARD 1: Sarah Jenkins - Standard Verified Log
        _buildAuditCard(
          avatarInitials: 'SJ',
          avatarBg: VocalisTheme.surfaceContainerHigh,
          avatarTextColor: VocalisTheme.primary,
          name: 'Sarah Jenkins',
          isVerified: true,
          subtitle: 'Client Dinner • Expensed today',
          amount: '\$184.50',
          amountSubtext: 'Auto-Calculated',
          authenticityMatchText: '99.8% Human Voice Match',
          syntheticBadgeText: '0% Deepfake',
          audioNoteTitle: 'Voice Note: "Dinner with Apex Partners"',
          audioDuration: '0:14s',
          waveformBars: [2, 3, 4, 2, 3.5, 4, 2, 3, 4, 2.5, 1.5, 2, 3, 1, 2, 1, 1.5, 1],
          isWaveformGlitched: false,
          merchant: 'Nobu Downtown',
          cardMatched: 'Amex 4092',
          category: 'Food & Bev',
          primaryActionText: 'Approve Expense',
          primaryActionIcon: Icons.check_rounded,
          onPrimaryAction: () {},
          secondaryActionText: 'Reject / Receipt',
          onSecondaryAction: () {},
        ),
        const SizedBox(height: 12),

        // CARD 2: Marcus Vance - AI SECURITY ALERT (Deepfake Risk)
        _buildDeepfakeAlertCard(
          avatarInitials: 'MV',
          name: 'Marcus Vance',
          subtitle: 'Urgent Wire Transfer',
          amount: '\$1,280.00',
          riskLevel: 'HIGH RISK',
          alertTitle: '⚠️ AI Alert: Synthetic Voice Artifacts Detected',
          syntheticScore: 'Score: 78% Synthetic',
          techDetail: 'Vocoder Freq Mismatch',
          statusText: 'Voice Authentication Failed',
          audioNoteTitle: 'Voice Sample: "Transfer to vendor immediately..."',
          audioDuration: '0:08s',
          waveformBars: [2, 3.5, 4, 3, 4, 2, 4, 3, 3, 1.5, 2, 1.5, 1, 2, 1.5, 1],
        ),
        const SizedBox(height: 12),

        // CARD 3: Elena Rostova - Flight & Receipt Match
        _buildAuditCard(
          avatarInitials: 'ER',
          avatarBg: VocalisTheme.surfaceContainerLow,
          avatarTextColor: VocalisTheme.textSecondary,
          name: 'Elena Rostova',
          isVerified: true,
          subtitle: 'Delta Airlines Flight • Q3 Summit',
          amount: '\$640.00',
          amountSubtext: 'Travel Desk',
          authenticityMatchText: 'Verified Authentic',
          syntheticBadgeText: 'Receipt & Voice Match Confirmed',
          audioNoteTitle: 'Vocal ticket match: DL-4091',
          audioDuration: '0:09s',
          waveformBars: [2, 3, 4, 3, 2, 3, 4, 2, 1.5, 2, 1],
          isWaveformGlitched: false,
          merchant: 'Delta Airlines',
          cardMatched: 'Card 1108',
          category: 'Travel',
          primaryActionText: 'Approve Expense',
          primaryActionIcon: Icons.check_rounded,
          onPrimaryAction: () {},
          secondaryActionText: null,
          onSecondaryAction: null,
        ),
      ],
    );
  }

  Widget _buildAuditCard({
    required String avatarInitials,
    required Color avatarBg,
    required Color avatarTextColor,
    required String name,
    required bool isVerified,
    required String subtitle,
    required String amount,
    required String amountSubtext,
    required String authenticityMatchText,
    required String syntheticBadgeText,
    required String audioNoteTitle,
    required String audioDuration,
    required List<double> waveformBars,
    required bool isWaveformGlitched,
    required String merchant,
    required String cardMatched,
    required String category,
    required String primaryActionText,
    required IconData primaryActionIcon,
    required VoidCallback onPrimaryAction,
    String? secondaryActionText,
    VoidCallback? onSecondaryAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: avatarBg,
                    child: Text(
                      avatarInitials,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: avatarTextColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.textPrimary),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.check_circle_rounded,
                                size: 16, color: VocalisTheme.accentEmerald),
                          ],
                        ],
                      ),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: VocalisTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amount,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.textPrimary)),
                  Text(amountSubtext,
                      style: const TextStyle(
                          fontSize: 10,
                          color: VocalisTheme.accentEmerald,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // AI Authenticity Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: VocalisTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: VocalisTheme.meshIce),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fingerprint_rounded,
                        size: 16, color: VocalisTheme.primary),
                    const SizedBox(width: 6),
                    Text(authenticityMatchText,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: VocalisTheme.textPrimary)),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: VocalisTheme.accentEmerald.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    syntheticBadgeText,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: VocalisTheme.accentEmerald),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Audio HUD Player
          _buildAudioPlayerHud(
              audioNoteTitle, audioDuration, waveformBars, isWaveformGlitched),
          const SizedBox(height: 8),

          // Data Points Grid
          Row(
            children: [
              Expanded(child: _buildDataChip('MERCHANT', merchant)),
              const SizedBox(width: 6),
              Expanded(child: _buildDataChip('CARD', cardMatched)),
              const SizedBox(width: 6),
              Expanded(child: _buildDataChip('CATEGORY', category)),
            ],
          ),
          const SizedBox(height: 10),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VocalisTheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: onPrimaryAction,
                  icon: Icon(primaryActionIcon, size: 16, color: Colors.white),
                  label: Text(primaryActionText,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              if (secondaryActionText != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    side: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionText,
                      style: const TextStyle(
                          fontSize: 12, color: VocalisTheme.textSecondary)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeepfakeAlertCard({
    required String avatarInitials,
    required String name,
    required String subtitle,
    required String amount,
    required String riskLevel,
    required String alertTitle,
    required String syntheticScore,
    required String techDetail,
    required String statusText,
    required String audioNoteTitle,
    required String audioDuration,
    required List<double> waveformBars,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: VocalisTheme.error.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: VocalisTheme.error.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: VocalisTheme.errorContainer,
                    child: Text(
                      avatarInitials,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.error),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.gpp_bad_rounded,
                              size: 16, color: VocalisTheme.error),
                        ],
                      ),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11,
                              color: VocalisTheme.error,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amount,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.error)),
                  Text(riskLevel,
                      style: const TextStyle(
                          fontSize: 10,
                          color: VocalisTheme.error,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Critical AI Risk Alert Pill
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VocalisTheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: VocalisTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.report_problem_rounded,
                    size: 18, color: VocalisTheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alertTitle,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: VocalisTheme.error),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              syntheticScore,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: VocalisTheme.error),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            techDetail,
                            style: const TextStyle(
                                fontSize: 9,
                                color: VocalisTheme.onErrorContainer,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Status Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: VocalisTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VocalisTheme.glassBorderSubtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.crisis_alert_rounded,
                        size: 14, color: VocalisTheme.error),
                    const SizedBox(width: 6),
                    Text(statusText,
                        style: const TextStyle(
                            fontSize: 11, color: VocalisTheme.textSecondary)),
                  ],
                ),
                const Text(
                  'Flagged Security',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: VocalisTheme.error),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Audio Player HUD Red Glitched
          _buildAudioPlayerHud(audioNoteTitle, audioDuration, waveformBars, true),
          const SizedBox(height: 10),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VocalisTheme.error,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.phone_in_talk_rounded,
                      size: 16, color: Colors.white),
                  label: const Text('Investigate / Call',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
                onPressed: () {},
                child: const Text('Dismiss Flag',
                    style: TextStyle(
                        fontSize: 12, color: VocalisTheme.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerHud(
      String title, String duration, List<double> bars, bool isGlitched) {
    final activeColor = isGlitched ? VocalisTheme.error : VocalisTheme.primary;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VocalisTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isGlitched
                ? VocalisTheme.error.withValues(alpha: 0.2)
                : VocalisTheme.glassBorderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: activeColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: isGlitched
                            ? VocalisTheme.error
                            : VocalisTheme.textTertiary,
                      ),
                    ),
                    Text(
                      duration,
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: VocalisTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: bars.map((val) {
                    return Container(
                      margin: const EdgeInsets.only(right: 2),
                      width: 3,
                      height: val * 3,
                      decoration: BoxDecoration(
                        color: isGlitched
                            ? VocalisTheme.error
                                .withValues(alpha: val > 2 ? 0.9 : 0.4)
                            : VocalisTheme.primary
                                .withValues(alpha: val > 2 ? 0.9 : 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: VocalisTheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VocalisTheme.glassBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  color: VocalisTheme.textTertiary,
                  fontWeight: FontWeight.bold)),
          Text(
            value,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: VocalisTheme.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicLogsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Live Backend Audit Log History',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary),
              ),
              Chip(
                avatar: Icon(Icons.circle,
                    color: VocalisTheme.accentEmerald, size: 8),
                label: Text('En Vivo', style: TextStyle(fontSize: 10)),
                backgroundColor: VocalisTheme.surfaceContainerLow,
              ),
            ],
          ),
          const Divider(height: 20),
          FutureBuilder<List<DetectionLogEntry>>(
            future: _logsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: VocalisTheme.primary),
                ));
              }

              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                      child: Text('No hay registros de audio procesados aún.')),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final log = logs[index];
                  return _buildDynamicLogRow(log);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicLogRow(DetectionLogEntry log) {
    final isAi = log.isSynthetic;
    final isFP = log.isFalsePositive;

    Color badgeColor = isFP
        ? VocalisTheme.accentAmber
        : (isAi ? VocalisTheme.error : VocalisTheme.accentEmerald);

    String statusText =
        isFP ? 'Falso Positivo' : (isAi ? 'IA / Deepfake' : 'Voz Humana');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFP
                  ? Icons.bug_report_rounded
                  : (isAi ? Icons.warning_rounded : Icons.check_circle_rounded),
              color: badgeColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      log.filename,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: VocalisTheme.textPrimary),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badgeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${log.location} • Reg: ${log.id}',
                  style: const TextStyle(
                      fontSize: 11, color: VocalisTheme.textTertiary),
                ),
                if (log.falsePositiveReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      'Motivo: ${log.falsePositiveReason}',
                      style: TextStyle(
                          fontSize: 10,
                          color: VocalisTheme.accentAmber,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${log.overallRiskAi.toStringAsFixed(1)}% IA',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isAi ? VocalisTheme.error : VocalisTheme.accentEmerald,
                ),
              ),
              if (!isFP && isAi)
                InkWell(
                  onTap: () => _showReportDialog(log),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Reportar FP',
                      style: TextStyle(
                        fontSize: 10,
                        color: VocalisTheme.accentAmber,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
