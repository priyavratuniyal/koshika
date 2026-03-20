import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/extraction_diagnostics.dart';
import '../services/fhir_export_service.dart';
import '../services/lab_report_parser.dart';
import '../services/pdf_import_service.dart';
import '../services/pdf_text_extractor.dart';
import 'report_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static final _fhirExportService = FhirExportService();
  bool _isImporting = false;

  Future<void> _exportAllFhir() async {
    final reports = objectbox.getAllReports();
    if (reports.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    try {
      final patient = objectbox.getOrCreateDefaultPatient();
      final resultsByReport = <int, List<BiomarkerResult>>{};
      for (final r in reports) {
        resultsByReport[r.id] = objectbox.getResultsForReport(r.id);
      }

      final jsonStr = _fhirExportService.exportAll(
        patient: patient,
        reports: reports,
        resultsByReport: resultsByReport,
      );

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(
        p.join(tempDir.path, 'koshika_health_data_$timestamp.fhir.json'),
      );
      await file.writeAsString(jsonStr);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'My Koshika Health Data (FHIR R4)');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importPdf() async {
    if (_isImporting) return;

    File? destFile;
    final progressMessage = ValueNotifier<String>('Preparing import...');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) return;

      final String sourcePath = result.files.single.path!;

      setState(() {
        _isImporting = true;
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: progressMessage,
              builder: (context, message, _) => Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 24),
                  Expanded(child: Text(message)),
                ],
              ),
            ),
          ),
        );
      }

      final File sourceFile = File(sourcePath);
      final Directory appDocsDir = await getApplicationDocumentsDirectory();
      final String destFileName =
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}';
      final String destPath = p.join(appDocsDir.path, destFileName);
      destFile = File(destPath);

      await sourceFile.copy(destPath);

      final extractor = PdfTextExtractorService();
      final parser = LabReportParser();
      final service = PdfImportService(
        extractor,
        parser,
        biomarkerDictionary,
        objectbox,
      );

      final importResult = await service.importPdf(
        destPath,
        onProgress: (progress) {
          progressMessage.value = progress.message;
        },
      );

      setState(() {
        _isImporting = false;
      });

      if (mounted) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      if (importResult.success) {
        // Index new results in VectorStore for semantic search
        if (importResult.report != null && vectorStoreService.isReady) {
          final newResults = objectbox.getResultsForReport(
            importResult.report!.id,
          );
          vectorStoreService.indexResults(newResults);
        }

        final successMessage = importResult.warnings.isEmpty
            ? 'Imported ${importResult.successfulMatches} biomarkers'
            : 'Imported ${importResult.successfulMatches} biomarkers with warnings';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            duration: const Duration(seconds: 3),
          ),
        );

        if (importResult.warnings.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                importResult.extractionMethod == ExtractionMethod.digital
                    ? 'Import Warnings'
                    : 'OCR Import Warnings',
              ),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Text(importResult.warnings.join('\n\n')),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }

        if (!mounted) return;

        if (importResult.report != null) {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) =>
                      ReportDetailScreen(reportId: importResult.report!.id),
                ),
              )
              .then((_) => setState(() {}));
        } else {
          setState(() {});
        }
      } else {
        if (await destFile.exists()) {
          await destFile.delete();
        }
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_failureTitle(importResult.failureReason)),
            content: Text(_failureMessage(importResult)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (destFile != null && await destFile.exists()) {
        await destFile.delete();
      }
      setState(() {
        _isImporting = false;
      });
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      progressMessage.dispose();
    }
  }

  String _failureTitle(ImportFailureReason? reason) {
    switch (reason) {
      case ImportFailureReason.encryptedPdf:
        return 'Encrypted PDF';
      case ImportFailureReason.invalidPdf:
        return 'Invalid PDF';
      case ImportFailureReason.ocrFailed:
        return 'OCR Failed';
      case ImportFailureReason.unsupportedFormat:
        return 'Unsupported Report';
      case ImportFailureReason.timeout:
        return 'Import Timed Out';
      default:
        return 'Import Failed';
    }
  }

  String _failureMessage(ImportResult importResult) {
    final message = importResult.errorMessage ?? 'Unknown error';
    if (importResult.warnings.isEmpty) return message;
    return '$message\n\nWarnings:\n${importResult.warnings.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = objectbox.getAllReports();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (reports.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export FHIR Bundle',
              onPressed: _exportAllFhir,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _importPdf,
        icon: _isImporting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_isImporting ? 'Importing...' : 'Import PDF'),
      ),
      body: reports.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_outlined,
                      size: 80,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No reports imported',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the button below to import your first lab report PDF.',
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return Dismissible(
                  key: Key('report-${report.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Report?'),
                            content: Text(
                              'Delete "${report.labName ?? report.originalFileName ?? "Lab Report"}" and all its biomarker results?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) {
                    objectbox.deleteReport(report.id);
                    try {
                      final file = File(report.pdfPath);
                      if (file.existsSync()) {
                        file.deleteSync();
                      }
                    } catch (_) {}
                    setState(() {});
                  },
                  child: Card(
                    child: ListTile(
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    ReportDetailScreen(reportId: report.id),
                              ),
                            )
                            .then((_) => setState(() {}));
                      },
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.description,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        report.labName ??
                            report.originalFileName ??
                            'Lab Report',
                      ),
                      subtitle: Text(
                        '${report.reportDate.day}/${report.reportDate.month}/${report.reportDate.year}'
                        ' • ${report.extractedCount} biomarkers',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
