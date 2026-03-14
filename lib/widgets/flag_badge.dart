import 'package:flutter/material.dart';
import '../models/models.dart';

class FlagBadge extends StatelessWidget {
  final BiomarkerFlag flag;

  const FlagBadge({super.key, required this.flag});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    switch (flag) {
      case BiomarkerFlag.normal:
        color = Colors.green;
        text = 'N';
        break;
      case BiomarkerFlag.low:
        color = Colors.orange;
        text = 'L';
        break;
      case BiomarkerFlag.high:
        color = Colors.red;
        text = 'H';
        break;
      case BiomarkerFlag.critical:
        color = Colors.red[900]!;
        text = 'C';
        break;
      case BiomarkerFlag.unknown:
        color = Colors.grey;
        text = '-';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
