import '../models/query_decision.dart';

/// Deterministic first-pass classifier that routes user messages before any
/// LLM call. Rules are evaluated top-to-bottom — first match wins.
///
/// Emergency patterns are always checked first for safety.
abstract final class IntentPrefilter {
  // ─── Emergency Patterns ──────────────────────────────────────────────

  static final _emergencyPatterns = [
    // Cardiac — match both word orders ("chest pain" and "pain in chest")
    RegExp(r'chest\s*(pain|pressure|tightness)', caseSensitive: false),
    RegExp(r'pain\s*(in|on)\s*(my\s*)?chest', caseSensitive: false),
    RegExp(r'heart\s*attack', caseSensitive: false),
    RegExp(r'cardiac\s*arrest', caseSensitive: false),

    // Respiratory
    RegExp(r"can'?t\s*breathe", caseSensitive: false),
    RegExp(r'cannot\s*breathe', caseSensitive: false),
    RegExp(r'difficulty\s*breathing', caseSensitive: false),
    RegExp(r'choking', caseSensitive: false),

    // Neurological
    RegExp(r'\bstroke\b', caseSensitive: false),
    RegExp(r'\bseizure\b', caseSensitive: false),
    RegExp(r'\bunconscious\b', caseSensitive: false),
    RegExp(r'\bparalysis\b', caseSensitive: false),
    RegExp(r'\bparalyzed\b', caseSensitive: false),

    // Self-harm / suicide
    RegExp(r'suicid(e|al)', caseSensitive: false),
    RegExp(r'kill\s*my\s*self', caseSensitive: false),
    RegExp(r'want\s*to\s*die', caseSensitive: false),
    RegExp(r'self\s*harm', caseSensitive: false),
    RegExp(r'end\s*my\s*life', caseSensitive: false),

    // Toxicological
    RegExp(r'\boverdose\b', caseSensitive: false),
    RegExp(r'\bpoisoning\b', caseSensitive: false),

    // Allergic
    RegExp(r'anaphyla', caseSensitive: false),

    // Severe bleeding
    RegExp(r'severe\s*bleeding', caseSensitive: false),
    RegExp(r'heavy\s*bleeding', caseSensitive: false),
  ];

  // ─── Personal Lab Patterns ───────────────────────────────────────────
  //
  // These indicate the user is asking about *their own* lab data, not just
  // asking what a biomarker is. Requires possessive/personal language.

  // Possessive pronouns — English + common Hinglish variants.
  // Used to detect personal lab queries ("my cholesterol", "mera sugar").
  static const _possessive =
      r'(my|mera|meri|mere|apna|apni|apne|hamara|hamari)';

  /// Biomarker names used inside possessive patterns. Kept as a string
  /// alternation so it can be embedded in regex groups.
  static const _biomarkerAlt =
      r'(thyroid|tsh|cholesterol|creatinine|hemoglobin|glucose|hba1c|a1c'
      r'|sgpt|sgot|alt|ast|bilirubin|albumin|iron|ferritin|vitamin'
      r'|sodium|potassium|calcium|platelet|triglyceride|urea|insulin'
      r'|ldl|hdl|liver|kidney|cbc|lft|kft|sugar|b12|wbc|rbc|hb|esr|crp'
      r'|anemia|anaemia|lipid|folate|tibc|transferrin|neutrophil)';

  /// Phrases that explicitly reference the user's own reports or results.
  static final _personalLabPatterns = [
    // Explicit report/result references (English)
    RegExp(r'lab\s*report', caseSensitive: false),
    RegExp(r'test\s*result', caseSensitive: false),
    RegExp(r'blood\s*test', caseSensitive: false),
    RegExp(r'blood\s*work', caseSensitive: false),

    // Possessive + generic result words (English + Hinglish)
    RegExp(
      '$_possessive\\s*(report|results|levels|values|numbers|test)',
      caseSensitive: false,
    ),

    // Possessive + biomarker name (English + Hinglish)
    // "my cholesterol", "mera sugar", "meri thyroid"
    RegExp('$_possessive\\s+$_biomarkerAlt\\b', caseSensitive: false),

    // "is my ... high/low/normal" (English)
    RegExp(r'is\s+my\b', caseSensitive: false),
    // "why is my ... high/low"
    RegExp(r'why\s+(is|are)\s+my\b', caseSensitive: false),
    // "show me my", "check my"
    RegExp(r'(show|check|tell)\s*(me\s+)?my\b', caseSensitive: false),

    // Hinglish report phrases
    // "meri report dikhao", "report dikhao", "mera report"
    RegExp('$_possessive\\s*report', caseSensitive: false),
    // "kitna hai" / "kitni hai" (how much is) — common Hinglish question form
    RegExp('$_biomarkerAlt\\s*(kitna|kitni|kitne)\\b', caseSensitive: false),
    // "kya hai mera/meri" — "what is my"
    RegExp('kya\\s+(hai|he|h)\\s+$_possessive', caseSensitive: false),

    // Value-with-unit pattern: "1.8 mg/dl", "120 mmol/l"
    // Only match medical compound units — excludes bare "g", "%", "ml" to
    // avoid false positives like "5g network", "100% sure", "500ml water".
    RegExp(
      r'\d+\.?\d*\s*(mg/dl|mg/l|mmol/l|mmol|miu/l|miu/ml|iu/l|iu/ml|µg/dl|µg/l|ng/ml|ng/dl|pg/ml|g/dl|g/l|meq/l|u/l|cells/cumm|lakh|thousand)',
      caseSensitive: false,
    ),
  ];

