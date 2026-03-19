import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/fhir_export_service.dart';

/// Settings screen with AI model management, data controls, and about section.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StreamSubscription<ModelInfo> _modelSub;
  late ModelInfo _modelInfo;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _modelInfo = gemmaService.currentModelInfo;
    _modelSub = gemmaService.modelStatusStream.listen((info) {
      if (mounted) setState(() => _modelInfo = info);
    });
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '0.1.0');
    }
  }

  @override
  void dispose() {
    _modelSub.cancel();
    super.dispose();
  }

  // ─── Data Actions ───────────────────────────────────────────────────

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
          size: 40,
        ),
        title: const Text('Delete All Data?'),
        content: const Text(
          'This will permanently delete all imported reports and biomarker '
          'results. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final reports = objectbox.getAllReports();
      for (final report in reports) {
        objectbox.deleteReport(report.id);
        try {
          final file = File(report.pdfPath);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All data deleted')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete data: $e')));
      }
    }
  }

  Future<void> _exportAllFhir() async {
    final reports = objectbox.getAllReports();
    if (reports.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No data to export')));
      }
      return;
    }

    try {
      final patient = objectbox.getOrCreateDefaultPatient();
      final fhirService = FhirExportService();
      final resultsByReport = <int, List<BiomarkerResult>>{};
      for (final r in reports) {
        resultsByReport[r.id] = objectbox.getResultsForReport(r.id);
      }

      final jsonStr = fhirService.exportAll(
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

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = objectbox.getAllReports();
    final biomarkerCount = objectbox.getLatestResults().length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── AI Model Section ──
          _SectionHeader(title: 'AI Model', icon: Icons.smart_toy_outlined),
          _ModelStatusTile(
            modelInfo: _modelInfo,
            onDownload: () => gemmaService.downloadModel(),
            onLoad: () => gemmaService.loadModel(),
            onUnload: () => gemmaService.unloadModel(),
          ),

          const Divider(height: 1),

          // ── Data Section ──
          _SectionHeader(
            title: 'Data Management',
            icon: Icons.storage_outlined,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Reports imported'),
            trailing: Text(
              '${reports.length}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.biotech_outlined),
            title: const Text('Biomarkers tracked'),
            trailing: Text(
              '$biomarkerCount',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.ios_share, color: theme.colorScheme.primary),
            title: const Text('Export All Data (FHIR R4)'),
            subtitle: const Text('Share as interoperable health bundle'),
            onTap: _exportAllFhir,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
            title: Text(
              'Delete All Data',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: const Text('Remove all reports and biomarkers'),
            onTap: _deleteAllData,
          ),

          const Divider(height: 1),

          // ── About Section ──
          _SectionHeader(title: 'About', icon: Icons.info_outline),
          ListTile(
            leading: const Icon(Icons.local_hospital),
            title: const Text('Koshika — कोशिका'),
            subtitle: const Text(
              'Offline-first health data tracker with on-device AI',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Version'),
            trailing: Text(
              _appVersion.isEmpty ? '...' : _appVersion,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: const Text('github.com/priyavratuniyal/koshika'),
          ),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('License'),
            trailing: Text('Apache 2.0', style: theme.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Built for FOSS Hack 2026 🇮🇳',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Model Status Tile
// ═══════════════════════════════════════════════════════════════════════

class _ModelStatusTile extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  const _ModelStatusTile({
    required this.modelInfo,
    required this.onDownload,
    required this.onLoad,
    required this.onUnload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon, color: _statusColor(theme), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      modelInfo.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(theme).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _statusColor(theme),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Size: ${modelInfo.formattedSize}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (modelInfo.status == ModelStatus.downloading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: modelInfo.downloadProgress / 100,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                Text(
                  '${modelInfo.downloadProgress}%',
                  style: theme.textTheme.labelSmall,
                ),
              ],
              if (modelInfo.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  modelInfo.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (modelInfo.canDownload)
                    FilledButton.icon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                    ),
                  if (modelInfo.canLoad)
                    FilledButton.tonal(
                      onPressed: onLoad,
                      child: const Text('Load Model'),
                    ),
                  if (modelInfo.isUsable)
                    OutlinedButton(
                      onPressed: onUnload,
                      child: const Text('Unload'),
                    ),
                  if (modelInfo.status == ModelStatus.downloading ||
                      modelInfo.status == ModelStatus.loading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _statusIcon {
    switch (modelInfo.status) {
      case ModelStatus.notDownloaded:
        return Icons.cloud_download_outlined;
      case ModelStatus.downloading:
        return Icons.downloading;
      case ModelStatus.ready:
        return Icons.check_circle_outline;
      case ModelStatus.loading:
        return Icons.hourglass_top;
      case ModelStatus.loaded:
        return Icons.check_circle;
      case ModelStatus.error:
        return Icons.error_outline;
    }
  }

  String get _statusLabel {
    switch (modelInfo.status) {
      case ModelStatus.notDownloaded:
        return 'Not Downloaded';
      case ModelStatus.downloading:
        return 'Downloading...';
      case ModelStatus.ready:
        return 'Ready';
      case ModelStatus.loading:
        return 'Loading...';
      case ModelStatus.loaded:
        return 'Active';
      case ModelStatus.error:
        return 'Error';
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (modelInfo.status) {
      case ModelStatus.notDownloaded:
        return theme.colorScheme.outline;
      case ModelStatus.downloading:
      case ModelStatus.loading:
        return Colors.amber.shade700;
      case ModelStatus.ready:
        return Colors.blue;
      case ModelStatus.loaded:
        return Colors.green;
      case ModelStatus.error:
        return theme.colorScheme.error;
    }
  }
}
