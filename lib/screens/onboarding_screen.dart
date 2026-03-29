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

  static final _pages = [
    _OnboardingPageData(
      illustration: const _WelcomeIllustration(),
      title: 'Your Health Data\nLives Here.',
      subtitle:
          'Not in the cloud. Not on our servers.\nRight here on your phone.',
      badges: const [
        'End-to-End Encryption',
        '0% Server Storage',
        'Patient-Centric',
      ],
    ),
    _OnboardingPageData(
      illustration: const _HowItWorksIllustration(),
      title: 'From PDF to Insight,\nLocally.',
      subtitle:
          'Koshika processes your sensitive medical records\n'
          'directly on your device. No cloud uploads, no shared\n'
          'data, just instant clinical intelligence.',
      featureItems: const [
        _FeatureItem(
          icon: Icons.description_outlined,
          title: 'Local PDF Parsing',
          subtitle:
              'Intelligent document reading that never\nleaves your smartphone\'s secure enclave.',
        ),
        _FeatureItem(
          icon: Icons.biotech_outlined,
          title: 'Biomarker Extraction',
          subtitle:
              'Automatically maps laboratory values\nto clinical trends and historical averages.',
        ),
        _FeatureItem(
          icon: Icons.wifi_off_rounded,
          title: 'No Internet Required',
          subtitle:
              'Works completely offline. Your health\ndata remains your personal property.',
        ),
      ],
    ),
    _OnboardingPageData(
      illustration: const _PrivacyIllustration(),
      title: 'Zero Cloud.\nZero Risk.',
      subtitle:
          'Koshika uses on-device AI to analyze\n'
          'your reports. No data ever leaves\nyour phone.',
      badges: const ['HIPAA Ready', 'Offline Mode'],
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
    final isLast = _currentPage == _pages.length - 1;
    final buttonLabels = [
      'See How it Works',
      'Next: Privacy First',
      'Start My Journey',
    ];

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
                child: !isLast
                    ? TextButton(
                        onPressed: _completeOnboarding,
                        child: Text(
                          'Skip Onboarding',
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

            // Action button — gradient pill CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KoshikaSpacing.xl,
                KoshikaSpacing.base,
                KoshikaSpacing.xl,
                KoshikaSpacing.sm,
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
                    onPressed: isLast ? _completeOnboarding : _goToNextPage,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          buttonLabels[_currentPage],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (!isLast) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Secondary action on last page
            if (isLast)
              Padding(
                padding: const EdgeInsets.only(bottom: KoshikaSpacing.lg),
                child: TextButton(
                  onPressed: () {},
                  child: Text(
                    'View Data Policy',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),

            if (!isLast) const SizedBox(height: KoshikaSpacing.lg),

            // Bottom badges for pages that have them
            if (_pages[_currentPage].badges != null)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: KoshikaSpacing.xxl,
                  left: KoshikaSpacing.xl,
                  right: KoshikaSpacing.xl,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _pages[_currentPage].badges!.map((label) {
                    return _BadgeChip(label: label);
                  }).toList(),
                ),
              )
            else
              const SizedBox(height: KoshikaSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Page Data
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPageData {
  final Widget illustration;
  final String title;
  final String subtitle;
  final List<String>? badges;
  final List<_FeatureItem>? featureItems;

  const _OnboardingPageData({
    required this.illustration,
    required this.title,
    required this.subtitle,
    this.badges,
    this.featureItems,
  });
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// Page Widget
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFeatures =
        data.featureItems != null && data.featureItems!.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KoshikaSpacing.xl),
      child: Column(
        children: [
          // Illustration
          SizedBox(height: hasFeatures ? 200 : 240, child: data.illustration),
          const SizedBox(height: KoshikaSpacing.xl),

          // Title
          Text(
            data.title,
            style: KoshikaTypography.sectionHeader.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: KoshikaSpacing.md),

          // Subtitle
          Text(
            data.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          // Feature list (only for "How it Works" page)
          if (hasFeatures) ...[
            const SizedBox(height: KoshikaSpacing.xl),
            ...data.featureItems!.map((item) => _FeatureRow(item: item)),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Feature Row (How it Works page)
// ═══════════════════════════════════════════════════════════════════════

class _FeatureRow extends StatelessWidget {
  final _FeatureItem item;

  const _FeatureRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.12),
              borderRadius: KoshikaRadius.lg,
            ),
            child: Icon(item.icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: KoshikaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
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

// ═══════════════════════════════════════════════════════════════════════
// Badge Chip
// ═══════════════════════════════════════════════════════════════════════

class _BadgeChip extends StatelessWidget {
  final String label;

  const _BadgeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Illustrations — Composed from basic shapes + icons
// ═══════════════════════════════════════════════════════════════════════

/// Welcome page: phone mockup with shield icon and floating labels.
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft radial glow behind the phone
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primaryContainer.withValues(alpha: 0.12),
                AppColors.surface,
              ],
            ),
          ),
        ),

        // Phone frame
        Container(
          width: 130,
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shield icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              // Simulated text lines
              _mockTextLine(
                width: 60,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 6),
              _mockTextLine(
                width: 44,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),

        // Floating badge: "DATA PRIVACY"
        Positioned(
          top: 24,
          right: 20,
          child: _FloatingBadge(
            label: 'DATA PRIVACY',
            icon: Icons.lock_outline,
          ),
        ),

        // Floating badge: "OFFLINE MODE"
        Positioned(
          bottom: 30,
          left: 16,
          child: _FloatingBadge(
            label: 'OFFLINE MODE',
            icon: Icons.wifi_off_rounded,
          ),
        ),

        // "Privacy Reimagined" pill
        Positioned(
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: KoshikaRadius.pill,
            ),
            child: const Text(
              'PRIVACY REIMAGINED',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _mockTextLine({required double width, required Color color}) {
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// How it Works page: document with magnifying glass overlay.
class _HowItWorksIllustration extends StatelessWidget {
  const _HowItWorksIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft background
        Container(
          width: 220,
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: RadialGradient(
              colors: [
                AppColors.primaryContainer.withValues(alpha: 0.10),
                AppColors.surface,
              ],
            ),
          ),
        ),

        // Document card
        Container(
          width: 150,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: KoshikaElevation.subtle,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PDF icon + filename
              Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'MEDICAL_REPORT.PDF',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Simulated text lines
              _mockDocLine(widthFraction: 1.0),
              const SizedBox(height: 6),
              _mockDocLine(widthFraction: 0.85),
              const SizedBox(height: 6),
              _mockDocLine(widthFraction: 0.7),
              const SizedBox(height: 12),
              _mockDocLine(widthFraction: 0.9),
              const SizedBox(height: 6),
              _mockDocLine(widthFraction: 0.6),
              const SizedBox(height: 6),
              _mockDocLine(widthFraction: 0.75),
            ],
          ),
        ),

        // Magnifying glass overlay
        Positioned(
          top: 12,
          left: 30,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: AppColors.primaryContainer.withValues(alpha: 0.6),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.search_rounded,
              size: 24,
              color: AppColors.primary,
            ),
          ),
        ),

        // Extraction badge
        Positioned(
          top: 16,
          right: 24,
          child: _FloatingBadge(
            label: 'EXTRACTING...',
            icon: Icons.autorenew_rounded,
          ),
        ),
      ],
    );
  }

  static Widget _mockDocLine({required double widthFraction}) {
    return FractionallySizedBox(
      widthFactor: widthFraction,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Privacy page: card with shield and lock indicators.
class _PrivacyIllustration extends StatelessWidget {
  const _PrivacyIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Soft background
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primaryContainer.withValues(alpha: 0.10),
                AppColors.surface,
              ],
            ),
          ),
        ),

        // Main card
        Container(
          width: 160,
          height: 190,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.4),
            ),
            boxShadow: KoshikaElevation.subtle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shield with check
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              // Simulated data rows
              for (int i = 0; i < 3; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.lock_rounded,
                        size: 10,
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
                if (i < 2) const SizedBox(height: 10),
              ],
            ],
          ),
        ),

        // "LOCAL STORAGE" floating badge
        Positioned(
          top: 20,
          left: 12,
          child: _FloatingBadge(
            label: 'LOCAL STORAGE',
            icon: Icons.smartphone_rounded,
          ),
        ),

        // Encrypted badge
        Positioned(
          bottom: 28,
          right: 12,
          child: _FloatingBadge(
            label: 'ENCRYPTED',
            icon: Icons.enhanced_encryption_rounded,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared: Floating Badge
// ═══════════════════════════════════════════════════════════════════════

class _FloatingBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FloatingBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: KoshikaRadius.pill,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
