import 'package:flutter/material.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.smallMedium),
              const SizedBox(height: 4),
              Text(value, style: AppTextStyles.h3.copyWith(fontSize: 22)),
            ],
          ),
        ),
      ],
    ),
  );
}