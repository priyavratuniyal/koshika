import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Lightweight [CustomPainter] that draws a simple sparkline from data points.
///
/// Designed for compact trend previews inside dashboard category cards.
/// No axes, no labels — pure sparkline.
class SimpleTrendLinePainter extends CustomPainter {
  SimpleTrendLinePainter({
    required this.values,
    this.lineColor = AppColors.secondary,
    this.lineWidth = 2.0,
    this.showFill = true,
  });

  final List<double> values;
  final Color lineColor;
  final double lineWidth;
  final bool showFill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;
    final effectiveRange = range == 0 ? 1.0 : range;

    // Add vertical padding so the line doesn't touch edges.
    const verticalPadding = 4.0;
    final drawHeight = size.height - verticalPadding * 2;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final normalized = (values[i] - minVal) / effectiveRange;
      final y = verticalPadding + drawHeight * (1 - normalized);
      points.add(Offset(x, y));
    }

    // Draw fill area.
    if (showFill) {
      final fillPath = Path()
        ..moveTo(points.first.dx, size.height)
        ..lineTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath
        ..lineTo(points.last.dx, size.height)
        ..close();

      canvas.drawPath(
        fillPath,
        Paint()..color = lineColor.withValues(alpha: 0.1),
      );
    }

    // Draw line.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SimpleTrendLinePainter oldDelegate) =>
      values != oldDelegate.values ||
      lineColor != oldDelegate.lineColor ||
      lineWidth != oldDelegate.lineWidth ||
      showFill != oldDelegate.showFill;
}
