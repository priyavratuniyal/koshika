import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

class DashboardSummaryCard extends StatelessWidget {
  final int totalTracked;
  final int normalCount;
  final int borderlineCount;
  final int lowCount;
  final int highCount;
  final int criticalCount;
  final int unknownCount;
  final LabReport? lastReport;
  final List<String> insights;

  const DashboardSummaryCard({
    super.key,
    required this.totalTracked,
    required this.normalCount,
    this.borderlineCount = 0,
    required this.lowCount,
    required this.highCount,
    required this.criticalCount,
    this.unknownCount = 0,
    this.lastReport,
    this.insights = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: KoshikaDecorations.heroCard,
      clipBehavior: Clip.antiAlias,
      padding: KoshikaSpacing.cardPaddingAsymmetric,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety,
                color: AppColors.onPrimaryContainer,
              ),
              const SizedBox(width: KoshikaSpacing.sm),
              Text(
                'Health Overview',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: KoshikaSpacing.base),
          Text(
            '$totalTracked Biomarkers Tracked',
            style: KoshikaTypography.sectionHeader.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: KoshikaSpacing.base),
          Wrap(
            spacing: KoshikaSpacing.sm,
            runSpacing: KoshikaSpacing.sm,
            children: [
              if (normalCount > 0)
                _buildStatChip('Normal', normalCount, AppColors.success),
              if (borderlineCount > 0)
                _buildStatChip(
                  'Borderline',
                  borderlineCount,
                  AppColors.warning,
                ),
              if (lowCount > 0)
                _buildStatChip('Low', lowCount, AppColors.error),
              if (highCount > 0)
                _buildStatChip('High', highCount, AppColors.error),
              if (criticalCount > 0)
                _buildStatChip('Critical', criticalCount, AppColors.error),
              if (unknownCount > 0)
                _buildStatChip('Unknown', unknownCount, AppColors.textMuted),
            ],
          ),
          // ── Synthesized Insights ──
          if (insights.isNotEmpty) ...[
            const SizedBox(height: KoshikaSpacing.base),
            ...insights.map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: TextStyle(
                        color: AppColors.onTertiaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        insight,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onPrimaryContainer.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (lastReport != null) ...[
            const SizedBox(height: KoshikaSpacing.base),
            Row(
              children: [
                Icon(
                  Icons.update,
                  size: 16,
                  color: AppColors.onPrimaryContainer.withValues(alpha: 0.6),
                ),
                const SizedBox(width: KoshikaSpacing.xs),
                Expanded(
                  child: Text(
                    'Last Import: ${DateFormat('MMM d').format(lastReport!.reportDate)} • ${lastReport!.labName ?? 'Unknown Lab'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onPrimaryContainer.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: KoshikaRadius.md,
        // No border — no-line rule
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: KoshikaTypography.statusText.copyWith(color: color),
          ),
          const SizedBox(width: KoshikaSpacing.xs),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
