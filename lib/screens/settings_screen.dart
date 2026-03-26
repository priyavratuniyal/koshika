import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
import '../models/models.dart';
import '../services/embedding_service.dart';
import '../services/fhir_export_service.dart';
import '../widgets/icon_container.dart';

/// Settings screen with AI model management, data controls, and about section.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StreamSubscription<ModelInfo> _modelSub;
  late StreamSubscription<ModelInfo> _embeddingSub;
  late ModelInfo _modelInfo;
  late ModelInfo _embeddingInfo;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _modelInfo = gemmaService.currentModelInfo;
    _embeddingInfo = embeddingService.currentModelInfo;
    _modelSub = gemmaService.modelStatusStream.listen((info) {
      if (mounted) setState(() => _modelInfo = info);
    });
    _embeddingSub = embeddingService.modelStatusStream.listen((info) {
      if (mounted) setState(() => _embeddingInfo = info);
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
    _embeddingSub.cancel();
    super.dispose();
  }

  // ─── Embedding Model ────────────────────────────────────────────────

  Future<void> _downloadEmbeddingModel() async {
    final token = await _getOrPromptHfToken();
    if (token == null || token.isEmpty) return;
    await embeddingService.downloadModel(hfToken: token);
  }

  Future<void> _downloadGemmaModel() async {
    final token = await _getOrPromptHfToken();
    if (token == null || token.isEmpty) return;
    await gemmaService.downloadModel(hfToken: token);
  }

  Future<String?> _getOrPromptHfToken() async {
    var token = await EmbeddingService.getHfToken();

    if (token == null || token.isEmpty) {
      if (!mounted) return null;
      token = await showDialog<String>(
        context: context,
        builder: (ctx) => _HfTokenDialog(),
      );
      if (token == null || token.isEmpty) return null;
      await EmbeddingService.saveHfToken(token);
    }

    return token;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete data. Please try again.'),
          ),
        );
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
        padding: const EdgeInsets.symmetric(horizontal: KoshikaSpacing.base),
        children: [
          // ── AI Model Section ──
          _SectionHeader(title: 'AI Models', icon: Icons.smart_toy_outlined),
          _ModelStatusTile(
            modelInfo: _modelInfo,
            onDownload: _downloadGemmaModel,
            onLoad: () => gemmaService.loadModel(),
            onUnload: () => gemmaService.unloadModel(),
          ),
          _EmbeddingModelTile(
            modelInfo: _embeddingInfo,
            onDownload: _downloadEmbeddingModel,
            onLoad: () => embeddingService.loadModel(),
            onUnload: () => embeddingService.unloadModel(),
          ),

          const SizedBox(height: KoshikaSpacing.sm),

          // ── Data Section ──
          _SectionHeader(
            title: 'Data Management',
            icon: Icons.storage_outlined,
          ),
          _SettingsRow(
            icon: Icons.description_outlined,
            iconColor: AppColors.primary,
            title: 'Reports imported',
            trailing: Text(
              '${reports.length}',
              style: KoshikaTypography.statusText.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.biotech_outlined,
            iconColor: AppColors.primary,
            title: 'Biomarkers tracked',
            trailing: Text(
              '$biomarkerCount',
              style: KoshikaTypography.statusText.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.ios_share,
            iconColor: AppColors.primary,
            title: 'Export All Data (FHIR R4)',
            subtitle: 'Share as interoperable health bundle',
            onTap: _exportAllFhir,
          ),
          _SettingsRow(
            icon: Icons.delete_forever,
            iconColor: AppColors.error,
            title: 'Delete All Data',
            titleColor: AppColors.error,
            subtitle: 'Remove all reports and biomarkers',
            onTap: _deleteAllData,
          ),

          const SizedBox(height: KoshikaSpacing.sm),

          // ── About Section ──
          _SectionHeader(title: 'About', icon: Icons.info_outline),
          _SettingsRow(
            icon: Icons.local_hospital,
            iconColor: AppColors.primary,
            title: 'Koshika',
            subtitle: 'Offline-first health data tracker with on-device AI',
          ),
          _SettingsRow(
            icon: Icons.tag,
            iconColor: AppColors.onSurfaceVariant,
            title: 'Version',
            trailing: Text(
              _appVersion.isEmpty ? '...' : _appVersion,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.code,
            iconColor: AppColors.onSurfaceVariant,
            title: 'Source Code',
            subtitle: 'github.com/priyavratuniyal/koshika',
          ),
          _SettingsRow(
            icon: Icons.balance,
            iconColor: AppColors.onSurfaceVariant,
            title: 'License',
            trailing: Text(
              'Apache 2.0',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KoshikaSpacing.xl),
            child: Text(
              'Built for FOSS Hack 2026',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        KoshikaSpacing.xl,
        0,
        KoshikaSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: KoshikaSpacing.sm),
          Text(
            title.toUpperCase(),
            style: KoshikaTypography.metricLabel.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Settings Row (replaces ListTile)
// ═══════════════════════════════════════════════════════════════════════

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: KoshikaRadius.lg,
        child: InkWell(
          onTap: onTap,
          borderRadius: KoshikaRadius.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KoshikaSpacing.base,
              vertical: KoshikaSpacing.md,
            ),
            child: Row(
              children: [
                IconContainer(icon: icon, color: iconColor),
                const SizedBox(width: KoshikaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: titleColor ?? AppColors.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
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
    final statusColor = _statusColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.sm),
      child: Container(
        decoration: KoshikaDecorations.card,
        padding: KoshikaSpacing.cardPaddingAsymmetric,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon, color: statusColor, size: 20),
                const SizedBox(width: KoshikaSpacing.sm),
                Expanded(
                  child: Text(
                    modelInfo.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoshikaSpacing.sm,
                    vertical: KoshikaSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: KoshikaRadius.md,
                  ),
                  child: Text(
                    _statusLabel,
                    style: KoshikaTypography.statusText.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'Size: ${modelInfo.formattedSize}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (modelInfo.status == ModelStatus.downloading) ...[
              const SizedBox(height: KoshikaSpacing.md),
              LinearProgressIndicator(
                value: modelInfo.downloadProgress / 100,
                borderRadius: KoshikaRadius.sm,
              ),
              const SizedBox(height: KoshikaSpacing.xs),
              Text(
                '${modelInfo.downloadProgress}%',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (modelInfo.errorMessage != null) ...[
              const SizedBox(height: KoshikaSpacing.sm),
              Text(
                modelInfo.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: KoshikaSpacing.md),
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
    );
  }

  IconData get _statusIcon => switch (modelInfo.status) {
    ModelStatus.notDownloaded => Icons.cloud_download_outlined,
    ModelStatus.downloading => Icons.downloading,
    ModelStatus.ready => Icons.check_circle_outline,
    ModelStatus.loading => Icons.hourglass_top,
    ModelStatus.loaded => Icons.check_circle,
    ModelStatus.error => Icons.error_outline,
  };

  String get _statusLabel => switch (modelInfo.status) {
    ModelStatus.notDownloaded => 'Not Downloaded',
    ModelStatus.downloading => 'Downloading...',
    ModelStatus.ready => 'Ready',
    ModelStatus.loading => 'Loading...',
    ModelStatus.loaded => 'Active',
    ModelStatus.error => 'Error',
  };

  Color get _statusColor => switch (modelInfo.status) {
    ModelStatus.notDownloaded => AppColors.onSurfaceVariant,
    ModelStatus.downloading || ModelStatus.loading => AppColors.statusBusy,
    ModelStatus.ready => AppColors.statusReady,
    ModelStatus.loaded => AppColors.statusActive,
    ModelStatus.error => AppColors.error,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Embedding Model Status Tile
// ═══════════════════════════════════════════════════════════════════════

class _EmbeddingModelTile extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  const _EmbeddingModelTile({
    required this.modelInfo,
    required this.onDownload,
    required this.onLoad,
    required this.onUnload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.sm),
      child: Container(
        decoration: KoshikaDecorations.card,
        padding: KoshikaSpacing.cardPaddingAsymmetric,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon, color: statusColor, size: 20),
                const SizedBox(width: KoshikaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modelInfo.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        'Enables semantic search for AI chat',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoshikaSpacing.sm,
                    vertical: KoshikaSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: KoshikaRadius.md,
                  ),
                  child: Text(
                    _statusLabel,
                    style: KoshikaTypography.statusText.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            Text(
              'Size: ${modelInfo.formattedSize}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (modelInfo.status == ModelStatus.downloading) ...[
              const SizedBox(height: KoshikaSpacing.md),
              LinearProgressIndicator(
                value: modelInfo.downloadProgress / 100,
                borderRadius: KoshikaRadius.sm,
              ),
              const SizedBox(height: KoshikaSpacing.xs),
              Text(
                '${modelInfo.downloadProgress}%',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (modelInfo.errorMessage != null) ...[
              const SizedBox(height: KoshikaSpacing.sm),
              Text(
                modelInfo.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: KoshikaSpacing.md),
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
                    child: const Text('Load'),
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
    );
  }

  IconData get _statusIcon => switch (modelInfo.status) {
    ModelStatus.notDownloaded => Icons.cloud_download_outlined,
    ModelStatus.downloading => Icons.downloading,
    ModelStatus.ready => Icons.check_circle_outline,
    ModelStatus.loading => Icons.hourglass_top,
    ModelStatus.loaded => Icons.check_circle,
    ModelStatus.error => Icons.error_outline,
  };

  String get _statusLabel => switch (modelInfo.status) {
    ModelStatus.notDownloaded => 'Not Downloaded',
    ModelStatus.downloading => 'Downloading...',
    ModelStatus.ready => 'Ready',
    ModelStatus.loading => 'Loading...',
    ModelStatus.loaded => 'Active',
    ModelStatus.error => 'Error',
  };

  Color get _statusColor => switch (modelInfo.status) {
    ModelStatus.notDownloaded => AppColors.onSurfaceVariant,
    ModelStatus.downloading || ModelStatus.loading => AppColors.statusBusy,
    ModelStatus.ready => AppColors.statusReady,
    ModelStatus.loaded => AppColors.statusActive,
    ModelStatus.error => AppColors.error,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// HuggingFace Token Dialog
// ═══════════════════════════════════════════════════════════════════════

class _HfTokenDialog extends StatefulWidget {
  @override
  State<_HfTokenDialog> createState() => _HfTokenDialogState();
}

class _HfTokenDialogState extends State<_HfTokenDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('HuggingFace Token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Koshika downloads gated Hugging Face models, so you need a token '
            'with access to both repos:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '1. Create a free account at huggingface.co\n'
            '2. Request/accept access for:\n'
            '   - litert-community/embeddinggemma-300m\n'
            '   - litert-community/Gemma3-1B-IT\n'
            '3. Create a Read token in Settings > Access Tokens\n'
            '4. Paste that token here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Access Token',
              hintText: 'hf_...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            obscureText: true,
            autocorrect: false,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final token = _controller.text.trim();
            if (token.isNotEmpty) {
              Navigator.of(context).pop(token);
            }
          },
          child: const Text('Download'),
        ),
      ],
    );
  }
}
