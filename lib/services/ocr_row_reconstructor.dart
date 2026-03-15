class OcrTextLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get height => (bottom - top).abs();
  double get centerY => top + (height / 2);
}

class OcrRowReconstructor {
  List<String> reconstructRows(List<OcrTextLine> lines) {
    if (lines.isEmpty) return const [];

    final sorted = List<OcrTextLine>.from(lines)
      ..sort((a, b) {
        final yCompare = a.centerY.compareTo(b.centerY);
        if (yCompare != 0) return yCompare;
        return a.left.compareTo(b.left);
      });

    final rows = <List<OcrTextLine>>[];

    for (final line in sorted) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }

      final currentRow = rows.last;
      final avgCenterY =
          currentRow.fold<double>(0, (sum, item) => sum + item.centerY) /
          currentRow.length;
      final avgHeight =
          currentRow.fold<double>(0, (sum, item) => sum + item.height) /
          currentRow.length;
      final tolerance = avgHeight <= 0 ? 8.0 : avgHeight * 0.45;

      if ((line.centerY - avgCenterY).abs() <= tolerance) {
        currentRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    return rows
        .map((row) {
          row.sort((a, b) => a.left.compareTo(b.left));
          return row
              .map((line) => line.text.trim())
              .where((text) => text.isNotEmpty)
              .join('  ');
        })
        .where((row) => row.isNotEmpty)
        .toList();
  }

  String reconstructText(List<OcrTextLine> lines) {
    return reconstructRows(lines).join('\n');
  }
}
