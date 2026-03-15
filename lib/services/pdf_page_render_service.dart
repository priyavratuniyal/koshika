import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

class RenderedPdfPage {
  final int pageNumber;
  final Uint8List bytes;
  final int width;
  final int height;

  const RenderedPdfPage({
    required this.pageNumber,
    required this.bytes,
    required this.width,
    required this.height,
  });
}

class PdfPageRenderService {
  PdfDocument? _document;
  String? _documentPath;

  Future<PdfDocument> _getDocument(String filePath) async {
    if (_document != null && _documentPath == filePath) {
      return _document!;
    }

    await close();
    _document = await PdfDocument.openFile(filePath);
    _documentPath = filePath;
    return _document!;
  }

  Future<RenderedPdfPage> renderPage(
    String filePath,
    int pageNumber, {
    int targetWidth = 1500,
  }) async {
    final document = await _getDocument(filePath);
    final page = await document.getPage(pageNumber);

    try {
      final aspectRatio = page.height == 0 ? 1.0 : page.width / page.height;
      final targetHeight = (targetWidth / aspectRatio).round().clamp(400, 2400);
      final image = await page.render(
        width: targetWidth.toDouble(),
        height: targetHeight.toDouble(),
        format: PdfPageImageFormat.png,
      );

      if (image == null || image.bytes.isEmpty) {
        throw const FormatException('Failed to render PDF page image.');
      }

      return RenderedPdfPage(
        pageNumber: pageNumber,
        bytes: image.bytes,
        width: image.width ?? targetWidth,
        height: image.height ?? targetHeight,
      );
    } finally {
      await page.close();
    }
  }

  Future<void> close() async {
    if (_document != null) {
      await _document!.close();
      _document = null;
      _documentPath = null;
    }
  }
}
