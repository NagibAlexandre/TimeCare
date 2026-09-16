import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tcc_timecare/screens/Medicine_screen.dart';
import 'package:tcc_timecare/screens/ProfileScreen.dart';
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
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: appPreferences.highContrast
            ? Colors.indigo
            : Colors.blue,
        fontFamily: GoogleFonts.poppins().fontFamily,
        scaffoldBackgroundColor: appPreferences.highContrast
            ? Colors.white
            : const Color(0xFFF7F9FC),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: appPreferences.highContrast
            ? Colors.yellow
            : Colors.blue,
        fontFamily: GoogleFonts.poppins().fontFamily,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(appPreferences.textScale)),
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
