import 'package:flutter/foundation.dart';

import '../constants/token_budgets.dart';
import '../constants/validation_strings.dart';

/// Result of validating LLM output before showing it to the user.
enum ValidationResult {
  /// Output passed all checks.
  passed,

  /// Output is empty or too short (< [TokenBudgets.minResponseChars]).
  empty,

  /// Output contains numeric values not present in the injected lab context.
  hallucinated,

  /// More than [TokenBudgets.repetitionThreshold] of the output is repeated.
  repetitive,

  /// Output contains prohibited diagnostic language.
  prohibited,

  /// Output exceeds [TokenBudgets.maxResponseChars] — needs truncation.
  tooLong,
}

/// Post-generation quality gate for LLM output.
///
/// This is NOT a safety classifier — safety decisions happen at the routing
/// layer (layer 2), before the model is called. This catches model-quality
/// failures: hallucinated values, empty output, repetition, and prohibited
/// diagnostic language.
abstract final class OutputValidator {
  // ─── Public API ─────────────────────────────────────────────────────

  /// Validate a model response against quality heuristics.
  ///
  /// [output] is the raw model response.
  /// [labContext] is the context that was injected into the prompt (if any).
  /// When provided, enables hallucination detection.
  static ValidationResult validate(String output, {String? labContext}) {
    // 1. Emptiness check
    if (output.trim().length < TokenBudgets.minResponseChars) {
      return ValidationResult.empty;
    }

    // 2. Hallucination check — values in output not in context
    if (labContext != null && labContext.isNotEmpty) {
      if (_hasHallucinatedValues(output, labContext)) {
        return ValidationResult.hallucinated;
      }
    }

    // 3. Repetition check
    if (_isRepetitive(output)) {
      return ValidationResult.repetitive;
    }

    // 4. Prohibited content check
    if (_hasProhibitedContent(output)) {
      return ValidationResult.prohibited;
    }

    // 5. Excessive length check
    if (output.length > TokenBudgets.maxResponseChars) {
      return ValidationResult.tooLong;
    }

    return ValidationResult.passed;
  }

  /// Apply the appropriate fallback for a validation failure.
  ///
  /// Returns the corrected output string. For [ValidationResult.tooLong],
  /// truncates at the last complete sentence within budget.
  /// For other failures, returns a deterministic fallback message.
  static String applyFallback(ValidationResult result, String originalOutput) {
    switch (result) {
      case ValidationResult.passed:
        return originalOutput;
      case ValidationResult.empty:
        return ValidationStrings.genericFallback;
      case ValidationResult.hallucinated:
        debugPrint(
          '${ValidationStrings.validationFailedPrefix}'
          'hallucinated values detected',
        );
        return ValidationStrings.hallucinationFallback;
      case ValidationResult.repetitive:
        debugPrint(
          '${ValidationStrings.validationFailedPrefix}'
          'excessive repetition detected',
        );
        return ValidationStrings.repetitionFallback;
      case ValidationResult.prohibited:
        debugPrint(
          '${ValidationStrings.validationFailedPrefix}'
          'prohibited diagnostic language detected',
        );
        return ValidationStrings.prohibitedContentFallback;
      case ValidationResult.tooLong:
        return _truncateAtSentence(originalOutput);
    }
  }

  // ─── Hallucination Detection ────────────────────────────────────────

  /// Extract numeric values with units from the output and check if they
  /// appear in the injected lab context.
  ///
  /// Only checks values with medical units (mg/dl, mmol/l, etc.) to avoid
  /// false positives on general numbers.
  static bool _hasHallucinatedValues(String output, String labContext) {
    final outputValues = _extractMedicalValues(output);
    if (outputValues.isEmpty) return false;

    final contextValues = _extractMedicalValues(labContext);
    // Also extract bare numbers from context for reference range matching
    final contextNumbers = _extractBareNumbers(labContext);

    for (final value in outputValues) {
      // Check if this value appears in context (exact match on the number)
      final number = value.number;
      if (!contextNumbers.contains(number) &&
          !contextValues.any((cv) => cv.number == number)) {
        return true;
      }
    }

    return false;
  }

