import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

/// Standard card container used throughout the app.
///
/// White card with 24px radius, asymmetric editorial padding, and no border.
/// Place on a tinted background (surfaceContainerLow) for tonal lift instead
/// of shadows.
class KoshikaCard extends StatelessWidget {
  const KoshikaCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.decoration,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? KoshikaSpacing.cardPaddingAsymmetric,
      margin: margin,
      decoration: decoration ?? KoshikaDecorations.card,
      child: child,
    );

    if (onTap == null) return content;

    return GestureDetector(onTap: onTap, child: content);
  }

  /// Hero card variant: primary gradient background, white text.
  static BoxDecoration get heroDecoration => KoshikaDecorations.heroCard;

  /// Insight card variant: dark green (tertiaryContainer) background.
  static BoxDecoration get insightDecoration => KoshikaDecorations.insightCard;

  /// Attention card variant: light red (errorContainer) background.
  static BoxDecoration get attentionDecoration =>
      KoshikaDecorations.attentionCard;

  /// Card on a non-tinted background (with subtle shadow for lift).
  static BoxDecoration get elevatedDecoration =>
      KoshikaDecorations.cardElevated;

  /// Section background band for visual separation.
  static BoxDecoration get sectionBackground =>
      const BoxDecoration(color: AppColors.surfaceContainerLow);
}
