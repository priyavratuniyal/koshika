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

  static double? parseNumericValue(String? rawValue) {
    if (rawValue == null) return null;

    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'[-+]?\d[\d,]*(?:\.\d+)?(?:[eE][-+]?\d+)?|[-+]?\d+(?:,\d+)?(?:[eE][-+]?\d+)?')
        .firstMatch(trimmed);
    if (match == null) return null;

    var numeric = match.group(0)!;

    if (numeric.contains(',') && numeric.contains('.')) {
      if (numeric.lastIndexOf(',') > numeric.lastIndexOf('.')) {
        numeric = numeric.replaceAll('.', '').replaceAll(',', '.');
      } else {
        numeric = numeric.replaceAll(',', '');
      }
    } else if (numeric.contains(',')) {
      final commaCount = ','.allMatches(numeric).length;
      final parts = numeric.split(',');
      if (commaCount > 1) {
        numeric = numeric.replaceAll(',', '');
      } else if (parts.length == 2 && parts[1].length == 3 && parts[0].length > 1) {
        numeric = numeric.replaceAll(',', '');
      } else {
        numeric = numeric.replaceAll(',', '.');
      }
    }

    return double.tryParse(numeric);
  }

  static ({double? low, double? high}) parseReferenceRange(String? rawRange) {
    if (rawRange == null || rawRange.trim().isEmpty) {
      return (low: null, high: null);
    }

    final trimmedRange = rawRange.trim();
    final rangeStr = trimmedRange.replaceAll(RegExp(r'[a-z/%µ]+', caseSensitive: false), '').trim();

    final betweenMatch = RegExp(r'([-+]?\d[\d,]*(?:\.\d+)?)\s*[-–]\s*([-+]?\d[\d,]*(?:\.\d+)?)')
        .firstMatch(rangeStr);
    if (betweenMatch != null) {
      return (
        low: parseNumericValue(betweenMatch.group(1)),
        high: parseNumericValue(betweenMatch.group(2)),
      );
    }

    final lessMatch = RegExp(
      r'(?:<|upto|up to)\s*([-+]?\d[\d,]*(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(trimmedRange);
    if (lessMatch != null) {
      return (low: null, high: parseNumericValue(lessMatch.group(1)));
    }

    final moreMatch = RegExp(r'>\s*([-+]?\d[\d,]*(?:\.\d+)?)').firstMatch(trimmedRange);
    if (moreMatch != null) {
      return (low: parseNumericValue(moreMatch.group(1)), high: null);
    }

    return (low: null, high: null);
  }

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

        if (match != null) {
          final def = match.definition;
          
          // De-duplication: if we already matched this biomarker key,
          // only override if the new row has a value and the existing one doesn't.
          if (bestMatches.containsKey(def.key)) {
             final existing = bestMatches[def.key]!;
             final bool existingHasNoValue = existing.value == null;
             final bool newRowHasValue = row.valueStr != null && row.valueStr!.trim().isNotEmpty;
             if (!(existingHasNoValue && newRowHasValue)) {
                continue; // Keep existing, skip this duplicate
             }
             // Otherwise fall through to override with the better row
          }

          // Parse value
          final parsedValue = parseNumericValue(row.valueStr);
          String? valueText;
          if (parsedValue == null) {
            valueText = row.valueStr;
          }

          // Parse reference range
          double? refLow = def.refLowMale;  // Default to male if patient has no sex defined
          double? refHigh = def.refHighMale;
          
          // Try to extract from the PDF string, if not fallback to dictionary
          if (row.refRangeStr != null) {
             final parsedRange = parseReferenceRange(row.refRangeStr);
             if (parsedRange.low != null || parsedRange.high != null) {
               refLow = parsedRange.low;
               refHigh = parsedRange.high;
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
        labName: extractResult.labName,
        reportDate: extractResult.reportDate ?? DateTime.now(),
        pdfPath: filePath,
        originalFileName: originalFileName,
        extractedCount: successCount,
        totalDetected: totalRows,
        rawText: extractResult.fullText,
      );
      report.patient.target = _store.getOrCreateDefaultPatient();

      // Always save the report so it appears in history, even with 0 results
      try {
        _store.saveReportWithResults(report, finalResults);
      } catch (e) {
        return ImportResult(
          success: false,
          errorMessage: 'Failed to save results to database: $e',
        );
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
