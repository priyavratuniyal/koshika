/// Policy strictness modes that control which query types the assistant accepts.
///
/// The active mode is a build-time constant ([kPolicyMode]) — users cannot
/// weaken the assistant's scope at runtime.
enum StrictnessMode {
  /// Lab interpretation + general health education. Blocks everything else.
  /// This is the default launch mode.
  strictHealthOnly,

  /// Only questions directly tied to the user's lab data.
  /// Blocks even general health education.
  labOnly,

  /// Broader lifestyle and wellness guidance on top of [strictHealthOnly].
  /// Still blocks unrelated general knowledge.
  healthPlusWellness,
}

/// Build-time policy mode — set per app flavor, not user-configurable.
///
/// The [QueryRouter] reads this constant to decide routing behavior.
/// Changing this value changes which query types reach the LLM.
const StrictnessMode kPolicyMode = StrictnessMode.strictHealthOnly;
