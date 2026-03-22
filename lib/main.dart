import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/objectbox_store.dart';
import 'services/biomarker_dictionary.dart';
import 'services/embedding_service.dart';
import 'services/gemma_service.dart';
import 'services/vector_store_service.dart';
import 'theme/app_colors.dart';
import 'theme/koshika_design_system.dart';

/// Global references — initialized in SplashScreen before navigation.
late ObjectBoxStore objectbox;
late BiomarkerDictionary biomarkerDictionary;
late GemmaService gemmaService;
late EmbeddingService embeddingService;
late VectorStoreService vectorStoreService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(maxDownloadRetries: 5);
  runApp(const KoshikaApp());
}

class KoshikaApp extends StatelessWidget {
  const KoshikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koshika',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
      routes: {
        '/home': (_) => const HomeScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
      },
    );
  }

  ThemeData _buildTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.info,
      onSecondaryContainer: Colors.white,
      tertiary: AppColors.tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outlineVariant,
      outlineVariant: AppColors.outlineVariant,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      textTheme: KoshikaTypography.textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: KoshikaRadius.xxl),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorColor: AppColors.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          KoshikaTypography.textTheme.labelSmall!.copyWith(
            color: AppColors.onSurface,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: KoshikaButtonStyles.pill),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: KoshikaButtonStyles.outlinedPill,
      ),
      scaffoldBackgroundColor: AppColors.surface,
    );
  }
}

/// Main screen with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const ReportsScreen();
      case 2:
        return const ChatScreen();
      case 3:
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
