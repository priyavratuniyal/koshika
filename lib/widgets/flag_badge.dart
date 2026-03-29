import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/koshika_design_system.dart';

class FlagBadge extends StatelessWidget {
  final BiomarkerFlag flag;

  const FlagBadge({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (flag) {
      BiomarkerFlag.normal => (AppColors.success, 'N'),
      BiomarkerFlag.borderline => (AppColors.warning, 'B'),
      BiomarkerFlag.low => (AppColors.error, 'L'),
      BiomarkerFlag.high => (AppColors.error, 'H'),
      BiomarkerFlag.critical => (AppColors.error, 'C'),
      BiomarkerFlag.unknown => (AppColors.textMuted, '-'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: KoshikaRadius.lg,
      ),
      child: Text(
        text,
        style: KoshikaTypography.statusText.copyWith(color: color),
      ),
    );
  }
}
