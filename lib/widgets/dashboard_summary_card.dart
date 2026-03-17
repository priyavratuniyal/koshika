import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class DashboardSummaryCard extends StatelessWidget {
  final int totalTracked;
  final int normalCount;
  final int borderlineCount;
  final int lowCount;
  final int highCount;
  final int criticalCount;
  final int unknownCount;
  final LabReport? lastReport;

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Health Overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '$totalTracked Biomarkers Tracked',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (normalCount > 0)
                  _buildStatChip(context, 'Normal', normalCount, Colors.green),
                if (borderlineCount > 0)
                  _buildStatChip(
                    context,
                    'Borderline',
                    borderlineCount,
                    Colors.amber,
                  ),
                if (lowCount > 0)
                  _buildStatChip(context, 'Low', lowCount, Colors.orange),
                if (highCount > 0)
                  _buildStatChip(context, 'High', highCount, Colors.red),
                if (criticalCount > 0)
                  _buildStatChip(
                    context,
                    'Critical',
                    criticalCount,
                    Colors.red[900]!,
                  ),
                if (unknownCount > 0)
                  _buildStatChip(context, 'Unknown', unknownCount, Colors.grey),
              ],
            ),
            if (lastReport != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.update,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last Import: ${DateFormat('MMM d').format(lastReport!.reportDate)} • ${lastReport!.labName ?? 'Unknown Lab'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
