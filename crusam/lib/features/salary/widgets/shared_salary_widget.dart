import 'package:crusam/core/theme/app_colors.dart';
import 'package:crusam/core/theme/app_spacing.dart';
import 'package:crusam/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

class SavedSalaryIndicatorBanner extends StatelessWidget {
  final String? periodLabel;

  const SavedSalaryIndicatorBanner({super.key, this.periodLabel});

  @override
  Widget build(BuildContext context) {
    if (periodLabel == null || periodLabel!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.indigo600.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 15,
            color: AppColors.indigo600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing Saved Salary: $periodLabel',
              style: AppTextStyles.small.copyWith(
                color: AppColors.indigo600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
