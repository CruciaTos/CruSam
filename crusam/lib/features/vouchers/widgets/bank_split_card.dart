import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/utils/format_utils.dart';

class BankSplitCard extends StatelessWidget {
  final double idbiToOther;
  final double idbiToIdbi;
  final double baseTotal;

  const BankSplitCard({
    super.key,
    required this.idbiToOther,
    required this.idbiToIdbi,
    required this.baseTotal,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.cardPadding),
    decoration: BoxDecoration(
      color: AppColors.slate900,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BANK TRANSFER SPLIT',
          style: AppTextStyles.label.copyWith(color: AppColors.slate500),
        ),
        const SizedBox(height: AppSpacing.md),
        _row('From IDBI to Other Bank', formatCurrency(idbiToOther)),
        _row('From IDBI to IDBI Bank', formatCurrency(idbiToIdbi)),

        const SizedBox(height: 69),
        const Divider(color: AppColors.slate700, height: 24),
        const SizedBox(height: 7),
        _row(
          'Total Base Amount',
          formatCurrency(baseTotal),
          labelColor: AppColors.white,
          valueStyle: AppTextStyles.bodyMedium.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
         const SizedBox(height: 9.3), 
      ],
    ),
  );

  static Widget _row(
    String label,
    String value, {
    Color? labelColor,
    TextStyle? valueStyle,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: labelColor ?? AppColors.slate400,
              ),
            ),
            Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                    fontSize: 13,
                    color: AppColors.slate300,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      );
}