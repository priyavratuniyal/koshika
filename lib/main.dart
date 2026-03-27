import 'dart:ui';

import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/objectbox_store.dart';
import 'services/biomarker_dictionary.dart';
import 'services/llm_embedding_service.dart';
import 'services/llm_service.dart';
import 'services/vector_store_service.dart';
import 'theme/app_colors.dart';
import 'theme/koshika_design_system.dart';

/// Global references — initialized in SplashScreen before navigation.
late ObjectBoxStore objectbox;
late BiomarkerDictionary biomarkerDictionary;
late LlmService llmService;
late LlmEmbeddingService embeddingService;
late VectorStoreService vectorStoreService;
Future<void>? _embeddingMigrationTask;

/// Whether AI features are enabled. Set by the entry point
/// (main_full.dart vs main_lite.dart).
bool kAiEnabled = true;

/// Default entry point — full flavor with AI enabled.
/// For flavor-specific builds, use main_full.dart or main_lite.dart.
Future<void> main() async => appMain(aiEnabled: true);

/// Shared app bootstrap — called from entry-point files.
Future<void> appMain({required bool aiEnabled}) async {
  WidgetsFlutterBinding.ensureInitialized();
  kAiEnabled = aiEnabled;
  runApp(const KoshikaApp());
}

Future<void> migrateEmbeddingsIfNeeded() {
  if (!kAiEnabled || !embeddingService.isLoaded) {
    return Future.value();
  }

  return _embeddingMigrationTask ??= _runEmbeddingMigration().whenComplete(() {
    _embeddingMigrationTask = null;
  });
}

Future<void> _runEmbeddingMigration() async {
  try {
    final allResults = objectbox.biomarkerResultBox.getAll();
    if (allResults.isEmpty) return;

    final needsMigration = allResults.any(
      (result) =>
          result.embedding == null ||
          result.embedding!.isEmpty ||
          result.embedding!.length != 384,
    );
    if (!needsMigration) return;

    debugPrint(
      'KoshikaApp: migrating ${allResults.length} embeddings to 384-dim',
    );
    await vectorStoreService.rebuildIndex(allResults);
  } catch (e) {
    debugPrint('Embedding migration failed (non-fatal): $e');
  }
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
        centerTitle: false,
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

  /// Screens available depends on whether AI is enabled.
  List<Widget> get _screens => kAiEnabled
      ? const [
          DashboardScreen(),
          ReportsScreen(),
          ChatScreen(),
          SettingsScreen(),
        ]
      : const [DashboardScreen(), ReportsScreen(), SettingsScreen()];

  Widget _buildCurrentScreen() {
    if (_currentIndex < _screens.length) return _screens[_currentIndex];
    return const DashboardScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentScreen(),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KoshikaSpacing.sm,
                  vertical: KoshikaSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      index: 0,
                      currentIndex: _currentIndex,
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard,
                      label: 'Dashboard',
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavItem(
                      index: 1,
                      currentIndex: _currentIndex,
                      icon: Icons.description_outlined,
                      activeIcon: Icons.description,
                      label: 'Reports',
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    if (kAiEnabled)
                      _NavItem(
                        index: 2,
                        currentIndex: _currentIndex,
                        icon: Icons.chat_outlined,
                        activeIcon: Icons.chat,
                        label: 'Chat',
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
                    _NavItem(
                      index: kAiEnabled ? 3 : 2,
                      currentIndex: _currentIndex,
                      icon: Icons.settings_outlined,
                      activeIcon: Icons.settings,
                      label: 'Settings',
                      onTap: () =>
                          setState(() => _currentIndex = kAiEnabled ? 3 : 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == currentIndex;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(
                horizontal: KoshikaSpacing.base,
                vertical: KoshikaSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryContainer.withValues(alpha: 0.3)
                    : Colors.transparent,
                borderRadius: KoshikaRadius.pill,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  isSelected ? activeIcon : icon,
                  key: ValueKey(isSelected),
                  size: 24,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
