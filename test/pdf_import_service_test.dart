import 'package:flutter_test/flutter_test.dart';

import 'package:koshika/services/pdf_import_service.dart';

void main() {
  group('PdfImportService.parseNumericValue', () {
    test('parses flagged numeric values', () {
      expect(PdfImportService.parseNumericValue('12.5 H'), 12.5);
      expect(PdfImportService.parseNumericValue('< 200'), 200);
    });

    test('parses comma decimal and thousands separators', () {
      expect(PdfImportService.parseNumericValue('4,5'), 4.5);
      expect(PdfImportService.parseNumericValue('12,500'), 12500);
      expect(PdfImportService.parseNumericValue('1,234.56'), 1234.56);
    });

    test('returns null for qualitative values', () {
      expect(PdfImportService.parseNumericValue('Reactive'), isNull);
      expect(PdfImportService.parseNumericValue(null), isNull);
    });

    test('normalizes common OCR artifacts before parsing', () {
      expect(PdfImportService.parseNumericValue('l.0'), 1.0);
      expect(PdfImportService.parseNumericValue('5,4'), 5.4);
    });
  });

  group('PdfImportService.parseReferenceRange', () {
    test('parses bounded ranges', () {
      final range = PdfImportService.parseReferenceRange('13.0 - 17.0 g/dL');
      expect(range.low, 13.0);
      expect(range.high, 17.0);
    });

    test('parses one sided ranges', () {
      final less = PdfImportService.parseReferenceRange('Upto 200');
      final more = PdfImportService.parseReferenceRange('> 40');

      expect(less.low, isNull);
      expect(less.high, 200);
      expect(more.low, 40);
      expect(more.high, isNull);
    });
  });
}
