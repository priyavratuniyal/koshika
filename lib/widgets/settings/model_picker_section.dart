import 'package:flutter/material.dart';

import '../../models/llm_model_config.dart';
import '../../models/model_info.dart';
import '../../theme/app_colors.dart';
import '../../theme/koshika_design_system.dart';

/// Model picker with curated list, custom option, and active model controls.
class ModelPickerSection extends StatelessWidget {
  final ModelInfo modelInfo;
  final LlmModelConfig currentConfig;
  final ValueChanged<LlmModelConfig> onModelSelected;
  final VoidCallback onCustomModelTap;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onCancelDownload;

  const ModelPickerSection({
    super.key,
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

// ─── Single selectable model row (radio-style) ─────────────────────

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

// ─── Active model controls — Download / Load / Unload + progress ───

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
