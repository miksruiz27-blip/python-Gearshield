import 'package:flutter/material.dart';
import '../theme/vocalis_theme.dart';
import 'mobile_detector_screen.dart';

class GearShieldLoginScreen extends StatefulWidget {
  const GearShieldLoginScreen({super.key});

  @override
  State<GearShieldLoginScreen> createState() => _GearShieldLoginScreenState();
}

class _GearShieldLoginScreenState extends State<GearShieldLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _proceedToMainApp() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const MobileDetectorScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _handleLogin() async {
    setState(() {
      _isLoading = true;
    });

    // Simulación de autenticación (listo para conectar con backend/Firebase)
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _proceedToMainApp();
    }
  }

  void _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    // Simulación de Google Sign-In (preparado para Firebase GoogleAuthProvider)
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión iniciada con Google correctamente'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      _proceedToMainApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: VocalisTheme.surface,
      body: Stack(
        children: [
          // Fondo decorativo con gradientes suaves
          Positioned(
            top: -size.width * 0.3,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.8,
              height: size.width * 0.8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x224F46E5),
                    Color(0x004F46E5),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.width * 0.4,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x153525CD),
                    Color(0x003525CD),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Barra Superior con Botón de Tachar (Cerrar / Omitir)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48), // Espaciador simétrico
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: VocalisTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: VocalisTheme.primary.withValues(alpha: 0.15)),
                        ),
                        child: Row(
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
                              'GEARSHIELD 2.0',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: VocalisTheme.primary,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _proceedToMainApp,
                        tooltip: 'Omitir inicio de sesión',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: VocalisTheme.textSecondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),

                        // Logo del Pulpo GearShield
                        Hero(
                          tag: 'gearshield_logo',
                          child: Container(
                            width: 100,
                            height: 100,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: VocalisTheme.primary.withValues(alpha: 0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                              border: Border.all(
                                color: VocalisTheme.primaryContainer.withValues(alpha: 0.4),
                                width: 2,
                              ),
                            ),
                            child: Image.asset(
                              'assets/logos/octopus_mask.png',
                              fit: BoxFit.contain,
                              color: Colors.white,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.shield_rounded,
                                  size: 50,
                                  color: Colors.white,
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Título y Subtítulo
                        const Text(
                          'GearShield',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: VocalisTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Seguridad Biométrica Vocal & IA Audit',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: VocalisTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Card Formulario de Login
                        Container(
                          padding: const EdgeInsets.all(22.0),
                          decoration: VocalisTheme.glassCardDecoration(
                            bg: Colors.white.withValues(alpha: 0.9),
                            borderRadius: 24.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: VocalisTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Campo Email
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'Correo Electrónico',
                                  hintText: 'usuario@gearshield.com',
                                  prefixIcon: const Icon(Icons.email_outlined, color: VocalisTheme.primaryContainer),
                                  filled: true,
                                  fillColor: VocalisTheme.surfaceContainerLow,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: VocalisTheme.glassBorderSubtle),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: VocalisTheme.primary, width: 1.5),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Campo Password
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  hintText: '••••••••',
                                  prefixIcon: const Icon(Icons.lock_outline, color: VocalisTheme.primaryContainer),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: VocalisTheme.textTertiary,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  filled: true,
                                  fillColor: VocalisTheme.surfaceContainerLow,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: VocalisTheme.glassBorderSubtle),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: VocalisTheme.primary, width: 1.5),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Función de recuperación enviada a su correo'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 30),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    '¿Olvidaste tu contraseña?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: VocalisTheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // Botón Iniciar Sesión Primary
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VocalisTheme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 4,
                                  shadowColor: VocalisTheme.primary.withValues(alpha: 0.4),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Iniciar Sesión',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),

                              const SizedBox(height: 20),

                              // Separador "o"
                              Row(
                                children: [
                                  const Expanded(child: Divider(color: VocalisTheme.glassBorderSubtle)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                    child: Text(
                                      'o accede con',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: VocalisTheme.textTertiary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider(color: VocalisTheme.glassBorderSubtle)),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // Botón de Inicio con Google
                              OutlinedButton(
                                onPressed: _isLoading ? null : _handleGoogleSignIn,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: VocalisTheme.textPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  side: const BorderSide(color: VocalisTheme.glassBorderSubtle, width: 1.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 1,
                                  shadowColor: Colors.black.withValues(alpha: 0.05),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                      ),
                                      child: CustomPaint(
                                        painter: _GoogleGLogoPainter(),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      'Continuar con Google',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: VocalisTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Opción de entrar como invitado
                        TextButton(
                          onPressed: _proceedToMainApp,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Continuar como invitado',
                                style: TextStyle(
                                  color: VocalisTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: VocalisTheme.textSecondary,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
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
}

/// Painter vectorizado para el logo oficial multiculor 'G' de Google
class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paintRed = Paint()..color = const Color(0xFFEA4335);
    final paintBlue = Paint()..color = const Color(0xFF4285F4);
    final paintGreen = Paint()..color = const Color(0xFF34A853);
    final paintYellow = Paint()..color = const Color(0xFFFBBC05);

    // Azul (Barra derecha y arco inferior azul)
    final bluePath = Path()
      ..moveTo(w * 0.95, h * 0.5)
      ..cubicTo(w * 0.95, h * 0.44, w * 0.94, h * 0.38, w * 0.93, h * 0.33)
      ..lineTo(w * 0.5, h * 0.33)
      ..lineTo(w * 0.5, h * 0.52)
      ..lineTo(w * 0.76, h * 0.52)
      ..cubicTo(w * 0.75, h * 0.60, w * 0.70, h * 0.67, w * 0.63, h * 0.72)
      ..lineTo(w * 0.63, h * 0.86)
      ..lineTo(w * 0.78, h * 0.86)
      ..cubicTo(w * 0.88, h * 0.77, w * 0.95, h * 0.65, w * 0.95, h * 0.5);
    canvas.drawPath(bluePath, paintBlue);

    // Verde (Arco inferior izquierdo)
    final greenPath = Path()
      ..moveTo(w * 0.5, h * 0.95)
      ..cubicTo(w * 0.63, h * 0.95, w * 0.74, h * 0.91, w * 0.82, h * 0.83)
      ..lineTo(w * 0.67, h * 0.71)
      ..cubicTo(w * 0.62, h * 0.74, w * 0.56, h * 0.76, w * 0.5, h * 0.76)
      ..cubicTo(w * 0.36, h * 0.76, w * 0.24, h * 0.67, w * 0.20, h * 0.54)
      ..lineTo(w * 0.05, h * 0.66)
      ..cubicTo(w * 0.13, h * 0.83, w * 0.30, h * 0.95, w * 0.5, h * 0.95);
    canvas.drawPath(greenPath, paintGreen);

    // Amarillo (Arco izquierdo)
    final yellowPath = Path()
      ..moveTo(w * 0.20, h * 0.54)
      ..cubicTo(w * 0.18, h * 0.49, w * 0.17, h * 0.44, w * 0.17, h * 0.39)
      ..cubicTo(w * 0.17, h * 0.34, w * 0.18, h * 0.29, w * 0.20, h * 0.24)
      ..lineTo(w * 0.05, h * 0.12)
      ..cubicTo(w * 0.01, h * 0.20, 0, h * 0.29, 0, h * 0.39)
      ..cubicTo(0, h * 0.49, w * 0.01, h * 0.58, w * 0.05, h * 0.66)
      ..lineTo(w * 0.20, h * 0.54);
    canvas.drawPath(yellowPath, paintYellow);

    // Rojo (Arco superior)
    final redPath = Path()
      ..moveTo(w * 0.5, h * 0.17)
      ..cubicTo(w * 0.58, h * 0.17, w * 0.65, h * 0.20, w * 0.71, h * 0.25)
      ..lineTo(w * 0.83, h * 0.13)
      ..cubicTo(w * 0.74, h * 0.05, w * 0.63, 0, w * 0.5, 0)
      ..cubicTo(w * 0.30, 0, w * 0.13, h * 0.12, w * 0.05, h * 0.29)
      ..lineTo(w * 0.20, h * 0.41)
      ..cubicTo(w * 0.24, h * 0.28, w * 0.36, h * 0.17, w * 0.5, h * 0.17);
    canvas.drawPath(redPath, paintRed);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
