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
import '../widgets/settings/settings_widgets.dart';

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
      builder: (ctx) => const CustomModelDialog(),
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
            SettingsSectionHeader(
              title: 'AI Models',
              icon: Icons.smart_toy_outlined,
            ),
            ModelPickerSection(
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
            EmbeddingModelTile(
              modelInfo: _embeddingInfo,
              onDownload: () => embeddingService.downloadModel(),
              onLoad: _loadEmbeddingModel,
              onUnload: () => embeddingService.unloadModel(),
            ),
            const SizedBox(height: KoshikaSpacing.md),
            SettingsSectionHeader(
              title: LlmStrings.hfTokenSectionTitle,
              icon: Icons.key_outlined,
            ),
            const HfTokenTile(),
            const SizedBox(height: KoshikaSpacing.sm),
          ],

          // ── Data Section ──
          SettingsSectionHeader(
            title: 'Data Management',
            icon: Icons.storage_outlined,
          ),
          SettingsRow(
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
          SettingsRow(
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
          SettingsRow(
            icon: Icons.ios_share,
            iconColor: AppColors.primary,
            title: 'Export All Data (FHIR R4)',
            subtitle: 'Share as interoperable health bundle',
            onTap: _exportAllFhir,
          ),
          SettingsRow(
            icon: Icons.delete_forever,
            iconColor: AppColors.error,
            title: 'Delete All Data',
            titleColor: AppColors.error,
            subtitle: 'Remove all reports and biomarkers',
            onTap: _deleteAllData,
          ),

          const SizedBox(height: KoshikaSpacing.sm),

          // ── About Section ──
          SettingsSectionHeader(title: 'About', icon: Icons.info_outline),
          SettingsRow(
            icon: Icons.local_hospital,
            iconColor: AppColors.primary,
            title: 'Koshika',
            subtitle: 'Offline-first health data tracker with on-device AI',
          ),
          SettingsRow(
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
          SettingsRow(
            icon: Icons.code,
            iconColor: AppColors.onSurfaceVariant,
            title: 'Source Code',
            subtitle: 'github.com/priyavratuniyal/koshika',
          ),
          SettingsRow(
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
