import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/koshika_design_system.dart';

/// Styled section header used in the Settings screen.
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.icon,
  });

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
