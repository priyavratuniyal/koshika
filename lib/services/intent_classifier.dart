import 'dart:math';

import 'package:flutter/foundation.dart';

import '../constants/intent_examples.dart';
import '../models/query_decision.dart';
import 'llm_embedding_service.dart';

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
  final LlmEmbeddingService _embedder;

  /// Pre-computed centroid vectors for each category.
  /// Null until [initialize] completes successfully.
  Map<PrefilterResult, List<double>>? _centroids;

  /// Whether centroids have been computed and the classifier is ready.
  bool get isReady => _centroids != null;

  IntentClassifier(this._embedder);

  /// Pre-compute category centroids from canonical examples.
  ///
  /// Must be called after the embedding model is loaded. Safe to call
  /// multiple times — subsequent calls are no-ops if already initialized.
  Future<void> initialize() async {
    if (_centroids != null) return;
    if (!_embedder.isLoaded) return;

    try {
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
      debugPrint(
        'IntentClassifier: initialized with ${centroids.length} '
        'category centroids',
      );
    } catch (e) {
      debugPrint('IntentClassifier.initialize failed: $e');
      // Non-fatal — classifier stays unavailable, router uses regex only
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
      debugPrint('IntentClassifier.classify failed: $e');
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
}
