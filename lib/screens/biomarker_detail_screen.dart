import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
import '../widgets/flag_badge.dart';
import '../widgets/status_badge.dart';
import '../widgets/biomarker_trend_chart.dart';
import '../widgets/reference_range_gauge.dart';
import '../widgets/shimmer_loading.dart';

class BiomarkerDetailScreen extends StatefulWidget {
  final String biomarkerKey;

  const BiomarkerDetailScreen({super.key, required this.biomarkerKey});

  @override
  State<BiomarkerDetailScreen> createState() => _BiomarkerDetailScreenState();
}

class _BiomarkerDetailScreenState extends State<BiomarkerDetailScreen> {
  late List<BiomarkerResult> history;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      history = objectbox.getHistoryForBiomarker(widget.biomarkerKey);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _classifyError(e);
      });
    }
  }

  String _classifyError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('objectbox') ||
        msg.contains('store') ||
        msg.contains('box')) {
      return 'Unable to access stored data. Please restart the app and try again.';
    }
    if (msg.contains('relation') || msg.contains('target')) {
      return 'Data relationship error. The linked report may have been deleted.';
    }
    if (msg.contains('date') ||
        msg.contains('format') ||
        msg.contains('parse')) {
      return 'Invalid date found in stored data. Try re-importing the affected report.';
    }
    if (msg.contains('range') || msg.contains('index')) {
      return 'Data index error. Please restart the app.';
    }
    return 'Could not load biomarker data. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Loading...')),
        body: ShimmerScope(
          child: ListView(
            padding: const EdgeInsets.all(KoshikaSpacing.base),
            children: [
              ShimmerBox(
                width: double.infinity,
                height: 200,
                borderRadius: KoshikaRadius.xxl,
              ),
              const SizedBox(height: KoshikaSpacing.xl),
              ShimmerLine(width: 120),
              const SizedBox(height: KoshikaSpacing.base),
              ShimmerBox(
                width: double.infinity,
                height: 180,
                borderRadius: KoshikaRadius.xxl,
              ),
              const SizedBox(height: KoshikaSpacing.xl),
              ShimmerLine(width: 80),
              const SizedBox(height: KoshikaSpacing.md),
              ShimmerBox(
                width: double.infinity,
                height: 60,
                borderRadius: KoshikaRadius.lg,
              ),
              const SizedBox(height: KoshikaSpacing.sm),
              ShimmerBox(
                width: double.infinity,
                height: 60,
                borderRadius: KoshikaRadius.lg,
              ),
              const SizedBox(height: KoshikaSpacing.sm),
              ShimmerBox(
                width: double.infinity,
                height: 60,
                borderRadius: KoshikaRadius.lg,
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(KoshikaSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: KoshikaSpacing.base),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: KoshikaSpacing.base),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _loadData();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (history.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('Biomarker Details')),
        body: const Center(
          child: Text('No data available for this biomarker.'),
        ),
      );
    }

    final latestResult = history.first;
    final hasNumericValues = history.any((r) => r.value != null);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(latestResult.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(KoshikaSpacing.base),
        children: [
          // ── Header Card ─────────────────────────────────────────────
          Container(
            decoration: KoshikaDecorations.card,
            padding: KoshikaSpacing.cardPaddingAsymmetric,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Metric label
                Text(
                  'LATEST RESULT • ${DateFormat('MMM d').format(latestResult.testDate).toUpperCase()}',
                  style: KoshikaTypography.metricLabel,
                ),
                const SizedBox(height: KoshikaSpacing.md),

                // Hero value
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      latestResult.formattedValue,
                      style: KoshikaTypography.heroMetric.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: KoshikaSpacing.sm),
                    if (latestResult.unit != null)
                      Text(
                        latestResult.unit!,
                        style: KoshikaTypography.metricUnit,
                      ),
                  ],
                ),
                const SizedBox(height: KoshikaSpacing.md),

                // Status badge
                StatusBadge(flag: latestResult.flag),

                const SizedBox(height: KoshikaSpacing.lg),

                // Reference gauge
                Text('REFERENCE RANGE', style: KoshikaTypography.metricLabel),
                const SizedBox(height: KoshikaSpacing.sm),
                ReferenceRangeGauge(
                  value: latestResult.value,
                  refLow: latestResult.refLow,
                  refHigh: latestResult.refHigh,
                ),
                const SizedBox(height: KoshikaSpacing.xs),
                Text(
                  latestResult.formattedRefRange,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),

                if (latestResult.loincCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: KoshikaSpacing.xs),
                    child: Text(
                      'LOINC: ${latestResult.loincCode}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: KoshikaSpacing.xl),

          // ── Trend Section ───────────────────────────────────────────
          Row(
            children: [
              Text(
                'Trend',
                style: KoshikaTypography.sectionHeader.copyWith(fontSize: 20),
              ),
              const SizedBox(width: KoshikaSpacing.sm),
              if (!hasNumericValues)
                Expanded(
                  child: Text(
                    '(No numeric data to chart)',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KoshikaSpacing.base),

          if (hasNumericValues) BiomarkerTrendChart(history: history),
          if (hasNumericValues) const SizedBox(height: KoshikaSpacing.xl),

          // ── History Section ─────────────────────────────────────────
          Text(
            'History',
            style: KoshikaTypography.sectionHeader.copyWith(fontSize: 20),
          ),
          const SizedBox(height: KoshikaSpacing.base),

          // History list with alternating backgrounds
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: KoshikaRadius.xxl,
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final result = history[index];
                final report = result.report.target;
                // Alternating row backgrounds
                final bgColor = index.isEven
                    ? AppColors.surfaceContainerLowest
                    : AppColors.surfaceContainerLow;

                return Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoshikaSpacing.lg,
                    vertical: KoshikaSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat.yMMMd().format(result.testDate),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              report?.labName ?? 'Unknown Lab',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${result.formattedValue} ${result.unit ?? ""}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: KoshikaSpacing.md),
                      FlagBadge(flag: result.flag),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
