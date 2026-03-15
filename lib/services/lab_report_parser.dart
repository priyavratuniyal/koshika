class RawLabRow {
  final String testName;
  final String? valueStr;
  final String? unit;
  final String? refRangeStr;
  final String? section;
  final String? inlineFlag;

  RawLabRow({
    required this.testName,
    this.valueStr,
    this.unit,
    this.refRangeStr,
    this.section,
    this.inlineFlag,
  });

  @override
  String toString() {
    return 'RawLabRow(test: "$testName", val: "$valueStr", unit: "$unit", ref: "$refRangeStr", sec: "$section", flag: "$inlineFlag")';
  }
}

class LabReportParser {
  /// Known section headers to group tests
  static const List<String> _sectionHeaders = [
    'COMPLETE BLOOD COUNT',
    'CBC',
    'HAEMOGRAM',
    'LIPID PROFILE',
    'LIPID',
    'THYROID PROFILE',
    'THYROID',
    'LIVER FUNCTION TEST',
    'LIVER FUNCTION',
    'LFT',
    'KIDNEY FUNCTION TEST',
    'KIDNEY FUNCTION',
    'KFT',
    'RENAL FUNCTION',
    'IRON STUDIES',
    'IRON PROFILE',
    'DIABETES',
    'SUGAR',
    'BLOOD SUGAR',
    'VITAMIN',
    'BIOCHEMISTRY',
    'SPECIAL SEROLOGY',
  ];

  /// Keywords that indicate a line is a header/footer, not a data row
  static const List<String> _ignoredLineKeywords = [
    'patient ',
    'patient:',
    'name ',
    'name:',
    'age ',
    'age:',
    'sex ',
    'sex:',
    'gender ',
    'gender:',
    'sample ',
    'sample:',
    'barcode',
    'report id',
    'report no',
    'report date',
    'reported on',
    'reported at',
    'date of', 'date:', 'collected', 'received',
    'doctor', 'ref by', 'referred', 'page ', 'page:', 'signature',
    'end of report', 'laboratory', 'test name', 'unit', 'reference',
    'biological reference interval', 'method',
    '--- page', // Page separator injected by PdfTextExtractorService
  ];

  /* 
   * Regex Patterns 
   */

  // Pattern A: Space-delimited with clear columns:
  // "Hemoglobin    14.2    g/dL    13.0 - 17.0"
  // "WBC Count      8500    cells/cumm   4000-11000"
  static final RegExp _patternA = RegExp(
    r'^([a-zA-Z0-9\s/().-]+?)\s{2,}([<>\d.,]+(?:\s*[HL\*])?)\s+([a-zA-Z0-9/%µ^.-]+)?\s*([<>\d.,]+ *[-–] *[\d.,]+|< *[\d.,]+|> *[\d.,]+|Upto\s*[\d.,]+|Up to\s*[\d.,]+)?$',
  );

  // Pattern B: Colon separated:
  // "Hemoglobin: 14.2 g/dL (13.0 - 17.0)"
  static final RegExp _patternB = RegExp(
    r'^([a-zA-Z0-9\s/().-]+?):\s*([<>\d.,]+(?:\s*[HL\*])?)\s*([a-zA-Z0-9/%µ^.-]*)\s*(?:\(?([<>\d.,]+ *[-–] *[\d.,]+|< *[\d.,]+|> *[\d.,]+|Upto\s*[\d.,]+|Up to\s*[\d.,]+)?\)?)?$',
  );

  // Pattern C: Pipe separated
  // "| Hemoglobin | 14.2 | g/dL | 13.0 - 17.0"
  static final RegExp _patternC = RegExp(
    r'^\|?\s*([a-zA-Z0-9\s/().-]+?)\s*\|\s*([<>\d.,]+(?:\s*[HL\*])?)\s*\|\s*([a-zA-Z0-9/%µ^.-]*)\s*\|\s*([<>\d.,]+ *[-–] *[\d.,]+|< *[\d.,]+|> *[\d.,]+|Upto\s*[\d.,]+|Up to\s*[\d.,]+)?$',
  );

