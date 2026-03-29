import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

// ═══════════════════════════════════════════════════════════════════════
// Typography
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaTypography {
  // ── Material text theme (Manrope headlines + Inter body) ───────────

  static TextTheme get textTheme {
    final manrope = GoogleFonts.manropeTextTheme();
    final inter = GoogleFonts.interTextTheme();

    return TextTheme(
      displayLarge: manrope.displayLarge!.copyWith(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        height: 1.12,
      ),
      displayMedium: manrope.displayMedium!.copyWith(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.16,
      ),
      displaySmall: manrope.displaySmall!.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.22,
      ),
      headlineLarge: manrope.headlineLarge!.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.25,
      ),
      headlineMedium: manrope.headlineMedium!.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.29,
      ),
      headlineSmall: manrope.headlineSmall!.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.33,
      ),
      titleLarge: manrope.titleLarge!.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.27,
      ),
      titleMedium: inter.titleMedium!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      titleSmall: inter.titleSmall!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.43,
      ),
      bodyLarge: inter.bodyLarge!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        height: 1.5,
      ),
      bodyMedium: inter.bodyMedium!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        height: 1.43,
      ),
      bodySmall: inter.bodySmall!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        height: 1.33,
      ),
      labelLarge: inter.labelLarge!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.43,
      ),
      labelMedium: inter.labelMedium!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        height: 1.33,
      ),
      labelSmall: inter.labelSmall!.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        height: 1.45,
      ),
    );
  }

  // ── Custom health-specific styles ──────────────────────────────────

  /// Dashboard hero biomarker values (48px/700 Manrope).
  static TextStyle get heroMetric => GoogleFonts.manrope(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.textPrimary,
  );

  /// Units next to hero values — e.g. "mg/dL" (14px/500 Inter).
  static TextStyle get metricUnit => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    color: AppColors.textMuted,
  );

  /// ALL-CAPS metric labels (12px/700 Inter).
  static TextStyle get metricLabel => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    height: 1.33,
    color: AppColors.textSecondary,
  );

  /// Section headers with editorial weight (24px/600 Manrope).
  static TextStyle get sectionHeader => GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.33,
    color: AppColors.textPrimary,
  );

  /// Subtitles within cards (16px/500 Inter).
  static TextStyle get cardSubtitle => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  /// Status badge text (12px/600 Inter).
  static TextStyle get statusText => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Spacing (8dp base grid)
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  // Screen-level constants
  static const double screenHorizontal = 16;
  static const double screenVertical = 8;
  static const double contentPadding = 20;
  static const double sectionGap = 24;
  static const double cardPadding = 20;

  // Asymmetric editorial card padding (more top than bottom)
  static const EdgeInsets cardPaddingAsymmetric = EdgeInsets.fromLTRB(
    20,
    24,
    20,
    16,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Border Radius
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaRadius {
  static const double smValue = 4;
  static const double mdValue = 8;
  static const double lgValue = 12;
  static const double xlValue = 16;
  static const double xxlValue = 24;
  static const double pillValue = 9999;

  static final BorderRadius sm = BorderRadius.circular(smValue);
  static final BorderRadius md = BorderRadius.circular(mdValue);
  static final BorderRadius lg = BorderRadius.circular(lgValue);
  static final BorderRadius xl = BorderRadius.circular(xlValue);
  static final BorderRadius xxl = BorderRadius.circular(xxlValue);
  static final BorderRadius pill = BorderRadius.circular(pillValue);
}

// ═══════════════════════════════════════════════════════════════════════
// Elevation (BoxShadow — NOT Material elevation)
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaElevation {
  static const _shadowColor = Color(0xFF191C1E);

  /// Default cards (optional — prefer tonal lift instead).
  static final List<BoxShadow> subtle = [
    BoxShadow(
      color: _shadowColor.withValues(alpha: 0.05),
      blurRadius: 1,
      offset: const Offset(0, 1),
    ),
  ];

  /// Slightly elevated interactive cards.
  static final List<BoxShadow> medium = [
    BoxShadow(
      color: _shadowColor.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// Floating elements, FABs, modals.
  static final List<BoxShadow> elevated = [
    BoxShadow(
      color: _shadowColor.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// Pre-built Decorations
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaDecorations {
  /// Standard card: white, 24px radius, no border.
  static BoxDecoration get card => BoxDecoration(
    color: AppColors.surfaceContainerLowest,
    borderRadius: KoshikaRadius.xxl,
  );

  /// Standard card on a non-tinted background (with subtle shadow).
  static BoxDecoration get cardElevated => BoxDecoration(
    color: AppColors.surfaceContainerLowest,
    borderRadius: KoshikaRadius.xxl,
    boxShadow: KoshikaElevation.subtle,
  );

  /// Hero card: primary gradient, 24px radius.
  static BoxDecoration get heroCard => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryContainer],
    ),
    borderRadius: KoshikaRadius.xxl,
    boxShadow: KoshikaElevation.medium,
  );

  /// Insight card: tertiaryContainer background.
  static BoxDecoration get insightCard => BoxDecoration(
    color: AppColors.tertiaryContainer,
    borderRadius: KoshikaRadius.xxl,
  );

  /// Attention card: errorContainer background.
  static BoxDecoration get attentionCard => BoxDecoration(
    color: AppColors.errorContainer,
    borderRadius: KoshikaRadius.xxl,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Pre-built Button Styles
// ═══════════════════════════════════════════════════════════════════════

abstract final class KoshikaButtonStyles {
  /// Primary pill button — deep teal, white text.
  static ButtonStyle get pill => FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: const StadiumBorder(),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
  );

  /// Outlined pill button — ghost border, primary text.
  static ButtonStyle get outlinedPill => OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: const StadiumBorder(),
    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
  );

  /// Outlined pill on dark background — white text/border.
  static ButtonStyle get outlinedPillLight => OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    elevation: 0,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: const StadiumBorder(),
    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
  );
}
