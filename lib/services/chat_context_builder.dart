import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';

/// Builds context strings from the user's lab data for injection into LLM prompts.
///
/// This is a keyword-based approach (Day 10 may add semantic/embedding search).
/// The context is prepended to the user's question so the LLM can reference
/// actual lab values instead of guessing.
class ChatContextBuilder {
  /// Keyword → category mapping for targeted context retrieval.
  static const _categoryKeywords = <String, List<String>>{
    'Thyroid': [
      'thyroid',
      'tsh',
      't3',
      't4',
      'hypothyroid',
      'hyperthyroid',
      'goiter',
    ],
    'CBC': [
      'blood count',
      'cbc',
      'hemoglobin',
      'hb',
      'wbc',
      'rbc',
      'platelet',
      'anemia',
      'anaemia',
      'tlc',
      'dlc',
      'neutrophil',
      'lymphocyte',
    ],
    'Lipid Panel': [
      'cholesterol',
      'lipid',
      'ldl',
      'hdl',
      'triglyceride',
      'heart',
      'cardiac',
      'vldl',
      'cardiovascular',
    ],
    'LFT': [
      'liver',
      'lft',
      'sgpt',
      'sgot',
      'alt',
      'ast',
      'bilirubin',
      'hepat',
      'albumin',
      'alkaline',
      'ggtp',
    ],
    'KFT': [
      'kidney',
      'kft',
      'creatinine',
      'urea',
      'bun',
      'renal',
      'gfr',
      'uric acid',
    ],
    'Diabetes': [
      'diabetes',
      'sugar',
      'glucose',
      'hba1c',
      'a1c',
      'fasting',
      'insulin',
      'diabetic',
      'glycated',
    ],
    'Vitamins': ['vitamin', 'b12', 'folate', 'folic', 'vitamin d', '25-oh'],
    'Iron Studies': ['iron', 'ferritin', 'tibc', 'transferrin'],
    'Electrolytes': [
      'sodium',
      'potassium',
      'calcium',
      'electrolyte',
      'mineral',
      'chloride',
      'magnesium',
      'phosphorus',
    ],
    'Inflammation': [
      'inflammation',
      'crp',
      'esr',
      'sed rate',
      'infection',
      'c-reactive',
    ],
  };

  /// Build a comprehensive context with ALL latest lab values.
  /// Used when no specific category matches the query, or for broad questions.
  String buildFullContext() {
    final latestResults = objectbox.getLatestResults();

    if (latestResults.isEmpty) {
      return 'No lab data has been imported yet. The user has not uploaded any lab reports.';
    }

    final buffer = StringBuffer();
    buffer.writeln('The user\'s latest biomarker readings:');
    buffer.writeln();

    // Group by category
    final grouped = <String, List<BiomarkerResult>>{};
    for (final result in latestResults.values) {
      final cat = result.category ?? 'Other';
      grouped.putIfAbsent(cat, () => []).add(result);
    }

    for (final entry in grouped.entries) {
      buffer.writeln('${entry.key}:');
      for (final r in entry.value) {
        final flagStr = _flagToString(r.flag);
        final refStr = r.formattedRefRange;
        buffer.writeln(
          '  - ${r.displayName}: ${r.formattedValue} ${r.unit ?? ""} '
          '[$flagStr] (Ref: $refStr) on ${_formatDate(r.testDate)}',
        );
      }
      buffer.writeln();
    }

    // Summarize out-of-range values
    final outOfRange = latestResults.values
        .where(
          (r) =>
              r.flag == BiomarkerFlag.high ||
              r.flag == BiomarkerFlag.low ||
              r.flag == BiomarkerFlag.critical ||
              r.flag == BiomarkerFlag.borderline,
        )
        .toList();

    if (outOfRange.isNotEmpty) {
      buffer.writeln('⚠ Out-of-range values requiring attention:');
      for (final r in outOfRange) {
        buffer.writeln(
          '  - ${r.displayName}: ${r.formattedValue} ${r.unit ?? ""} '
          '(${_flagToString(r.flag)})',
        );
      }
    } else {
      buffer.writeln('All values are within normal reference ranges.');
    }

    return buffer.toString();
  }

  /// Build a targeted context by matching the user's query to relevant categories.
  ///
  /// If the query mentions "thyroid", only thyroid panel data is included.
  /// If no category matches, falls back to [buildFullContext].
  String buildQueryContext(String userQuery) {
    final queryLower = userQuery.toLowerCase();
    final latestResults = objectbox.getLatestResults();

    if (latestResults.isEmpty) {
      return 'No lab data has been imported yet. The user has not uploaded any lab reports.';
    }

    // Find which categories the query is about
    final matchedCategories = <String>{};
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (queryLower.contains(keyword)) {
          matchedCategories.add(entry.key);
        }
      }
    }

    // If no specific category matched, return full context
    if (matchedCategories.isEmpty) {
      return buildFullContext();
    }

    // Build targeted context with only matched categories
    final buffer = StringBuffer();
    buffer.writeln('Relevant lab data for the user\'s question:');
    buffer.writeln();

    int matchCount = 0;
    for (final r in latestResults.values) {
      if (!matchedCategories.contains(r.category)) continue;
      matchCount++;

      final flagStr = _flagToString(r.flag);
      buffer.writeln(
        '${r.displayName}: ${r.formattedValue} ${r.unit ?? ""} '
        '[$flagStr] (Ref: ${r.formattedRefRange}) on ${_formatDate(r.testDate)}',
      );

      // Add trend info if multiple data points exist
      final history = objectbox.getHistoryForBiomarker(r.biomarkerKey);
      if (history.length >= 2) {
        final prev = history[1]; // second most recent
        if (prev.value != null && r.value != null) {
          final diff = r.value! - prev.value!;
          final direction = diff > 0
              ? 'increased'
              : diff < 0
              ? 'decreased'
              : 'unchanged';
          buffer.writeln(
            '  → Trend: $direction from ${prev.formattedValue} '
            'on ${_formatDate(prev.testDate)}',
          );
        }
      }
    }

    // If the matched categories had no actual data, fall back
    if (matchCount == 0) {
      return buildFullContext();
    }

    return buffer.toString();
  }

  String _flagToString(BiomarkerFlag flag) {
    switch (flag) {
      case BiomarkerFlag.normal:
        return 'NORMAL';
      case BiomarkerFlag.borderline:
        return 'BORDERLINE';
      case BiomarkerFlag.low:
        return 'LOW';
      case BiomarkerFlag.high:
        return 'HIGH';
      case BiomarkerFlag.critical:
        return 'CRITICAL';
      case BiomarkerFlag.unknown:
        return 'UNKNOWN';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('d MMM yyyy').format(date);
  }
}
