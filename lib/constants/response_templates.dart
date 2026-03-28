/// Deterministic response strings returned without invoking the LLM.
///
/// These bypass the model entirely — they are fixed, instant, and safe.
/// Keep copy concise and actionable. Product-facing text, not debug messages.
abstract final class ResponseTemplates {
  /// Shown when the user describes potentially urgent symptoms.
  static const String emergencyEscalation =
      'Your message may describe a medical emergency. '
      'Please contact emergency services (112) or visit your nearest '
      'emergency room immediately.\n\n'
      'Koshika is a lab-report assistant and cannot provide emergency '
      'medical guidance.';

  /// Shown when the user asks something outside Koshika's health domain.
  static const String offTopicRefusal =
      "I'm Koshika AI, a health assistant focused on helping you understand "
      'your lab reports and biomarker results.\n\n'
      "I can't help with that topic, but feel free to ask about your lab "
      'values or general health questions.';

  /// Shown when the user asks for personalised interpretation but has no
  /// lab data imported yet.
  static const String needLabReport =
      "I don't have any lab data to reference yet. To get personalised "
      'insights, import a lab report using the Reports tab.\n\n'
      'In the meantime, I can answer general health and biomarker questions.';
}
