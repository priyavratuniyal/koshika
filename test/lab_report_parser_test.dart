import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/services/lab_report_parser.dart';

void main() {
  group('LabReportParser', () {
    final parser = LabReportParser();

    test('combines multiline test names before parsing', () {
      final rows = parser.parseRawText(
        'Alanine Aminotransferase\n'
        '(ALT)  45 H  U/L  0 - 40',
      );

      expect(rows, hasLength(1));
      expect(rows.first.testName, 'Alanine Aminotransferase (ALT)');
      expect(rows.first.valueStr, '45');
      expect(rows.first.inlineFlag, 'H');
    });

    test('normalizes OCR decimal commas in parsed values', () {
      final rows = parser.parseRawText('HbA1c  5,4  %  4.0 - 5.6');

      expect(rows, hasLength(1));
      expect(rows.first.valueStr, '5.4');
    });

    test('buffers multiline labels that contain digits', () {
      final rows = parser.parseRawText(
        'Vitamin B12\n'
        '245 pg/mL  200 - 900',
      );

      expect(rows, hasLength(1));
      expect(rows.first.testName, 'Vitamin B12');
      expect(rows.first.valueStr, '245');
    });

    test('parses OCR flattened analyte names that contain digits', () {
      final rows = parser.parseRawText('25-OH Vitamin D 18.4 ng/mL 30 - 100');

      expect(rows, hasLength(1));
      expect(rows.first.testName, '25-OH Vitamin D');
      expect(rows.first.valueStr, '18.4');
    });
  });
}
