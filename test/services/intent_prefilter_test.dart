import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/models/query_decision.dart';
import 'package:koshika/services/intent_prefilter.dart';

void main() {
  group('IntentPrefilter.classify', () {
    // ─── Emergency Detection ──────────────────────────────────────────

    group('emergency patterns', () {
      test('detects "chest pain"', () {
        expect(
          IntentPrefilter.classify('I have chest pain'),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects reverse word order "pain in my chest"', () {
        expect(
          IntentPrefilter.classify('pain in my chest'),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "heart attack"', () {
        expect(
          IntentPrefilter.classify("I think I'm having a heart attack"),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "can\'t breathe"', () {
        expect(
          IntentPrefilter.classify("I can't breathe"),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "suicidal"', () {
        expect(
          IntentPrefilter.classify('I feel suicidal'),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "stroke"', () {
        expect(
          IntentPrefilter.classify('I think I had a stroke'),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "severe bleeding"', () {
        expect(
          IntentPrefilter.classify('I have severe bleeding'),
          PrefilterResult.emergencyDetected,
        );
      });

      test('detects "overdose"', () {
        expect(
          IntentPrefilter.classify('I took an overdose'),
          PrefilterResult.emergencyDetected,
        );
      });
    });

    // ─── Personal Lab Queries ─────────────────────────────────────────

    group('personal lab patterns', () {
      test('detects "my cholesterol"', () {
        expect(
          IntentPrefilter.classify('Why is my cholesterol high?'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects "my creatinine"', () {
        expect(
          IntentPrefilter.classify('Why is my creatinine high?'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects "lab report"', () {
        expect(
          IntentPrefilter.classify('Show me my lab report'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects "test results"', () {
        expect(
          IntentPrefilter.classify('What do my test results mean?'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects value with medical unit', () {
        expect(
          IntentPrefilter.classify('My creatinine is 1.8 mg/dl'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects "is my ... normal"', () {
        expect(
          IntentPrefilter.classify('Is my TSH normal?'),
          PrefilterResult.likelyLabQuery,
        );
      });

      // Hinglish
      test('detects Hinglish "mera sugar"', () {
        expect(
          IntentPrefilter.classify('mera sugar kitna hai?'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects Hinglish "meri report"', () {
        expect(
          IntentPrefilter.classify('meri report dikhao'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects Hinglish "apna cholesterol"', () {
        expect(
          IntentPrefilter.classify('apna cholesterol check karo'),
          PrefilterResult.likelyLabQuery,
        );
      });

      test('detects Hinglish "kya hai mera"', () {
        expect(
          IntentPrefilter.classify('kya hai mera hemoglobin'),
          PrefilterResult.likelyLabQuery,
        );
      });
    });

    // ─── Off-Topic Detection ──────────────────────────────────────────

    group('off-topic patterns', () {
      test('detects programming request', () {
        expect(
          IntentPrefilter.classify('Write me some Python code'),
          PrefilterResult.offTopicDetected,
        );
      });

      test('detects creative writing', () {
        expect(
          IntentPrefilter.classify('Write me a poem'),
          PrefilterResult.offTopicDetected,
        );
      });

      test('detects geography question', () {
        expect(
          IntentPrefilter.classify('What is the capital of France?'),
          PrefilterResult.offTopicDetected,
        );
      });

      test('detects recipe request', () {
        expect(
          IntentPrefilter.classify('How do I cook pasta?'),
          PrefilterResult.offTopicDetected,
        );
      });

      test('detects joke request', () {
        expect(
          IntentPrefilter.classify('Tell me a joke'),
          PrefilterResult.offTopicDetected,
        );
      });
    });

    // ─── Biomarker Education (Health, not Lab) ────────────────────────

    group('bare biomarker → health query (not lab)', () {
      test('"What is cholesterol?" → health, not lab', () {
        expect(
          IntentPrefilter.classify('What is cholesterol?'),
          PrefilterResult.likelyHealthQuery,
        );
      });

      test('"What does HbA1c measure?" → health', () {
        expect(
          IntentPrefilter.classify('What does HbA1c measure?'),
          PrefilterResult.likelyHealthQuery,
        );
      });

      test('"What is creatinine?" → health', () {
        expect(
          IntentPrefilter.classify('What is creatinine?'),
          PrefilterResult.likelyHealthQuery,
        );
      });

      test('"What causes anemia?" → health', () {
        expect(
          IntentPrefilter.classify('What causes anemia?'),
          PrefilterResult.likelyHealthQuery,
        );
      });
    });

    // ─── General Health ───────────────────────────────────────────────

    group('health keywords', () {
      test('"Is heart disease hereditary?" → health (not lab)', () {
        expect(
          IntentPrefilter.classify('Is heart disease hereditary?'),
          PrefilterResult.likelyHealthQuery,
        );
      });

      test('"What foods help lower blood pressure?" → health', () {
        expect(
          IntentPrefilter.classify('What foods help lower blood pressure?'),
          PrefilterResult.likelyHealthQuery,
        );
      });

      test('"How much exercise should I do?" → health', () {
        expect(
          IntentPrefilter.classify('How much exercise should I do?'),
          PrefilterResult.likelyHealthQuery,
        );
      });
    });

    // ─── Ambiguous / Default ──────────────────────────────────────────

    group('ambiguous messages', () {
      test('"hello" → ambiguous', () {
        expect(IntentPrefilter.classify('hello'), PrefilterResult.ambiguous);
      });

      test('empty → ambiguous', () {
        expect(IntentPrefilter.classify(''), PrefilterResult.ambiguous);
      });

      test('"thanks" → ambiguous', () {
        expect(IntentPrefilter.classify('thanks'), PrefilterResult.ambiguous);
      });
    });

    // ─── False Positive Prevention ────────────────────────────────────

    group('false positive prevention', () {
      test('"100% sure about this" → not lab query', () {
        final result = IntentPrefilter.classify('100% sure about this');
        expect(result, isNot(PrefilterResult.likelyLabQuery));
      });

      test('"my package was delivered" → not lab (liver)', () {
        final result = IntentPrefilter.classify('my package was delivered');
        expect(result, isNot(PrefilterResult.likelyLabQuery));
      });

      test('"alternative medicine" → not lab (alt)', () {
        final result = IntentPrefilter.classify(
          'What about alternative medicine?',
        );
        expect(result, isNot(PrefilterResult.likelyLabQuery));
      });

      test('"I need to fast" → not lab (fasting)', () {
        // "fasting" with word boundary should still match health
        final result = IntentPrefilter.classify(
          'Should I do intermittent fasting?',
        );
        expect(result, PrefilterResult.likelyHealthQuery);
      });
    });
  });
}
