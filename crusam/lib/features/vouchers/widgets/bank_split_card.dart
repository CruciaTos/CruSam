import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
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
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BANK TRANSFER SPLIT', style: AppTextStyles.label),
        const SizedBox(height: AppSpacing.md),
        _row('From IDBI to Other Bank', formatCurrency(idbiToOther)),
        _row('From IDBI to IDBI Bank',  formatCurrency(idbiToIdbi)),
        const Divider(height: 24, color: AppColors.slate100),
        _row('Total Base Amount', formatCurrency(baseTotal), bold: true),
      ],
    ),
  );

  static Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: bold ? AppTextStyles.bodySemi.copyWith(fontSize: 13) : AppTextStyles.small.copyWith(color: AppColors.slate600)),
        Text(value,  style: bold ? AppTextStyles.bodySemi : AppTextStyles.bodyMedium.copyWith(fontSize: 13)),
      ],
    ),
  );
}