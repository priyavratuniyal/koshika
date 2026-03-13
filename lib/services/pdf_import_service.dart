
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'objectbox_store.dart';
import 'biomarker_dictionary.dart';
import 'pdf_text_extractor.dart';
import 'lab_report_parser.dart';

class ImportResult {
  final bool success;
  final LabReport? report;
  final List<BiomarkerResult> results;
  final int totalRowsDetected;
  final int successfulMatches;
  final List<String> unmatchedTests;
  final List<String> warnings;
  final String? errorMessage;

  ImportResult({
    required this.success,
    this.report,
    this.results = const [],
    this.totalRowsDetected = 0,
    this.successfulMatches = 0,
    this.unmatchedTests = const [],
    this.warnings = const [],
    this.errorMessage,
  });
}

class PdfImportService {
  final PdfTextExtractorService _extractor;
  final LabReportParser _parser;
  final BiomarkerDictionary _dictionary;
  final ObjectBoxStore _store;

  PdfImportService(this._extractor, this._parser, this._dictionary, this._store);

  Future<ImportResult> importPdf(String filePath) async {
    final List<String> warnings = [];
    final List<String> unmatchedTests = [];
    
    try {
      // 1. Extract text
      final PdfExtractionResult extractResult = await _extractor.extractText(filePath);
      
      if (extractResult.isEmpty) {
        return ImportResult(
          success: false, 
          errorMessage: 'This PDF appears to be a scanned image or empty. Text extraction from images is not yet supported.',
        );
      }

      // 2. Parse raw text into candidate rows
      final List<RawLabRow> candidateRows = _parser.parseRawText(extractResult.fullText);
      final int totalRows = candidateRows.length;

      if (totalRows == 0) {
        warnings.add('No biomarker data was found in this PDF. It may not be a lab report, or the format is not recognized.');
      }

      // 3. Match candidate rows to the dictionary and build BiomarkerResults
      final Map<String, BiomarkerResult> bestMatches = {}; // Use Map for de-duplication

      for (final row in candidateRows) {
        final BiomarkerMatch? match = _dictionary.fuzzyMatch(row.testName);

        if (match != null && match.score >= 0.5) {
          final def = match.definition;
          
          // Check for better match if we already found this biomarker
          if (bestMatches.containsKey(def.key)) {
             // Basic de-duplication: we'll just keep the first one found or we could compare scores 
             // if we kept the raw score in the BiomarkerResult. For simplicity, we just keep the first valid one.
             // Or better: over-write if this row has actual values and the old one didn't.
             final existing = bestMatches[def.key]!;
             if (existing.value == null && row.valueStr != null) {
                // If the new row has a value and old doesn't, override.
             } else {
                continue; // Skip duplicate
             }
          }

          // Parse value
          String cleanValueStr = row.valueStr?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
          double? parsedValue = double.tryParse(cleanValueStr);
          String? valueText;
          if (parsedValue == null) {
            valueText = row.valueStr;
          }

          // Parse reference range
          double? refLow = def.refLowMale;  // Default to male if patient has no sex defined
          double? refHigh = def.refHighMale;
          
          // Try to extract from the PDF string, if not fallback to dictionary
          if (row.refRangeStr != null) {
             final rangeStr = row.refRangeStr!.replaceAll(RegExp(r'[a-zA-Z/%µ]+'), '').trim();
             // Match format: 13.0 - 17.0
             final match = RegExp(r'([\d.]+)\s*[-–]\s*([\d.]+)').firstMatch(rangeStr);
             if (match != null) {
                refLow = double.tryParse(match.group(1)!);
                refHigh = double.tryParse(match.group(2)!);
             } else {
                // Formatting like "< 200"
                final lessMatch = RegExp(r'<\s*([\d.]+)').firstMatch(rangeStr);
                if (lessMatch != null) {
                    refLow = null;
                    refHigh = double.tryParse(lessMatch.group(1)!);
                } else {
                   // "> 40"
                   final moreMatch = RegExp(r'>\s*([\d.]+)').firstMatch(rangeStr);
                   if (moreMatch != null) {
                       refLow = double.tryParse(moreMatch.group(1)!);
                       refHigh = null;
                   }
                }
             }
          }

          final result = BiomarkerResult(
            biomarkerKey: def.key,
            displayName: def.displayName,
            originalName: row.testName,
            value: parsedValue,
            valueText: valueText,
            unit: row.unit ?? def.unit,
            refLow: refLow,
            refHigh: refHigh,
            refRangeRaw: row.refRangeStr,
            loincCode: def.loincCode,
            category: def.category,
            testDate: extractResult.reportDate ?? DateTime.now(),
          );
          
          result.computeFlag();
          bestMatches[def.key] = result;
        } else {
          // No good match found
          unmatchedTests.add(row.testName);
        }
      }

      final List<BiomarkerResult> finalResults = bestMatches.values.toList();
      final int successCount = finalResults.length;

      // Create Report object
      final String originalFileName = p.basename(filePath);
      
      final LabReport report = LabReport(
        reportDate: extractResult.reportDate ?? DateTime.now(),
        pdfPath: filePath,
        originalFileName: originalFileName,
        extractedCount: successCount,
        totalDetected: totalRows,
        rawText: extractResult.fullText,
      );
      report.patient.target = _store.getOrCreateDefaultPatient();

      // Save to database
      if (successCount > 0 || totalRows > 0) {
        try {
          _store.saveReportWithResults(report, finalResults);
        } catch (e) {
          return ImportResult(
            success: false,
            errorMessage: 'Failed to save results to database: $e',
          );
        }
      }

      return ImportResult(
        success: true,
        report: report,
        results: finalResults,
        totalRowsDetected: totalRows,
        successfulMatches: successCount,
        unmatchedTests: unmatchedTests,
        warnings: warnings,
      );

    } catch (e) {
      return ImportResult(
        success: false,
        errorMessage: 'An unexpected error occurred during import: $e',
      );
    }
  }
}
