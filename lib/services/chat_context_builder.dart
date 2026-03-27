import 'package:intl/intl.dart';

import '../models/retrieval_result.dart';

import '../main.dart';
import '../models/models.dart';
import 'vector_store_service.dart';

/// Builds context strings from the user's lab data for injection into LLM prompts.
///
/// Uses semantic search (via VectorStore) when available, with keyword-based
/// fallback for when the embedding model isn't loaded.
///
/// A [maxContextChars] budget prevents prompt overflow on models with small
/// context windows (e.g. Gemma 3 1B IT at 1024 tokens ≈ 4000 chars).
class ChatContextBuilder {
  /// Maximum characters allowed in the context string.
  /// ~2000 chars ≈ 500 tokens, leaving room for system prompt + user query.
  static const int maxContextChars = 2000;

  final VectorStoreService? _vectorStore;

  /// Retrieved documents from the last semantic search.
  /// Used by CitationExtractor to map [N] references in the response.
  List<RetrievalResult> lastRetrievedDocs = [];

  ChatContextBuilder({VectorStoreService? vectorStore})
    : _vectorStore = vectorStore;

  /// Whether semantic search is currently available.
  bool get isSemanticSearchActive {
    final vs = _vectorStore;
    return vs != null && vs.isReady;
  }

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
  ///
  /// If the total context exceeds [maxContextChars], normal-range biomarkers
  /// are omitted first (out-of-range values are always kept).
  String buildFullContext() {
    final latestResults = objectbox.getLatestResults();

    if (latestResults.isEmpty) {
      return 'No lab data has been imported yet. The user has not uploaded any lab reports.';
    }

    // Separate out-of-range from normal results
    final outOfRange = <BiomarkerResult>[];
    final normalRange = <BiomarkerResult>[];

    for (final r in latestResults.values) {
      if (r.flag == BiomarkerFlag.high ||
          r.flag == BiomarkerFlag.low ||
          r.flag == BiomarkerFlag.critical ||
          r.flag == BiomarkerFlag.borderline) {
        outOfRange.add(r);
      } else {
        normalRange.add(r);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('The user\'s latest biomarker readings:');
    buffer.writeln();

    // Always include out-of-range values first
    if (outOfRange.isNotEmpty) {
      buffer.writeln('⚠ Out-of-range values requiring attention:');
      for (final r in outOfRange) {
        buffer.writeln(
          '  - ${r.displayName}: ${r.formattedValue} ${r.unit ?? ""} '
          '[${_flagToString(r.flag)}] (Ref: ${r.formattedRefRange}) '
          'on ${_formatDate(r.testDate)}',
        );
      }
      buffer.writeln();
    }

    // Add normal-range values if there's budget remaining
    if (normalRange.isNotEmpty && buffer.length < maxContextChars) {
      buffer.writeln('Normal-range values:');
      for (final r in normalRange) {
        final line =
            '  - ${r.displayName}: ${r.formattedValue} ${r.unit ?? ""} '
            '[NORMAL] (Ref: ${r.formattedRefRange})\n';
        if (buffer.length + line.length > maxContextChars) {
          final shown = outOfRange.length + normalRange.indexOf(r);
          buffer.writeln(
            '[Context truncated: showing $shown of '
            '${latestResults.length} biomarkers. '
            'Ask about a specific category for full detail.]',
          );
          break;
        }
        buffer.write(line);
      }
    }

    if (outOfRange.isEmpty) {
      buffer.writeln('All values are within normal reference ranges.');
    }

    return buffer.toString();
  }

  /// Build context using semantic search (preferred) or keyword fallback.
  ///
  /// When VectorStore is available and the embedder is loaded, performs
  /// semantic search and returns numbered results for citation.
  /// Otherwise, falls back to keyword-based category matching.
  Future<String> buildQueryContext(String userQuery) async {
    lastRetrievedDocs = [];

    // Try semantic search first
    final vs = _vectorStore;
    if (vs != null && vs.isReady) {
      final semanticContext = await _buildSemanticContext(userQuery);
      if (semanticContext != null) return semanticContext;
    }

    // Fallback to keyword-based
    return _buildKeywordContext(userQuery);
  }

  /// Semantic search → formatted context with numbered citations.
  Future<String?> _buildSemanticContext(String query) async {
    final results = await _vectorStore!.search(query, topK: 5);
    if (results.isEmpty) return null;

    lastRetrievedDocs = results;

    final buffer = StringBuffer();
    buffer.writeln(
      '=== YOUR LAB DATA (${results.length} relevant results) ===',
    );
    buffer.writeln(
      'Reference sources by number [1], [2], etc. in your response.',
    );
    buffer.writeln();

    for (int i = 0; i < results.length; i++) {
      buffer.writeln('[${i + 1}] ${results[i].content}');

      if (buffer.length > maxContextChars) {
        buffer.writeln('[Context truncated. Ask a more specific question.]');
        break;
      }
    }

    buffer.writeln('=== END LAB DATA ===');
    return buffer.toString();
  }

  /// Keyword-based context matching (original Day 10 implementation).
  String _buildKeywordContext(String userQuery) {
    // Guard: blank queries get full context
    if (userQuery.trim().isEmpty) return buildFullContext();

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

      // Add trend info if multiple data points exist.
      // Wrapped in try-catch so a DB error doesn't crash the entire context.
      try {
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
      } catch (_) {
        // Silently skip trend info for this biomarker if DB lookup fails
      }

      // Budget check
      if (buffer.length > maxContextChars) {
        buffer.writeln(
          '[Context truncated. Ask a more specific question for full detail.]',
        );
        break;
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
