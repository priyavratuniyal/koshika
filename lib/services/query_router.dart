import '../constants/response_templates.dart';
import '../constants/validation_strings.dart';
import '../models/query_decision.dart';
import '../models/strictness_mode.dart';
import 'intent_classifier.dart';
import 'intent_prefilter.dart';
import 'llm_service.dart';

/// Routes a user message to a [QueryDecision] by combining the deterministic
/// [IntentPrefilter] result with lab-data availability, optional Stage 2
/// embedding classification, and the active [StrictnessMode].
///
/// This is a class (not static) because the embedding classifier is injected
/// as an optional constructor dependency.
class QueryRouter {
  final IntentClassifier? Function() _classifierGetter;

  /// Create a router with a lazy Stage 2 embedding classifier.
  ///
  /// [classifierGetter] is called at route time so the classifier can become
  /// available after the router is constructed (e.g. once embeddings load).
  /// When the getter returns null or the classifier isn't ready, falls back
  /// to Stage 1 (regex/keyword) only.
  QueryRouter({required IntentClassifier? Function() classifierGetter})
    : _classifierGetter = classifierGetter;

  /// Classify the [message] and decide how to respond.
  ///
  /// [hasLabData] should be `true` when the user has at least one imported
  /// lab report with parsed biomarker results.
  ///
  /// [conversationHistory] is an optional list of prior turns used to
  /// resolve ambiguous follow-up queries (e.g. "is that normal?" after
  /// a lab-related exchange).
  Future<QueryRouteResult> route(
    String message, {
    required bool hasLabData,
    List<ChatHistoryTurn>? conversationHistory,
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

      case PrefilterResult.pleasantryDetected:
        return const QueryRouteResult(
          decision: QueryDecision.conversationalAck,
          deterministicResponse: ResponseTemplates.pleasantryAck,
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
        return _routeHealthQuery(hasLabData: hasLabData);

      case PrefilterResult.ambiguous:
        return _routeAmbiguous(
          message,
          hasLabData: hasLabData,
          conversationHistory: conversationHistory,
        );
    }
  }

  /// Route a health query, enriching with lab context when available.
  ///
  /// When the user asks a general health question (e.g. "what is cholesterol?")
  /// and has lab data, we route to [answerWithLabContext] so the model can
  /// reference their actual values for a richer answer.
  QueryRouteResult _routeHealthQuery({required bool hasLabData}) {
    if (hasLabData) {
      return const QueryRouteResult(
        decision: QueryDecision.answerWithLabContext,
      );
    }
    return _applyStrictnessMode(
      const QueryRouteResult(decision: QueryDecision.answerGeneralHealth),
    );
  }

  /// Route ambiguous messages using conversation history and Stage 2 classifier.
  ///
  /// History-aware routing: if the prior user turn was a lab query,
  /// ambiguous follow-ups like "is that normal?" or "what does that mean?"
  /// are promoted to lab queries instead of falling through to general health.
  Future<QueryRouteResult> _routeAmbiguous(
    String message, {
    required bool hasLabData,
    List<ChatHistoryTurn>? conversationHistory,
  }) async {
    // History-aware routing — check if prior context implies lab intent
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      final priorUserTurn = conversationHistory
          .where((t) => t.isUser)
          .lastOrNull;

      if (priorUserTurn != null) {
        final priorIntent = IntentPrefilter.classify(priorUserTurn.content);
        if (priorIntent == PrefilterResult.likelyLabQuery ||
            priorIntent == PrefilterResult.likelyHealthQuery) {
          // Prior turn was health/lab related — promote this ambiguous
          // follow-up (e.g. "how to reduce it?" after "what is SGOT?")
          if (hasLabData) {
            return const QueryRouteResult(
              decision: QueryDecision.answerWithLabContext,
            );
          }
          return const QueryRouteResult(
            decision: QueryDecision.answerGeneralHealth,
          );
        }
      }
    }

    // Fall through to Stage 2 classifier (resolved lazily)
    final classifier = _classifierGetter();
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

      case PrefilterResult.emergencyDetected:
        return QueryRouteResult(
          decision: QueryDecision.escalateUrgentMedical,
          deterministicResponse: ResponseTemplates.emergencyEscalation,
          confidence: result.confidence,
        );

      case PrefilterResult.pleasantryDetected:
        return QueryRouteResult(
          decision: QueryDecision.conversationalAck,
          deterministicResponse: ResponseTemplates.pleasantryAck,
          confidence: result.confidence,
        );

      case PrefilterResult.likelyHealthQuery:
      case PrefilterResult.ambiguous:
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
