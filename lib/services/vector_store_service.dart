import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';
import '../models/retrieval_result.dart';
import '../objectbox.g.dart';
import 'llm_embedding_service.dart';

/// Manages semantic search over biomarker results using ObjectBox native HNSW.
///
/// Replaces the flutter_gemma SQLite-backed VectorStore. Embeddings are
/// stored directly on [BiomarkerResult.embedding] and queried via
/// ObjectBox's [nearestNeighborsF32].
class VectorStoreService {
  final LlmEmbeddingService _embeddingService;

  VectorStoreService(this._embeddingService);

  /// Whether the service can perform semantic search right now.
  bool get isReady => _embeddingService.isLoaded;

  // ═══════════════════════════════════════════════════════════════════════
  // INDEXING
  // ═══════════════════════════════════════════════════════════════════════

  /// Compute and store embeddings for the given biomarker results.
  ///
  /// Each result's [BiomarkerResult.embedding] field is updated in-place
  /// and persisted to ObjectBox. Returns the number indexed.
  Future<int> indexResults(List<BiomarkerResult> results) async {
    if (!_embeddingService.isLoaded) return 0;
    if (results.isEmpty) return 0;

    try {
      final chunks = results.map(_buildChunkText).toList();
      final embeddings = await _embeddingService.embedBatch(chunks);

      for (int i = 0; i < results.length; i++) {
        results[i].embedding = embeddings[i];
      }

      objectbox.biomarkerResultBox.putMany(results);

      debugPrint('VectorStoreService: indexed ${results.length} results');
      return results.length;
    } catch (e) {
      debugPrint('VectorStoreService.indexResults failed: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SEARCH
  // ═══════════════════════════════════════════════════════════════════════

  /// Semantic search for biomarker results relevant to [query].
  ///
  /// Embeds the query, then uses ObjectBox HNSW nearest-neighbor search
  /// to find the closest results. Returns up to [topK] results.
  Future<List<RetrievalResult>> search(String query, {int topK = 5}) async {
    if (!_embeddingService.isLoaded) return [];

    try {
      final queryEmbedding = await _embeddingService.embed(query);

      final hnswQuery = objectbox.biomarkerResultBox
          .query(
            BiomarkerResult_.embedding.nearestNeighborsF32(
              queryEmbedding,
              topK,
            ),
          )
          .build();

      final results = hnswQuery.find();
      hnswQuery.close();

      return results.map((r) {
        final docId = '${r.biomarkerKey}_${r.report.targetId}';
        return RetrievalResult(
          id: docId,
          content: _buildChunkText(r),
          metadata: jsonEncode({
            'biomarkerKey': r.biomarkerKey,
            'reportId': r.report.targetId,
            'flag': r.flag.name,
            'category': r.category,
            'testDate': r.testDate.toIso8601String(),
            'labName': r.report.target?.labName,
          }),
        );
      }).toList();
    } catch (e) {
      debugPrint('VectorStoreService.search failed: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INDEX MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Recompute embeddings for all biomarker results.
  ///
  /// Used after first launch on update (embedding dimension change 768 → 384)
  /// or after the embedding model is loaded for the first time.
  Future<int> rebuildIndex(List<BiomarkerResult> allResults) async {
    return indexResults(allResults);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Build a rich text chunk for a biomarker result.
  ///
  /// This is what gets embedded — should contain enough context
  /// for the LLM to reference meaningfully.
  String _buildChunkText(BiomarkerResult r) {
    final buf = StringBuffer();
    buf.write('${r.displayName}: ${r.formattedValue}');
    if (r.unit != null) buf.write(' ${r.unit}');
    buf.write(' [${r.flag.name.toUpperCase()}]');
    buf.write(' (Ref: ${r.formattedRefRange})');

    if (r.category != null) {
      buf.write('\nCategory: ${r.category}');
    }

    buf.write('\nTested: ${DateFormat("d MMM yyyy").format(r.testDate)}');
    final report = r.report.target;
    if (report?.labName != null) {
      buf.write(' at ${report!.labName}');
    }

    return buf.toString();
  }
}
