enum ExtractionMethod { digital, ocr, hybrid, failed }

enum ImportFailureReason {
  fileNotFound,
  invalidPdf,
  encryptedPdf,
  ocrFailed,
  unsupportedFormat,
  timeout,
  unknown,
}

enum ImportStage {
  readingPdf,
  runningOcr,
  parsingRows,
  matchingBiomarkers,
  savingResults,
}

class ImportProgress {
  final ImportStage stage;
  final String message;
  final int? current;
  final int? total;

  const ImportProgress({
    required this.stage,
    required this.message,
    this.current,
    this.total,
  });
}

class PageExtractionDiagnostics {
  final int pageNumber;
  final bool usedOcr;
  final bool ocrFailed;
  final int digitalTextLength;
  final int finalTextLength;
  final String? warning;

  const PageExtractionDiagnostics({
    required this.pageNumber,
    required this.usedOcr,
    required this.ocrFailed,
    required this.digitalTextLength,
    required this.finalTextLength,
    this.warning,
  });
}
