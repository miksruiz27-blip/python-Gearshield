import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
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
import '../services/pdf_download.dart';
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

  // GenUI State variables
  final TextEditingController _genUiPromptController = TextEditingController();
  bool _isGenUiProcessing = false;
  String _genUiLogText = 'Esperando intención del usuario... Listo para orquestar interfaz.';
  List<String> _genUiActiveWidgets = ['spectrogram', 'gauge', 'ab_player', 'gemini_note', 'pdf_preview'];
  double _genUiRiskProb = 89.4;
  bool _isExportingPdf = false;
  bool _isReportingBlacklist = false;
  bool _blacklistReportedForCurrentResult = false;

  // State mockup variables for settings
  final bool _autoPdfReport = true;
  final bool _realtimeAlerts = true;
  final bool _localFallbackEnabled = true;
  double _sensitivityThreshold = 65.0;
  String _apiEndpoint = GearShieldService.activeBaseUrl;

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
      debugPrint('[MobileDetectorScreen] Error listando dispositivos de entrada: $e');
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
        debugPrint('[MobileDetectorScreen] Fallback al verificar permiso: $e');
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
            debugPrint('[MobileDetectorScreen] path_provider no disponible: $e');
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
      debugPrint('[MobileDetectorScreen] Timeout iniciando AudioRecorder');
      try {
        await _audioRecorder.cancel();
      } catch (_) {}
    } catch (e) {
      startError = '$e';
      debugPrint('[MobileDetectorScreen] Error en AudioRecorder: $e');
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

    // Cerrar la grabación. Si el plugin nativo no responde, usamos la ruta
    // que ya conocíamos en vez de esperar para siempre.
    String? audioPath;
    try {
      audioPath = await _audioRecorder
          .stop()
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('[MobileDetectorScreen] Timeout en AudioRecorder.stop(); usando ruta conocida.');
      audioPath = _recordedAudioPath;
    } catch (e) {
      debugPrint('[MobileDetectorScreen] Error en AudioRecorder.stop(): $e');
      audioPath = _recordedAudioPath;
    }

    await _runAnalysis(
      audioPath: audioPath ?? _recordedAudioPath,
      spokenText: _spokenText,
      durationSec: durationSec,
    );
  }

  /// Abre el selector de archivos, toma una nota de voz (WAV/MP3/M4A/OGG/FLAC)
  /// y la manda por el mismo pipeline de análisis que la grabación en vivo.
  Future<void> _pickAndAnalyzeFile() async {
    if (_isListening || _isAnalyzing) return;

    PlatformFile? file;
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'Selecciona una nota de voz',
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'ogg', 'flac', 'aac'],
        withData: true,
      );
      if (res != null && res.files.isNotEmpty) {
        file = res.files.first;
      }
    } catch (e) {
      debugPrint('[MobileDetectorScreen] Error abriendo selector de archivos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el selector de archivos ($e)'),
            backgroundColor: VocalisTheme.error,
          ),
        );
      }
      return;
    }

    if (file == null) return; // usuario canceló
    final String fileName = file.name;
    final path = file.path;
    final bytes = file.bytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El archivo seleccionado no se pudo leer correctamente.'),
            backgroundColor: VocalisTheme.error,
          ),
        );
      }
      return;
    }

    const maxBytes = 50 * 1024 * 1024;
    int sizeBytes = file.size;
    if (sizeBytes > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El archivo supera el límite de 50MB.'),
            backgroundColor: VocalisTheme.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _latestResult = null;
      _recordedAudioPath = path;
      _spokenText = 'Archivo cargado: $fileName';
      _confidence = 1.0;
    });

    await _runAnalysis(
      audioPath: path,
      audioBytes: bytes,
      spokenText: '',
      durationSec: _estimateDurationSeconds(path ?? fileName, sizeBytes),
    );
  }

  /// Estimación de duración para el motor local de respaldo (el backend real
  /// no la necesita): WAV PCM 16-bit mono 16 kHz ≈ 32 KB/s; formatos
  /// comprimidos ≈ 16 KB/s a 128 kbps. Sólo se usa para dimensionar el timeline.
  double _estimateDurationSeconds(String path, int sizeBytes) {
    final lower = path.toLowerCase();
    final double bytesPerSec = lower.endsWith('.wav') || lower.endsWith('.flac')
        ? 32000.0
        : 16000.0;
    final est = sizeBytes / bytesPerSec;
    return est.clamp(1.5, 600.0);
  }

  /// Pipeline de análisis compartido (grabación en vivo y archivo subido).
  /// Nunca lanza excepción y siempre apaga el spinner `_isAnalyzing`.
  Future<void> _runAnalysis({
    required String? audioPath,
    List<int>? audioBytes,
    required String spokenText,
    required double durationSec,
  }) async {
    GearShieldResult? result;
    try {
      // Análisis remoto con tope global; si excede, motor local.
      result = await GearShieldService.analyzeVoice(
        audioPath: audioPath,
        audioBytes: audioBytes,
        spokenText: spokenText,
        durationSeconds: durationSec,
      ).timeout(const Duration(seconds: 60));
    } catch (e) {
      debugPrint('[MobileDetectorScreen] Análisis falló o excedió el tiempo: $e. Usando motor local.');
      try {
        result = await GearShieldService.runLocalFallback(
          spokenText: spokenText,
          durationSeconds: durationSec,
          audioPath: audioPath,
        );
      } catch (e2) {
        debugPrint('[MobileDetectorScreen] Motor local también falló: $e2');
      }
    } finally {
      // Pase lo que pase, nunca dejamos el spinner girando.
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          if (result != null) {
            _latestResult = result;
            _blacklistReportedForCurrentResult = false;
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
        _buildTopHeader(subtitle: 'Métricas Forenses & GenUI Orquestado por Gemini'),
        const SizedBox(height: 16),

        // 1. Probabilidad orgánica del último audio analizado
        AiProbabilityWidget(result: activeResult),
        const SizedBox(height: 18),

        // 2. Banner de Orquestación GenUI (prompt libre + casos rápidos)
        _buildGenUiOrchestrationBanner(),
        const SizedBox(height: 14),

        // Terminal Log de Orquestación Gemini (texto real de la respuesta de Gemini)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: VocalisTheme.forensicCanvas,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: VocalisTheme.forensicCanvasAlt),
          ),
          child: Row(
            children: [
              const Text(
                'gemini@gearshield-genui:~\$ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: VocalisTheme.accentEmerald,
                ),
              ),
              Expanded(
                child: Text(
                  _genUiLogText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: VocalisTheme.forensicHighEnergy,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Deck de widgets dinámicos orquestados por Gemini (o por los casos rápidos)
        if (_isGenUiProcessing)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator(color: VocalisTheme.primary)),
          )
        else
          ..._buildGenUiWidgetDeck(activeResult),
      ],
    );
  }

  Widget _buildGenUiOrchestrationBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: VocalisTheme.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: VocalisTheme.primaryContainer.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bolt_rounded, size: 14, color: VocalisTheme.primaryContainer),
                    SizedBox(width: 4),
                    Text(
                      'Gemini API Activo',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: VocalisTheme.primaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Campo de Entrada para Libre Consulta Conversacional GenUI (Gemini real)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _genUiPromptController,
                  decoration: InputDecoration(
                    hintText: 'Pregunta a Gemini (ej. "Compara la voz con una muestra humana")...',
                    hintStyle: const TextStyle(fontSize: 11, color: VocalisTheme.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: VocalisTheme.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: VocalisTheme.primaryContainer),
                    ),
                  ),
                  onSubmitted: _executeGenUiPrompt,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _executeGenUiPrompt(_genUiPromptController.text),
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

          const SizedBox(height: 12),
          const Text(
            'O selecciona un caso directo (sin llamar a Gemini):',
            style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
          ),
          const SizedBox(height: 8),

          // 6 Casos rápidos deterministas (instantáneos, sin red)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildGenUiPill('🔎 Explicación Forense', () => _setGenUiWidgetsLocal(
                    ['gemini_note'], 'Mostrando explicación forense generada por Gemini.')),
                const SizedBox(width: 8),
                _buildGenUiPill('📈 Espectrograma', () => _setGenUiWidgetsLocal(
                    ['spectrogram'], 'Renderizando espectrograma de frecuencia.')),
                const SizedBox(width: 8),
                _buildGenUiPill('🎚️ Medidor de Riesgo', () => _setGenUiWidgetsLocal(
                    ['gauge'], 'Renderizando medidor radial de riesgo biométrico.')),
                const SizedBox(width: 8),
                _buildGenUiPill('🔀 Comparar A/B', () => _setGenUiWidgetsLocal(
                    ['ab_player'], 'Renderizando comparador de audio A/B.')),
                const SizedBox(width: 8),
                _buildGenUiPill('📊 Estado de Reportes', () => _setGenUiWidgetsLocal(
                    ['audit_stats'], 'Cargando el resumen auditado de reportes.')),
                const SizedBox(width: 8),
                _buildGenUiPill('📜 Certificado PDF', () => _setGenUiWidgetsLocal(
                    ['pdf_preview'], 'Preparando el certificado PDF de auditoría.'), isDanger: true),
                const SizedBox(width: 8),
                _buildGenUiPill('🚫 Lista Negra', () => _setGenUiWidgetsLocal(
                    ['blacklist_stats'], 'Mostrando el total de intentos de engaño reportados.'), isDanger: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Activa un widget directamente (sin llamar a Gemini) para los casos rápidos.
  void _setGenUiWidgetsLocal(List<String> widgets, String logMessage) {
    setState(() {
      _genUiActiveWidgets = widgets;
      _genUiRiskProb = _activeMetricsResult.overallRiskAi;
      _genUiLogText = logMessage;
    });
  }

  /// Construye el stack de widgets activos según lo que decidió Gemini
  /// (o el caso rápido elegido). Vocabulario compartido con el backend
  /// `/gemini/genui-intent`: spectrogram, gauge, ab_player, gemini_note,
  /// pdf_preview, audit_stats.
  bool get _isRedCase => _activeMetricsResult.riskZone == 'ZONA_ROJA' || _activeMetricsResult.overallRiskAi >= 65.0;

  Future<void> _reportCurrentResultToBlacklist(GearShieldResult result) async {
    setState(() => _isReportingBlacklist = true);
    final total = await GearShieldService.reportToBlacklist(result);
    if (!mounted) return;
    setState(() {
      _isReportingBlacklist = false;
      if (total != null) _blacklistReportedForCurrentResult = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(total != null
            ? 'Voz reportada a la lista negra. Total de intentos: $total'
            : 'No se pudo reportar: el servidor no respondió.'),
        backgroundColor: total != null ? VocalisTheme.accentEmerald : VocalisTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Widget> _buildGenUiWidgetDeck(GearShieldResult result) {
    final List<Widget> deck = [];

    // Caso rojo detectado: GenUI ofrece automáticamente reportar a lista negra.
    if (_isRedCase) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VocalisTheme.error.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(color: VocalisTheme.error.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.report_gmailerrorred_rounded, color: VocalisTheme.error, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GenUI: Caso de Alto Riesgo Detectado',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: VocalisTheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Riesgo IA: ${result.overallRiskAi.toStringAsFixed(1)}% • ${result.label}',
              style: const TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blacklistReportedForCurrentResult ? VocalisTheme.accentEmerald : VocalisTheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_isReportingBlacklist || _blacklistReportedForCurrentResult)
                    ? null
                    : () => _reportCurrentResultToBlacklist(result),
                icon: _isReportingBlacklist
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_blacklistReportedForCurrentResult ? Icons.check_circle_rounded : Icons.gpp_bad_rounded, size: 18),
                label: Text(
                  _blacklistReportedForCurrentResult
                      ? 'Reportado a Lista Negra'
                      : (_isReportingBlacklist ? 'Reportando...' : 'Reportar a Lista Negra'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('spectrogram')) {
      deck.add(Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VocalisTheme.forensicCanvas,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: VocalisTheme.forensicCanvasAlt),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.graphic_eq_rounded, color: VocalisTheme.forensicHighEnergy, size: 18),
                    SizedBox(width: 8),
                    Text('Espectrograma de Frecuencia',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: VocalisTheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('16kHz STFT',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: VocalisTheme.forensicHighEnergy)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SpectrogramViewerWidget(result: result),
          ],
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('gauge')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: VocalisTheme.accentRose, size: 20),
                    SizedBox(width: 8),
                    Text('Riesgo Biométrico IA',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_genUiRiskProb > 65 ? VocalisTheme.accentRose : (_genUiRiskProb > 35 ? VocalisTheme.accentAmber : VocalisTheme.accentEmerald)).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (_genUiRiskProb > 65 ? VocalisTheme.accentRose : (_genUiRiskProb > 35 ? VocalisTheme.accentAmber : VocalisTheme.accentEmerald)).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _genUiRiskProb > 65 ? 'ALERTA DEEPFAKE' : (_genUiRiskProb > 35 ? 'VERIFICAR' : 'VOZ HUMANA REAL'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _genUiRiskProb > 65 ? VocalisTheme.accentRose : (_genUiRiskProb > 35 ? VocalisTheme.accentAmber : VocalisTheme.accentEmerald),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AiProbabilityWidget(result: result),
          ],
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('ab_player')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.compare_arrows_rounded, color: VocalisTheme.accentEmerald, size: 20),
                SizedBox(width: 8),
                Text('Comparador A/B de Audio',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            _buildAudioTrackItem('Track A: Voz Humana de Referencia', '${(100 - result.overallRiskAi).toStringAsFixed(1)}% Humano • Banco de Muestras', '0:14s', VocalisTheme.accentEmerald),
            const SizedBox(height: 8),
            _buildAudioTrackItem('Track B: Último Audio Analizado', '${result.overallRiskAi.toStringAsFixed(1)}% IA • ${result.label}', '0:09s', VocalisTheme.accentRose, isHighlight: result.overallRiskAi >= 50),
          ],
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('audit_stats')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: const AuditStatsWidget(),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('blacklist_stats')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: FutureBuilder<int>(
          future: GearShieldService.fetchBlacklistTotal(),
          builder: (context, snapshot) {
            final total = snapshot.data;
            return Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: VocalisTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.gpp_bad_rounded, color: VocalisTheme.error, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total de Intentos de Engaño',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VocalisTheme.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      snapshot.connectionState == ConnectionState.waiting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: VocalisTheme.error),
                            )
                          : Text(
                              '${total ?? 0}',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: VocalisTheme.error),
                            ),
                      const Text(
                        'Voces reportadas a la lista negra',
                        style: TextStyle(fontSize: 10, color: VocalisTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('gemini_note')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: GeminiAiExplanationWidget(result: result),
      ));
      deck.add(const SizedBox(height: 12));
      deck.add(EngineResultsWidget(result: result));
      deck.add(const SizedBox(height: 16));
    }

    if (_genUiActiveWidgets.contains('pdf_preview')) {
      deck.add(Container(
        padding: const EdgeInsets.all(16),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: VocalisTheme.accentAmber, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Certificado Forense en PDF',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Riesgo IA: ${result.overallRiskAi.toStringAsFixed(1)}% • ${result.label}',
              style: const TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: VocalisTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isExportingPdf ? null : () => _exportAndDownloadPdf(result),
              icon: _isExportingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                _isExportingPdf ? 'Generando en el servidor...' : 'Descargar Certificado PDF',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ));
      deck.add(const SizedBox(height: 16));
    }

    if (deck.isEmpty) {
      deck.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: VocalisTheme.glassCardDecoration(borderRadius: 14),
        child: Row(
          children: const [
            Icon(Icons.info_outline_rounded, color: VocalisTheme.primaryContainer, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Elige un caso rápido o escribe una consulta para que Gemini orqueste los widgets aquí abajo.',
                style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
              ),
            ),
          ],
        ),
      ));
    }

    return deck;
  }

  /// Pide el PDF forense real al backend (Railway) y lo descarga/guarda.
  /// Funciona en Web (descarga de navegador) y en escritorio/móvil (guardado local).
  Future<void> _exportAndDownloadPdf(GearShieldResult result) async {
    setState(() => _isExportingPdf = true);
    final bytes = await GearShieldService.exportForensicPdf(result.toJson());
    if (!mounted) return;
    setState(() => _isExportingPdf = false);

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo generar el PDF: el servidor no respondió.'),
          backgroundColor: VocalisTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final filename = 'GearShield_Reporte_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final savedPath = await savePdfBytes(bytes, filename);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(kIsWeb
            ? 'Descarga del certificado PDF iniciada.'
            : 'Certificado PDF guardado en: $savedPath'),
        backgroundColor: VocalisTheme.accentEmerald,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  Widget _buildGenUiPill(String label, VoidCallback onTap, {bool isDanger = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (isDanger ? VocalisTheme.accentRose : VocalisTheme.primary).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDanger ? VocalisTheme.accentRose : VocalisTheme.primary).withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDanger ? VocalisTheme.accentRose : VocalisTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioTrackItem(String title, String subtitle, String duration, Color color, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.05) : VocalisTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHighlight ? color.withValues(alpha: 0.3) : VocalisTheme.glassBorderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(Icons.play_arrow_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: VocalisTheme.textPrimary)),
                  Text(subtitle, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ],
          ),
          Text(duration, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: VocalisTheme.textSecondary)),
        ],
      ),
    );
  }

  void _executeGenUiPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;
    setState(() {
      _isGenUiProcessing = true;
      _genUiLogText = 'Orquestando GenUI para "$prompt"... Interpretando intención con Gemini...';
    });

    final activeResult = _activeMetricsResult;
    final res = await GeminiForensicService.resolveGenUiIntent(
      prompt,
      overallRiskAi: activeResult.overallRiskAi,
      maxAiProb: activeResult.maxAiProb,
      label: activeResult.label,
    );

    if (!mounted) return;
    final bool isGemini = res['source'] == 'gemini';
    setState(() {
      _isGenUiProcessing = false;
      _genUiActiveWidgets = (res['widgets'] as List?)?.cast<String>() ?? const ['gemini_note'];
      // No confiamos en que Gemini repita el score correctamente (a veces lo
      // devuelve en escala 0-1 en vez de 0-100): el riesgo real siempre viene
      // del motor ONNX, nunca del LLM.
      _genUiRiskProb = activeResult.overallRiskAi;
      _genUiLogText = '${isGemini ? 'Gemini GenUI' : 'GenUI (motor local, Gemini no disponible)'}: '
          '${res['response_text'] ?? 'Orquestando vista.'}';
    });
  }

  /// Tarjeta de perfil para usuario con sesión real (registrado o logueado).
  Widget _buildUserProfileCard(String displayName, String userEmail) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3525CD), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: VocalisTheme.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase() : '??',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: VocalisTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail,
                  style: const TextStyle(
                    fontSize: 13,
                    color: VocalisTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: VocalisTheme.accentEmerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Sesión Activa • Cuenta Verificada',
                      style: TextStyle(
                        fontSize: 11,
                        color: VocalisTheme.accentEmerald,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await HiveService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const GearShieldLoginScreen()),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout_rounded, color: VocalisTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de perfil para modo invitado: sin cuenta, invita a registrarse.
  Widget _buildGuestProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: VocalisTheme.glassCardDecoration(borderRadius: 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: VocalisTheme.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: VocalisTheme.glassBorderSubtle, width: 1.5),
            ),
            child: const Icon(Icons.person_outline_rounded, color: VocalisTheme.textSecondary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Invitado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: VocalisTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: VocalisTheme.accentAmber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VocalisTheme.accentAmber.withValues(alpha: 0.25)),
                      ),
                      child: const Text(
                        'SIN CUENTA',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.accentAmber,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Explorando sin iniciar sesión. Tus reportes no se respaldarán en la nube.',
                  style: TextStyle(
                    fontSize: 12,
                    color: VocalisTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VocalisTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const GearShieldLoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.login_rounded, size: 16),
                    label: const Text(
                      'Crear cuenta / Iniciar sesión',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // PANTALLA 4: SETTINGS (Ajustes Rediseñados)
  // ==========================================
  Widget _buildSettingsTab() {
    final bool isGuest = HiveService.isGuest();
    final String currentUsername = HiveService.getUsername() ?? '';
    final String userEmail = HiveService.getEmail() ?? '';
    final String displayName = isGuest ? 'Invitado' : currentUsername;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopHeader(subtitle: 'Perfil, Términos & Configuración'),
        const SizedBox(height: 16),

        // 1. SECCIÓN SUPERIOR: Widget de Invitado o Perfil de Usuario Real
        isGuest ? _buildGuestProfileCard() : _buildUserProfileCard(displayName, userEmail),

        const SizedBox(height: 20),

        // 2. SECCIÓN PRINCIPAL: Términos, Condiciones & Privacidad (RELLENO)
        _buildSettingsSectionHeader('LEGAL & PRIVACIDAD', Icons.gavel_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 18),
          child: Column(
            children: [
              // Tile Términos y Condiciones
              _buildLegalTile(
                title: 'Términos y Condiciones del Servicio',
                subtitle: 'Normas de uso del sistema biométrico y alcance del análisis forense de IA.',
                icon: Icons.description_outlined,
                onTap: () => _showTermsModal(context),
              ),
              const Divider(height: 24, color: VocalisTheme.glassBorderSubtle),
              // Tile Política de Privacidad
              _buildLegalTile(
                title: 'Política de Privacidad & Protección de Datos',
                subtitle: 'Garantía de cifrado local en Hive Vault y política de cero telemetría externa.',
                icon: Icons.privacy_tip_outlined,
                onTap: () => _showPrivacyModal(context),
              ),
              const Divider(height: 24, color: VocalisTheme.glassBorderSubtle),
              // Tile Licencias Open Source
              _buildLegalTile(
                title: 'Licencias & Reconocimientos de Código Abierto',
                subtitle: 'Especificaciones de ONNX Runtime, Flutter Web Engine, Hive DB y Gemini API.',
                icon: Icons.verified_user_outlined,
                onTap: () => _showLicensesModal(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 3. SECCIÓN CONFIGURACIÓN AVANZADA
        _buildSettingsSectionHeader('CONFIGURACIÓN AVANZADA & BASE DE DATOS', Icons.tune_rounded),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: VocalisTheme.glassCardDecoration(borderRadius: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Personalización de cuenta, calibración del motor ONNX y gestión de la Base de Datos local.',
                style: TextStyle(fontSize: 12, color: VocalisTheme.textSecondary),
              ),
              const SizedBox(height: 14),

              // Botón Entrar a Configuración Avanzada
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: VocalisTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                  shadowColor: VocalisTheme.primary.withValues(alpha: 0.3),
                ),
                onPressed: () => _showAdvancedSettingsDialog(context),
                icon: const Icon(Icons.settings_suggest_rounded, size: 20),
                label: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Abrir Configuración Avanzada',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 4. SECCIÓN ACERCA DEL SISTEMA
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLegalTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: VocalisTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: VocalisTheme.primary, size: 20),
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 2),
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
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: VocalisTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showTermsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: VocalisTheme.primary),
            SizedBox(width: 10),
            Text('Términos y Condiciones'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GEARSHIELD 2.0 - TÉRMINOS Y CONDICIONES DE SERVICIO\n\n'
            '1. Licencia de Uso Corporativo: GearShield proporciona servicios de análisis biométrico vocal e inferencia local de deepfakes exclusivamente para auditoría autorizada.\n\n'
            '2. Exención de Responsabilidad Forense: Los dictámenes generados por el motor ONNX constituyen evidencia analítica probabilística de apoyo y deben ser reconfirmados por peritos certificados en procesos judiciales.\n\n'
            '3. Propiedad Intelectual: Todos los algoritmos, modelos ONNX y marcas asociadas son propiedad exclusiva de la suite GearShield 2.0.',
            style: TextStyle(fontSize: 12, height: 1.5, color: VocalisTheme.textPrimary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined, color: VocalisTheme.accentEmerald),
            SizedBox(width: 10),
            Text('Política de Privacidad'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'GEARSHIELD 2.0 - POLÍTICA DE PRIVACIDAD & ARCO\n\n'
            '1. Privacidad Local Cifrada: El audio procesado se almacena de forma segura en la Bóveda Local (Hive Vault) del dispositivo sin enviar muestras biométricas a servidores externos sin su consentimiento.\n\n'
            '2. Cero Telemetría de Terceros: No compartimos datos de llamadas ni registros de voz con redes publicitarias ni entidades externas.\n\n'
            '3. Derecho de Eliminación: El usuario conserva la facultad de borrar su cuenta y eliminar de forma definitiva la base de datos local en cualquier momento.',
            style: TextStyle(fontSize: 12, height: 1.5, color: VocalisTheme.textPrimary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showLicensesModal(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'GearShield 2.0 Enterprise',
      applicationVersion: '1.0.0+1',
      applicationIcon: const Padding(
        padding: EdgeInsets.all(12.0),
        child: Icon(Icons.shield_rounded, size: 48, color: VocalisTheme.primary),
      ),
    );
  }

  void _showAdvancedSettingsDialog(BuildContext context) {
    final nameController = TextEditingController(text: HiveService.getUsername() ?? 'Invitado');
    final emailController = TextEditingController(text: HiveService.getEmail() ?? '');
    final passwordController = TextEditingController(text: '123456');
    final apiController = TextEditingController(text: _apiEndpoint);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 540),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Encabezado
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.tune_rounded, color: VocalisTheme.primary, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'Configuración Avanzada',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: VocalisTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            icon: const Icon(Icons.close_rounded, color: VocalisTheme.textSecondary),
                          ),
                        ],
                      ),
                      const Divider(height: 20),

                      const Text(
                        'MODIFICAR DATOS EN LA BASE DE DATOS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.primary,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Nombre
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nombre de Usuario / Firma',
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: VocalisTheme.primaryContainer),
                          filled: true,
                          fillColor: VocalisTheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Email
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Correo Electrónico de Cuenta',
                          prefixIcon: const Icon(Icons.email_outlined, color: VocalisTheme.primaryContainer),
                          filled: true,
                          fillColor: VocalisTheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Password
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Contraseña de Acceso',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: VocalisTheme.primaryContainer),
                          filled: true,
                          fillColor: VocalisTheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // API Endpoint
                      TextField(
                        controller: apiController,
                        decoration: InputDecoration(
                          labelText: 'URL Servidor API Backend',
                          prefixIcon: const Icon(Icons.dns_rounded, color: VocalisTheme.primaryContainer),
                          filled: true,
                          fillColor: VocalisTheme.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Umbral Slider
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
                        onChanged: (val) {
                          setModalState(() {
                            _sensitivityThreshold = val;
                          });
                          setState(() {});
                        },
                      ),

                      const SizedBox(height: 14),

                      // Botón Guardar Cambios en BD
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VocalisTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final newName = nameController.text.trim();
                          final newApi = apiController.text.trim();

                          if (newName.isNotEmpty) {
                            await HiveService.updateUserData(newName);
                          }
                          if (newApi.isNotEmpty) {
                            _apiEndpoint = newApi;
                          }

                          await LocalVaultService.saveSettings(
                            apiEndpoint: _apiEndpoint,
                            sensitivityThreshold: _sensitivityThreshold,
                            localFallbackEnabled: _localFallbackEnabled,
                            autoPdfReport: _autoPdfReport,
                            realtimeAlerts: _realtimeAlerts,
                          );

                          setState(() {});

                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Datos modificados y guardados en la Base de Datos exitosamente!'),
                                backgroundColor: VocalisTheme.accentEmerald,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'Guardar Cambios en Base de Datos',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(color: VocalisTheme.error, height: 1),
                      const SizedBox(height: 16),

                      // Sección Peligrosa: Eliminar Cuenta
                      const Text(
                        'GESTIÓN DE CUENTA & ELIMINACIÓN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: VocalisTheme.error,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Esta opción desconectará tu usuario y borrará permanentemente la información en la Base de Datos.',
                        style: TextStyle(fontSize: 11, color: VocalisTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),

                      // Botón Eliminar Cuenta
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VocalisTheme.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          _confirmDeleteAccount(dialogCtx, context);
                        },
                        icon: const Icon(Icons.delete_forever_rounded, size: 20),
                        label: const Text(
                          'Eliminar Cuenta Permanentemente',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext modalCtx, BuildContext parentCtx) {
    showDialog(
      context: modalCtx,
      builder: (confirmCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: VocalisTheme.error),
            SizedBox(width: 8),
            Text('¿Eliminar Cuenta?'),
          ],
        ),
        content: const Text(
          'Esta acción borrará tus credenciales de la Base de Datos local y eliminará permanentemente todo tu historial de reportes. Esta acción no se puede deshacer.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: VocalisTheme.error),
            onPressed: () async {
              Navigator.of(confirmCtx).pop();
              if (modalCtx.mounted) {
                Navigator.of(modalCtx).pop();
              }

              await HiveService.deleteAccount();

              if (parentCtx.mounted) {
                ScaffoldMessenger.of(parentCtx).showSnackBar(
                  const SnackBar(
                    content: Text('La cuenta ha sido eliminada permanentemente de la Base de Datos.'),
                    backgroundColor: VocalisTheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                Navigator.of(parentCtx).pushReplacement(
                  MaterialPageRoute(builder: (_) => const GearShieldLoginScreen()),
                );
              }
            },
            child: const Text('Eliminar Definitivamente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
    return InkWell(
      onTap: (_isListening || _isAnalyzing) ? null : _pickAndAnalyzeFile,
      borderRadius: BorderRadius.circular(16),
      child: _buildFileDropzoneBody(),
    );
  }

  Widget _buildFileDropzoneBody() {
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
                    'WAV, MP3, M4A, OGG, FLAC hasta 50MB',
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
            onPressed: (_isListening || _isAnalyzing) ? null : _pickAndAnalyzeFile,
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
          _buildNavItem(1, Icons.auto_awesome_rounded, 'Métricas'),
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
