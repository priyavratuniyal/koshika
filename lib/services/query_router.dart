import '../constants/response_templates.dart';
import '../models/query_decision.dart';
import 'intent_prefilter.dart';

/// Routes a user message to a [QueryDecision] by combining the deterministic
/// [IntentPrefilter] result with lab-data availability.
///
/// This is a class (not static) because Stage 2 will inject the embedding
/// classifier as a constructor dependency for ambiguous queries.
class QueryRouter {
  /// Classify the [message] and decide how to respond.
  ///
  /// [hasLabData] should be `true` when the user has at least one imported
  /// lab report with parsed biomarker results.
  QueryRouteResult route(String message, {required bool hasLabData}) {
    final prefilter = IntentPrefilter.classify(message);

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
        return const QueryRouteResult(
          decision: QueryDecision.answerGeneralHealth,
        );

      case PrefilterResult.ambiguous:
        return const QueryRouteResult(
          decision: QueryDecision.answerGeneralHealth,
        );
    }
  }
}
