/// App-owned retrieval result for the RAG pipeline.
///
/// Replaces flutter_gemma's RetrievalResult so the pipeline is
/// decoupled from the inference engine.
class RetrievalResult {
  final String id;
  final String content;

  /// JSON-encoded metadata (biomarkerKey, reportId, flag, testDate, labName).
  final String? metadata;

  /// Cosine similarity score in [0, 1].
  final double score;

  const RetrievalResult({
    required this.id,
    required this.content,
    this.metadata,
    this.score = 0.0,
  });
}
