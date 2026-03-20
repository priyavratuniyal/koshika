import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'embedding_service.dart';

/// Wraps flutter_gemma's VectorStore for biomarker document management.
///
/// Handles:
/// 1. VectorStore initialization (SQLite-backed with HNSW)
/// 2. Indexing biomarker results as rich text documents
/// 3. Semantic search for RAG context retrieval
/// 4. Index rebuild after imports or deletions
class VectorStoreService {
  final EmbeddingService _embeddingService;
  bool _initialized = false;

  VectorStoreService(this._embeddingService);

  bool get isInitialized => _initialized;

  /// Whether the service can perform semantic search right now.
  bool get isReady => _initialized && _embeddingService.isLoaded;

  // ═══════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════

  /// Initialize the VectorStore database.
  Future<void> initialize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}/koshika_vectors.db';
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
      FlutterGemmaPlugin.instance.enableHnsw = true;
      _initialized = true;
      debugPrint('VectorStoreService: initialized at $dbPath');
    } catch (e) {
      debugPrint('VectorStoreService.initialize failed: $e');
      _initialized = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // INDEXING
  // ═══════════════════════════════════════════════════════════════════

  /// Index a list of biomarker results into the VectorStore.
  ///
  /// Each result becomes one document with a rich text chunk and metadata.
  /// Uses batch embedding for efficiency.
  Future<int> indexResults(List<BiomarkerResult> results) async {
    if (!_initialized || !_embeddingService.isLoaded) return 0;
    if (results.isEmpty) return 0;

    try {
      final chunks = results.map(_buildChunkText).toList();
      final embeddings = await _embeddingService.embedBatch(chunks);

      int indexed = 0;
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        final docId = '${r.biomarkerKey}_${r.report.targetId}';

        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: docId,
          content: chunks[i],
          embedding: embeddings[i],
          metadata: jsonEncode({
            'biomarkerKey': r.biomarkerKey,
            'reportId': r.report.targetId,
            'flag': r.flag.name,
            'category': r.category,
            'testDate': r.testDate.toIso8601String(),
            'labName': r.report.target?.labName,
          }),
        );
        indexed++;
      }

      debugPrint('VectorStoreService: indexed $indexed documents');
      return indexed;
    } catch (e) {
      debugPrint('VectorStoreService.indexResults failed: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEARCH
  // ═══════════════════════════════════════════════════════════════════

  /// Semantic search for documents relevant to a user query.
  ///
  /// Returns top-K results above the similarity threshold.
  /// The VectorStore auto-embeds the query using the active embedder.
  Future<List<RetrievalResult>> search(String query, {int topK = 5}) async {
    if (!_initialized) return [];

    try {
      return await FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: topK,
        threshold: 0.3,
      );
    } catch (e) {
      debugPrint('VectorStoreService.search failed: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // INDEX MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════

  /// Clear and rebuild the entire index from scratch.
  Future<int> rebuildIndex(List<BiomarkerResult> allResults) async {
    if (!_initialized) return 0;

    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();
      return await indexResults(allResults);
    } catch (e) {
      debugPrint('VectorStoreService.rebuildIndex failed: $e');
      return 0;
    }
  }

  /// Get VectorStore statistics.
  Future<VectorStoreStats?> getStats() async {
    if (!_initialized) return null;
    try {
      return await FlutterGemmaPlugin.instance.getVectorStoreStats();
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Build a rich text chunk for a biomarker result.
  ///
  /// This is what gets embedded and stored — should contain enough
  /// context for the LLM to reference meaningfully.
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
