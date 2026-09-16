import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:tcc_timecare/services/patient_profile.dart';
import 'package:tcc_timecare/screens/medicines_screen.dart';
import 'package:tcc_timecare/screens/profile_screen.dart';
import 'package:tcc_timecare/screens/analysis_screen.dart';
import 'package:tcc_timecare/screens/occurrences_screen.dart';
import 'package:tcc_timecare/screens/firebase_options.dart';
import 'package:tcc_timecare/services/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
    runApp(const _StartupErrorApp());
    return;
  }
  runApp(const MyApp());
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não foi possível iniciar a conexão segura com o serviço.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appPreferences,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TimeCare',
      themeMode: appPreferences.themeMode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(context).scale(16) /
                16 *
                appPreferences.textScale,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;
  late final PageController pc;
  @override
  void initState() {
    super.initState();
    pc = PageController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      await patientProfile.load();
      final saved = patientProfile.data['preferences'];
      if (saved is Map) {
        appPreferences.update(
          themeMode: ThemeMode.values.firstWhere(
            (t) => t.name == saved['theme'],
            orElse: () => ThemeMode.system,
          ),
          textScale: saved['textScale'] is num
              ? (saved['textScale'] as num).toDouble()
              : 1,
          highContrast: saved['highContrast'] == true,
        );
      }
    } catch (_) {
      // Profile has a retry action; the medicine list stays available.
    }
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageView(
      controller: pc,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) => setState(() => selected = index),
      children: const [
        MedicineScreen(),
        AnalysisScreen(),
        OccurrencesScreen(),
        ProfileScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (index) {
        setState(() => selected = index);
        pc.jumpToPage(index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.medication_outlined),
          selectedIcon: Icon(Icons.medication),
          label: 'Remédios',
        ),
        NavigationDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          selectedIcon: Icon(Icons.monitor_heart),
          label: 'Sinais vitais',
        ),
        NavigationDestination(
          icon: Icon(Icons.warning_amber_outlined),
          selectedIcon: Icon(Icons.warning_amber),
          label: 'Ocorrências',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Perfil',
        ),
      ],
    ),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF246B78),
    brightness: brightness,
    contrastLevel: appPreferences.highContrast ? 1 : 0,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}
