import 'dart:io';
import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'extraction_diagnostics.dart';
import 'ocr_row_reconstructor.dart';
import 'ocr_text_recognition_service.dart';
import 'pdf_page_render_service.dart';

class PdfExtractionResult {
  final String fullText;
  final List<String> pageTexts;
  final int pageCount;
  final bool isEmpty;
  final String? labName;
  final DateTime? reportDate;
  final ExtractionMethod extractionMethod;
  final List<PageExtractionDiagnostics> pageDiagnostics;
  final List<String> warnings;

  PdfExtractionResult({
    required this.fullText,
    required this.pageTexts,
    required this.pageCount,
    required this.isEmpty,
    this.labName,
    this.reportDate,
    this.extractionMethod = ExtractionMethod.digital,
    this.pageDiagnostics = const [],
    this.warnings = const [],
  });
}

class PdfTextExtractorService {
  static const int _maxPagesToExtract = 15;
  static const Duration _ocrTimeout = Duration(seconds: 12);

  /// Known Indian lab names for auto-detection
  static const List<String> _knownLabs = [
    'thyrocare',
    'dr lal',
    'dr. lal',
    'srl',
    'metropolis',
    'redcliffe',
    'pathkind',
    'suburban',
    'agilus',
    'lucid',
  ];

  static final RegExp _dateRegex = RegExp(
    r'(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})',
  );

  final PdfPageRenderService _pageRenderService;
  final OcrTextRecognitionService _ocrTextRecognitionService;
  final OcrRowReconstructor _ocrRowReconstructor;

  PdfTextExtractorService({
    PdfPageRenderService? pageRenderService,
    OcrTextRecognitionService? ocrTextRecognitionService,
    OcrRowReconstructor? ocrRowReconstructor,
  }) : _pageRenderService = pageRenderService ?? PdfPageRenderService(),
       _ocrTextRecognitionService =
           ocrTextRecognitionService ?? OcrTextRecognitionService(),
       _ocrRowReconstructor = ocrRowReconstructor ?? OcrRowReconstructor();