  // ─── Biomarker Vocabulary ────────────────────────────────────────────
  //
  // Bare biomarker mentions (without personal signal) indicate the user
  // wants health *education*, not personalised interpretation.

  /// Long/unambiguous biomarker keywords — safe for plain `contains` matching.
  static const _biomarkerKeywords = <String>[
    // Thyroid
    'thyroid', 'hypothyroid', 'hyperthyroid', 'goiter',
    // CBC
    'blood count', 'hemoglobin', 'platelet',
    'anemia', 'anaemia', 'neutrophil', 'lymphocyte',
    // Lipid Panel
    'cholesterol', 'triglyceride',
    // LFT
    'sgpt', 'sgot', 'bilirubin', 'albumin',
    // KFT
    'creatinine',
    // Diabetes
    'glucose', 'hba1c', 'glycated',
    // Vitamins
    'folate', 'folic',
    // Iron Studies
    'ferritin', 'tibc', 'transferrin',
    // Electrolytes
    'electrolyte',
    // Inflammation
    'sed rate', 'c-reactive',
  ];

  /// Short or ambiguous biomarker terms that need word-boundary matching.
  static final _biomarkerBoundaryPatterns = [
    RegExp(r'\btsh\b', caseSensitive: false),
    RegExp(r'\bt3\b', caseSensitive: false),
    RegExp(r'\bt4\b', caseSensitive: false),
    RegExp(r'\bcbc\b', caseSensitive: false),
    RegExp(r'\bhb\b', caseSensitive: false),
    RegExp(r'\bwbc\b', caseSensitive: false),
    RegExp(r'\brbc\b', caseSensitive: false),
    RegExp(r'\btlc\b', caseSensitive: false),
    RegExp(r'\bdlc\b', caseSensitive: false),
    RegExp(r'\bldl\b', caseSensitive: false),
    RegExp(r'\bhdl\b', caseSensitive: false),
    RegExp(r'\bvldl\b', caseSensitive: false),
    RegExp(r'\blft\b', caseSensitive: false),
    RegExp(r'\balt\b', caseSensitive: false),
    RegExp(r'\bast\b', caseSensitive: false),
    RegExp(r'\bggtp\b', caseSensitive: false),
    RegExp(r'\bkft\b', caseSensitive: false),
    RegExp(r'\bbun\b', caseSensitive: false),
    RegExp(r'\bgfr\b', caseSensitive: false),
    RegExp(r'\ba1c\b', caseSensitive: false),
    RegExp(r'\bb12\b', caseSensitive: false),
    RegExp(r'\biron\b', caseSensitive: false),
    RegExp(r'\bcrp\b', caseSensitive: false),
    RegExp(r'\besr\b', caseSensitive: false),
    RegExp(r'\bsugar\b', caseSensitive: false),
    RegExp(r'\bfasting\b', caseSensitive: false),
    RegExp(r'\bhepat', caseSensitive: false),
    RegExp(r'\blipid\b', caseSensitive: false),
    RegExp(r'\binsulin\b', caseSensitive: false),
    RegExp(r'\burea\b', caseSensitive: false),
    RegExp(r'\bliver\b', caseSensitive: false),
    RegExp(r'\bkidney\b', caseSensitive: false),
    RegExp(r'\brenal\b', caseSensitive: false),
    RegExp(r'\balkaline\b', caseSensitive: false),
    RegExp(r'\bvitamin\b', caseSensitive: false),
    RegExp(r'\bdiabetes\b', caseSensitive: false),
    RegExp(r'\bdiabetic\b', caseSensitive: false),
  ];

  // ─── Off-Topic Patterns ──────────────────────────────────────────────

