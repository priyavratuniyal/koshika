import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

/// Key used in SharedPreferences to track onboarding completion.
const kOnboardingCompleteKey = 'onboarding_complete';

/// Three-screen onboarding flow shown on first launch.
///
/// Persists completion state via [SharedPreferences] so it only shows once.
/// Can be re-triggered by clearing app data or SharedPreferences.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Check if onboarding has been completed.
  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kOnboardingCompleteKey) ?? false;
  }

  /// Mark onboarding as complete.
  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingCompleteKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.local_hospital_rounded,
      title: 'Welcome to Koshika',
      subtitle: 'Your health data, understood.',
      description:
          '100% offline. Zero cloud dependency.\n'
          'Your data never leaves your device.',
    ),
    _OnboardingPageData(
      icon: Icons.auto_awesome_rounded,
      title: 'How it Works',
      subtitle: 'Three simple steps',
      description:
          '📄  Import your lab report PDFs\n'
          '🔬  We parse and track every biomarker\n'
          '🤖  Chat with AI to understand your results',
    ),
    _OnboardingPageData(
      icon: Icons.shield_rounded,
      title: 'Your Privacy, First',
      subtitle: 'No accounts. No servers. No tracking.',
      description:
          'Koshika runs entirely on your device.\n'
          'Your health data is yours alone.\n'
          'Open source. Transparent. Always.',
    ),
  ];

  void _goToNextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    await OnboardingScreen.markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (hidden on last page)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(KoshikaSpacing.base),
                child: _currentPage < _pages.length - 1
                    ? TextButton(
                        onPressed: _completeOnboarding,
                        child: Text(
                          'Skip',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : const SizedBox(height: 40),
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                itemBuilder: (context, index) {
                  return _OnboardingPage(data: _pages[index]);
                },
              ),
            ),

            // Page indicator dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KoshikaSpacing.xl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(
                      horizontal: KoshikaSpacing.xs,
                    ),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: KoshikaRadius.sm,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  );
                }),
              ),
            ),

            // Action button — gradient pill CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KoshikaSpacing.xl,
                0,
                KoshikaSpacing.xl,
                KoshikaSpacing.xxxl,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFF0D9488)],
                    ),
                    borderRadius: KoshikaRadius.pill,
                    boxShadow: KoshikaElevation.medium,
                  ),
                  child: FilledButton(
                    onPressed: _currentPage == _pages.length - 1
                        ? _completeOnboarding
                        : _goToNextPage,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      _currentPage == _pages.length - 1
                          ? 'Get Started'
                          : 'Next',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page Data & Widget
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoshikaSpacing.xxxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryContainer.withValues(alpha: 0.15),
            ),
            child: Icon(data.icon, size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: KoshikaSpacing.xxxl),
          Text(
            data.title,
            style: KoshikaTypography.sectionHeader.copyWith(
              fontSize: 28,
              color: AppColors.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoshikaSpacing.sm),
          Text(
            data.subtitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoshikaSpacing.xl),
          Text(
            data.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
