import 'package:flutter/material.dart';

import '../theme/koshika_design_system.dart';

/// Icon wrapped in a colored rounded-rect background.
///
/// Used as the leading element in list items, feature cards, and settings rows.
/// The accent color is applied at 10% opacity for the background and full
/// opacity for the icon.
class IconContainer extends StatelessWidget {
  const IconContainer({
    super.key,
    required this.icon,
    required this.color,
    this.size = 24,
    this.padding = 12,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: KoshikaRadius.lg,
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}
