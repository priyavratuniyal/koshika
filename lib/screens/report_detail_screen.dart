import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/models.dart';
import 'biomarker_detail_screen.dart';
import '../widgets/flag_badge.dart';
import '../services/fhir_export_service.dart';

class ReportDetailScreen extends StatelessWidget {
  final int reportId;

  const ReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Let's get the report object directly
    final report = objectbox.labReportBox.get(reportId);
    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Details')),
        body: const Center(child: Text('Report not found')),
      );
    }

    final results = objectbox.getResultsForReport(reportId);

    // Group by category
    final groupedResults = <String, List<BiomarkerResult>>{};
    for (final r in results) {
      final cat = r.category ?? 'Other';
      groupedResults.putIfAbsent(cat, () => []).add(r);
    }

    final outOfRangeCount = results
        .where(
          (r) =>
              r.flag == BiomarkerFlag.high ||
              r.flag == BiomarkerFlag.low ||
              r.flag == BiomarkerFlag.critical,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          report.labName ?? report.originalFileName ?? 'Report Details',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export as FHIR',
            onPressed: () async {
              try {
                final patient = objectbox.getOrCreateDefaultPatient();
                final fhirService = FhirExportService();
                final jsonStr = fhirService.exportReport(
                  patient: patient,
                  report: report,
                  results: results,
                );

                final tempDir = await getTemporaryDirectory();
                final dateStr = DateTime.now()
                    .toIso8601String()
                    .split('T')
                    .first
                    .replaceAll('-', '');
                final labName = (report.labName ?? 'Lab').replaceAll(
                  RegExp(r'[^a-zA-Z0-9]'),
                  '_',
                );
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final file = File(
                  p.join(
                    tempDir.path,
                    'koshika_${labName}_${dateStr}_$timestamp.fhir.json',
                  ),
                );
                await file.writeAsString(jsonStr);

                await Share.shareXFiles([
                  XFile(file.path),
                ], text: '${report.labName ?? "Lab"} Report (FHIR R4)');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              }
            },
          ),
        ],
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
                          ...entry.value.map(
                            (r) => ListTile(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BiomarkerDetailScreen(
                                    biomarkerKey: r.biomarkerKey,
                                  ),
                                ),
                              ),
                              title: Text(r.displayName),
                              subtitle: Text('Range: ${r.formattedRefRange}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${r.formattedValue} ',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(r.unit ?? ''),
                                  const SizedBox(width: 8),
                                  FlagBadge(flag: r.flag),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