  /// Extracts all text from a PDF file at the given path.
  Future<PdfExtractionResult> extractText(
    String filePath, {
    void Function(ImportProgress progress)? onProgress,
  }) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) {
        throw const FileSystemException('File not found');
      }

      final Uint8List bytes = await file.readAsBytes();

      PdfDocument document;
      try {
        document = PdfDocument(inputBytes: bytes);
      } catch (e) {
        throw const FormatException(
          'This file does not appear to be a valid or supported PDF.',
        );
      }

      final int pageCount = document.pages.count;
      final int pagesToProcess = pageCount > _maxPagesToExtract
          ? _maxPagesToExtract
          : pageCount;

      final List<String> pageTexts = [];
      final List<PageExtractionDiagnostics> pageDiagnostics = [];
      final List<String> warnings = [];
      final StringBuffer fullTextBuffer = StringBuffer();
      int ocrPagesAttempted = 0;
      int ocrPagesSucceeded = 0;

      // Set up Syncfusion extractor
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      for (int i = 0; i < pagesToProcess; i++) {
        onProgress?.call(
          ImportProgress(
            stage: ImportStage.readingPdf,
            message: 'Reading PDF page ${i + 1} of $pagesToProcess...',
            current: i + 1,
            total: pagesToProcess,
          ),
        );

        final String pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );

        final bool shouldUseOcr = shouldUseOcrForPage(pageText);
        String finalPageText = pageText.trim();
        bool usedOcr = false;
        bool ocrFailed = false;
        String? pageWarning;

        if (shouldUseOcr) {
          usedOcr = true;
          ocrPagesAttempted++;
          onProgress?.call(
            ImportProgress(
              stage: ImportStage.runningOcr,
              message: 'Running OCR on page ${i + 1} of $pagesToProcess...',
              current: i + 1,
              total: pagesToProcess,
            ),
          );

          try {
            final renderedPage = await _pageRenderService.renderPage(
              filePath,
              i + 1,
            );
            final ocrResult = await _ocrTextRecognitionService.recognizePage(
              renderedPage,
              timeout: _ocrTimeout,
            );
            final reconstructed = _ocrRowReconstructor
                .reconstructText(ocrResult.lines)
                .trim();
            finalPageText = reconstructed.isNotEmpty
                ? reconstructed
                : ocrResult.rawText.trim();
            if (finalPageText.isNotEmpty) {
              ocrPagesSucceeded++;
            }

            if (finalPageText.isEmpty) {
              pageWarning = 'OCR found no readable text on page ${i + 1}.';
            }
          } catch (_) {
            ocrFailed = true;
            pageWarning = 'OCR failed on page ${i + 1}; using digital text.';
            finalPageText = pageText.trim();
          }
        }

        if (finalPageText.isEmpty) {
          pageWarning ??= 'Page ${i + 1} contained very little readable text.';
        }

        if (pageWarning != null) {
          warnings.add(pageWarning);
        }

        pageTexts.add(finalPageText);
        pageDiagnostics.add(
          PageExtractionDiagnostics(
            pageNumber: i + 1,
            usedOcr: usedOcr,
            ocrFailed: ocrFailed,
            digitalTextLength: _meaningfulCharacterCount(pageText),
            finalTextLength: _meaningfulCharacterCount(finalPageText),
            warning: pageWarning,
          ),
        );
        fullTextBuffer.writeln('--- PAGE ${i + 1} ---');
        fullTextBuffer.writeln(finalPageText);
      }

      // Dispose document to free memory
      document.dispose();
      await _pageRenderService.close();

      final String fullText = fullTextBuffer.toString();
      final int actualTextLength = pageTexts.fold<int>(
        0,
        (sum, t) => sum + _meaningfulCharacterCount(t),
      );
      final bool isEmpty = actualTextLength < 50;

      String? detectedLabName;
      DateTime? detectedReportDate;

      if (!isEmpty && pageTexts.isNotEmpty) {
        final String firstPageLower = pageTexts.first.toLowerCase();

        // Detect lab name
        for (final lab in _knownLabs) {
          if (firstPageLower.contains(lab)) {
            // Capitalize properly for display
            detectedLabName = lab
                .split(' ')
                .map(
                  (word) => word.isEmpty
                      ? ''
                      : '${word[0].toUpperCase()}${word.substring(1)}',
                )
                .join(' ');
            break;
          }
        }

        // Detect report date
        final match = _dateRegex.firstMatch(firstPageLower);
        if (match != null) {
          final String dateStr = match.group(1)!;
          try {
            // Very simple date parsing (assumes DD/MM/YY or DD/MM/YYYY)
            // A more robust app would use intl.DateFormat, but this is a fallback
            final parts = dateStr.split(RegExp(r'[\/\-\.]'));
            if (parts.length >= 3) {
              int day = int.parse(parts[0]);
              int month = int.parse(parts[1]);
              int year = int.parse(parts[2]);

              if (year < 100) year += 2000;

              // Basic sanity check
              if (day > 0 && day <= 31 && month > 0 && month <= 12) {
                detectedReportDate = DateTime(year, month, day);
              }
            }
          } catch (e) {
            // Ignore date parsing errors
          }
        }
      }

      final extractionMethod = ocrPagesSucceeded == 0
          ? ExtractionMethod.digital
          : ocrPagesSucceeded == pagesToProcess ||
                (ocrPagesAttempted > 0 &&
                    ocrPagesSucceeded == ocrPagesAttempted)
          ? ExtractionMethod.ocr
          : ExtractionMethod.hybrid;

      return PdfExtractionResult(
        fullText: fullText,
        pageTexts: pageTexts,
        pageCount: pageCount,
        isEmpty: isEmpty,
        labName: detectedLabName,
        reportDate: detectedReportDate,
        extractionMethod: isEmpty ? ExtractionMethod.failed : extractionMethod,
        pageDiagnostics: pageDiagnostics,
        warnings: warnings,
      );
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('password') || lower.contains('encrypted')) {
        throw const FormatException(
          'This PDF appears to be password protected or encrypted.',
        );
      }
      if (e is FileSystemException || e is FormatException) {
        rethrow;
      }
      throw FormatException('Failed to process PDF: $e');
    }
  }

  static int _meaningfulCharacterCount(String text) {
    return RegExp(r'[A-Za-z0-9]').allMatches(text).length;
  }

  static bool shouldUseOcrForPage(String pageText) {
    final trimmed = pageText.trim();
    if (trimmed.isEmpty) return true;

    final meaningfulChars = _meaningfulCharacterCount(trimmed);
    final lineCount = '\n'.allMatches(trimmed).length + 1;
    final hasLabPatterns = RegExp(
      r'(\d+\s*[-–]\s*\d+|mg/dl|g/dl|u/l|iu/l|mmol/l|%|platelet|hemoglobin|cholesterol|tsh|creatinine)',
      caseSensitive: false,
    ).hasMatch(trimmed);

    if (meaningfulChars < 35) return true;
    if (meaningfulChars < 100 && !hasLabPatterns) return true;
    if (lineCount <= 2 && meaningfulChars < 120) return true;
    return false;
  }
}
