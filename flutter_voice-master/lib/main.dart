import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:hive_flutter/hive_flutter.dart';

import 'models/pdf_report_item.dart';
import 'theme/vocalis_theme.dart';
import 'views/admin/admin_dashboard_screen.dart';
import 'views/gearshield_splash_screen.dart';
import 'views/mobile_detector_screen.dart';

bool get isDesktopOrWeb {
  if (kIsWeb) return true;
  try {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar Hive
  await Hive.initFlutter();

  // 2. Registrar Adaptadores
  Hive.registerAdapter(PdfReportItemAdapter());

  // 3. Abrir las Cajas (Boxes)
  await Hive.openBox<PdfReportItem>('pdf_reports_box');
  await Hive.openBox('user_session_box'); // Guarda tokens JWT y datos de login

  runApp(const VocalisGearShieldApp());
}

class VocalisGearShieldApp extends StatelessWidget {
  const VocalisGearShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GearShield 2.0 - Voice AI Detector & Audit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: VocalisTheme.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: VocalisTheme.primary,
          surface: VocalisTheme.surface,
          primary: VocalisTheme.primary,
          secondary: VocalisTheme.primaryContainer,
          error: VocalisTheme.error,
        ),
        fontFamily: 'Inter',
      ),
      home: const GearShieldSplashScreen(),
    );
  }
}

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    AdminDashboardScreen(),
    GearShieldSplashScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // 1. Si se ejecuta en Celular (Android / iOS) -> Muestra exclusivamente la App Móvil
    if (!isDesktopOrWeb) {
      return const MobileDetectorScreen();
    }

    // 2. Si se ejecuta en Laptop / Desktop / Web -> Muestra el Portal de Administración y opción de simulador
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: VocalisTheme.textPrimary,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: Colors.white, size: 26),
            unselectedIconTheme: const IconThemeData(color: VocalisTheme.textTertiary, size: 22),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            unselectedLabelTextStyle: const TextStyle(
              color: VocalisTheme.textTertiary,
              fontSize: 10,
            ),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18.0),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: VocalisTheme.primaryContainer,
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.policy_outlined),
                selectedIcon: Icon(Icons.policy_rounded),
                label: Text('Admin Audit'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.phone_android_outlined),
                selectedIcon: Icon(Icons.phone_android_rounded),
                label: Text('Mobile View'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: VocalisTheme.glassBorderSubtle),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }
}
