import 'package:flutter/material.dart';

/// Centralized design token palette for Koshika.
///
/// All screens and widgets should reference these constants instead of using
/// hardcoded [Color] literals or [Theme.of(context).colorScheme.*] directly.
///
/// Generated from the Stitch mockup design system (teal/forest-green palette).
abstract final class AppColors {
  // ── Primary brand ───────────────────────────────────────────────────
  static const primary = Color(0xFF00342B);
  static const primaryContainer = Color(0xFF004D40);
  static const onPrimaryContainer = Color(0xFF7EBDAC);

  // ── Surface ─────────────────────────────────────────────────────────
  static const surface = Color(0xFFF7F9FB);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF2F4F6);
  static const surfaceContainerHigh = Color(0xFFE6E8EA);

  // ── On-surface ──────────────────────────────────────────────────────
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF3F4945);
  static const outlineVariant = Color(0xFFBFC9C4);

  // ── Error ───────────────────────────────────────────────────────────
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);

  // ── Accent ──────────────────────────────────────────────────────────
  static const secondary = Color(0xFF006399);
  static const tertiary = Color(0xFF003422);
  static const tertiaryContainer = Color(0xFF074D34);

  // ── Model-status palette ─────────────────────────────────────────────
  /// Model is actively loaded in memory.
  static const statusActive = Color(0xFF00695C);

  /// Model downloaded and ready to load.
  static const statusReady = Color(0xFF006399); // same as [secondary]

  /// Model is downloading or loading (in-progress).
  static const statusBusy = Color(0xFFB45309);
}
