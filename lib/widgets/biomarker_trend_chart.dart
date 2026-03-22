import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

class BiomarkerTrendChart extends StatelessWidget {
  final List<BiomarkerResult> history;

  const BiomarkerTrendChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Filter numeric results and sort by date ascending
    final numericResults = history.where((r) => r.value != null).toList()
      ..sort((a, b) => a.testDate.compareTo(b.testDate));

    if (numericResults.isEmpty) {
      return Container(
        height: 250,
        decoration: KoshikaDecorations.card,
        alignment: Alignment.center,
        child: const Text('No numeric data to chart.'),
      );
    }

    // 2. Prepare Data Points
    final spots = numericResults.map((r) {
      return FlSpot(r.testDate.millisecondsSinceEpoch.toDouble(), r.value!);
    }).toList();

    // Calculate basic Y range
    double rawMinY = numericResults.map((r) => r.value!).reduce(min);
    double rawMaxY = numericResults.map((r) => r.value!).reduce(max);

    // Get reference range from latest result (newest is last)
    final latestResult = numericResults.last;
    final refLow = latestResult.refLow;
    final refHigh = latestResult.refHigh;

    if (refLow != null) rawMinY = min(rawMinY, refLow);
    if (refHigh != null) rawMaxY = max(rawMaxY, refHigh);

    double minY = rawMinY;
    double maxY = rawMaxY;

    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    } else {
      final padding = (maxY - minY) * 0.1;
      minY -= padding;
      maxY += padding;
    }

    // Calculate X range
    double minX = spots.first.x;
    double maxX = spots.last.x;

    if (minX == maxX) {
      final oneDayMs = const Duration(days: 1).inMilliseconds.toDouble();
      minX -= oneDayMs;
      maxX += oneDayMs;
    }

    // X axis interval
    final xRange = maxX - minX;
    final oneDayMs = const Duration(days: 1).inMilliseconds.toDouble();
    final xInterval = xRange > 0 ? max(xRange / 4, oneDayMs) : oneDayMs;

    // Define line bars for Reference Band
    final barDataList = <LineChartBarData>[];

    LineChartBarData? highLine;
    LineChartBarData? lowLine;

    final extraLines = <HorizontalLine>[];

    if (refHigh != null || refLow != null) {
      final shadeTop = refHigh ?? maxY;
      final shadeBottom = refLow ?? 0.0;

      extraLines.add(
        HorizontalLine(
          y: shadeTop,
          color: AppColors.success.withValues(alpha: 0.3),
        ),
      );
      if (refLow != null) {
        extraLines.add(
          HorizontalLine(
            y: shadeBottom,
            color: AppColors.success.withValues(alpha: 0.3),
          ),
        );
      }

      highLine = LineChartBarData(
        spots: [FlSpot(minX, shadeTop), FlSpot(maxX, shadeTop)],
        show: false,
      );
      lowLine = LineChartBarData(
        spots: [FlSpot(minX, shadeBottom), FlSpot(maxX, shadeBottom)],
        show: false,
      );
      barDataList.add(highLine);
      barDataList.add(lowLine);
    }

    // Add main data line
    final mainDataLineIndex = barDataList.length;
    final mainDataLine = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: AppColors.secondary,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          final result = numericResults[index];
          final dotColor =
              (result.flag == BiomarkerFlag.normal ||
                  result.flag == BiomarkerFlag.unknown)
              ? AppColors.success
              : AppColors.error;
          return FlDotCirclePainter(
            radius: 5,
            color: dotColor,
            strokeWidth: 2,
            strokeColor: AppColors.surface,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        color: AppColors.secondary.withValues(alpha: 0.1),
      ),
    );

    barDataList.add(mainDataLine);

    final betweenBarsData = <BetweenBarsData>[];
    if (highLine != null && lowLine != null) {
      betweenBarsData.add(
        BetweenBarsData(
          fromIndex: 0,
          toIndex: 1,
          color: AppColors.success.withValues(alpha: 0.1),
        ),
      );
    }

    return Container(
      decoration: KoshikaDecorations.card,
      padding: const EdgeInsets.only(right: 18, left: 12, top: 24, bottom: 12),
      child: SizedBox(
        height: 250,
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: xInterval,
                  getTitlesWidget: (value, meta) {
                    if (value == maxX || value == minX) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      value.toInt(),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('MMM d').format(date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    String formattedValue;
                    if (value.abs() >= 10000) {
                      formattedValue = '${(value / 1000).toStringAsFixed(0)}k';
                    } else if (value.abs() >= 100) {
                      formattedValue = value.toStringAsFixed(0);
                    } else if (value.abs() >= 1) {
                      formattedValue = value.toStringAsFixed(1);
                    } else {
                      formattedValue = value.toStringAsFixed(2);
                    }
                    return Text(
                      formattedValue,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: barDataList,
            betweenBarsData: betweenBarsData,
            extraLinesData: ExtraLinesData(horizontalLines: extraLines),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.surfaceContainerHighest,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    if (spot.barIndex != mainDataLineIndex) {
                      return null;
                    }
                    final result = numericResults[spot.spotIndex];
                    final dateStr = DateFormat(
                      'dd MMM yyyy',
                    ).format(result.testDate);
                    final flagStr = _getFlagCode(result.flag);
                    final flagColor = (result.flag == BiomarkerFlag.normal)
                        ? AppColors.success
                        : AppColors.error;
                    return LineTooltipItem(
                      '$dateStr\n',
                      TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.normal,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(
                          text: '${result.formattedValue} ${result.unit ?? ""}',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        TextSpan(
                          text: ' ($flagStr)',
                          style: TextStyle(
                            color: flagColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getFlagCode(BiomarkerFlag flag) {
    return switch (flag) {
      BiomarkerFlag.normal => 'N',
      BiomarkerFlag.borderline => 'B',
      BiomarkerFlag.low => 'L',
      BiomarkerFlag.high => 'H',
      BiomarkerFlag.critical => 'C',
      BiomarkerFlag.unknown => '-',
    };
  }
}