  // Pattern D: Loose catch-all (name + value)
  // "Hemoglobin 14.2"
  static final RegExp _patternD = RegExp(
    r'^([a-zA-Z0-9][a-zA-Z0-9\s/%+_/().-]{2,80}?)\s+([<>\d]+[.,]*\d*(?:\s*[HL\*])?)',
  );

  /// Try to parse raw text into structured rows
  List<RawLabRow> parseRawText(String fullText) {
    final List<RawLabRow> results = [];
    final List<String> lines = fullText.split('\n');

    String? currentSection;
    String? pendingLabel;

    for (int i = 0; i < lines.length; i++) {
      String line = _normalizeLine(lines[i]);

      // Skip empty lines or very long lines (likely paragraphs)
      if (line.isEmpty || line.length > 200) continue;

      // 1. Check if line is an ignored header/footer
      final lowerLine = line.toLowerCase();
      bool shouldIgnore = false;
      for (final kw in _ignoredLineKeywords) {
        if (lowerLine.startsWith(kw) || lowerLine.contains('$kw :')) {
          shouldIgnore = true;
          break;
        }
      }
      if (shouldIgnore) continue;

      // 2. Check if line is a section header
      final upperLine = line.toUpperCase();
      bool foundSection = false;
      for (final sec in _sectionHeaders) {
        if (_isSectionHeader(line, sec, upperLine)) {
          currentSection = sec;
          foundSection = true;
          break;
        }
      }
      if (foundSection) continue;

      if (pendingLabel != null) {
        final combined = '$pendingLabel $line'.replaceAll(RegExp(r'\s+'), ' ');
        final pendingRow = _tryPatterns(combined, currentSection);
        if (pendingRow != null) {
          results.add(pendingRow);
          pendingLabel = null;
          continue;
        }

        if (_looksLikeLabelOnlyLine(line)) {
          pendingLabel = '$pendingLabel $line';
          continue;
        }

        pendingLabel = null;
      }

      // 3. Try to match data row patterns on the original spacing
      RawLabRow? row = _tryPatterns(line, currentSection);

      // 4. If nothing matched, clean up common OCR artifacts or strange spacing and try again
      if (row == null) {
        final cleanLine = line.replaceAll(RegExp(r'\s+'), ' ').trim();
        row = _tryPatterns(cleanLine, currentSection);
      }

      // Handle multiline test names (e.g., test name split over two lines)
      if (row == null && i < lines.length - 1) {
        // Check if the NEXT line has numbers
        final nextLine = _normalizeLine(lines[i + 1]);
        if (nextLine.isNotEmpty &&
            RegExp(r'\d').hasMatch(nextLine) &&
            _looksLikeLabelOnlyLine(line)) {
          // This line is just text, next line has the data. Combine them.
          final combinedLine = '$line $nextLine';
          row = _tryPatterns(combinedLine, currentSection);

          if (row == null) {
            final cleanCombinedLine = combinedLine
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            row = _tryPatterns(cleanCombinedLine, currentSection);
          }

          if (row != null) {
            i++; // Skip the next line since we consumed it
          }
        }
      }

      if (row != null && row.testName.trim().isNotEmpty) {
        results.add(row);
      } else if (_looksLikeLabelOnlyLine(line)) {
        pendingLabel = line;
      }
    }

    return results;
  }

