import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../constants/llm_strings.dart';
import '../main.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';
import '../models/models.dart';
import '../models/llm_model_config.dart';
import '../services/fhir_export_service.dart';
import '../services/hf_token_service.dart';
import '../widgets/icon_container.dart';

/// Settings screen with AI model management, data controls, and about section.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription<ModelInfo>? _modelSub;
  StreamSubscription<ModelInfo>? _embeddingSub;
  ModelInfo _modelInfo = const ModelInfo(
    name: '',
    downloadUrl: '',
    estimatedSizeMB: 0,
  );
  ModelInfo _embeddingInfo = const ModelInfo(
    name: '',
    downloadUrl: '',
    estimatedSizeMB: 0,
  );
  String _appVersion = '';

  @override
  void initState() {
    super.initState();

    if (kAiEnabled) {
      _modelInfo = llmService.currentModelInfo;
      _embeddingInfo = embeddingService.currentModelInfo;
      _modelSub = llmService.modelStatusStream.listen((info) {
        if (mounted) setState(() => _modelInfo = info);
      });
      _embeddingSub = embeddingService.modelStatusStream.listen((info) {
        if (mounted) setState(() => _embeddingInfo = info);
      });
    }

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
    _modelSub?.cancel();
    _embeddingSub?.cancel();
    super.dispose();
  }

  // ─── Model Actions ───────────────────────────────────────────────────

  Future<void> _onModelSelected(LlmModelConfig config) async {
    if (config.id == llmService.currentConfig.id && !config.isCustom) return;

    // Warn if switching away from a downloaded model
    if (_modelInfo.status != ModelStatus.notDownloaded) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch Model?'),
          content: Text(
            'Switching will remove ${_modelInfo.name} '
            '(~${_modelInfo.formattedSize}) from this device. '
            'The new model will need to be downloaded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await llmService.switchModel(config);
  }

  Future<void> _onCustomModelTap() async {
    if (!mounted) return;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (ctx) => const _CustomModelDialog(),
    );
    if (result != null) await _onModelSelected(result);
  }

  Future<void> _loadEmbeddingModel() async {
    await embeddingService.loadModel();
    await migrateEmbeddingsIfNeeded();
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
          // ── AI Model Section (full flavor only) ──
          if (kAiEnabled) ...[
            _SectionHeader(title: 'AI Models', icon: Icons.smart_toy_outlined),
            _ModelPickerSection(
              modelInfo: _modelInfo,
              currentConfig: llmService.currentConfig,
              onModelSelected: _onModelSelected,
              onCustomModelTap: _onCustomModelTap,
              onDownload: () => llmService.downloadModel(),
              onLoad: () => llmService.loadModel(),
              onUnload: () => llmService.unloadModel(),
              onCancelDownload: () => llmService.cancelDownload(),
            ),
            const SizedBox(height: KoshikaSpacing.sm),
            _EmbeddingModelTile(
              modelInfo: _embeddingInfo,
              onDownload: () => embeddingService.downloadModel(),
              onLoad: _loadEmbeddingModel,
              onUnload: () => embeddingService.unloadModel(),
            ),
            const SizedBox(height: KoshikaSpacing.md),
            _SectionHeader(
              title: LlmStrings.hfTokenSectionTitle,
              icon: Icons.key_outlined,
            ),
            const _HfTokenTile(),
            const SizedBox(height: KoshikaSpacing.sm),
          ],

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
// Settings Row
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
// Model Picker Section — curated list + active model controls
// ═══════════════════════════════════════════════════════════════════════

class _ModelPickerSection extends StatelessWidget {
  final ModelInfo modelInfo;
  final LlmModelConfig currentConfig;
  final ValueChanged<LlmModelConfig> onModelSelected;
  final VoidCallback onCustomModelTap;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onCancelDownload;

  const _ModelPickerSection({
    required this.modelInfo,
    required this.currentConfig,
    required this.onModelSelected,
    required this.onCustomModelTap,
    required this.onDownload,
    required this.onLoad,
    required this.onUnload,
    required this.onCancelDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: KoshikaDecorations.card,
      padding: KoshikaSpacing.cardPaddingAsymmetric,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chat Model',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: KoshikaSpacing.sm),

          // Curated model options
          ...LlmModelRegistry.curated.map(
            (config) => _ModelOptionCard(
              config: config,
              isSelected: config.id == currentConfig.id,
              onTap: () => onModelSelected(config),
            ),
          ),

          // Custom model option
          _ModelOptionCard(
            config: LlmModelConfig(
              id: 'custom',
              name: 'Custom model',
              downloadUrl: '',
              estimatedSizeMB: 0,
              description: 'Use any GGUF URL',
              isCustom: true,
            ),
            isSelected: currentConfig.isCustom,
            onTap: onCustomModelTap,
          ),

          const SizedBox(height: KoshikaSpacing.md),

          // Active model controls
          _ActiveModelControls(
            modelInfo: modelInfo,
            onDownload: onDownload,
            onLoad: onLoad,
            onUnload: onUnload,
            onCancelDownload: onCancelDownload,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Single selectable model row (radio-style)
// ═══════════════════════════════════════════════════════════════════════

class _ModelOptionCard extends StatelessWidget {
  final LlmModelConfig config;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModelOptionCard({
    required this.config,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
      child: InkWell(
        borderRadius: KoshikaRadius.md,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KoshikaSpacing.md,
            vertical: KoshikaSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: KoshikaRadius.md,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : AppColors.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 1,
            ),
            color: isSelected
                ? AppColors.primaryContainer.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: KoshikaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      config.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (config.estimatedSizeMB > 0)
                Text(
                  config.formattedSize,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Active model controls — Download / Load / Unload + progress
// ═══════════════════════════════════════════════════════════════════════

class _ActiveModelControls extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onCancelDownload;

  const _ActiveModelControls({
    required this.modelInfo,
    required this.onDownload,
    required this.onLoad,
    required this.onUnload,
    required this.onCancelDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Row(
          children: [
            Icon(_statusIcon, color: statusColor, size: 16),
            const SizedBox(width: KoshikaSpacing.xs),
            Text(
              _statusLabel,
              style: KoshikaTypography.statusText.copyWith(color: statusColor),
            ),
          ],
        ),

        // Progress bar
        if (modelInfo.status == ModelStatus.downloading) ...[
          const SizedBox(height: KoshikaSpacing.sm),
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

        // Error message
        if (modelInfo.errorMessage != null) ...[
          const SizedBox(height: KoshikaSpacing.sm),
          Text(
            modelInfo.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],

        // Action buttons
        const SizedBox(height: KoshikaSpacing.sm),
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
              OutlinedButton(onPressed: onUnload, child: const Text('Unload')),
            if (modelInfo.status == ModelStatus.downloading)
              Padding(
                padding: const EdgeInsets.only(left: KoshikaSpacing.sm),
                child: OutlinedButton.icon(
                  onPressed: onCancelDownload,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                ),
              ),
            if (modelInfo.status == ModelStatus.loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ],
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
// Embedding Model Tile
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

    return Container(
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
// Custom Model Dialog
// ═══════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════
// Hugging Face Token Tile
// ═══════════════════════════════════════════════════════════════════════

class _HfTokenTile extends StatefulWidget {
  const _HfTokenTile();

  @override
  State<_HfTokenTile> createState() => _HfTokenTileState();
}

class _HfTokenTileState extends State<_HfTokenTile> {
  final _controller = TextEditingController();
  bool _hasToken = false;
  bool _obscured = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await HfTokenService.getToken();
    if (mounted) {
      setState(() {
        _hasToken = token != null;
        if (token != null) _controller.text = token;
        _loading = false;
      });
    }
  }

  Future<void> _saveToken() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    await HfTokenService.setToken(token);
    if (mounted) {
      setState(() => _hasToken = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(LlmStrings.hfTokenSaved)));
    }
  }

  Future<void> _clearToken() async {
    await HfTokenService.setToken(null);
    if (mounted) {
      setState(() {
        _hasToken = false;
        _controller.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(LlmStrings.hfTokenCleared)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(KoshikaSpacing.base),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: KoshikaRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(KoshikaSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Description
              Text(
                LlmStrings.hfTokenDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: KoshikaSpacing.md),

              // Token input
              TextField(
                controller: _controller,
                obscureText: _obscured,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: LlmStrings.hfTokenFieldLabel,
                  hintText: LlmStrings.hfTokenFieldHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ),
              const SizedBox(height: KoshikaSpacing.sm),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_hasToken)
                    TextButton(
                      onPressed: _clearToken,
                      child: const Text(LlmStrings.hfTokenClearButton),
                    ),
                  const SizedBox(width: KoshikaSpacing.sm),
                  FilledButton.tonal(
                    onPressed: _saveToken,
                    child: const Text(LlmStrings.hfTokenSaveButton),
                  ),
                ],
              ),
              const SizedBox(height: KoshikaSpacing.md),

              // Info banner
              Container(
                padding: const EdgeInsets.all(KoshikaSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: KoshikaRadius.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: KoshikaSpacing.sm),
                    Expanded(
                      child: Text(
                        LlmStrings.hfTokenInfoMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Custom Model Dialog
// ═══════════════════════════════════════════════════════════════════════

class _CustomModelDialog extends StatefulWidget {
  const _CustomModelDialog();

  @override
  State<_CustomModelDialog> createState() => _CustomModelDialogState();
}

class _CustomModelDialogState extends State<_CustomModelDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();

    if (url.isEmpty) {
      setState(() => _urlError = 'URL is required');
      return;
    }
    try {
      final parsed = LlmModelRegistry.inspectCustomDownloadUrl(url);
      final displayName = name.isNotEmpty ? name : parsed.suggestedName;
      Navigator.of(
        context,
      ).pop(LlmModelRegistry.custom(name: displayName, downloadUrl: url));
    } on ArgumentError catch (e) {
      setState(() => _urlError = e.message?.toString() ?? 'Invalid GGUF URL');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom GGUF Model'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste the direct download URL for any GGUF model file. '
            'You are responsible for model compatibility.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'GGUF Download URL',
              hintText: 'https://huggingface.co/.../model.gguf',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _urlError,
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display Name (optional)',
              hintText: 'e.g. Phi-3 Mini',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Use Model')),
      ],
    );
  }
}
