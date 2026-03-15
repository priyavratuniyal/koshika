import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ocr_row_reconstructor.dart';
import 'pdf_page_render_service.dart';

class OcrPageResult {
  final int pageNumber;
  final List<OcrTextLine> lines;
  final String rawText;

  const OcrPageResult({
    required this.pageNumber,
    required this.lines,
    required this.rawText,
  });
}

class OcrTextRecognitionService {
  Future<OcrPageResult> recognizePage(
    RenderedPdfPage renderedPage, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    File? tempFile;

    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        p.join(
          tempDir.path,
          'koshika_ocr_page_${renderedPage.pageNumber}_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await tempFile.writeAsBytes(renderedPage.bytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await recognizer
          .processImage(inputImage)
          .timeout(timeout);

      final lines = <OcrTextLine>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add(
            OcrTextLine(
              text: line.text,
              left: box.left,
              top: box.top,
              right: box.right,
              bottom: box.bottom,
            ),
          );
        }
      }

      return OcrPageResult(
        pageNumber: renderedPage.pageNumber,
        lines: lines,
        rawText: recognizedText.text,
      );
    } finally {
      await recognizer.close();
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
