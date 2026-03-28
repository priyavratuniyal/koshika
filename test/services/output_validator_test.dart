import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/constants/validation_strings.dart';
import 'package:koshika/services/output_validator.dart';

void main() {
  group('OutputValidator.validate', () {
    // ─── Emptiness ────────────────────────────────────────────────────

    test('empty string → empty', () {
      expect(OutputValidator.validate(''), ValidationResult.empty);
    });

    test('whitespace only → empty', () {
      expect(OutputValidator.validate('   \n  '), ValidationResult.empty);
    });

    test('very short → empty', () {
      expect(OutputValidator.validate('ok'), ValidationResult.empty);
    });

    // ─── Hallucination Detection ──────────────────────────────────────

    test('passes when output values match context', () {
      const context = 'Creatinine: 1.8 mg/dl [HIGH] (Ref: 0.7–1.3)';
      const output =
          'Your creatinine is 1.8 mg/dl, which is above the '
          'reference range of 0.7 to 1.3 mg/dl.';
      expect(
        OutputValidator.validate(output, labContext: context),
        ValidationResult.passed,
      );
    });

    test('detects hallucinated value not in context', () {
      const context = 'Creatinine: 1.8 mg/dl [HIGH] (Ref: 0.7–1.3)';
      const output = 'Your creatinine is 2.3 mg/dl, which is elevated.';
      expect(
        OutputValidator.validate(output, labContext: context),
        ValidationResult.hallucinated,
      );
    });

    test('no hallucination check without context', () {
      const output = 'Your creatinine is 2.3 mg/dl, which is elevated.';
      expect(OutputValidator.validate(output), ValidationResult.passed);
    });

    // ─── Repetition ───────────────────────────────────────────────────

    test('detects excessive sentence repetition', () {
      final output = List.generate(
        10,
        (_) => 'Your cholesterol level is important for heart health.',
      ).join(' ');
      expect(OutputValidator.validate(output), ValidationResult.repetitive);
    });

    test('passes non-repetitive text', () {
      const output =
          'Your TSH is 2.5 mIU/L which is within normal range. '
          'TSH is produced by the pituitary gland and regulates thyroid '
          'function. Normal range is typically 0.4 to 4.0 mIU/L. '
          'Your value suggests healthy thyroid function.';
      expect(OutputValidator.validate(output), ValidationResult.passed);
    });

    // ─── Prohibited Content ───────────────────────────────────────────

    test('detects "you have diabetes"', () {
      const output =
          'Based on your results, you have diabetes and should '
          'start medication immediately.';
      expect(OutputValidator.validate(output), ValidationResult.prohibited);
    });

    test('detects "you are suffering from"', () {
      const output =
          'You are suffering from kidney disease based on these '
          'creatinine levels.';
      expect(OutputValidator.validate(output), ValidationResult.prohibited);
    });

    test('passes educational language about diseases', () {
      const output =
          'HbA1c measures average blood sugar over 2-3 months. '
          'Values above 6.5% may indicate diabetes. '
          'Consult your doctor for proper diagnosis.';
      expect(OutputValidator.validate(output), ValidationResult.passed);
    });

    // ─── Excessive Length ─────────────────────────────────────────────

    test('detects overly long response', () {
      final output = 'A' * 2000;
      expect(OutputValidator.validate(output), ValidationResult.tooLong);
    });

    // ─── Normal Responses ─────────────────────────────────────────────

    test('passes a good response', () {
      const output =
          'Your TSH level of 2.5 mIU/L is within the normal '
          'range (0.4–4.0 mIU/L). This suggests your thyroid is functioning '
          'well. However, please consult your doctor for a complete '
          'assessment of your thyroid health.';
      expect(OutputValidator.validate(output), ValidationResult.passed);
    });
  });

  group('OutputValidator.applyFallback', () {
    test('passed → returns original output', () {
      const output = 'Your values look normal.';
      expect(
        OutputValidator.applyFallback(ValidationResult.passed, output),
        output,
      );
    });

    test('empty → generic fallback', () {
      expect(
        OutputValidator.applyFallback(ValidationResult.empty, ''),
        ValidationStrings.genericFallback,
      );
    });

    test('hallucinated → hallucination fallback', () {
      expect(
        OutputValidator.applyFallback(ValidationResult.hallucinated, 'bad'),
        ValidationStrings.hallucinationFallback,
      );
    });

    test('repetitive → repetition fallback', () {
      expect(
        OutputValidator.applyFallback(ValidationResult.repetitive, 'repeat'),
        ValidationStrings.repetitionFallback,
      );
    });

    test('prohibited → prohibited content fallback', () {
      expect(
        OutputValidator.applyFallback(ValidationResult.prohibited, 'diagnose'),
        ValidationStrings.prohibitedContentFallback,
      );
    });

    test('tooLong → truncated at sentence boundary', () {
      final output = 'First sentence. Second sentence. ${' ' * 1500}Third.';
      final result = OutputValidator.applyFallback(
        ValidationResult.tooLong,
        output,
      );
      expect(result.length, lessThan(output.length));
      expect(result, contains(ValidationStrings.truncationNotice));
    });
  });
}
