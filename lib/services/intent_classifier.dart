import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../constants/intent_examples.dart';
import '../constants/llm_strings.dart';
import '../models/query_decision.dart';
import 'llm_embedding_service.dart';
import 'model_downloader.dart';

/// Result of the Stage 2 embedding-based classification.
class ClassificationResult {
  /// The classified intent.
  final PrefilterResult intent;

  /// Cosine similarity score (0.0 – 1.0). Higher = more confident.
  final double confidence;

  const ClassificationResult({required this.intent, required this.confidence});

  /// Whether the classification exceeds the high-confidence threshold.
  bool get isHighConfidence =>
      confidence >= IntentExamples.highConfidenceThreshold;

  /// Whether the classification is below the low-confidence threshold.
  bool get isLowConfidence =>
      confidence < IntentExamples.lowConfidenceThreshold;
}

/// Stage 2 intent classifier using embedding similarity.
///
/// Compares user messages against pre-computed category centroids
/// (mean embeddings of canonical example queries). Falls back gracefully
/// when the embedding model is not loaded.
///
/// Emergency detection is NOT handled here — it stays regex-only in
/// [IntentPrefilter] for safety.
class IntentClassifier {
  static const _cacheFilename = 'intent_centroids.json';

  final LlmEmbeddingService _embedder;

  /// Pre-computed centroid vectors for each category.
  /// Null until [initialize] completes successfully.
  Map<PrefilterResult, List<double>>? _centroids;

  /// Whether centroids have been computed and the classifier is ready.
  bool get isReady => _centroids != null;

  IntentClassifier(this._embedder);

  /// Pre-compute category centroids from canonical examples.
  ///
  /// Tries to load cached centroids from disk first. If no cache exists
  /// (or it's stale), computes fresh centroids and persists them.
  ///
  /// Must be called after the embedding model is loaded. Safe to call
  /// multiple times — subsequent calls are no-ops if already initialized.
  Future<void> initialize() async {
    if (_centroids != null) return;
    if (!_embedder.isLoaded) return;

    try {
      // Try loading from cache first
      final cached = await _loadCachedCentroids();
      if (cached != null) {
        _centroids = cached;
        debugPrint(LlmStrings.classifierCacheLoaded);
        return;
      }

      // Compute fresh centroids
      final categories = <PrefilterResult, List<String>>{
        PrefilterResult.likelyLabQuery: IntentExamples.labInterpretation,
        PrefilterResult.likelyHealthQuery:
            IntentExamples.generalHealthEducation,
        PrefilterResult.offTopicDetected: IntentExamples.offTopic,
      };

      final centroids = <PrefilterResult, List<double>>{};

      for (final entry in categories.entries) {
        final embeddings = await _embedder.embedBatch(entry.value);
        centroids[entry.key] = _computeCentroid(embeddings);
      }

      _centroids = centroids;
      debugPrint(LlmStrings.classifierCentroidsComputed);

      // Persist to disk for next launch
      await _saveCentroids(centroids);
    } catch (e) {
      debugPrint('${LlmStrings.classifierInitFailed}$e');
      // Non-fatal — classifier stays unavailable, router uses regex only
    }
  }

  /// Invalidate the cached centroids (e.g. when examples change).
  static Future<void> clearCache() async {
    try {
      final file = await _getCacheFile();
      if (file.existsSync()) {
        file.deleteSync();
        debugPrint(LlmStrings.classifierCacheCleared);
      }
    } catch (e) {
      debugPrint('${LlmStrings.classifierCacheClearFailed}$e');
    }
  }

  /// Classify a user message by comparing its embedding against category
  /// centroids. Returns null if the classifier is not ready.
  Future<ClassificationResult?> classify(String message) async {
    final centroids = _centroids;
    if (centroids == null || !_embedder.isLoaded) return null;

    try {
      final queryEmbedding = await _embedder.embed(message);

      PrefilterResult? bestCategory;
      double bestScore = -1;

      for (final entry in centroids.entries) {
        final score = _cosineSimilarity(queryEmbedding, entry.value);
        if (score > bestScore) {
          bestScore = score;
          bestCategory = entry.key;
        }
      }

      if (bestCategory == null) return null;

      return ClassificationResult(intent: bestCategory, confidence: bestScore);
    } catch (e) {
      debugPrint('${LlmStrings.classifierClassifyFailed}$e');
      return null;
    }
  }

  // ─── Vector Math ────────────────────────────────────────────────────

  /// Compute the centroid (mean) of a list of embedding vectors.
  List<double> _computeCentroid(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    final dims = embeddings.first.length;
    final sum = List<double>.filled(dims, 0.0);

    for (final vec in embeddings) {
      for (int i = 0; i < dims; i++) {
        sum[i] += vec[i];
      }
    }

    final n = embeddings.length;
    for (int i = 0; i < dims; i++) {
      sum[i] /= n;
    }

    // Normalize the centroid
    return _normalize(sum);
  }

  /// Cosine similarity between two vectors. Both should be normalized.
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  /// L2-normalize a vector.
  List<double> _normalize(List<double> vec) {
    double norm = 0.0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0.0) return vec;
    return [for (final v in vec) v / norm];
  }

  // ─── Centroid Cache I/O ───────────────────────────────────────────

  static Future<File> _getCacheFile() async {
    final dir = await ModelDownloader.getModelsDir();
    return File('${dir.path}/$_cacheFilename');
  }

  /// Serialize centroids to a JSON file alongside the model files.
  ///
  /// Format: `{ "version": <int>, "centroids": { "<enum_name>": [<doubles>] } }`
  /// Version tracks the canonical example count so stale caches are
  /// automatically discarded when examples change.
  Future<void> _saveCentroids(
    Map<PrefilterResult, List<double>> centroids,
  ) async {
    try {
      final file = await _getCacheFile();
      final json = {
        'version': _cacheVersion,
        'centroids': {
          for (final entry in centroids.entries) entry.key.name: entry.value,
        },
      };
      await file.writeAsString(jsonEncode(json));
      debugPrint(LlmStrings.classifierCacheSaved);
    } catch (e) {
      debugPrint('${LlmStrings.classifierCacheSaveFailed}$e');
    }
  }

  /// Load cached centroids from disk. Returns null if the cache is
  /// missing, corrupt, or from a different version.
  Future<Map<PrefilterResult, List<double>>?> _loadCachedCentroids() async {
    try {
      final file = await _getCacheFile();
      if (!file.existsSync()) return null;

      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      // Version mismatch → stale cache
      if (raw['version'] != _cacheVersion) {
        debugPrint(LlmStrings.classifierCacheVersionMismatch);
        return null;
      }

      final centroidsJson = raw['centroids'] as Map<String, dynamic>;
      final centroids = <PrefilterResult, List<double>>{};

      for (final entry in centroidsJson.entries) {
        final intent = PrefilterResult.values.firstWhere(
          (v) => v.name == entry.key,
          orElse: () => PrefilterResult.ambiguous,
        );
        if (intent == PrefilterResult.ambiguous) continue;

        centroids[intent] = (entry.value as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();
      }

      if (centroids.length < 3) return null; // incomplete cache
      return centroids;
    } catch (e) {
      debugPrint('${LlmStrings.classifierCacheLoadFailed}$e');
      return null;
    }
  }

  /// Cache version derived from the total number of canonical examples.
  /// Changes whenever examples are added/removed, invalidating the cache.
  static int get _cacheVersion =>
      IntentExamples.labInterpretation.length +
      IntentExamples.generalHealthEducation.length +
      IntentExamples.offTopic.length;
}
