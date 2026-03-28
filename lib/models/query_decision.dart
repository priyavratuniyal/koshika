/// Result of the first-pass regex/keyword classification.
///
/// Evaluated top-to-bottom: emergency → lab reference → off-topic → health → ambiguous.
enum PrefilterResult {
  /// User message contains urgent medical language (chest pain, suicidal, etc.).
  emergencyDetected,

  /// User message is clearly outside Koshika's health domain.
  offTopicDetected,

  /// User message references specific lab tests, biomarkers, or reports.
  likelyLabQuery,

  /// User message is health-related but not tied to a specific lab result.
  likelyHealthQuery,

  /// Message could not be confidently classified.
  ambiguous,
}

/// The routing decision produced by [QueryRouter] after combining prefilter
/// output with lab-data availability.
enum QueryDecision {
  /// User asked about their lab results and data is available → LLM with context.
  answerWithLabContext,

  /// User asked a general health question → LLM without lab context.
  answerGeneralHealth,

  /// User wants personalised interpretation but has no lab data imported.
  needLabReportFirst,

  /// Message is too vague to route confidently.
  askClarifyingQuestion,

  /// Message is outside Koshika's domain → deterministic refusal.
  refuseOffTopic,

  /// Message indicates a potential medical emergency → deterministic safety copy.
  escalateUrgentMedical,
}

/// The output of [QueryRouter.route]: a decision plus an optional pre-built
/// response that bypasses the LLM entirely.
class QueryRouteResult {
  final QueryDecision decision;

  /// When non-null the chat screen should display this text directly instead
  /// of calling the LLM. Null means "proceed with model inference".
  final String? deterministicResponse;

  /// Classification confidence from the Stage 2 embedding classifier.
  /// Null when only Stage 1 (regex) was used.
  final double? confidence;

  const QueryRouteResult({
    required this.decision,
    this.deterministicResponse,
    this.confidence,
  });

  /// Whether this result requires an LLM call.
  bool get requiresLlm => deterministicResponse == null;
}
