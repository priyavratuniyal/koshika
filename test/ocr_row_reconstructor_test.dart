import 'package:flutter_test/flutter_test.dart';
import 'package:koshika/services/ocr_row_reconstructor.dart';

void main() {
  group('OcrRowReconstructor', () {
    test('groups nearby lines into the same row and sorts by x position', () {
      final reconstructor = OcrRowReconstructor();
      final text = reconstructor.reconstructText([
        const OcrTextLine(
          text: '14.2',
          left: 150,
          top: 10,
          right: 180,
          bottom: 20,
        ),
        const OcrTextLine(
          text: 'Hemoglobin',
          left: 10,
          top: 12,
          right: 120,
          bottom: 22,
        ),
        const OcrTextLine(
          text: 'TSH',
          left: 10,
          top: 50,
          right: 40,
          bottom: 60,
        ),
      ]);

      expect(text.split('\n'), ['Hemoglobin  14.2', 'TSH']);
    });
  });
}
