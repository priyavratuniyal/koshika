import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/services/pdf_text_extractor.dart';

void main() {
  group('PdfTextExtractorService.shouldUseOcrForPage', () {
    test('returns true for nearly empty pages', () {
      expect(PdfTextExtractorService.shouldUseOcrForPage('  '), isTrue);
      expect(PdfTextExtractorService.shouldUseOcrForPage('abc'), isTrue);
    });

    test('returns false for rich lab-text pages', () {
      expect(
        PdfTextExtractorService.shouldUseOcrForPage(
          'Hemoglobin 14.2 g/dL 13.0 - 17.0\n'
          'TSH 2.1 uIU/mL 0.4 - 4.0\n'
          'Creatinine 0.9 mg/dL 0.7 - 1.3',
        ),
        isFalse,
      );
    });
  });
}