  static final _offTopicPatterns = [
    // Programming / tech
    RegExp(
      r'\b(python|javascript|java|html|css|sql|code|coding|programming|debug|compile|algorithm|api)\b',
      caseSensitive: false,
    ),
    RegExp(r'help\s*me\s*(code|program|debug|build)', caseSensitive: false),
    RegExp(
      r'write\s*(me\s+)?(a\s+)?(code|script|function|program)',
      caseSensitive: false,
    ),

    // Creative writing
    RegExp(
      r'write\s*(me\s+)?(a\s+)?(poem|story|essay|song|lyrics|letter|email)',
      caseSensitive: false,
    ),
    RegExp(r'\b(poem|poetry|fiction|novel)\b', caseSensitive: false),

    // Academic (but not biochemistry/medical)
    RegExp(
      r'\b(calculus|algebra|geometry|physics|geography|capital\s*of)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bhistory\s+(of\s+)?(the\s+)?(world|war|country|nation|empire)',
      caseSensitive: false,
    ),

    // General knowledge / entertainment
    RegExp(
      r'\b(weather|recipe|cook|movie|sports?\s*score|stock\s*price|crypto|bitcoin)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'tell\s*(me\s+)?(a\s+)?(joke|riddle|fun\s*fact)',
      caseSensitive: false,
    ),
    RegExp(r'translate\s+this', caseSensitive: false),

    // Explicit off-topic asks
    RegExp(
      r'who\s+(is|was)\s+(the\s+)?(president|king|queen|prime\s*minister)',
      caseSensitive: false,
    ),
  ];

  // ─── Health Patterns ─────────────────────────────────────────────────

  static const _healthKeywords = <String>[
    'health',
    'healthy',
    'diet',
    'exercise',
    'symptom',
    'symptoms',
    'disease',
    'condition',
    'treatment',
    'medication',
    'medicine',
    'supplement',
    'nutrition',
    'fitness',
    'wellness',
    'immunity',
    'immune',
    'blood pressure',
    'weight',
    'obesity',
    'infection',
    'fever',
    'fatigue',
    'tired',
    'headache',
    'digestion',
    'probiotic',
    'antibiotic',
    'hormone',
    'metabolism',
    'calorie',
    'protein',
    'carbohydrate',
    'hydration',
    'sleep',
    'stress',
    'anxiety',
    'depression',
    'cardiac',
    'cardiovascular',
    'heart',
    'doctor',
    'medical',
  ];

  /// Short health terms needing word-boundary matching.
  static final _healthBoundaryPatterns = [
    RegExp(r'\bfat\b', caseSensitive: false),
    RegExp(r'\bbp\b', caseSensitive: false),
    RegExp(r'\bbmi\b', caseSensitive: false),
    RegExp(r'\bgut\b', caseSensitive: false),
    RegExp(r'\bpain\b', caseSensitive: false),
  ];

  // ─── Public API ──────────────────────────────────────────────────────

  /// Classify a user message into a [PrefilterResult].
  ///
  /// Rule order:
  ///   1. Emergency (safety-critical, always first)
  ///   2. Personal lab references (possessive + biomarker, or report phrases)
  ///   3. Off-topic (clearly outside health domain)
  ///   4. Biomarker mentions without personal signal (educational)
  ///   5. General health keywords
  ///   6. Ambiguous (default)
  static PrefilterResult classify(String message) {
    if (message.trim().isEmpty) return PrefilterResult.ambiguous;

    final lower = message.toLowerCase();

    // 1. Emergency — always checked first for safety
    for (final pattern in _emergencyPatterns) {
      if (pattern.hasMatch(lower)) return PrefilterResult.emergencyDetected;
    }

    // 2. Personal lab references — user is asking about *their own* data
    if (_matchesPersonalLab(lower)) return PrefilterResult.likelyLabQuery;

    // 3. Off-topic — checked before biomarker/health so that a message
    //    like "write python code" isn't rescued by a stray health keyword
    for (final pattern in _offTopicPatterns) {
      if (pattern.hasMatch(lower)) return PrefilterResult.offTopicDetected;
    }

    // 4. Bare biomarker mentions — educational, no personal data needed
    if (_matchesBiomarker(lower)) return PrefilterResult.likelyHealthQuery;

    // 5. General health keywords
    if (_matchesHealth(lower)) return PrefilterResult.likelyHealthQuery;

    // 6. Default
    return PrefilterResult.ambiguous;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  static bool _matchesPersonalLab(String lower) {
    for (final pattern in _personalLabPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  static bool _matchesBiomarker(String lower) {
    for (final keyword in _biomarkerKeywords) {
      if (lower.contains(keyword)) return true;
    }
    for (final pattern in _biomarkerBoundaryPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  static bool _matchesHealth(String lower) {
    for (final keyword in _healthKeywords) {
      if (lower.contains(keyword)) return true;
    }
    for (final pattern in _healthBoundaryPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }
}