  RawLabRow? _tryPatterns(String line, String? section) {
    // Try Pattern A
    var match = _patternA.firstMatch(line);
    if (match != null) {
      final valueMeta = _extractInlineFlag(match.group(2));
      return RawLabRow(
        testName: _normalizeTestName(match.group(1)!),
        valueStr: valueMeta.value,
        unit: match.group(3)?.trim(),
        refRangeStr: match.group(4)?.trim(),
        section: section,
        inlineFlag: valueMeta.flag,
      );
    }

    // Try Pattern C (Pipe)
    match = _patternC.firstMatch(line);
    if (match != null) {
      final valueMeta = _extractInlineFlag(match.group(2));
      return RawLabRow(
        testName: _normalizeTestName(match.group(1)!),
        valueStr: valueMeta.value,
        unit: match.group(3)?.trim(),
        refRangeStr: match.group(4)?.trim(),
        section: section,
        inlineFlag: valueMeta.flag,
      );
    }

    // Try Pattern B (Colon)
    match = _patternB.firstMatch(line);
    if (match != null) {
      final valueMeta = _extractInlineFlag(match.group(2));
      return RawLabRow(
        testName: _normalizeTestName(match.group(1)!),
        valueStr: valueMeta.value,
        unit: match.group(3)?.trim(),
        refRangeStr: match.group(4)?.trim(),
        section: section,
        inlineFlag: valueMeta.flag,
      );
    }

    // Try Pattern D (Loose Catch-all)
    match = _patternD.firstMatch(line);
    if (match != null) {
      // Look ahead in the line to see if we missed units/range
      final remaining = line.substring(match.end).trim();
      String? unit;
      String? range;

      // Very rudimentary check for unit or range in the remainder
      if (remaining.isNotEmpty) {
        final tokens = remaining.split(' ');
        if (tokens.isNotEmpty && !tokens[0].contains(RegExp(r'\d'))) {
          unit = tokens[0];
        }
        final rangeMatch = RegExp(
          r'([<>\d.,]+ *[-–] *[\d.,]+|< *[\d.,]+|> *[\d.,]+)',
        ).firstMatch(remaining);
        if (rangeMatch != null) {
          range = rangeMatch.group(1);
        }
      }

      final valueMeta = _extractInlineFlag(match.group(2));
      return RawLabRow(
        testName: _normalizeTestName(match.group(1)!),
        valueStr: valueMeta.value,
        unit: unit,
        refRangeStr: range,
        section: section,
        inlineFlag: valueMeta.flag,
      );
    }

    return null;
  }

  static String _normalizeLine(String input) {
    var line = input.trim();
    if (line.isEmpty) return line;

    line = line.replaceAll('—', '-').replaceAll('–', '-');
    line = line.replaceAllMapped(RegExp(r'(?<=\d),(?=\d{1,2}\b)'), (_) => '.');
    line = line.replaceAll('..', '.');
    line = line.replaceAllMapped(
      RegExp(r'(^|[<>\s])([lI])(?=\d)'),
      (match) => '${match.group(1)}1',
    );
    return line.trim();
  }

  static String _normalizeTestName(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _looksLikeLabelOnlyLine(String line) {
    if (line.isEmpty) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(line) || line.length < 4) {
      return false;
    }
    if (RegExp(
      r'(<|>|(?:^|\s)\d+(?:[.,]\d+)?(?:\s*[HL\*])?(?:\s|$)|\d+\s*[-–]\s*\d+)',
    ).hasMatch(line)) {
      return false;
    }
    return true;
  }

  static bool _isSectionHeader(String line, String section, String upperLine) {
    if (RegExp(r'\d').hasMatch(line)) return false;

    final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized != normalized.toUpperCase()) {
      return false;
    }

    return upperLine == section || upperLine.contains(section);
  }

  static ({String? value, String? flag}) _extractInlineFlag(String? rawValue) {
    if (rawValue == null) return (value: null, flag: null);

    final trimmed = rawValue.trim();
    final match = RegExp(
      r'^(.*?)(?:\s+)?(H|L|HIGH|LOW|\*)$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match == null) {
      return (value: trimmed, flag: null);
    }

    final value = match.group(1)?.trim();
    final flag = match.group(2)?.toUpperCase();
    return (value: value, flag: flag);
  }
}
