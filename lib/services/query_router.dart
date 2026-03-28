import '../constants/response_templates.dart';
import '../constants/validation_strings.dart';
import '../models/query_decision.dart';
import '../models/strictness_mode.dart';
import 'intent_classifier.dart';
import 'intent_prefilter.dart';

/// Routes a user message to a [QueryDecision] by combining the deterministic
/// [IntentPrefilter] result with lab-data availability, optional Stage 2
/// embedding classification, and the active [StrictnessMode].
///
/// This is a class (not static) because the embedding classifier is injected
/// as an optional constructor dependency.
class QueryRouter {
  final IntentClassifier? _classifier;

  /// Create a router with an optional Stage 2 embedding classifier.
  ///
  /// When [classifier] is null or not ready, falls back to Stage 1
  /// (regex/keyword) only.
  QueryRouter({IntentClassifier? classifier}) : _classifier = classifier;

  /// Classify the [message] and decide how to respond.
  ///
  /// [hasLabData] should be `true` when the user has at least one imported
  /// lab report with parsed biomarker results.
  Future<QueryRouteResult> route(
    String message, {
    required bool hasLabData,
  }) async {
    final prefilter = IntentPrefilter.classify(message);

    // Emergency and off-topic are always handled by Stage 1 (deterministic).
    // These never go through the embedding classifier.
    switch (prefilter) {
      case PrefilterResult.emergencyDetected:
        return const QueryRouteResult(
          decision: QueryDecision.escalateUrgentMedical,
          deterministicResponse: ResponseTemplates.emergencyEscalation,
        );

      case PrefilterResult.offTopicDetected:
        return const QueryRouteResult(
          decision: QueryDecision.refuseOffTopic,
          deterministicResponse: ResponseTemplates.offTopicRefusal,
        );

      case PrefilterResult.likelyLabQuery:
        if (!hasLabData) {
          return const QueryRouteResult(
            decision: QueryDecision.needLabReportFirst,
            deterministicResponse: ResponseTemplates.needLabReport,
          );
        }
        return const QueryRouteResult(
          decision: QueryDecision.answerWithLabContext,
        );

      case PrefilterResult.likelyHealthQuery:
        return _applyStrictnessMode(
          const QueryRouteResult(decision: QueryDecision.answerGeneralHealth),
        );

      case PrefilterResult.ambiguous:
        return _routeAmbiguous(message, hasLabData: hasLabData);
    }
  }

  /// Route ambiguous messages using Stage 2 classifier when available.
  Future<QueryRouteResult> _routeAmbiguous(
    String message, {
    required bool hasLabData,
  }) async {
    final classifier = _classifier;
    if (classifier == null || !classifier.isReady) {
      // No Stage 2 — default to general health (safe fallback)
      return _applyStrictnessMode(
        const QueryRouteResult(decision: QueryDecision.answerGeneralHealth),
      );
    }

    final result = await classifier.classify(message);
    if (result == null) {
      return _applyStrictnessMode(
        const QueryRouteResult(decision: QueryDecision.answerGeneralHealth),
      );
    }

    // Low confidence → ask for clarification
    if (result.isLowConfidence) {
      return QueryRouteResult(
        decision: QueryDecision.askClarifyingQuestion,
        deterministicResponse: ValidationStrings.clarificationRequest,
        confidence: result.confidence,
      );
    }

    // Map classifier intent to routing decision
    switch (result.intent) {
      case PrefilterResult.likelyLabQuery:
        if (!hasLabData) {
          return QueryRouteResult(
            decision: QueryDecision.needLabReportFirst,
            deterministicResponse: ResponseTemplates.needLabReport,
            confidence: result.confidence,
          );
        }
        return QueryRouteResult(
          decision: QueryDecision.answerWithLabContext,
          confidence: result.confidence,
        );

      case PrefilterResult.offTopicDetected:
        return QueryRouteResult(
          decision: QueryDecision.refuseOffTopic,
          deterministicResponse: ResponseTemplates.offTopicRefusal,
          confidence: result.confidence,
        );

      case PrefilterResult.likelyHealthQuery:
      case PrefilterResult.ambiguous:
      case PrefilterResult.emergencyDetected:
        return _applyStrictnessMode(
          QueryRouteResult(
            decision: QueryDecision.answerGeneralHealth,
            confidence: result.confidence,
          ),
        );
    }
  }

  /// Apply the build-time strictness mode to a routing result.
  ///
  /// In [StrictnessMode.labOnly], general health queries are refused
  /// with a deterministic message instead of reaching the LLM.
  QueryRouteResult _applyStrictnessMode(QueryRouteResult result) {
    if (kPolicyMode == StrictnessMode.labOnly &&
        result.decision == QueryDecision.answerGeneralHealth) {
      return const QueryRouteResult(
        decision: QueryDecision.refuseOffTopic,
        deterministicResponse: ValidationStrings.labOnlyRefusal,
      );
    }
    return result;
  }
}
