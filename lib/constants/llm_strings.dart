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

  // ─── Conversation History Labels ─────────────────────────────────────

  /// ChatML role tag for prior user turns injected as history.
  static const String historyUserRole = 'user';

  /// ChatML role tag for prior assistant turns injected as history.
  static const String historyAssistantRole = 'assistant';

  // ─── Hugging Face Token UI ──────────────────────────────────────────

  /// Section title in Settings.
  static const String hfTokenSectionTitle = 'Hugging Face Token';

  /// Explanation shown above the token input field.
  static const String hfTokenDescription =
      'Some models are gated and require a Hugging Face access token to '
      'download. You can create one at huggingface.co/settings/tokens.';

  /// Info banner text explaining common issues.
  static const String hfTokenInfoMessage =
      'Having a token does not guarantee access. You must also:\n'
      '  1. Accept the model\'s license on its HuggingFace page\n'
      '  2. Ensure your token has "Read" permission\n\n'
      'If downloads fail with 401/403 errors after adding a token, visit '
      'the model page and accept the license agreement, then retry.';

  /// Label for the token text field.
  static const String hfTokenFieldLabel = 'Access Token';

  /// Hint text for the token text field.
  static const String hfTokenFieldHint = 'hf_...';

  /// Shown when token is saved successfully.
  static const String hfTokenSaved = 'Token saved';

  /// Shown when token is cleared.
  static const String hfTokenCleared = 'Token removed';

  /// Button label to save the token.
  static const String hfTokenSaveButton = 'Save';

  /// Button label to clear the token.
  static const String hfTokenClearButton = 'Clear';

  // ─── Chat Screen Copy ────────────────────────────────────────────────

  /// Snackbar shown when chat message persistence fails.
  static const String persistenceWarning =
      'Could not save chat history for one or more messages.';

  /// Debug log when query routing fails.
  static const String routingFailedLog =
      'Query routing failed, falling through to LLM: ';

  /// Debug log when retrying after empty/failed generation.
  static const String retryingGenerationLog =
      'Generation produced empty/failed output, retrying once';

  // ─── Intent Classifier Debug Logs ──────────────────────────────────

  /// Logged when centroids are loaded from disk cache.
  static const String classifierCacheLoaded =
      'IntentClassifier: loaded cached centroids';

  /// Logged when centroids are computed fresh from examples.
  static const String classifierCentroidsComputed =
      'IntentClassifier: computed category centroids';

  /// Logged when centroid initialization fails.
  static const String classifierInitFailed =
      'IntentClassifier.initialize failed: ';

  /// Logged when centroids are written to disk cache.
  static const String classifierCacheSaved =
      'IntentClassifier: centroids cached to disk';

  /// Logged when centroid cache write fails.
  static const String classifierCacheSaveFailed =
      'IntentClassifier: failed to cache centroids: ';

  /// Logged when cached centroids have a version mismatch.
  static const String classifierCacheVersionMismatch =
      'IntentClassifier: cache version mismatch, recomputing';

  /// Logged when centroid cache read fails.
  static const String classifierCacheLoadFailed =
      'IntentClassifier: failed to load cache: ';

  /// Logged when the in-memory centroid cache is cleared.
  static const String classifierCacheCleared =
      'IntentClassifier: cache cleared';

  /// Logged when cache clearing fails.
  static const String classifierCacheClearFailed =
      'IntentClassifier.clearCache failed: ';

  /// Logged when a classify() call fails.
  static const String classifierClassifyFailed =
      'IntentClassifier.classify failed: ';
}
