/// Canonical example queries per intent category for the Stage 2
/// embedding-based classifier.
///
/// Each category has 10–20 representative queries. The classifier embeds
/// these at initialization and compares incoming messages against category
/// centroids via cosine similarity.
///
/// Emergency detection stays regex-only (too safety-critical for ML).
abstract final class IntentExamples {
  /// Queries about the user's own lab results — require lab context.
  static const labInterpretation = <String>[
    'Why is my creatinine high?',
    'What does my HbA1c mean?',
    'Can you explain my thyroid results?',
    'Is my cholesterol level normal?',
    'Why is my TSH elevated?',
    'What do my liver function tests show?',
    'My hemoglobin is low, should I worry?',
    'Are my kidney values okay?',
    'Why is my SGPT higher than normal?',
    'What does my CBC report say?',
    'Is my vitamin D level sufficient?',
    'My triglycerides are high, what does that mean?',
    'Can you compare my LDL from last month?',
    'What is my fasting glucose trend?',
    'Why is my ESR elevated?',
  ];

  /// General health education — no personal lab data needed.
  static const generalHealthEducation = <String>[
    'What is cholesterol?',
    'How does insulin work?',
    'What causes anemia?',
    'What does vitamin D do?',
    'How is HbA1c measured?',
    'What is the normal range for TSH?',
    'What are the symptoms of diabetes?',
    'What foods help lower cholesterol?',
    'How does the thyroid gland work?',
    'What is creatinine and why is it tested?',
    'What are electrolytes?',
    'How can I improve my iron levels?',
    'What is a lipid panel?',
    'What does LDL stand for?',
    'How does exercise affect blood sugar?',
  ];

  /// Queries that are clearly outside Koshika's domain.
  static const offTopic = <String>[
    'What is the capital of France?',
    'Write me a poem about the moon.',
    'Help me with my Python code.',
    'Tell me a joke.',
    'What is the weather today?',
    'Who is the president?',
    'Solve this math equation.',
    'Recommend a good movie.',
    'Translate this to Hindi.',
    'What is the stock price of Tesla?',
    'How do I make pasta?',
    'Write an email to my boss.',
    'What is quantum physics?',
    'Help me debug my JavaScript.',
    'What year did World War 2 end?',
  ];

  // ─── Classifier Configuration ────────────────────────────────────────

  /// Cosine similarity threshold for high-confidence classification.
  static const double highConfidenceThreshold = 0.80;

  /// Lower bound for low-confidence classification.
  /// Below this → route to clarification.
  static const double lowConfidenceThreshold = 0.60;
}
