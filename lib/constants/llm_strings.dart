/// Centralised user-facing strings for the LLM chat flow.
///
/// No hardcoded copy should exist in service or screen files — all
/// user-visible text (errors, labels, placeholders) lives here so it
/// can be reviewed, translated, and updated in one place.
abstract final class LlmStrings {
  // ─── Generation Errors ───────────────────────────────────────────────

  /// Shown in chat when the user sends a message but the model is not loaded.
  static const String errorModelNotLoaded =
      '[Error: Model is not loaded. Please load the model first.]';

  /// Shown in chat when the user sends a message while generation is active.
  static const String errorAlreadyGenerating =
      '[Error: Another response is still being generated.]';

  /// Shown in chat when an exception occurs mid-generation.
  /// The caller appends truncated error details.
  static const String errorGenerationPrefix = '[Generation error: ';

  /// Shown in chat when the model produces an empty response.
  static const String errorEmptyResponse =
      "I wasn't able to generate a response. Please try again.";

  /// Shown in chat when the .listen(onError:) callback fires.
  static const String errorDuringGeneration =
      'An error occurred during generation: ';

  // ─── Generation State ────────────────────────────────────────────────

  /// Appended when the user manually stops generation.
  static const String generationStopped = '[Generation stopped]';

  // ─── Model Loading Errors ────────────────────────────────────────────

  /// Thrown as a [StateError] when [LlmService.loadModel] is called in
  /// the wrong state.
  static String errorCannotLoad(String statusName) =>
      'Cannot load model — current status is $statusName. '
      'Model must be downloaded first.';

  // ─── Prompt Formatting Labels ────────────────────────────────────────

  /// Label injected before lab context in the user turn so the model
  /// knows what follows is structured data, not the user's question.
  static const String labContextLabel = 'My lab data:';

  /// Prefix for the user's actual question when lab context is present.
  static const String questionPrefix = 'Question: ';

  // ─── Chat Screen Copy ────────────────────────────────────────────────

  /// Snackbar shown when chat message persistence fails.
  static const String persistenceWarning =
      'Could not save chat history for one or more messages.';
}
