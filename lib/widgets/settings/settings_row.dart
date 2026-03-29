import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/koshika_design_system.dart';
import '../icon_container.dart';

/// A standard row widget for the Settings screen — icon, title, optional
/// subtitle, and optional trailing widget.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
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
