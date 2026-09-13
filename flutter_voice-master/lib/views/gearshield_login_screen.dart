import 'package:flutter/material.dart';
import '../theme/vocalis_theme.dart';
import '../services/gearshield_service.dart';
import 'mobile_detector_screen.dart';

class GearShieldLoginScreen extends StatefulWidget {
  const GearShieldLoginScreen({super.key});

  @override
  State<GearShieldLoginScreen> createState() => _GearShieldLoginScreenState();
}

class _GearShieldLoginScreenState extends State<GearShieldLoginScreen> {
  final _emailController = TextEditingController(text: 'juanperez@gmail.com');
  final _passwordController = TextEditingController(text: '12345');
  final _fullNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
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
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese correo y contraseña'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await GearShieldService.login(email, password);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Sesión iniciada correctamente'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        _proceedToMainApp();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Error iniciando sesión'),
            backgroundColor: VocalisTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleRegister() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese correo y contraseña'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (password.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña debe tener al menos 5 caracteres'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await GearShieldService.register(
      email,
      password,
      fullName: fullName.isEmpty ? null : fullName,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Cuenta creada correctamente'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        _proceedToMainApp();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Error al crear la cuenta'),
            backgroundColor: VocalisTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    // Simulación de Google Sign-In
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
    return Scaffold(
      backgroundColor: VocalisTheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          if (isDesktop) {
            return _buildDesktopLayout(context);
          } else {
            return _buildMobileLayout(context);
          }
        },
      ),
    );
  }

  /// Layout para pantallas anchas (Laptop / Web App - Split Screen)
  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Panel Izquierdo: Hero Branding & Valor Agregado
        Expanded(
          flex: 5,
          child: _buildDesktopHeroPanel(),
        ),

        // Panel Derecho: Formulario de Login Centrado
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              // Fondo decorativo sutil
              Positioned(
                top: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VocalisTheme.primary.withValues(alpha: 0.05),
                  ),
                ),
              ),

              // Botón de Omitir / Cerrar en la esquina superior derecha
              Positioned(
                top: 24,
                right: 28,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _proceedToMainApp,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text(
                        'Omitir / Invitado',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: VocalisTheme.textSecondary,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: VocalisTheme.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        backgroundColor: Colors.white,
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Formulario Centrado
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                  child: _buildLoginFormCard(context, isDesktop: true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Panel Hero Branding para Escritorio / Laptop
  Widget _buildDesktopHeroPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Luces decorativas en fondo oscuro
          Positioned(
            top: -120,
            left: -120,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VocalisTheme.primary.withValues(alpha: 0.25),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VocalisTheme.primaryContainer.withValues(alpha: 0.18),
              ),
            ),
          ),

          // Contenido Hero
          Padding(
            padding: const EdgeInsets.all(52.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Badge de versión superior
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: VocalisTheme.accentEmerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'GEARSHIELD 2.0 WEB APP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Centro: Logo, Titulo y Características
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'gearshield_logo',
                      child: Container(
                        width: 90,
                        height: 90,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: VocalisTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(
                            color: VocalisTheme.primaryContainer.withValues(alpha: 0.5),
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
                              size: 46,
                              color: Colors.white,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'GearShield',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Seguridad Biométrica Vocal & Auditoría de IA en Tiempo Real',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF94A3B8),
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 38),

                    _buildFeatureItem(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Detección de Deepfakes Vocales',
                      subtitle: 'Inferencia biométrica acelerada con motor local ONNX.',
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureItem(
                      icon: Icons.verified_user_outlined,
                      title: 'Auditoría & Certificados PDF',
                      subtitle: 'Generación instantánea de dictámenes forenses firmados.',
                    ),
                    const SizedBox(height: 16),
                    _buildFeatureItem(
                      icon: Icons.laptop_chromebook_rounded,
                      title: 'Consola Web Optimizada',
                      subtitle: 'Panel multitarea diseñado para pantallas de alta resolución.',
                    ),
                  ],
                ),

                // Footer
                Row(
                  children: const [
                    Icon(Icons.shield_outlined, color: Color(0xFF64748B), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Motor Biométrico v2.0 • Conexión Segura Corporativa',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: const Color(0xFF818CF8), size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Layout para pantallas estrechas / tablets / móviles (< 900px)
  Widget _buildMobileLayout(BuildContext context) {
    return Stack(
      children: [
        // Fondos decorativos acotados
        Positioned(
          top: -120,
          right: -100,
          child: Container(
            width: 320,
            height: 340,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x224F46E5), Color(0x004F46E5)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -100,
          child: Container(
            width: 340,
            height: 340,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x153525CD), Color(0x003525CD)],
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // Barra Superior
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                            'GEARSHIELD 2.0 WEB',
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
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Hero(
                          tag: 'gearshield_logo',
                          child: Container(
                            width: 84,
                            height: 84,
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
                                  size: 42,
                                  color: Colors.white,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'GearShield',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: VocalisTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Seguridad Biométrica Vocal & IA Audit',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: VocalisTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Form Card (Con constraint máximo de 440px)
                        _buildLoginFormCard(context, isDesktop: false),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Card reutilizable del Formulario de Inicio de Sesión
  Widget _buildLoginFormCard(BuildContext context, {required bool isDesktop}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: EdgeInsets.all(isDesktop ? 32.0 : 22.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: isDesktop ? 0.07 : 0.05),
            blurRadius: isDesktop ? 28 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isRegisterMode ? 'Crear Cuenta' : 'Iniciar Sesión',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: VocalisTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isRegisterMode
                ? 'Regístrate para respaldar tus reportes en la nube'
                : 'Accede a la consola web con tus credenciales',
            style: const TextStyle(
              fontSize: 12,
              color: VocalisTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 18),

          // Selector Iniciar Sesión / Crear Cuenta
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: VocalisTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: VocalisTheme.glassBorderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isRegisterMode = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !_isRegisterMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: !_isRegisterMode
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                            : [],
                      ),
                      child: Text(
                        'Iniciar Sesión',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: !_isRegisterMode ? VocalisTheme.primary : VocalisTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isRegisterMode = true;
                      if (_emailController.text == 'juanperez@gmail.com') _emailController.clear();
                      if (_passwordController.text == '12345') _passwordController.clear();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _isRegisterMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: _isRegisterMode
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]
                            : [],
                      ),
                      child: Text(
                        'Crear Cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isRegisterMode ? VocalisTheme.primary : VocalisTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Campo Nombre Completo (solo en modo Registro)
          if (_isRegisterMode) ...[
            TextField(
              controller: _fullNameController,
              decoration: InputDecoration(
                labelText: 'Nombre Completo',
                hintText: 'Ej. María Fernández',
                prefixIcon: const Icon(Icons.badge_outlined, color: VocalisTheme.primaryContainer, size: 20),
                filled: true,
                fillColor: VocalisTheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: VocalisTheme.glassBorderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: VocalisTheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Campo Email
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Correo Electrónico',
              hintText: 'usuario@gearshield.com',
              prefixIcon: const Icon(Icons.email_outlined, color: VocalisTheme.primaryContainer, size: 20),
              filled: true,
              fillColor: VocalisTheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: VocalisTheme.glassBorderSubtle),
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
              prefixIcon: const Icon(Icons.lock_outline, color: VocalisTheme.primaryContainer, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: VocalisTheme.textTertiary,
                  size: 20,
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
                borderSide: const BorderSide(color: VocalisTheme.glassBorderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: VocalisTheme.primary, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 8),

          if (!_isRegisterMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Instrucciones de recuperación enviadas a su correo'),
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

          // Botón Primario: Iniciar Sesión o Crear Cuenta según el modo
          ElevatedButton(
            onPressed: _isLoading ? null : (_isRegisterMode ? _handleRegister : _handleLogin),
            style: ElevatedButton.styleFrom(
              backgroundColor: VocalisTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 3,
              shadowColor: VocalisTheme.primary.withValues(alpha: 0.35),
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
                : Text(
                    _isRegisterMode ? 'Crear Cuenta' : 'Iniciar Sesión',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),

          const SizedBox(height: 20),

          // Separador "o"
          Row(
            children: const [
              Expanded(child: Divider(color: VocalisTheme.glassBorderSubtle)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'o accede con',
                  style: TextStyle(
                    fontSize: 11,
                    color: VocalisTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: VocalisTheme.glassBorderSubtle)),
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
              shadowColor: Colors.black.withValues(alpha: 0.04),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
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

          const SizedBox(height: 18),

          // Botón invitado
          TextButton(
            onPressed: _proceedToMainApp,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
        ],
      ),
    );
  }
}

/// Painter vectorizado para el logo oficial multicolor 'G' de Google
class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paintRed = Paint()..color = const Color(0xFFEA4335);
    final paintBlue = Paint()..color = const Color(0xFF4285F4);
    final paintGreen = Paint()..color = const Color(0xFF34A853);
    final paintYellow = Paint()..color = const Color(0xFFFBBC05);

    // Azul
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

    // Verde
    final greenPath = Path()
      ..moveTo(w * 0.5, h * 0.95)
      ..cubicTo(w * 0.63, h * 0.95, w * 0.74, h * 0.91, w * 0.82, h * 0.83)
      ..lineTo(w * 0.67, h * 0.71)
      ..cubicTo(w * 0.62, h * 0.74, w * 0.56, h * 0.76, w * 0.5, h * 0.76)
      ..cubicTo(w * 0.36, h * 0.76, w * 0.24, h * 0.67, w * 0.20, h * 0.54)
      ..lineTo(w * 0.05, h * 0.66)
      ..cubicTo(w * 0.13, h * 0.83, w * 0.30, h * 0.95, w * 0.5, h * 0.95);
    canvas.drawPath(greenPath, paintGreen);

    // Amarillo
    final yellowPath = Path()
      ..moveTo(w * 0.20, h * 0.54)
      ..cubicTo(w * 0.18, h * 0.49, w * 0.17, h * 0.44, w * 0.17, h * 0.39)
      ..cubicTo(w * 0.17, h * 0.34, w * 0.18, h * 0.29, w * 0.20, h * 0.24)
      ..lineTo(w * 0.05, h * 0.12)
      ..cubicTo(w * 0.01, h * 0.20, 0, h * 0.29, 0, h * 0.39)
      ..cubicTo(0, h * 0.49, w * 0.01, h * 0.58, w * 0.05, h * 0.66)
      ..lineTo(w * 0.20, h * 0.54);
    canvas.drawPath(yellowPath, paintYellow);

    // Rojo
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
