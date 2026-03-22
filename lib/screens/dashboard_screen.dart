import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
import 'biomarker_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _categoryIcons = <String, IconData>{
    'CBC': Icons.opacity,
    'Thyroid': Icons.psychology,
    'Lipid Panel': Icons.favorite,
    'Liver (LFT)': Icons.local_hospital,
    'Kidney (KFT)': Icons.water_drop,
    'Vitamins': Icons.eco,
    'Iron Studies': Icons.opacity,
    'Electrolytes': Icons.bolt,
    'Diabetes': Icons.monitor_weight_outlined,
    'Inflammation': Icons.healing,
  };

  /// Compute a health score (0–1) for a list of biomarkers based on flags.
  double _categoryScore(List<BiomarkerResult> results) {
    if (results.isEmpty) return 1.0;
    double total = 0;
    for (final r in results) {
      switch (r.flag) {
        case BiomarkerFlag.normal:
          total += 1.0;
        case BiomarkerFlag.borderline:
          total += 0.65;
        case BiomarkerFlag.low:
        case BiomarkerFlag.high:
          total += 0.35;
        case BiomarkerFlag.critical:
          total += 0.1;
        case BiomarkerFlag.unknown:
          total += 0.8;
      }
    }
    return total / results.length;
  }

  /// Build 4 illustrative bar heights for the category mini-chart.
  List<double> _categoryBarHeights(
    List<BiomarkerResult> catResults,
    Map<String, List<BiomarkerResult>> allHistories,
  ) {
    final score = _categoryScore(catResults);
    // Try to pull real historical scores (up to 4 points, oldest→newest).
    // Fall back to an illustrative ramp if not enough history.
    final historicalScores = <double>[];
    for (final r in catResults) {
      final history = allHistories[r.biomarkerKey] ?? [];
      if (history.length >= 2) {
        for (final h in history.reversed.take(4)) {
          double s = 1.0;
          switch (h.flag) {
            case BiomarkerFlag.normal:
              s = 1.0;
            case BiomarkerFlag.borderline:
              s = 0.65;
            case BiomarkerFlag.low:
            case BiomarkerFlag.high:
              s = 0.35;
            case BiomarkerFlag.critical:
              s = 0.1;
            case BiomarkerFlag.unknown:
              s = 0.8;
          }
          historicalScores.add(s);
        }
        break; // use the first biomarker that has history
      }
    }

    if (historicalScores.length >= 4) {
      return historicalScores
          .sublist(historicalScores.length - 4)
          .map((s) => s.clamp(0.15, 1.0))
          .toList();
    }

    // Illustrative: show a simple ramp ending at current score
    final end = score.clamp(0.15, 1.0);
    final mid1 = (0.6 + end) / 2;
    final mid2 = (0.8 + end) / 2;
    return [0.55, mid1, mid2, end];
  }

  ({String label, Color color, Color bgColor}) _categoryStatusBadge(
    List<BiomarkerResult> results,
  ) {
    final hasCritical = results.any((r) => r.flag == BiomarkerFlag.critical);
    final hasHighLow = results.any(
      (r) => r.flag == BiomarkerFlag.high || r.flag == BiomarkerFlag.low,
    );
    final hasBorderline = results.any(
      (r) => r.flag == BiomarkerFlag.borderline,
    );
    final allNormal = results.every(
      (r) => r.flag == BiomarkerFlag.normal || r.flag == BiomarkerFlag.unknown,
    );

    if (hasCritical) {
      return (
        label: 'Critical',
        color: AppColors.error,
        bgColor: AppColors.errorContainer.withValues(alpha: 0.5),
      );
    }
    if (hasHighLow) {
      return (
        label: 'Declined',
        color: AppColors.error,
        bgColor: AppColors.errorContainer.withValues(alpha: 0.3),
      );
    }
    if (hasBorderline) {
      return (
        label: 'Borderline',
        color: AppColors.secondary,
        bgColor: AppColors.secondary.withValues(alpha: 0.1),
      );
    }
    if (allNormal) {
      return (
        label: 'Stable',
        color: AppColors.tertiary,
        bgColor: AppColors.tertiaryContainer.withValues(alpha: 0.2),
      );
    }
    return (
      label: 'Optimizing',
      color: AppColors.secondary,
      bgColor: AppColors.secondary.withValues(alpha: 0.1),
    );
  }

  List<String> _buildInsights({
    required Map<String, BiomarkerResult> latestResults,
    required Map<String, List<BiomarkerResult>> allHistories,
    required int outOfRangeCount,
    required int normalCount,
  }) {
    final insights = <String>[];
    if (outOfRangeCount == 0 && normalCount > 0) {
      insights.add('All biomarkers within normal range ✓');
    } else if (outOfRangeCount > 0) {
      insights.add(
        '$outOfRangeCount value${outOfRangeCount == 1 ? '' : 's'} need${outOfRangeCount == 1 ? 's' : ''} attention',
      );
    }
    final trendingDown = <String>[];
    final trendingUp = <String>[];
    for (final entry in allHistories.entries) {
      if (entry.value.length < 2) continue;
      final latest = entry.value.first;
      final prev = entry.value[1];
      if (latest.value == null || prev.value == null) continue;
      final diff = latest.value! - prev.value!;
      if (diff.abs() < 0.01) continue;
      if (diff > 0) {
        trendingUp.add(latest.displayName);
      } else {
        trendingDown.add(latest.displayName);
      }
    }
    if (trendingDown.isNotEmpty) {
      final names = trendingDown.take(2).join(', ');
      final suffix = trendingDown.length > 2
          ? ' and ${trendingDown.length - 2} more'
          : '';
      insights.add('$names trending down ↘$suffix');
    }
    if (trendingUp.isNotEmpty) {
      final names = trendingUp.take(2).join(', ');
      final suffix = trendingUp.length > 2
          ? ' and ${trendingUp.length - 2} more'
          : '';
      insights.add('$names trending up ↗$suffix');
    }
    return insights.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final latestResults = objectbox.getLatestResults();
    final categories = biomarkerDictionary.categories;

    int normalCount = 0;
    int criticalCount = 0;
    final outOfRangeResults = <BiomarkerResult>[];

    for (final r in latestResults.values) {
      switch (r.flag) {
        case BiomarkerFlag.normal:
          normalCount++;
        case BiomarkerFlag.borderline:
          outOfRangeResults.add(r);
        case BiomarkerFlag.low:
          outOfRangeResults.add(r);
        case BiomarkerFlag.high:
          outOfRangeResults.add(r);
        case BiomarkerFlag.critical:
          criticalCount++;
          outOfRangeResults.add(r);
        case BiomarkerFlag.unknown:
          break;
      }
    }

    outOfRangeResults.sort((a, b) {
      if (a.flag == BiomarkerFlag.critical && b.flag != BiomarkerFlag.critical)
        return -1;
      if (b.flag == BiomarkerFlag.critical && a.flag != BiomarkerFlag.critical)
        return 1;
      return 0;
    });

    final allHistories = objectbox.getHistoryForBiomarkers(
      latestResults.keys.toSet(),
    );
    final reports = objectbox.getAllReports();
    final lastReport = reports.isNotEmpty ? reports.first : null;
    final abnormalCount = outOfRangeResults.length;
    final insights = _buildInsights(
      latestResults: latestResults,
      allHistories: allHistories,
      outOfRangeCount: abnormalCount,
      normalCount: normalCount,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: latestResults.isEmpty
          ? _buildEmpty(context)
          : CustomScrollView(
              slivers: [
                _buildAppBar(context),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KoshikaSpacing.screenHorizontal,
                      KoshikaSpacing.screenVertical,
                      KoshikaSpacing.screenHorizontal,
                      KoshikaSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Hero Card ────────────────────────────────────
                        _HeroCard(
                          totalTracked: latestResults.length,
                          abnormalCount: abnormalCount,
                          criticalCount: criticalCount,
                          lastReport: lastReport,
                        ),
                        const SizedBox(height: KoshikaSpacing.xl),

                        // ── Attention Needed ─────────────────────────────
                        if (outOfRangeResults.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Attention Needed',
                            action: outOfRangeResults.length > 3
                                ? TextButton(
                                    onPressed: () {},
                                    child: Text(
                                      'View All',
                                      style: KoshikaTypography.metricLabel
                                          .copyWith(color: AppColors.secondary),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: KoshikaSpacing.md),
                          ...outOfRangeResults
                              .take(3)
                              .map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _AttentionCard(
                                    result: r,
                                    onTap: () => Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                BiomarkerDetailScreen(
                                                  biomarkerKey: r.biomarkerKey,
                                                ),
                                          ),
                                        )
                                        .then((_) => setState(() {})),
                                  ),
                                ),
                              ),
                          const SizedBox(height: KoshikaSpacing.xl),
                        ],

                        // ── Category Trends ──────────────────────────────
                        _SectionHeader(title: 'Core Category Trends'),
                        const SizedBox(height: KoshikaSpacing.md),
                        ...categories.map((cat) {
                          final catResults = latestResults.values
                              .where((r) => r.category == cat)
                              .toList();
                          if (catResults.isEmpty)
                            return const SizedBox.shrink();
                          final barHeights = _categoryBarHeights(
                            catResults,
                            allHistories,
                          );
                          final badge = _categoryStatusBadge(catResults);
                          final icon = _categoryIcons[cat] ?? Icons.science;
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: KoshikaSpacing.md,
                            ),
                            child: _CategoryTrendCard(
                              category: cat,
                              icon: icon,
                              results: catResults,
                              barHeights: barHeights,
                              badgeLabel: badge.label,
                              badgeColor: badge.color,
                              badgeBgColor: badge.bgColor,
                              onTap: (r) => Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => BiomarkerDetailScreen(
                                        biomarkerKey: r.biomarkerKey,
                                      ),
                                    ),
                                  )
                                  .then((_) => setState(() {})),
                            ),
                          );
                        }),

                        // ── Clinical Insights ────────────────────────────
                        if (insights.isNotEmpty) ...[
                          const SizedBox(height: KoshikaSpacing.md),
                          _InsightsCard(insights: insights),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(KoshikaSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.biotech_outlined,
                  size: 60,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: KoshikaSpacing.xl),
              Text(
                'No lab reports yet',
                style: KoshikaTypography.sectionHeader,
              ),
              const SizedBox(height: KoshikaSpacing.sm),
              Text(
                'Import a lab report PDF from the Reports tab to get started.',
                style: KoshikaTypography.cardSubtitle.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: KoshikaSpacing.lg,
      title: Text(
        'Koshika',
        style: KoshikaTypography.sectionHeader.copyWith(
          color: AppColors.primary,
          fontSize: 20,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hero Card
// ═══════════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final int totalTracked;
  final int abnormalCount;
  final int criticalCount;
  final LabReport? lastReport;

  const _HeroCard({
    required this.totalTracked,
    required this.abnormalCount,
    required this.criticalCount,
    this.lastReport,
  });

  String get _statusTitle {
    if (criticalCount > 0) return 'Under Review';
    if (abnormalCount > 3) return 'Needs Attention';
    if (abnormalCount > 0) return 'Minor Variances';
    return 'Healthy Standing';
  }

  String get _statusDescription {
    if (abnormalCount == 0) {
      return 'Your metabolic profile looks good. All tracked values are within normal reference ranges.';
    }
    final plural = abnormalCount == 1 ? 'variance' : 'variances';
    return 'We detected $abnormalCount $plural that may require your attention. Review the details below.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: KoshikaDecorations.heroCard,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Decorative circle blur
          Positioned(
            right: -40,
            bottom: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KoshikaSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label
                Text(
                  'CLINICAL STATUS',
                  style: KoshikaTypography.metricLabel.copyWith(
                    color: AppColors.onPrimaryContainer.withValues(alpha: 0.8),
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: KoshikaSpacing.xs),
                // Status title
                Text(
                  _statusTitle,
                  style: KoshikaTypography.sectionHeader.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: KoshikaSpacing.sm),
                // Description
                Text(
                  _statusDescription,
                  style: TextStyle(
                    color: AppColors.onPrimaryContainer.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: KoshikaSpacing.xl),
                // Stats row
                Row(
                  children: [
                    _StatItem(
                      value: '$totalTracked',
                      label: 'TRACKED',
                      valueColor: Colors.white,
                    ),
                    const SizedBox(width: KoshikaSpacing.xxl),
                    _StatItem(
                      value: '$abnormalCount',
                      label: 'FLAGGED',
                      valueColor: abnormalCount > 0
                          ? const Color(0xFFFFB4AB)
                          : Colors.white,
                    ),
                    if (lastReport != null) ...[
                      const SizedBox(width: KoshikaSpacing.xxl),
                      _StatItem(
                        value: DateFormat(
                          'MMM d',
                        ).format(lastReport!.reportDate),
                        label: 'LAST REPORT',
                        valueColor: AppColors.onPrimaryContainer,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _StatItem({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: KoshikaTypography.heroMetric.copyWith(
            color: valueColor,
            fontSize: 36,
          ),
        ),
        Text(
          label,
          style: KoshikaTypography.metricLabel.copyWith(
            color: AppColors.onPrimaryContainer.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Attention Card
// ═══════════════════════════════════════════════════════════════════════════

class _AttentionCard extends StatelessWidget {
  final BiomarkerResult result;
  final VoidCallback onTap;

  const _AttentionCard({required this.result, required this.onTap});

  Color get _bgColor {
    switch (result.flag) {
      case BiomarkerFlag.critical:
        return AppColors.errorContainer.withValues(alpha: 0.5);
      case BiomarkerFlag.high:
      case BiomarkerFlag.low:
        return AppColors.errorContainer.withValues(alpha: 0.3);
      case BiomarkerFlag.borderline:
        return AppColors.surfaceContainerHigh.withValues(alpha: 0.6);
      default:
        return AppColors.surfaceContainerLow;
    }
  }

  Color get _iconBgColor {
    switch (result.flag) {
      case BiomarkerFlag.critical:
      case BiomarkerFlag.high:
      case BiomarkerFlag.low:
        return AppColors.errorContainer;
      default:
        return AppColors.surfaceContainerHigh;
    }
  }

  Color get _iconColor {
    switch (result.flag) {
      case BiomarkerFlag.critical:
      case BiomarkerFlag.high:
      case BiomarkerFlag.low:
        return AppColors.error;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  IconData get _icon {
    switch (result.flag) {
      case BiomarkerFlag.critical:
        return Icons.warning_rounded;
      case BiomarkerFlag.high:
        return Icons.trending_up;
      case BiomarkerFlag.low:
        return Icons.trending_down;
      default:
        return Icons.info_outline;
    }
  }

  String get _flagLabel {
    switch (result.flag) {
      case BiomarkerFlag.critical:
        return 'Critical';
      case BiomarkerFlag.high:
        return 'High';
      case BiomarkerFlag.low:
        return 'Low';
      case BiomarkerFlag.borderline:
        return 'Borderline';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _bgColor,
          borderRadius: KoshikaRadius.xxl,
        ),
        padding: const EdgeInsets.all(KoshikaSpacing.base),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _iconBgColor,
                borderRadius: KoshikaRadius.lg,
              ),
              child: Icon(_icon, color: _iconColor, size: 20),
            ),
            const SizedBox(width: KoshikaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.formattedValue} ${result.unit ?? ''} · Ref: ${result.formattedRefRange}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KoshikaSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest.withValues(alpha: 0.5),
                borderRadius: KoshikaRadius.pill,
              ),
              child: Text(
                _flagLabel.toUpperCase(),
                style: KoshikaTypography.metricLabel.copyWith(
                  fontSize: 10,
                  color: _iconColor,
                ),
              ),
            ),
            const SizedBox(width: KoshikaSpacing.xs),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Category Trend Card
// ═══════════════════════════════════════════════════════════════════════════

class _CategoryTrendCard extends StatelessWidget {
  final String category;
  final IconData icon;
  final List<BiomarkerResult> results;
  final List<double> barHeights;
  final String badgeLabel;
  final Color badgeColor;
  final Color badgeBgColor;
  final void Function(BiomarkerResult) onTap;

  const _CategoryTrendCard({
    required this.category,
    required this.icon,
    required this.results,
    required this.barHeights,
    required this.badgeLabel,
    required this.badgeColor,
    required this.badgeBgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final biomarkerNames = results.map((r) => r.displayName).take(3).join(', ');
    final catColor = AppColors.categoryColor(category);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: KoshikaRadius.xxl,
      ),
      padding: KoshikaSpacing.cardPaddingAsymmetric,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(KoshikaSpacing.sm),
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.1),
                  borderRadius: KoshikaRadius.lg,
                ),
                child: Icon(icon, color: catColor, size: 20),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  borderRadius: KoshikaRadius.md,
                ),
                child: Text(
                  badgeLabel.toUpperCase(),
                  style: KoshikaTypography.metricLabel.copyWith(
                    fontSize: 9,
                    color: badgeColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KoshikaSpacing.md),
          Text(
            category,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            biomarkerNames,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KoshikaSpacing.base),
          // Mini bar chart
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: barHeights.map((h) {
                final isLatest =
                    barHeights.last == h &&
                    barHeights.indexOf(h) == barHeights.length - 1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FractionallySizedBox(
                      heightFactor: h,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isLatest
                              ? catColor
                              : AppColors.outlineVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: KoshikaSpacing.md),
          // Biomarker rows
          ...results.map(
            (r) => InkWell(
              onTap: () => onTap(r),
              borderRadius: KoshikaRadius.md,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.displayName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${r.formattedValue} ${r.unit ?? ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(width: KoshikaSpacing.sm),
                    _FlagDot(flag: r.flag),
                    const SizedBox(width: KoshikaSpacing.xs),
                    const Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Flag dot indicator
// ═══════════════════════════════════════════════════════════════════════════

class _FlagDot extends StatelessWidget {
  final BiomarkerFlag flag;

  const _FlagDot({required this.flag});

  Color get _color {
    switch (flag) {
      case BiomarkerFlag.normal:
        return AppColors.success;
      case BiomarkerFlag.borderline:
        return AppColors.warning;
      case BiomarkerFlag.low:
      case BiomarkerFlag.high:
        return AppColors.error;
      case BiomarkerFlag.critical:
        return AppColors.error;
      case BiomarkerFlag.unknown:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Insights Card
// ═══════════════════════════════════════════════════════════════════════════

class _InsightsCard extends StatelessWidget {
  final List<String> insights;

  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: KoshikaDecorations.insightCard,
      padding: KoshikaSpacing.cardPaddingAsymmetric,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clinical Insights',
            style: KoshikaTypography.sectionHeader.copyWith(
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: KoshikaSpacing.md),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: KoshikaSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    decoration: const BoxDecoration(
                      color: AppColors.onTertiaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      insight,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.onTertiaryContainer,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: KoshikaTypography.sectionHeader.copyWith(fontSize: 18),
        ),
        if (action != null) ...[const Spacer(), action!],
      ],
    );
  }
}
