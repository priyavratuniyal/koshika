import 'package:flutter/material.dart';

import '../../models/model_info.dart';
import '../../theme/app_colors.dart';
import '../../theme/koshika_design_system.dart';

/// Tile showing embedding model status with download/load/unload controls.
class EmbeddingModelTile extends StatelessWidget {
  final ModelInfo modelInfo;
  final VoidCallback onDownload;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  const EmbeddingModelTile({
    super.key,
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
