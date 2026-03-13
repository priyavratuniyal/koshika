import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfExtractionResult {
  final String fullText;
  final List<String> pageTexts;
  final int pageCount;
  final bool isEmpty;
  final String? labName;
  final DateTime? reportDate;

  PdfExtractionResult({
    required this.fullText,
    required this.pageTexts,
    required this.pageCount,
    required this.isEmpty,
    this.labName,
    this.reportDate,
  });
}

class PdfTextExtractorService {
  static const int _maxPagesToExtract = 15;

  /// Known Indian lab names for auto-detection
  static const List<String> _knownLabs = [
    'thyrocare', 'dr lal', 'dr. lal', 'srl', 'metropolis',
    'redcliffe', 'pathkind', 'suburban', 'agilus', 'lucid'
  ];

  static final RegExp _dateRegex = RegExp(r'(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})');

  /// Extracts all text from a PDF file at the given path.
  Future<PdfExtractionResult> extractText(String filePath) async {
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
        throw const FormatException('This file does not appear to be a valid or supported PDF.');
      }

      final int pageCount = document.pages.count;
      final int pagesToProcess = pageCount > _maxPagesToExtract ? _maxPagesToExtract : pageCount;

      final List<String> pageTexts = [];
      final StringBuffer fullTextBuffer = StringBuffer();

      // Set up Syncfusion extractor
      final PdfTextExtractor extractor = PdfTextExtractor(document);

      for (int i = 0; i < pagesToProcess; i++) {
        final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        
        pageTexts.add(pageText);
        fullTextBuffer.writeln('--- PAGE ${i + 1} ---');
        fullTextBuffer.writeln(pageText);
      }

      // Dispose document to free memory
      document.dispose();

      final String fullText = fullTextBuffer.toString();
      final bool isEmpty = fullText.length < 50;

      String? detectedLabName;
      DateTime? detectedReportDate;

      if (!isEmpty && pageTexts.isNotEmpty) {
        final String firstPageLower = pageTexts.first.toLowerCase();
        
        // Detect lab name
        for (final lab in _knownLabs) {
          if (firstPageLower.contains(lab)) {
            // Capitalize properly for display
            detectedLabName = lab.split(' ').map((word) => 
              word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}'
            ).join(' ');
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

      return PdfExtractionResult(
        fullText: fullText,
        pageTexts: pageTexts,
        pageCount: pageCount,
        isEmpty: isEmpty,
        labName: detectedLabName,
        reportDate: detectedReportDate,
      );
    } catch (e) {
      if (e is FileSystemException || e is FormatException) {
        rethrow;
      }
      throw FormatException('Failed to process PDF: $e');
    }
  }
}
