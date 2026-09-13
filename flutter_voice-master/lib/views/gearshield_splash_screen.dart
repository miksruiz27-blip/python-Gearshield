import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../widgets/gearshield_octopus_painter.dart';
import 'gearshield_login_screen.dart';

/// Pantalla de carga (Splash Screen) animada cinematográfica para GearShield.
/// Secuencia completa de 5 Fases:
/// 1. Aparición inicial del pulpo agresivo.
/// 2. Revelación sutil del texto "gearshield" desde la derecha.
/// 3. Ascenso de la onda de agua negra invirtiendo los tonos a plata metálico.
/// 4. Transformación morphing de la mascota al widget principal de micrófono.
/// 5. Transición fluida a la pantalla de detección interactiva.
class GearShieldSplashScreen extends StatefulWidget {
  final VoidCallback? onCompleted;

  const GearShieldSplashScreen({super.key, this.onCompleted});

  @override
  State<GearShieldSplashScreen> createState() => _GearShieldSplashScreenState();
}

class _GearShieldSplashScreenState extends State<GearShieldSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _waveWavefrontController;

  // Animaciones escalonadas por intervalos
  late Animation<double> _mascotAnim;
  late Animation<double> _textAnim;
  late Animation<double> _waveAnim;
  late Animation<double> _morphAnim;
  late Animation<double> _uiFadeAnim;

  bool _isCompleted = false;

  /// Imagen del pulpo cargada desde `assets/logos/octopus_mask.png`. Se
  /// carga de forma asíncrona porque `rootBundle`/`instantiateImageCodec`
  /// no son síncronos; mientras es null, el painter simplemente aún no
  /// dibuja la mascota (la animación no se bloquea por esto).
  ui.Image? _octopusImage;

  Future<void> _loadOctopusImage() async {
    final data = await rootBundle.load('assets/logos/octopus_mask.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _octopusImage = frame.image;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    _loadOctopusImage();

    // Duración total cinemática (~8.5 segundos)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8500),
    );

    // Animación continua de la fase de fluidos
    _waveWavefrontController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Fase 1: Aparición del Pulpo (0.0s -> 1.5s -> 0.0 - 0.18 del tiempo)
    _mascotAnim = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.18, curve: Curves.easeOutBack),
    );

    // Fase 2: Revelación de "gearshield" (1.5s -> 3.0s -> 0.18 - 0.35 del tiempo)
    _textAnim = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.18, 0.35, curve: Curves.easeInOutCubic),
    );

    // Fase 3: Onda de Agua Negra Ascendente (3.0s -> 6.5s -> 0.35 - 0.75 del tiempo)
    // Curva lineal a propósito: el ritmo "lento al cruzar al pulpo, rápido en
    // el resto" ya lo controla GearShieldOctopusPainter._waveHeightFor según
    // waveProgress. Si aquí se aplica además una curva easeInOutSine, esta
    // avanza más rápido justo en el tramo medio (donde el painter ya había
    // decidido ir lento), y el resultado es que la onda cruza al pulpo casi
    // instantáneamente — que es precisamente el efecto de "corte" que se
    // quería evitar.
    _waveAnim = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.35, 0.75, curve: Curves.linear),
    );

    // Fase 4: Morphing a Micrófono (6.5s -> 8.0s -> 0.75 - 0.94 del tiempo)
    _morphAnim = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.75, 0.94, curve: Curves.easeInOutBack),
    );

    // Fase 5: Transición fluida a UI principal (8.0s -> 8.5s -> 0.94 - 1.0 del tiempo)
    _uiFadeAnim = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.94, 1.0, curve: Curves.easeIn),
    );

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isCompleted = true;
        });
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        }
      }
    });

    _mainController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _waveWavefrontController.dispose();
    super.dispose();
  }

  void _skipOrProceed() {
    if (!_isCompleted) {
      _mainController.stop();
      setState(() {
        _isCompleted = true;
      });
      if (widget.onCompleted != null) {
        widget.onCompleted!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompleted) {
      return const GearShieldLoginScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      body: GestureDetector(
        onTap: _skipOrProceed,
        child: Stack(
          children: [
            // 0. Pantalla principal real, montada por debajo y revelada con un
            // fundido cruzado durante la Fase 5, en vez de un corte instantáneo
            // de un árbol de widgets a otro cuando termina el controller.
            AnimatedBuilder(
              animation: _uiFadeAnim,
              builder: (context, child) {
                if (_uiFadeAnim.value <= 0.0) return const SizedBox.shrink();
                return IgnorePointer(
                  child: Opacity(
                    opacity: _uiFadeAnim.value,
                    child: const GearShieldLoginScreen(),
                  ),
                );
              },
            ),

            // 1. Renderizado principal de la secuencia cinemática (CustomPainter)
            AnimatedBuilder(
              animation: Listenable.merge([
                _mainController,
                _waveWavefrontController,
              ]),
              builder: (context, child) {
                return FadeTransition(
                  opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_uiFadeAnim),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: GearShieldOctopusPainter(
                      mascotProgress: _mascotAnim.value,
                      textProgress: _textAnim.value,
                      waveProgress: _waveAnim.value,
                      wavePhase: _waveWavefrontController.value * 2.0 * 3.14159,
                      morphProgress: _morphAnim.value,
                      octopusImage: _octopusImage,
                    ),
                  ),
                );
              },
            ),

            // 2. Elemento de control sutil para saltar intro si el usuario lo requiere
            Positioned(
              top: 48,
              right: 20,
              child: AnimatedBuilder(
                animation: _waveAnim,
                builder: (context, child) {
                  final isDark = _waveAnim.value > 0.6;
                  return TextButton(
                    onPressed: _skipOrProceed,
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SALTAR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.fast_forward_rounded, size: 14),
                      ],
                    ),
                  );
                },
              ),
            ),

            // 3. Indicador de estado tecnológico inferior durante la carga
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _mainController,
                builder: (context, child) {
                  String statusText = 'INICIALIZANDO GEARSHIELD AI';
                  if (_mainController.value >= 0.18 && _mainController.value < 0.35) {
                    statusText = 'VERIFICANDO IDENTIDAD SENSORIAL';
                  } else if (_mainController.value >= 0.35 && _mainController.value < 0.75) {
                    statusText = 'CARGANDO MOTOR BIOFÍSICO DE AUDIO...';
                  } else if (_mainController.value >= 0.75) {
                    statusText = 'CONFIGURANDO SISTEMA DE MICRÓFONO';
                  }

                  final isDark = _waveAnim.value > 0.5;

                  return Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: (_mascotAnim.value > 0.5 && _morphAnim.value < 0.8) ? 0.9 : 0.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.8) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
