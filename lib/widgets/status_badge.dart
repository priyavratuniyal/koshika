import 'package:flutter/material.dart';

import '../models/biomarker_result.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

/// Pill-shaped status badge with icon and label.
///
/// Maps [BiomarkerFlag] to the appropriate semantic color and icon per the
/// design spec.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.flag, this.label});

  final BiomarkerFlag flag;

  /// Optional override label. If null, derives from [flag].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(flag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: KoshikaRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 6),
          Text(
            label ?? status.label,
            style: KoshikaTypography.statusText.copyWith(color: status.color),
          ),
        ],
      ),
    );
  }

  /// Convenience constructor from a raw string flag value.
  factory StatusBadge.fromString(String flag, {String? label}) {
    final mapped = switch (flag.toLowerCase().trim()) {
      'normal' || 'n' => BiomarkerFlag.normal,
      'low' || 'l' => BiomarkerFlag.low,
      'high' || 'h' => BiomarkerFlag.high,
      'critical' || 'c' => BiomarkerFlag.critical,
      'borderline' || 'b' => BiomarkerFlag.borderline,
      _ => BiomarkerFlag.unknown,
    };
    return StatusBadge(flag: mapped, label: label);
  }

  static _StatusInfo _statusFor(BiomarkerFlag flag) => switch (flag) {
    BiomarkerFlag.normal => const _StatusInfo(
      color: AppColors.success,
      icon: Icons.check_circle_outline,
      label: 'NORMAL',
    ),
    BiomarkerFlag.borderline => const _StatusInfo(
      color: AppColors.warning,
      icon: Icons.warning_amber_rounded,
      label: 'BORDERLINE',
    ),
    BiomarkerFlag.low => const _StatusInfo(
      color: AppColors.error,
      icon: Icons.arrow_downward,
      label: 'LOW',
    ),
    BiomarkerFlag.high => const _StatusInfo(
      color: AppColors.error,
      icon: Icons.arrow_upward,
      label: 'HIGH',
    ),
    BiomarkerFlag.critical => const _StatusInfo(
      color: AppColors.error,
      icon: Icons.error_outline,
      label: 'CRITICAL',
    ),
    BiomarkerFlag.unknown => const _StatusInfo(
      color: AppColors.textMuted,
      icon: Icons.help_outline,
      label: 'UNKNOWN',
    ),
  };
}

class _StatusInfo {
  const _StatusInfo({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;
}
