import 'package:flutter/services.dart';

/// Centralized haptic feedback wrapper.
///
/// Every user tap should produce haptic feedback:
/// - [light]: Card taps, nav taps, toggle switches
/// - [selection]: List item selection, chip toggles
/// - [heavy]: Destructive actions (delete confirmation), import complete
abstract final class Haptics {
  static void light() => HapticFeedback.lightImpact();
  static void selection() => HapticFeedback.selectionClick();
  static void heavy() => HapticFeedback.heavyImpact();
}