  /// Pattern for medical values: number + compound unit.
  static final _medicalValuePattern = RegExp(
    r'(\d+\.?\d*)\s*(mg/dl|mg/l|mmol/l|mmol|miu/l|miu/ml|iu/l|iu/ml|µg/dl|µg/l|ng/ml|ng/dl|pg/ml|g/dl|g/l|meq/l|u/l|cells/cumm|%|lakh|thousand)',
    caseSensitive: false,
  );

  /// Extract all medical number+unit pairs from text.
  static List<_MedicalValue> _extractMedicalValues(String text) {
    final values = <_MedicalValue>[];
    for (final match in _medicalValuePattern.allMatches(text)) {
      final number = match.group(1)!;
      final unit = match.group(2)!.toLowerCase();
      values.add(_MedicalValue(number: number, unit: unit));
    }
    return values;
  }

  /// Extract all bare numbers from text (for reference range matching).
  static Set<String> _extractBareNumbers(String text) {
    final pattern = RegExp(r'\d+\.?\d*');
    return {for (final m in pattern.allMatches(text)) m.group(0)!};
  }

  // ─── Repetition Detection ──────────────────────────────────────────

  /// Check if > [TokenBudgets.repetitionThreshold] of the output consists
  /// of repeated phrases (common small-model failure mode).
  static bool _isRepetitive(String output) {
    if (output.length < 100) return false;

    // Split into sentences and check for duplicates
    final sentences = output
        .split(RegExp(r'[.!?]\s+'))
        .where((s) => s.trim().length > 10)
        .toList();

    if (sentences.length < 3) return false;

    final unique = sentences.toSet();
    final duplicateRatio = 1.0 - (unique.length / sentences.length);

    if (duplicateRatio >= TokenBudgets.repetitionThreshold) return true;

    // Also check for repeated n-grams (3-word sequences)
    final words = output.toLowerCase().split(RegExp(r'\s+'));
    if (words.length < 12) return false;

    final trigrams = <String>{};
    int repeatedCount = 0;
    for (int i = 0; i < words.length - 2; i++) {
      final trigram = '${words[i]} ${words[i + 1]} ${words[i + 2]}';
      if (!trigrams.add(trigram)) {
        repeatedCount++;
      }
    }

    final trigramRatio = repeatedCount / (words.length - 2);
    return trigramRatio >= TokenBudgets.repetitionThreshold;
  }

  // ─── Prohibited Content ────────────────────────────────────────────

  /// Prohibited diagnostic language patterns.
  /// These indicate the model is making diagnoses instead of explaining values.
  static final _prohibitedPatterns = [
    RegExp(
      r'you\s+have\s+(diabetes|cancer|anemia|disease)',
      caseSensitive: false,
    ),
    RegExp(r'you\s+are\s+suffering\s+from', caseSensitive: false),
    RegExp(r'you\s+are\s+diagnosed\s+with', caseSensitive: false),
    RegExp(r'i\s+diagnose\s+you', caseSensitive: false),
    RegExp(r'your\s+diagnosis\s+is', caseSensitive: false),
    RegExp(
      r'you\s+(definitely|certainly|clearly)\s+have',
      caseSensitive: false,
    ),
  ];

  static bool _hasProhibitedContent(String output) {
    final lower = output.toLowerCase();
    for (final pattern in _prohibitedPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  // ─── Truncation ─────────────────────────────────────────────────────

  /// Truncate at the last complete sentence within the character budget.
  static String _truncateAtSentence(String output) {
    final budget = TokenBudgets.maxResponseChars;
    if (output.length <= budget) return output;

    final truncated = output.substring(0, budget);
    // Find the last sentence boundary
    final lastPeriod = truncated.lastIndexOf('. ');
    final lastQuestion = truncated.lastIndexOf('? ');
    final lastExclamation = truncated.lastIndexOf('! ');

    final lastBoundary = [
      lastPeriod,
      lastQuestion,
      lastExclamation,
    ].reduce((a, b) => a > b ? a : b);

    if (lastBoundary > budget ~/ 2) {
      return '${output.substring(0, lastBoundary + 1)}'
          '${ValidationStrings.truncationNotice}';
    }

    // No good sentence boundary — hard cut
    return '${truncated.trimRight()}...'
        '${ValidationStrings.truncationNotice}';
  }
}

/// Internal value type for hallucination checking.
class _MedicalValue {
  final String number;
  final String unit;

  const _MedicalValue({required this.number, required this.unit});
}
