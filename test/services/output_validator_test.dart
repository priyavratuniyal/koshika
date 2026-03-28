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

    // ─── Garbled Output ───────────────────────────────────────────────

    test('detects high non-ASCII ratio as garbled', () {
      // Build a string with >30% non-ASCII characters
      final garbled = 'ÿ' * 40 + 'normal text here abcdef';
      expect(OutputValidator.validate(garbled), ValidationResult.garbled);
    });

    test('detects consonant-only gibberish as garbled', () {
      // Words without vowels
      final garbled = List.generate(
        20,
        (_) => 'bcrdfg hklmnp qrstvw xyzbrn',
      ).join(' ');
      expect(OutputValidator.validate(garbled), ValidationResult.garbled);
    });

    test('detects abnormally long words as garbled', () {
      // Average word length > 15
      final garbled = List.generate(
        10,
        (_) => 'abcdefghijklmnopqrstuvwxyz',
      ).join(' ');
      expect(OutputValidator.validate(garbled), ValidationResult.garbled);
    });

    test('passes normal text with some non-ASCII', () {
      // Medical text with a few special chars should pass
      const output =
          'Your TSH level of 2.5 mIU/L is within the normal range. '
          'The reference range is 0.4–4.0 mIU/L. This suggests healthy '
          'thyroid function.';
      expect(OutputValidator.validate(output), ValidationResult.passed);
    });

    // ─── Excessive Length ─────────────────────────────────────────────

    test('detects overly long response', () {
      // Use text that passes garbled + repetition checks but exceeds length.
      // Each sentence is unique to avoid repetition detection.
      final sentences = [
        'Cholesterol is a waxy substance found in blood.',
        'High-density lipoprotein helps remove other forms of cholesterol.',
        'Low-density lipoprotein is often called bad cholesterol.',
        'Triglycerides are another type of fat found in blood.',
        'A lipid panel measures all major types of fats.',
        'Dietary changes can help improve cholesterol levels.',
        'Exercise increases high-density lipoprotein cholesterol.',
        'Genetics play a role in cholesterol levels.',
        'Statins are commonly prescribed to lower cholesterol.',
        'Regular testing helps monitor cardiovascular health.',
        'Hemoglobin carries oxygen throughout the body.',
        'Iron deficiency can lead to low hemoglobin levels.',
        'Complete blood count reveals many important markers.',
        'White blood cells fight infection and disease.',
        'Platelets help with blood clotting processes.',
        'Creatinine levels indicate kidney function status.',
        'Estimated GFR measures how well kidneys filter blood.',
        'Blood urea nitrogen also reflects kidney health.',
        'Thyroid stimulating hormone regulates metabolism rate.',
        'Free T4 is the active form of thyroid hormone.',
        'Vitamin D supports bone health and immune function.',
        'Calcium levels affect muscle and nerve function.',
        'Liver enzymes indicate hepatic function status.',
        'Albumin is a protein made by the liver.',
        'Bilirubin is a waste product from red blood cells.',
        'Potassium balance is critical for heart rhythm stability.',
        'Sodium levels help regulate fluid balance in the body.',
        'Magnesium supports hundreds of enzymatic reactions daily.',
        'Phosphorus works with calcium for strong bones.',
        'Uric acid buildup can cause gout and joint pain.',
        'Ferritin reflects the iron stores in your body.',
        'Transferrin saturation shows iron transport capacity.',
        'Reticulocyte count indicates new red blood cell production.',
        'Mean corpuscular volume describes red blood cell size.',
      ];
      final output = sentences.join(' ');
      expect(output.length, greaterThan(1500));
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

    test('garbled → garbled fallback', () {
      expect(
        OutputValidator.applyFallback(ValidationResult.garbled, 'xyzbrn'),
        ValidationStrings.garbledFallback,
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
