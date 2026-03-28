/// User-facing strings for output validation and fallback responses.
///
/// When the LLM produces invalid output (hallucinated values, empty response,
/// excessive repetition, or prohibited content), the system shows these
/// deterministic messages instead.
abstract final class ValidationStrings {
  // ─── Fallback Responses ─────────────────────────────────────────────

  /// Generic safe fallback — shown when all else fails.
  /// Hardcoded (not config-loaded) so it works even if config parsing fails.
  static const String genericFallback =
      "I wasn't able to process that. You can try rephrasing your question, "
      'or check your biomarker values directly on the dashboard.';

  /// Shown when the model hallucinates lab values not present in context.
  static const String hallucinationFallback =
      'I noticed an inconsistency in my response. '
      'Please check your actual values on the dashboard for accurate data. '
      'For interpretation, consult your doctor.';

  /// Shown when the model output is excessively repetitive.
  static const String repetitionFallback =
      "I wasn't able to generate a clear response. "
      'Please try rephrasing your question.';

  /// Shown when the model output contains prohibited diagnostic language.
  static const String prohibitedContentFallback =
      'I can help explain your lab values, but I cannot provide diagnoses. '
      'Please consult a healthcare professional for medical advice.';

  // ─── Truncation ─────────────────────────────────────────────────────

  /// Appended when a response exceeds the maximum length and is truncated.
  static const String truncationNotice =
      '\n\n[Response truncated. Ask a more specific question for details.]';

  // ─── Strictness Mode Messages ───────────────────────────────────────

  /// Shown in labOnly mode when a general health question is asked.
  static const String labOnlyRefusal =
      "I'm focused on helping you understand your lab reports. "
      'Please ask about your specific test results, or import a report '
      'using the Reports tab.';

  // ─── Clarification ──────────────────────────────────────────────────

  /// Shown when the classifier confidence is too low to route.
  static const String clarificationRequest =
      "I'm not sure I understand your question. Could you rephrase it? "
      'For example:\n'
      '  - "What does my TSH mean?" (about your lab results)\n'
      '  - "What is cholesterol?" (general health question)';

  // ─── Validation Debug Labels ────────────────────────────────────────

  /// Prefix for debug-level validation failure logs.
  static const String validationFailedPrefix = 'Output validation failed: ';
}
