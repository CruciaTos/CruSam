import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/company_config_model.dart';
import '../notifiers/voucher_notifier.dart';
import 'tax_invoice_preview.dart';
import 'voucher_pdf_preview.dart';
import 'bank_disbursement_preview.dart';

enum PreviewType { invoice, bank }

class InvoicePreviewDialog extends StatelessWidget {
  final VoucherNotifier notifier;
  final CompanyConfigModel config;
  final PreviewType type;

  const InvoicePreviewDialog({
    super.key,
    required this.notifier,
    required this.config,
    required this.type,
  });

  static Future<void> show(
    BuildContext context,
    VoucherNotifier notifier,
    CompanyConfigModel config,
    PreviewType type,
  ) => showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => InvoicePreviewDialog(notifier: notifier, config: config, type: type),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notifier,
        builder: (ctx, _) {
          final voucher = notifier.enriched;
          return Dialog(
            insetPadding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.slate50,
                      border: Border(bottom: BorderSide(color: AppColors.slate200)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            type == PreviewType.invoice
                                ? 'Tax Invoice & Voucher Preview'
                                : 'Bank Disbursement Sheet',
                            style: AppTextStyles.h4,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          label: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: type == PreviewType.invoice
                              ? Column(children: [
                                  TaxInvoicePreview(voucher: voucher, config: config),
                                  const SizedBox(height: 32),
                                  VoucherPdfPreview(voucher: voucher, config: config),
                                ])
                              : BankDisbursementPreview(voucher: voucher, config: config),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}