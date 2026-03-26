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

  static const surfaceContainerHighest = Color(0xFFDEE3DF);

  // ── Error ───────────────────────────────────────────────────────────
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  // ── Accent ──────────────────────────────────────────────────────────
  static const secondary = Color(0xFF006399);
  static const tertiary = Color(0xFF003422);
  static const tertiaryContainer = Color(0xFF074D34);
  static const onTertiaryContainer = Color(0xFF7FBD9D);

  // ── Semantic status ────────────────────────────────────────────────
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF9A825);
  static const info = Color(0xFF0277BD);

  // ── Text hierarchy aliases ─────────────────────────────────────────
  static const textPrimary = Color(0xFF191C1E); // same as onSurface
  static const textSecondary = Color(0xFF3F4945); // same as onSurfaceVariant
  static const textMuted = Color(0xFF9E9E9E);

  // ── Health category colors ─────────────────────────────────────────
  static const categoryCbc = Color(0xFF1565C0);
  static const categoryThyroid = Color(0xFF7B1FA2);
  static const categoryLipid = Color(0xFFE65100);
  static const categoryLiver = Color(0xFF2E7D32);
  static const categoryKidney = Color(0xFF0097A7);
  static const categoryVitamins = Color(0xFF558B2F);
  static const categoryIron = Color(0xFFBF360C);
  static const categoryElectrolytes = Color(0xFFFF8F00);
  static const categoryDiabetes = Color(0xFF4527A0);
  static const categoryInflammation = Color(0xFFC62828);

  /// Returns the category color for a given category name, with fallback.
  static Color categoryColor(String category) {
    final key = category.toLowerCase().trim();
    if (key.contains('blood') ||
        key.contains('cbc') ||
        key.contains('hematology')) {
      return categoryCbc;
    }
    if (key.contains('thyroid') || key.contains('endocrine')) {
      return categoryThyroid;
    }
    if (key.contains('lipid') || key.contains('cholesterol')) {
      return categoryLipid;
    }
    if (key.contains('liver') || key.contains('hepatic')) {
      return categoryLiver;
    }
    if (key.contains('kidney') || key.contains('renal')) {
      return categoryKidney;
    }
    if (key.contains('vitamin') || key.contains('nutrient')) {
      return categoryVitamins;
    }
    if (key.contains('iron') || key.contains('ferritin')) {
      return categoryIron;
    }
    if (key.contains('electrolyte') || key.contains('mineral')) {
      return categoryElectrolytes;
    }
    if (key.contains('diabetes') ||
        key.contains('glucose') ||
        key.contains('hba1c')) {
      return categoryDiabetes;
    }
    if (key.contains('inflam') || key.contains('crp') || key.contains('esr')) {
      return categoryInflammation;
    }
    return secondary; // fallback
  }

  // ── Model-status palette ─────────────────────────────────────────────
  /// Model is actively loaded in memory.
  static const statusActive = Color(0xFF00695C);

  /// Model downloaded and ready to load.
  static const statusReady = Color(0xFF006399); // same as [secondary]

  /// Model is downloading or loading (in-progress).
  static const statusBusy = Color(0xFFB45309);
}
