import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../widgets/dashboard_summary_card.dart';
import '../widgets/flag_badge.dart';
import 'biomarker_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ({Color color, IconData icon}) _getTrend(List<BiomarkerResult> history) {
    if (history.length < 2) {
      return (color: Colors.grey, icon: Icons.arrow_forward);
    }
    final latest = history[0];
    final prev = history[1];
    if (latest.value == null || prev.value == null) {
      return (color: Colors.grey, icon: Icons.arrow_forward);
    }

    final valL = latest.value!;
    final valP = prev.value!;

    if (valL == valP) {
      return (color: Colors.grey, icon: Icons.arrow_forward);
    }

    final icon = valL > valP ? Icons.arrow_upward : Icons.arrow_downward;
    Color color = Colors.grey;

    // Only compute midpoint-based coloring when both bounds exist.
    if (latest.refLow != null && latest.refHigh != null) {
      final mid = (latest.refLow! + latest.refHigh!) / 2;
      final distL = (valL - mid).abs();
      final distP = (valP - mid).abs();
      if (distL < distP) {
        color = Colors.green;
      } else if (distL > distP) {
        color = Colors.red;
      }
    }

    return (color: color, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestResults = objectbox.getLatestResults();
    final categories = biomarkerDictionary.categories;

    int normalCount = 0;
    int lowCount = 0;
    int highCount = 0;
    int criticalCount = 0;
    int unknownCount = 0;
    int borderlineCount = 0;
    final outOfRangeResults = <BiomarkerResult>[];

    for (final r in latestResults.values) {
      switch (r.flag) {
        case BiomarkerFlag.normal:
          normalCount++;
        case BiomarkerFlag.borderline:
          borderlineCount++;
          outOfRangeResults.add(r);
        case BiomarkerFlag.low:
          lowCount++;
          outOfRangeResults.add(r);
        case BiomarkerFlag.high:
          highCount++;
          outOfRangeResults.add(r);
        case BiomarkerFlag.critical:
          criticalCount++;
          outOfRangeResults.add(r);
        case BiomarkerFlag.unknown:
          unknownCount++;
      }
    }

    final trendMap = <String, ({Color color, IconData icon})>{};
    final allHistories = objectbox.getHistoryForBiomarkers(
      latestResults.keys.toSet(),
    );
    for (final key in latestResults.keys) {
      trendMap[key] = _getTrend(allHistories[key] ?? []);
    }

    outOfRangeResults.sort((a, b) {
      if (a.flag == BiomarkerFlag.critical &&
          b.flag != BiomarkerFlag.critical) {
        return -1;
      }
      if (b.flag == BiomarkerFlag.critical &&
          a.flag != BiomarkerFlag.critical) {
        return 1;
      }
      return 0;
    });

    final reports = objectbox.getAllReports();
    final lastReport = reports.isNotEmpty ? reports.first : null;

    // ── Generate synthesized textual insights ──
    final insights = _buildInsights(
      latestResults: latestResults,
      allHistories: allHistories,
      outOfRangeCount: outOfRangeResults.length,
      normalCount: normalCount,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Koshika')),
      body: latestResults.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.biotech_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No lab reports yet',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import a lab report PDF from the Reports tab to get started.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DashboardSummaryCard(
                  totalTracked: latestResults.length,
                  normalCount: normalCount,
                  borderlineCount: borderlineCount,
                  lowCount: lowCount,
                  highCount: highCount,
                  criticalCount: criticalCount,
                  unknownCount: unknownCount,
                  lastReport: lastReport,
                  insights: insights,
                ),
                if (outOfRangeResults.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.3,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Attention Needed',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...outOfRangeResults.map(
                            (r) => ListTile(
                              onTap: () {
                                Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (_) => BiomarkerDetailScreen(
                                          biomarkerKey: r.biomarkerKey,
                                        ),
                                      ),
                                    )
                                    .then((_) => setState(() {}));
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                r.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${r.formattedValue} ${r.unit ?? ""}'),
                                  const SizedBox(width: 8),
                                  FlagBadge(flag: r.flag),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...categories.map((cat) {
                  final catResults = latestResults.values
                      .where((r) => r.category == cat)
                      .toList();
                  if (catResults.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const Divider(),
                            ...catResults.map((r) {
                              final trend =
                                  trendMap[r.biomarkerKey] ??
                                  (
                                    color: Colors.grey,
                                    icon: Icons.arrow_forward,
                                  );
                              Color bgColor = Colors.transparent;
                              switch (r.flag) {
                                case BiomarkerFlag.low:
                                  bgColor = Colors.orange.withValues(
                                    alpha: 0.05,
                                  );
                                case BiomarkerFlag.borderline:
                                  bgColor = Colors.amber.withValues(
                                    alpha: 0.08,
                                  );
                                case BiomarkerFlag.high:
                                  bgColor = Colors.red.withValues(alpha: 0.05);
                                case BiomarkerFlag.critical:
                                  bgColor = Colors.red.withValues(alpha: 0.1);
                                case BiomarkerFlag.normal:
                                  bgColor = Colors.green.withValues(
                                    alpha: 0.05,
                                  );
                                case BiomarkerFlag.unknown:
                                  break;
                              }

                              return InkWell(
                                onTap: () {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (_) => BiomarkerDetailScreen(
                                            biomarkerKey: r.biomarkerKey,
                                          ),
                                        ),
                                      )
                                      .then((_) => setState(() {}));
                                },
                                child: Container(
                                  color: bgColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(r.displayName)),
                                      Text(
                                        '${r.formattedValue} ${r.unit ?? ""}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FlagBadge(flag: r.flag),
                                      const SizedBox(width: 8),
                                      Icon(
                                        trend.icon,
                                        color: trend.color,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  /// Build human-readable insight sentences from trend and flag data.
  List<String> _buildInsights({
    required Map<String, BiomarkerResult> latestResults,
    required Map<String, List<BiomarkerResult>> allHistories,
    required int outOfRangeCount,
    required int normalCount,
  }) {
    final insights = <String>[];

    // Overall status
    if (outOfRangeCount == 0 && normalCount > 0) {
      insights.add('All biomarkers within normal range ✓');
    } else if (outOfRangeCount > 0) {
      insights.add(
        '$outOfRangeCount value${outOfRangeCount == 1 ? '' : 's'} '
        'need${outOfRangeCount == 1 ? 's' : ''} attention',
      );
    }

    // Find trending biomarkers (those with 2+ data points and a clear direction)
    final trendingDown = <String>[];
    final trendingUp = <String>[];

    for (final entry in allHistories.entries) {
      if (entry.value.length < 2) continue;
      final latest = entry.value.first;
      final prev = entry.value[1];
      if (latest.value == null || prev.value == null) continue;

      final diff = latest.value! - prev.value!;
      if (diff.abs() < 0.01) continue; // negligible change

      final name = latest.displayName;
      if (diff > 0) {
        trendingUp.add(name);
      } else {
        trendingDown.add(name);
      }
    }

    // Report up to 2 trending-down biomarkers (more concerning)
    if (trendingDown.isNotEmpty) {
      final names = trendingDown.take(2).join(', ');
      final suffix = trendingDown.length > 2
          ? ' and ${trendingDown.length - 2} more'
          : '';
      insights.add('$names trending down ↘$suffix');
    }

    // Report up to 2 trending-up biomarkers
    if (trendingUp.isNotEmpty) {
      final names = trendingUp.take(2).join(', ');
      final suffix = trendingUp.length > 2
          ? ' and ${trendingUp.length - 2} more'
          : '';
      insights.add('$names trending up ↗$suffix');
    }

    // Cap at 3 insights to keep the card compact
    return insights.take(3).toList();
  }
}
