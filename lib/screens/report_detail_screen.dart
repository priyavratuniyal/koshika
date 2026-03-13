import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';

class ReportDetailScreen extends StatelessWidget {
  final int reportId;

  const ReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Using a FutureBuilder simple pattern
    return FutureBuilder<List<BiomarkerResult>>(
      future: Future.value(objectbox.getResultsForReport(reportId)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final results = snapshot.data!;
        
        // Let's get the report object directly
        final report = objectbox.labReportBox.get(reportId);
        if (report == null) {
          return Scaffold(
             appBar: AppBar(title: const Text('Report Details')),
             body: const Center(child: Text('Report not found')),
          );
        }

        // Group by category
        final groupedResults = <String, List<BiomarkerResult>>{};
        for (final r in results) {
           final cat = r.category ?? 'Other';
           groupedResults.putIfAbsent(cat, () => []).add(r);
        }

        final outOfRangeCount = results.where((r) => r.flag == BiomarkerFlag.high || r.flag == BiomarkerFlag.low || r.flag == BiomarkerFlag.critical).length;

        return Scaffold(
          appBar: AppBar(
            title: Text(report.labName ?? report.originalFileName ?? 'Report Details'),
          ),
          body: results.isEmpty 
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No biomarkers extracted',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We could not parse any structured data from this report. This may be an unsupported lab format.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${results.length} Biomarkers extracted',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  outOfRangeCount > 0
                                      ? '$outOfRangeCount out of range'
                                      : 'All within range ✓',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: outOfRangeCount > 0
                                        ? theme.colorScheme.error
                                        : Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...groupedResults.entries.map((entry) {
                       return Padding(
                         padding: const EdgeInsets.only(bottom: 16),
                         child: Card(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                Padding(
                                   padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                   child: Text(
                                     entry.key,
                                     style: theme.textTheme.titleMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                     ),
                                   ),
                                ),
                                const Divider(height: 1),
                                ...entry.value.map((r) => ListTile(
                                   title: Text(r.displayName),
                                   subtitle: Text('Range: ${r.formattedRefRange}'),
                                   trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                         Text(
                                           '${r.formattedValue} ',
                                           style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                           ),
                                         ),
                                         Text(r.unit ?? ''),
                                         const SizedBox(width: 8),
                                         _buildFlagBadge(r.flag, theme),
                                      ],
                                   ),
                                )),
                             ],
                           ),
                         ),
                       );
                    }),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFlagBadge(BiomarkerFlag flag, ThemeData theme) {
     Color color;
     String text;
     
     switch (flag) {
        case BiomarkerFlag.normal:
           color = Colors.green;
           text = 'N';
           break;
        case BiomarkerFlag.low:
           color = Colors.orange;
           text = 'L';
           break;
        case BiomarkerFlag.high:
           color = Colors.red;
           text = 'H';
           break;
        case BiomarkerFlag.critical:
           color = Colors.red[900]!;
           text = 'C';
           break;
        case BiomarkerFlag.unknown:
           color = Colors.grey;
           text = '-';
           break;
     }

     return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
           color: color.withValues(alpha: 0.2),
           borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
           text,
           style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
           ),
        ),
     );
  }
}
