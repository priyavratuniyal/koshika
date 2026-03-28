/// Token and character budgets for LLM context assembly.
///
/// Small local models have limited context windows — every token matters.
/// Each slot has a defined ceiling, not an unbounded allocation.
///
/// Character estimates assume ~4 chars per token for English text.
abstract final class TokenBudgets {
  // ─── Token Budgets ──────────────────────────────────────────────────

  /// System prompt (prompt family template).
  static const int systemPromptTokens = 300;

  /// Prior conversation turns (max 2: 1 user + 1 assistant).
  static const int conversationHistoryTokens = 200;

  /// Retrieved biomarker data injected as context.
  static const int labContextTokens = 400;

  /// Current user message.
  static const int userMessageTokens = 100;

  /// Reserved for model output generation.
  static const int generationHeadroomTokens = 500;

  /// Hard ceiling for total prompt size.
  static const int totalHardLimitTokens = 1500;

  // ─── Character Equivalents ──────────────────────────────────────────

  /// Approximate characters per token for English text.
  static const int charsPerToken = 4;

  /// Maximum characters for the system prompt slot.
  static const int maxSystemPromptChars = systemPromptTokens * charsPerToken;

  /// Maximum characters for conversation history.
  static const int maxHistoryChars = conversationHistoryTokens * charsPerToken;

  /// Maximum characters for lab context.
  static const int maxLabContextChars = labContextTokens * charsPerToken;

  /// Maximum characters for the user message.
  static const int maxUserMessageChars = userMessageTokens * charsPerToken;

  /// Maximum total prompt characters (hard limit).
  static const int maxTotalChars = totalHardLimitTokens * charsPerToken;

  // ─── Output Validation ──────────────────────────────────────────────

  /// Maximum response length before truncation (3x expected).
  /// Expected: ~5 sentences ≈ 500 chars. Max: 1500 chars.
  static const int maxResponseChars = 1500;

  /// Minimum response length — below this is treated as empty.
  static const int minResponseChars = 10;

  /// Repetition threshold — if more than this fraction of the response
  /// consists of repeated phrases, flag as repetitive.
  static const double repetitionThreshold = 0.40;
}
