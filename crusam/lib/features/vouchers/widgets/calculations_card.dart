import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/utils/format_utils.dart';

class CalculationsCard extends StatelessWidget {
  final double baseTotal;
  final double cgst;
  final double sgst;
  final double roundOff;
  final double finalTotal;

  const CalculationsCard({
    super.key,
    required this.baseTotal,
    required this.cgst,
    required this.sgst,
    required this.roundOff,
    required this.finalTotal,
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
        Text('FINAL CALCULATIONS', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
        const SizedBox(height: AppSpacing.md),
        _row('Base Total', formatCurrency(baseTotal)),
        _row('CGST (9%)',  formatCurrency(cgst)),
        _row('SGST (9%)',  formatCurrency(sgst)),
        _row('Round Off',  '${roundOff >= 0 ? '+' : ''}${roundOff.toStringAsFixed(2)}',
            valueColor: roundOff >= 0 ? AppColors.emerald600 : AppColors.rose400),
        const Divider(color: AppColors.slate700, height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Grand Total', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white, fontSize: 16)),
            Text(formatCurrency(finalTotal), style: AppTextStyles.grandTotal),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(numberToWords(finalTotal), style: AppTextStyles.amountWords),
        ),
      ],
    ),
  );

  static Widget _row(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.slate400)),
        Text(value, style: TextStyle(fontSize: 13, color: valueColor ?? AppColors.slate300, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}