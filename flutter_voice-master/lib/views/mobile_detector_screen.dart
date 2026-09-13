import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/gearshield_result.dart';
import '../services/gearshield_service.dart';
import '../theme/vocalis_theme.dart';
import '../widgets/ai_probability_widget.dart';
import '../widgets/engine_results_widget.dart';
import '../widgets/gearshield_mic_widget.dart';
import '../widgets/spectrogram_viewer_widget.dart';
import '../widgets/gemini_ai_explanation_widget.dart';
import '../widgets/audit_stats_widget.dart';
import '../services/gemini_forensic_service.dart';
import '../services/hive_service.dart';
import '../services/local_vault_service.dart';
import 'gearshield_login_screen.dart';

class MobileDetectorScreen extends StatefulWidget {
  const MobileDetectorScreen({super.key});

  @override
  State<MobileDetectorScreen> createState() => _MobileDetectorScreenState();
}

class _MobileDetectorScreenState extends State<MobileDetectorScreen>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late AudioRecorder _audioRecorder;
  late AnimationController _pulseController;

  bool _isListening = false;
  bool _isAnalyzing = false;
  String _spokenText = '';
  double _confidence = 1.0;

  String? _recordedAudioPath;
  DateTime? _startTime;
  GearShieldResult? _latestResult;

  int _selectedNavIndex = 0;
  int _selectedFilterIndex = 0;

  // GenUI State variables
  final List<String> _genUiWidgetsStack = [];
  final TextEditingController _genUiPromptController = TextEditingController();
  bool _isGenUiProcessing = false;

  // State mockup variables for settings
  bool _autoPdfReport = true;
  bool _realtimeAlerts = true;
  bool _localFallbackEnabled = true;
  double _sensitivityThreshold = 65.0;
  String _apiEndpoint = GearShieldService.activeBaseUrl;
  final String _inferenceEngine = 'ONNX Runtime (Acelerado)';

  final List<Map<String, String>> _staticDetections = [
    {
      'title': 'Llamada Soporte Cliente #104',
      'category': 'SOPORTE',
      'duration': '0:14s',
      'time': 'Hoy, 1:15 PM',
      'amount': '12.5% IA',
      'transcription':
          '"Confirmación de identidad del titular de cuenta bancaria vía canal telefónico principal."',
      'card': 'Voz Orgánica Humana',
      'status': 'Aprobado',
      'statusColor': 'emerald',
    },
    {
      'title': 'Auditoría Clonación Voz #102',
      'category': 'SEGURIDAD',
      'duration': '0:09s',
      'time': 'Ayer',
      'amount': '89.4% IA',
      'transcription':
          '"Transferencia urgente solicitada imitando timbre vocal de ejecutivo sin modulación espectral."',
      'card': 'Voz Sintética Detectada',
      'status': 'Alerta Deepfake',
      'statusColor': 'error',
    },
    {
      'title': 'Verificación de Firma #103',
      'category': 'AUDITORÍA',
      'duration': '0:06s',
      'time': '12 Sep',
      'amount': '42.0% IA',
      'transcription':
          '"Prueba de voz con ligera distorsión en micrófono secundario. Requiere segunda validación."',
      'card': 'Reconfirmación Requerida',
      'status': 'Sospechoso',
      'statusColor': 'amber',
    },
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _audioRecorder = AudioRecorder();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initSpeech();
    _loadSavedEndpoint();
  }

  Future<void> _loadSavedEndpoint() async {
    await GearShieldService.loadSavedEndpoint();
    if (mounted) setState(() => _apiEndpoint = GearShieldService.activeBaseUrl);
  }

  /// Diálogo para cambiar la URL del backend (p.ej. IP LAN de la PC desde el celular)
  Future<void> _editApiEndpoint() async {
    final controller = TextEditingController(text: _apiEndpoint);
    final String? newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL de API Servidor'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.50:8000',
            helperText: 'En celular físico usa la IP LAN de la PC, no 127.0.0.1',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (newUrl == null) return;

    GearShieldService.setApiEndpoint(newUrl);
    await LocalVaultService.saveSettings(
      apiEndpoint: newUrl.trim(),
      sensitivityThreshold: _sensitivityThreshold,
      localFallbackEnabled: _localFallbackEnabled,
      autoPdfReport: _autoPdfReport,
      realtimeAlerts: _realtimeAlerts,
    );
    if (mounted) setState(() => _apiEndpoint = GearShieldService.activeBaseUrl);
  }

  void _initSpeech() async {
    try {
      await _speech.initialize(
        onStatus: (val) {},
        onError: (val) {},
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _genUiPromptController.dispose();
    _pulseController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // Busca un micrófono externo (USB o auriculares con cable) entre los
  // dispositivos de entrada disponibles. `record` no enruta automáticamente
  // a un micrófono USB conectado al celular: hay que seleccionarlo de forma
  // explícita en el RecordConfig o el sistema se queda con el micrófono
  // integrado del teléfono aunque el USB esté conectado.
  Future<InputDevice?> _pickExternalInputDevice() async {
    try {
      final devices = await _audioRecorder.listInputDevices();
      for (final d in devices) {
        if (d.type == InputDeviceType.usb) return d;
      }
      for (final d in devices) {
        if (d.type == InputDeviceType.wiredHeadset) return d;
      }
    } catch (e) {
      print('[MobileDetectorScreen] Error listando dispositivos de entrada: $e');
    }
    return null;
  }

  void _toggleListening() {
    if (!_isListening) {
      _startListening();
    } else {
      _stopListeningAndAnalyze();
    }
  }

  void _startListening() async {
    // 1. Solicitar permiso de micrófono (exclusivo para dispositivos móviles físicos)
    if (!kIsWeb) {
      try {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permiso de micrófono no concedido. Por favor habilítalo en los ajustes del dispositivo.'),
                backgroundColor: VocalisTheme.error,
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('[MobileDetectorScreen] Fallback al verificar permiso: $e');
      }
    }

    setState(() {
      _isListening = true;
      _spokenText = 'Escuchando audio... (Grabación en curso)';
      _latestResult = null;
      _startTime = DateTime.now();
    });

    bool recordedStarted = false;
    String startError = '';
    InputDevice? externalDevice;
    try {
      final hasPerm = await _audioRecorder
          .hasPermission()
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!hasPerm) {
        startError = 'Permiso de micrófono denegado por el sistema.';
      } else {
        if (!kIsWeb) {
          externalDevice = await _pickExternalInputDevice()
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
        }

        AudioEncoder encoder = AudioEncoder.wav;
        if (!await _audioRecorder.isEncoderSupported(AudioEncoder.wav)) {
          encoder = AudioEncoder.aacLc;
        }

        String recordPath = '';
        if (!kIsWeb) {
          try {
            final tempDir = await getTemporaryDirectory();
            final ext = (encoder == AudioEncoder.wav) ? 'wav' : 'm4a';
            recordPath = '${tempDir.path}/gear_audio_${DateTime.now().millisecondsSinceEpoch}.$ext';
          } catch (e) {
            print('[MobileDetectorScreen] path_provider no disponible: $e');
          }
        }
        _recordedAudioPath = recordPath.isNotEmpty ? recordPath : null;

        // manageBluetooth: false -> el plugin NO desvía la captura a auriculares /
        // relojes Bluetooth SCO emparejados (por defecto lo hace, y en Android 12+
        // eso deja el micrófono integrado del teléfono sin usar o cuelga start()
        // si el enlace SCO no conecta). Con device == null se usa el mic integrado.
        await _audioRecorder
            .start(
              RecordConfig(
                encoder: encoder,
                sampleRate: 16000,
                numChannels: 1,
                device: externalDevice,
                androidConfig: const AndroidRecordConfig(
                  manageBluetooth: false,
                  audioSource: AndroidAudioSource.mic,
                ),
              ),
              path: recordPath,
            )
            .timeout(const Duration(seconds: 10));
        recordedStarted = true;
      }
    } on TimeoutException {
      startError = 'El micrófono no respondió a tiempo (timeout).';
      print('[MobileDetectorScreen] Timeout iniciando AudioRecorder');
      try {
        await _audioRecorder.cancel();
      } catch (_) {}
    } catch (e) {
      startError = '$e';
      print('[MobileDetectorScreen] Error en AudioRecorder: $e');
    }

    // SpeechToText para transcripción en pantalla sólo si hay un micrófono externo.
    if (externalDevice != null) {
      try {
        bool available = await _speech.initialize(
          onError: (val) {},
        );
        if (available) {
          _speech.listen(
            onResult: (val) {
              if (mounted) {
                setState(() {
                  if (val.recognizedWords.isNotEmpty) {
                    _spokenText = val.recognizedWords;
                  }
                  if (val.hasConfidenceRating && val.confidence > 0) {
                    _confidence = val.confidence;
                  }
                });
              }
            },
          );
        }
      } catch (_) {}
    }

    if (!recordedStarted && mounted) {
      setState(() {
        _spokenText = 'No se pudo iniciar la grabación del micrófono. $startError'.trim();
        _isListening = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo iniciar la grabación. $startError'.trim()),
          backgroundColor: VocalisTheme.error,
        ),
      );
    }
  }

  void _stopListeningAndAnalyze() async {
    if (!_isListening) return;

    setState(() {
      _isListening = false;
      _isAnalyzing = true;
    });

    try {
      _speech.stop();
    } catch (_) {}

    double durationSec = 3.0;
    if (_startTime != null) {
      durationSec =
          DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
      if (durationSec < 1.0) durationSec = 1.5;
    }

    GearShieldResult? result;
    try {
      // 1. Cerrar la grabación. Si el plugin nativo no responde, usamos la ruta
      //    que ya conocíamos en vez de esperar para siempre.
      String? audioPath;
      try {
        audioPath = await _audioRecorder
            .stop()
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        print('[MobileDetectorScreen] Timeout en AudioRecorder.stop(); usando ruta conocida.');
        audioPath = _recordedAudioPath;
      } catch (e) {
        print('[MobileDetectorScreen] Error en AudioRecorder.stop(): $e');
        audioPath = _recordedAudioPath;
      }

      // 2. Análisis remoto con tope global; si excede, motor local.
      result = await GearShieldService.analyzeVoice(
        audioPath: audioPath ?? _recordedAudioPath,
        spokenText: _spokenText,
        durationSeconds: durationSec,
      ).timeout(const Duration(seconds: 60));
    } catch (e) {
      print('[MobileDetectorScreen] Análisis falló o excedió el tiempo: $e. Usando motor local.');
      try {
        result = await GearShieldService.runLocalFallback(
          spokenText: _spokenText,
          durationSeconds: durationSec,
          audioPath: _recordedAudioPath,
        );
      } catch (e2) {
        print('[MobileDetectorScreen] Motor local también falló: $e2');
      }
    } finally {
      // Pase lo que pase, nunca dejamos el spinner girando.
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          if (result != null) {
            _latestResult = result;
            // Navega automáticamente a la pestaña de métricas para mostrar el pergamino de resultados
            _selectedNavIndex = 1;
          } else {
            _spokenText = 'No se pudo analizar el audio. Intenta de nuevo.';
          }
        });
        if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo analizar el audio. Intenta de nuevo.'),
              backgroundColor: VocalisTheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VocalisTheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Atmospheric Background Blobs
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  color: VocalisTheme.meshIce,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -40,
              child: Container(
                width: 240,
                height: 240,
                decoration: const BoxDecoration(
                  color: VocalisTheme.meshLilac,
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // Contenido dinámico según la pestaña seleccionada
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: _buildCurrentTabContent(),
              ),
            ),

            // Bottom Navigation Bar Flotante (3 Pantallas: Voz, Métricas, Settings)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildBottomNavBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildVoiceTab();
      case 1:
        return _buildMetricsTab();
      case 2:
      default:
        return _buildSettingsTab();
    }
  }

  // Header superior unificado con el Pulpo GearShield
  Widget _buildTopHeader({String subtitle = 'Detección & Auditoría IA'}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: VocalisTheme.textPrimary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/logos/octopus_mask.png',
                fit: BoxFit.contain,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GearShield',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: VocalisTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // PANTALLA 1: VOZ (Botón Grabación + Subir Archivo)
  // ==========================================
  Widget _buildVoiceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildTopHeader(subtitle: 'Auditoría & Entrada de Voz'),
        const SizedBox(height: 12),
        _buildStatusPill(),
        const SizedBox(height: 24),
        _buildHeroRecordSection(),
        const SizedBox(height: 28),
        _buildFileDropzone(),
        const SizedBox(height: 20),
        if (_isAnalyzing) _buildAnalyzingState(),
        if (!_isAnalyzing && _latestResult != null) _buildResultBanner(),
      ],
    );
  }

  Widget _buildResultBanner() {
    final isSynth = _latestResult!.overallRiskAi >= 50.0;
    final bannerColor = isSynth ? VocalisTheme.error : VocalisTheme.accentEmerald;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: bannerColor.withValues(alpha: 0.4),
        borderRadius: 16,
      ),
      child: Row(
        children: [
          Icon(
            isSynth ? Icons.warning_rounded : Icons.verified_user_rounded,
            color: bannerColor,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Último Análisis Disponible',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: bannerColor,
                  ),
                ),
                Text(
                  _latestResult!.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: bannerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () {
              setState(() => _selectedNavIndex = 1);
            },
            icon: const Icon(Icons.description_rounded, size: 16),
            label: const Text(
              'Ver Métricas',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  GearShieldResult get _activeMetricsResult {
    return _latestResult ??
        GearShieldResult(
          audioPath: 'ultimo_audio_demo.wav',
          label: 'Voz Orgánica Humana (Último Audio)',
          riskZone: 'ZONA_VERDE',
          actionRequired: 'APROBADO_ACCESO_CONCEDIDO',
          overallRiskAi: 12.5,
          maxAiProb: 15.2,
          avgAiProb: 10.1,
          aiDetectedIntervals: const [],
          timeline: const [],
        );
  }

  // ==========================================
  // PANTALLA 2: MÉTRICAS (GenUI Orquestado por Gemini API)
  // ==========================================
  Widget _buildMetricsTab() {
    final activeResult = _activeMetricsResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(subtitle: 'Métricas Forenses & GenUI Orquestado'),
        const SizedBox(height: 16),

        // 1. WIDGET ÚNICO INICIAL: Probabilidad Orgánica del Último Audio (Solicitado por el usuario)
        AiProbabilityWidget(result: activeResult),
        const SizedBox(height: 18),

        // 2. PANEL DE ORQUESTACIÓN DE INTENCIÓN DE GEMINI API (3 Botones + Chatbot Prompt)
        _buildGenUiOrchestrationPanel(),
        const SizedBox(height: 18),

        // 3. RENDERIZADO DINÁMICO HACIA ABAJO (Stack de Widgets Generados por Gemini)
        if (_genUiWidgetsStack.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: VocalisTheme.glassCardDecoration(borderRadius: 14),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: VocalisTheme.primaryContainer, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Toca uno de los 3 casos arriba o escribe una duda para que Gemini orqueste y haga aparecer el widget dinámico hacia abajo.',
                    style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          ..._genUiWidgetsStack.asMap().entries.map((entry) {
            final index = entry.key;
            final intent = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildGenUiWidgetByIntent(intent, activeResult, index),
            );
          }),
      ],
    );
  }

  Widget _buildGenUiOrchestrationPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: VocalisTheme.glassCardDecoration(
        borderColor: VocalisTheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.auto_awesome, color: VocalisTheme.primaryContainer, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Orquestador GenUI de Gemini API',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: VocalisTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              if (_genUiWidgetsStack.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _genUiWidgetsStack.clear();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: VocalisTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.clear_all_rounded, size: 14, color: VocalisTheme.error),
                        SizedBox(width: 4),
                        Text(
                          'Limpiar Vista',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: VocalisTheme.error),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Selecciona uno de los 3 casos simples para generar su widget hacia abajo:',
            style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
          ),
          const SizedBox(height: 12),

          // 3 Botones de Selección Rápida (Los 3 casos pedidos por el usuario)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // CASO 1
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VocalisTheme.primaryContainer,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _handleGenUiChoice('EXPLANATION'),
                  icon: const Icon(Icons.saved_search_rounded, size: 16),
                  label: const Text(
                    'Caso 1: ¿Qué delató al último audio?',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),

                // CASO 2
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VocalisTheme.primaryContainer,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _handleGenUiChoice('SPECTROGRAM'),
                  icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                  label: const Text(
                    'Caso 2: Ver Espectrograma',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),

                // CASO 3
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VocalisTheme.primaryContainer,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _handleGenUiChoice('AUDIT_STATS'),
                  icon: const Icon(Icons.assessment_outlined, size: 16),
                  label: const Text(
                    'Caso 3: Estado de Reportes',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Campo de Entrada para Libre Consulta Conversacional GenUI
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _genUiPromptController,
                  decoration: InputDecoration(
                    hintText: 'Pregunta a Gemini GenUI (ej. "Muéstrame el espectrograma")...',
                    hintStyle: const TextStyle(fontSize: 11, color: VocalisTheme.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: VocalisTheme.primaryContainer),
                    ),
                  ),
                  onSubmitted: (val) => _sendGenUiQuery(val),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _sendGenUiQuery(_genUiPromptController.text),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: VocalisTheme.textPrimary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isGenUiProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleGenUiChoice(String intent) {
    setState(() {
      _genUiWidgetsStack.add(intent);
    });
  }

  void _sendGenUiQuery(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _genUiPromptController.clear();
    setState(() => _isGenUiProcessing = true);

    final res = await GeminiForensicService.resolveGenUiIntent(query);
    final String intent = res['intent'] ?? 'EXPLANATION';

    if (mounted) {
      setState(() {
        _isGenUiProcessing = false;
        _genUiWidgetsStack.add(intent);
      });
    }
  }

  Widget _buildGenUiWidgetByIntent(String intent, GearShieldResult result, int index) {
    Widget content;
    String labelText;
    IconData iconData;

    switch (intent) {
      case 'SPECTROGRAM':
        labelText = 'GenUI: Visor de Espectrograma';
        iconData = Icons.graphic_eq_rounded;
        content = SpectrogramViewerWidget(result: result);
        break;
      case 'AUDIT_STATS':
        labelText = 'GenUI: Resumen Auditado de Reportes';
        iconData = Icons.assessment_rounded;
        content = const AuditStatsWidget();
        break;
      case 'EXPLANATION':
      default:
        labelText = 'GenUI: Explicación de lo que Delató al Audio';
        iconData = Icons.auto_awesome;
        content = Column(
          children: [
            GeminiAiExplanationWidget(result: result),
            const SizedBox(height: 12),
            EngineResultsWidget(result: result),
          ],
        );
        break;
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10),
          child: content,
        ),
        Positioned(
          top: 0,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VocalisTheme.textPrimary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, color: Colors.white, size: 12),
                const SizedBox(width: 4),
                Text(
                  '$labelText #${index + 1}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // PANTALLA 3: SETTINGS (Ajustes Mockup)
  // ==========================================
  Widget _buildSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(subtitle: 'Configuración & Preferencias'),
        const SizedBox(height: 16),

        // Sección Servidor y Conexión
        _buildSettingsSectionHeader('SERVIDOR & CONEXIÓN API', Icons.dns_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
          child: Column(
            children: [
              _buildSettingsTile(
                title: 'URL de API Servidor',
                subtitle: _apiEndpoint,
                icon: Icons.link_rounded,
                trailing: TextButton(
                  onPressed: _editApiEndpoint,
                  child: const Text('Editar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const Divider(height: 20),
              _buildSettingsTile(
                title: 'Estado del Servidor API',
                subtitle: 'En línea • HTTP 200 (ONNX listo)',
                icon: Icons.cloud_done_rounded,
                trailing: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: VocalisTheme.accentEmerald,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _localFallbackEnabled,
                activeThumbColor: VocalisTheme.primaryContainer,
                onChanged: (val) => setState(() => _localFallbackEnabled = val),
                title: const Text(
                  'Respaldo Heurístico Local',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Ejecutar inferencia local si el backend no responde',
                  style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sección Motor Analítico
        _buildSettingsSectionHeader('MOTOR GEARSHIELD 2.0', Icons.memory_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsTile(
                title: 'Motor de Inferencia',
                subtitle: _inferenceEngine,
                icon: Icons.speed_rounded,
                trailing: const Icon(Icons.chevron_right_rounded, color: VocalisTheme.textTertiary),
              ),
              const Divider(height: 20),
              Text(
                'Umbral de Sensibilidad IA: ${_sensitivityThreshold.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary),
              ),
              Slider(
                value: _sensitivityThreshold,
                min: 30.0,
                max: 90.0,
                divisions: 12,
                activeColor: VocalisTheme.primaryContainer,
                label: '${_sensitivityThreshold.round()}%',
                onChanged: (val) => setState(() => _sensitivityThreshold = val),
              ),
              const Text(
                'Calibrado a 65% conforme especificación Altur HackMTY26',
                style: TextStyle(fontSize: 10, color: VocalisTheme.textTertiary),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sección Auditoría & Notificaciones
        _buildSettingsSectionHeader('AUDITORÍA & REPORTES', Icons.shield_outlined),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoPdfReport,
                activeThumbColor: VocalisTheme.primaryContainer,
                onChanged: (val) => setState(() => _autoPdfReport = val),
                title: const Text(
                  'Generación Automática de Reportes PDF',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Generar informe forense descargable en audios de 5% audit',
                  style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
                ),
              ),
              const Divider(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _realtimeAlerts,
                activeThumbColor: VocalisTheme.primaryContainer,
                onChanged: (val) => setState(() => _realtimeAlerts = val),
                title: const Text(
                  'Alertas Inmediatas de Clonación',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary),
                ),
                subtitle: const Text(
                  'Notificar eventos con riesgo IA superior al 75%',
                  style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sección Cuenta de Usuario & Sesión
        _buildSettingsSectionHeader('CUENTA DE USUARIO & SESIÓN', Icons.person_outline_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: VocalisTheme.primaryContainer.withValues(alpha: 0.15),
                    child: const Icon(Icons.person_rounded, color: VocalisTheme.primaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          HiveService.getUsername() ?? 'juanperez@gmail.com',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: VocalisTheme.textPrimary,
                          ),
                        ),
                        const Text(
                          'Sesión Activa • Base de Datos Conectada',
                          style: TextStyle(
                            fontSize: 11,
                            color: VocalisTheme.accentEmerald,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Botón Cerrar Sesión
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await HiveService.logout();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const GearShieldLoginScreen()),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18, color: VocalisTheme.textPrimary),
                      label: const Text(
                        'Cerrar Sesión',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Botón Eliminar Cuenta DB
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VocalisTheme.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('¿Eliminar Cuenta?'),
                            content: const Text(
                              'Esta acción conectará a la Base de Datos y eliminará permanentemente tu usuario y registros de reportes.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: VocalisTheme.error),
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  final userEmail = HiveService.getUsername() ?? 'juanperez@gmail.com';
                                  final result = await GearShieldService.deleteAccount(userEmail);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(result['message'] ?? 'Cuenta eliminada de la Base de Datos'),
                                        backgroundColor: VocalisTheme.error,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (_) => const GearShieldLoginScreen()),
                                    );
                                  }
                                },
                                child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_forever_rounded, size: 18),
                      label: const Text(
                        'Eliminar Cuenta',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Sección Información
        _buildSettingsSectionHeader('ACERCA DEL SISTEMA', Icons.info_outline_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
          child: Column(
            children: [
              _buildSettingsTile(
                title: 'Versión de la Aplicación',
                subtitle: 'GearShield 2.0 Enterprise v1.0.0+1',
                icon: Icons.verified_rounded,
              ),
              const Divider(height: 20),
              _buildSettingsTile(
                title: 'Cumplimiento Benchmark',
                subtitle: 'Altur HackMTY26 Compatible (POST /detect 8kHz Stereo Base64)',
                icon: Icons.task_alt_rounded,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: VocalisTheme.primaryContainer),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: VocalisTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: VocalisTheme.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: VocalisTheme.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: VocalisTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  // ==========================================
  // COMPONENTES DE UI AUXILIARES
  // ==========================================

  Widget _buildStatusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: VocalisTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VocalisTheme.glassBorderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isListening ? VocalisTheme.error : VocalisTheme.accentEmerald,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? VocalisTheme.error : VocalisTheme.accentEmerald)
                          .withValues(alpha: 0.4 + _pulseController.value * 0.4),
                      blurRadius: 6 * _pulseController.value,
                      spreadRadius: 2 * _pulseController.value,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            _isListening
                ? 'LISTENING IN REAL-TIME...'
                : (_isAnalyzing ? 'ANALYZING AUDIO...' : 'READY TO LISTEN'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: VocalisTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroRecordSection() {
    return Column(
      children: [
        GearShieldMicWidget(
          isListening: _isListening,
          isAnalyzing: _isAnalyzing,
          onTap: _toggleListening,
          size: 210,
        ),
        const SizedBox(height: 14),
        Text(
          _isListening
              ? 'Escuchando voz en tiempo real...'
              : (_isAnalyzing
                  ? 'Analizando firma de voz...'
                  : 'Toca el micrófono para Auditar Voz'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: VocalisTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _spokenText.isNotEmpty
              ? 'Transcripción (${(_confidence * 100).toStringAsFixed(0)}% precisión): "$_spokenText"'
              : 'Motor GearShield 2.0 • Detección de Deepfakes & Voces Sintéticas',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: VocalisTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildFileDropzone() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VocalisTheme.glassBorderSubtle, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: VocalisTheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.audio_file_outlined,
                    color: VocalisTheme.primaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Subir o arrastrar nota de voz',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: VocalisTheme.textPrimary,
                    ),
                  ),
                  Text(
                    'WAV, MP3, M4A, OGG hasta 50MB',
                    style: TextStyle(
                      fontSize: 10,
                      color: VocalisTheme.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: VocalisTheme.surfaceContainerLow,
              foregroundColor: VocalisTheme.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: () {},
            child: const Text('Examinar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 16),
      child: Column(
        children: const [
          CircularProgressIndicator(strokeWidth: 3, color: VocalisTheme.primary),
          SizedBox(height: 12),
          Text(
            'Procesando en Motor GearShield 2.0...',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: VocalisTheme.primary),
          ),
          SizedBox(height: 4),
          Text(
            'Extrayendo 220 características biofísicas temporales y suavizado EMA',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
          ),
        ],
      ),
    );
  }


  // Bottom Navigation Bar Flotante (3 Pantallas)
  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: VocalisTheme.glassBorderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x150F172A),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.mic_rounded, 'Voz'),
          _buildNavItem(1, Icons.description_rounded, 'Métricas'),
          _buildNavItem(2, Icons.settings_rounded, 'Settings'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedNavIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedNavIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 18 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? VocalisTheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : VocalisTheme.textSecondary,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
