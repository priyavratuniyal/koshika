import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
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
              r.flag == BiomarkerFlag.critical ||
              r.flag == BiomarkerFlag.borderline,
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
                  final msg = _classifyExportError(e);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
              }
            },
          ),
        ],
      ),
      body: results.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(KoshikaSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: KoshikaSpacing.xl),
                    Text(
                      'No biomarkers extracted',
                      style: KoshikaTypography.sectionHeader.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: KoshikaSpacing.sm),
                    Text(
                      'We could not parse any structured data from this report. This may be an unsupported lab format.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(KoshikaSpacing.base),
              children: [
                Container(
                  decoration: KoshikaDecorations.card,
                  padding: KoshikaSpacing.cardPaddingAsymmetric,
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${results.length} Biomarkers extracted',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: KoshikaSpacing.xs),
                          Text(
                            outOfRangeCount > 0
                                ? '$outOfRangeCount out of range'
                                : 'All within range',
                            style: KoshikaTypography.statusText.copyWith(
                              color: outOfRangeCount > 0
                                  ? AppColors.error
                                  : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KoshikaSpacing.base),
                ...groupedResults.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: KoshikaSpacing.base),
                    child: Container(
                      decoration: KoshikaDecorations.card,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              KoshikaSpacing.base,
                              KoshikaSpacing.base,
                              KoshikaSpacing.base,
                              KoshikaSpacing.sm,
                            ),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: KoshikaTypography.metricLabel.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          ...entry.value.map(
                            (r) => ListTile(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BiomarkerDetailScreen(
                                    biomarkerKey: r.biomarkerKey,
                                  ),
                                ),
                              ),
                              title: Text(
                                r.displayName,
                                style: const TextStyle(
                                  color: AppColors.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                'Range: ${r.formattedRefRange}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${r.formattedValue} ',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    r.unit ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: KoshikaSpacing.sm),
                                  FlagBadge(flag: r.flag),
                                  const SizedBox(width: KoshikaSpacing.xs),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: AppColors.onSurfaceVariant,
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

  static String _classifyExportError(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('storage') ||
        msg.contains('space') ||
        msg.contains('permission')) {
      return 'Unable to save file. Check available storage and permissions.';
    }
    if (msg.contains('share') || msg.contains('activity')) {
      return 'Sharing is not available on this device.';
    }
    return 'Export failed. Please try again.';
  }
}
