import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/retrieval_result.dart';

/// Extracts [N] citation references from an LLM response and builds a source footer.
///
/// When the LLM references data using [1], [2], etc., this maps those numbers
/// back to the original RetrievalResult metadata (lab name, test date) and
/// appends a "Sources:" footer to the response.
class CitationExtractor {
  static final _citationPattern = RegExp(r'\[(\d+)\]');

  /// Extract citations from the response and append a source footer.
  ///
  /// If no [N] patterns are found in the response, returns it unchanged.
  static String appendSourceFooter(
    String response,
    List<RetrievalResult> retrievedDocs,
  ) {
    if (retrievedDocs.isEmpty) return response;

    final cited = <int>{};
    for (final match in _citationPattern.allMatches(response)) {
      final n = int.tryParse(match.group(1) ?? '');
      if (n != null && n >= 1 && n <= retrievedDocs.length) {
        cited.add(n);
      }
    }

    if (cited.isEmpty) return response;

    final footer = StringBuffer('\n\n---\nSources:');
    for (final n in cited.toList()..sort()) {
      final doc = retrievedDocs[n - 1];
      final label = _buildSourceLabel(doc);
      footer.write('\n[$n] $label');
    }

    return '$response${footer.toString()}';
  }

  static String _buildSourceLabel(RetrievalResult doc) {
    try {
      final metadata = jsonDecode(doc.metadata ?? '{}') as Map<String, dynamic>;
      final parts = <String>[];

      final labName = metadata['labName'] as String?;
      if (labName != null) parts.add(labName);

      final testDateStr = metadata['testDate'] as String?;
      if (testDateStr != null) {
        final date = DateTime.tryParse(testDateStr);
        if (date != null) {
          parts.add(DateFormat('d MMM yyyy').format(date));
        }
      }

      return parts.isNotEmpty ? parts.join(', ') : doc.id;
    } catch (_) {
      return doc.id;
    }
  }
}
