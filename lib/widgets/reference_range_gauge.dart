import 'dart:math';
import 'package:flutter/material.dart';

class ReferenceRangeGauge extends StatelessWidget {
  final double? value;
  final double? refLow;
  final double? refHigh;

  const ReferenceRangeGauge({
    super.key,
    required this.value,
    this.refLow,
    this.refHigh,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    if (refLow == null && refHigh == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: CustomPaint(
              size: const Size(double.infinity, 24),
              painter: _GaugePainter(
                value: value!,
                refLow: refLow,
                refHigh: refHigh,
                theme: Theme.of(context),
              ),
            ),
          ),
          // Adding small labels below the gauge for context (optional, but requested in plan)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (refLow != null)
                Text(
                  'Low',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Colors.orange,
                  ),
                ),
              Text(
                'Normal',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: Colors.green,
                ),
              ),
              if (refHigh != null)
                Text(
                  'High',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Colors.red,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double? refLow;
  final double? refHigh;
  final ThemeData theme;

  _GaugePainter({
    required this.value,
    this.refLow,
    this.refHigh,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Use actual bounds for display range; only synthesize for display padding
    final effectiveLow = refLow ?? 0.0;
    final effectiveHigh = refHigh ?? (refLow != null ? refLow! * 2.0 : 100.0);

    // Calculate display range to ensure everything fits (pad by 20%)
    double displayMin = min(value, effectiveLow);
    double displayMax = max(value, effectiveHigh);

    // Add 20% padding to display bounds, except don't go below 0 if all values are positive
    final rangePad = (displayMax - displayMin) * 0.2;
    displayMin = displayMin - rangePad;
    displayMax = displayMax + rangePad;

    if (displayMin < 0 && value >= 0 && effectiveLow >= 0) {
      displayMin = 0;
    }

    final range = displayMax - displayMin;
    final width = size.width;

    double xPos(double val) {
      if (range == 0) return width / 2;
      return ((val - displayMin) / range) * width;
    }

    final lowX = xPos(effectiveLow).clamp(0.0, width);
    final highX = xPos(effectiveHigh).clamp(0.0, width);

    final paint = Paint()..style = PaintingStyle.fill;
    final radius = const Radius.circular(6);
    final isDark = theme.brightness == Brightness.dark;

    final lowColor = Colors.orange.withValues(alpha: isDark ? 0.6 : 0.3);
    final normalColor = Colors.green.withValues(alpha: isDark ? 0.6 : 0.3);
    final highColor = Colors.red.withValues(alpha: isDark ? 0.6 : 0.3);

    // Draw the background bar based on available reference limits
    if (refLow != null && refHigh != null) {
      // 3 zones (Low, Normal, High)
      // Low Zone
      paint.color = lowColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(0, 10, lowX, 18),
          topLeft: radius,
          bottomLeft: radius,
        ),
        paint,
      );
      // Normal Zone
      paint.color = normalColor;
      canvas.drawRect(Rect.fromLTRB(lowX, 10, highX, 18), paint);
      // High Zone
      paint.color = highColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(highX, 10, width, 18),
          topRight: radius,
          bottomRight: radius,
        ),
        paint,
      );
    } else if (refLow != null) {
      // 2 zones (Low, Normal)
      paint.color = lowColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(0, 10, lowX, 18),
          topLeft: radius,
          bottomLeft: radius,
        ),
        paint,
      );
      paint.color = normalColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(lowX, 10, width, 18),
          topRight: radius,
          bottomRight: radius,
        ),
        paint,
      );
    } else if (refHigh != null) {
      // 2 zones (Normal, High)
      paint.color = normalColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(0, 10, highX, 18),
          topLeft: radius,
          bottomLeft: radius,
        ),
        paint,
      );
      paint.color = highColor;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(highX, 10, width, 18),
          topRight: radius,
          bottomRight: radius,
        ),
        paint,
      );
    }

    // Draw reference limit ticks
    final limitTickPaint = Paint()
      ..color = theme.colorScheme.onSurface.withValues(alpha: 0.5)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    if (refLow != null) {
      canvas.drawLine(Offset(lowX, 8), Offset(lowX, 20), limitTickPaint);
    }
    if (refHigh != null) {
      canvas.drawLine(Offset(highX, 8), Offset(highX, 20), limitTickPaint);
    }

    // Draw current value marker
    final valX = xPos(value).clamp(4.0, width - 4.0);

    // Check if it's out of bounds and we clamped it heavily (unlikely due to displayMin/Max scaling, but safe)
    bool outOfBoundsRight = value > displayMax;
    bool outOfBoundsLeft = value < displayMin;

    final markerPaint = Paint()
      ..color = theme.colorScheme.onSurface
      ..style = PaintingStyle.fill;

    // Triangle marker pointing down
    final path = Path();
    if (outOfBoundsRight) {
      path
        ..moveTo(width - 4, 0)
        ..lineTo(width, 4)
        ..lineTo(width - 4, 8)
        ..close();
    } else if (outOfBoundsLeft) {
      path
        ..moveTo(4, 0)
        ..lineTo(0, 4)
        ..lineTo(4, 8)
        ..close();
    } else {
      path
        ..moveTo(valX, 8)
        ..lineTo(valX - 4, 2)
        ..lineTo(valX + 4, 2)
        ..close();
    }

    final tickPaint = Paint()
      ..color = theme.colorScheme.onSurface
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, markerPaint);

    if (!outOfBoundsLeft && !outOfBoundsRight) {
      canvas.drawLine(Offset(valX, 8), Offset(valX, 20), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.refLow != refLow ||
        oldDelegate.refHigh != refHigh ||
        oldDelegate.theme != theme;
  }
}
