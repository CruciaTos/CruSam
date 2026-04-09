import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/company_config_model.dart';
import '../notifiers/voucher_notifier.dart';
import '../services/excel_export_service.dart';
import 'tax_invoice_preview.dart';
import 'voucher_pdf_preview.dart';
import 'bank_disbursement_preview.dart';

enum PreviewType { invoice, bank }

class InvoicePreviewDialog extends StatefulWidget {
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
  ) =>
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => InvoicePreviewDialog(
            notifier: notifier, config: config, type: type),
      );

  @override
  State<InvoicePreviewDialog> createState() => _InvoicePreviewDialogState();
}

class _InvoicePreviewDialogState extends State<InvoicePreviewDialog> {
  bool _exporting = false;

  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final voucher = widget.notifier.enriched;
      final path = widget.type == PreviewType.invoice
          ? await ExcelExportService.exportTaxInvoice(voucher, widget.config)
          : await ExcelExportService.exportBankDisbursement(
              voucher, widget.config);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path)],
        subject: widget.type == PreviewType.invoice
            ? 'Tax Invoice'
            : 'Bank Disbursement',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.notifier,
        builder: (ctx, _) {
          final voucher = widget.notifier.enriched;
          return Dialog(
            insetPadding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  // ── Header bar ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.slate50,
                      border: Border(
                          bottom: BorderSide(color: AppColors.slate200)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.type == PreviewType.invoice
                                ? 'Tax Invoice & Voucher Preview'
                                : 'Bank Disbursement Sheet',
                            style: AppTextStyles.h4,
                          ),
                        ),
                        // ── Export to Excel ────────────────────────────
                        _exporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : OutlinedButton.icon(
                                onPressed: _exportExcel,
                                icon: const Icon(Icons.table_chart_outlined,
                                    size: 16),
                                label: const Text('Export Excel'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.green.shade700,
                                  side: BorderSide(
                                      color: Colors.green.shade400),
                                ),
                              ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 16),
                          label: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  // ── Preview content ─────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 800),
                          child: widget.type == PreviewType.invoice
                              ? Column(children: [
                                  TaxInvoicePreview(
                                      voucher: voucher,
                                      config: widget.config),
                                  const SizedBox(height: 32),
                                  VoucherPdfPreview(
                                      voucher: voucher,
                                      config: widget.config),
                                ])
                              : BankDisbursementPreview(
                                  voucher: voucher,
                                  config: widget.config),
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