import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ComingSoonScreen extends StatelessWidget {
  final String feature;
  const ComingSoonScreen({super.key, required this.feature});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.construction_outlined, size: 64, color: AppColors.slate300),
        const SizedBox(height: 16),
        Text(feature, style: AppTextStyles.h3),
        const SizedBox(height: 8),
        Text('Coming Soon', style: AppTextStyles.small),
      ],
    ),
  );
}