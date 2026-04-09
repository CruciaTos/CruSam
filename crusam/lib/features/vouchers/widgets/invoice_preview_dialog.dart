import 'package:crusam/data/models/margin_settings_model.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/company_config_model.dart';
import '../notifiers/voucher_notifier.dart';
import '../services/excel_export_service.dart';
import '../notifiers/margin_settings_notifier.dart';
import '../services/pdf_export_service.dart';
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
  final MarginSettingsNotifier _marginNotifier = MarginSettingsNotifier();
  final GlobalKey _previewKey = GlobalKey();
  bool _showMarginPanel = false;

  @override
  void initState() {
    super.initState();
    _marginNotifier.load();
  }

  @override
  void dispose() {
    _marginNotifier.dispose();
    super.dispose();
  }

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
                        IconButton(
                          icon: Icon(
                            _showMarginPanel ? Icons.margin : Icons.format_indent_increase,
                            size: 18,
                            color: _showMarginPanel ? AppColors.indigo600 : AppColors.slate500,
                          ),
                          tooltip: 'Adjust Margins',
                          onPressed: () => setState(() => _showMarginPanel = !_showMarginPanel),
                        ),
                        const SizedBox(width: 8),
                        if (widget.type == PreviewType.invoice)
                          _exporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : OutlinedButton.icon(
                                  onPressed: _exportPdf,
                                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                  label: const Text('Save PDF'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(color: Colors.red.shade400),
                                  ),
                                ),
                        const SizedBox(width: 8),
                        // ── Export to Excel ────────────────────────────
                        _exporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton.icon(
                                onPressed: _exportExcel,
                                icon: const Icon(Icons.table_chart_outlined, size: 16),
                                label: const Text('Export Excel'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.green.shade700,
                                  side: BorderSide(color: Colors.green.shade400),
                                ),
                              ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          label: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  // ── Preview content ─────────────────────────────────────
                  Expanded(
                    child: Row(
                      children: [
                        if (_showMarginPanel)
                          ListenableBuilder(
                            listenable: _marginNotifier,
                            builder: (_, __) => _MarginPanel(notifier: _marginNotifier),
                          ),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: _marginNotifier,
                            builder: (_, __) => SingleChildScrollView(
                              padding: const EdgeInsets.all(AppSpacing.xxl),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 800),
                                  child: widget.type == PreviewType.invoice
                                      ? Column(children: [
                                          RepaintBoundary(
                                            key: _previewKey,
                                            child: TaxInvoicePreview(
                                              voucher: voucher,
                                              config: widget.config,
                                              margins: EdgeInsets.fromLTRB(
                                                _marginNotifier.settings.left,
                                                _marginNotifier.settings.top,
                                                _marginNotifier.settings.right,
                                                _marginNotifier.settings.bottom,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 32),
                                          VoucherPdfPreview(
                                              voucher: voucher,
                                              config: widget.config),
                                        ])
                                      : ListenableBuilder(
                                          listenable: _marginNotifier,
                                          builder: (_, __) => RepaintBoundary(
                                            key: _previewKey,
                                            child: BankDisbursementPreview(
                                              voucher: voucher,
                                              config: widget.config,
                                              margins: EdgeInsets.fromLTRB(
                                                _marginNotifier.settings.left,
                                                _marginNotifier.settings.top,
                                                _marginNotifier.settings.right,
                                                _marginNotifier.settings.bottom,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await PdfExportService.exportTaxInvoiceFromWidget(
        _previewKey,
        widget.notifier.enriched.billNo,
      );
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)], subject: 'Tax Invoice');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _MarginPanel extends StatefulWidget {
  final MarginSettingsNotifier notifier;
  const _MarginPanel({required this.notifier});
  @override
  State<_MarginPanel> createState() => _MarginPanelState();
}

class _MarginPanelState extends State<_MarginPanel> {
  late final Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    final s = widget.notifier.settings;
    _ctrls = {
      'top': TextEditingController(text: s.top.toStringAsFixed(1)),
      'bottom': TextEditingController(text: s.bottom.toStringAsFixed(1)),
      'left': TextEditingController(text: s.left.toStringAsFixed(1)),
      'right': TextEditingController(text: s.right.toStringAsFixed(1)),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    widget.notifier.update(MarginSettings(
      top: double.tryParse(_ctrls['top']!.text) ?? 24,
      bottom: double.tryParse(_ctrls['bottom']!.text) ?? 24,
      left: double.tryParse(_ctrls['left']!.text) ?? 24,
      right: double.tryParse(_ctrls['right']!.text) ?? 24,
    ));
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.slate200)),
          color: AppColors.slate50,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Margins (px)', style: AppTextStyles.label),
            const SizedBox(height: 12),
            _MarginDiagram(notifier: widget.notifier),
            const SizedBox(height: 16),
            for (final side in ['top', 'bottom', 'left', 'right']) ...[
              Text(side[0].toUpperCase() + side.substring(1), style: AppTextStyles.small),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _ctrls[side],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppTextStyles.input,
                  decoration: const InputDecoration(isDense: true, suffixText: 'px'),
                  onChanged: (_) => _apply(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
          ],
        ),
      );
}

class _MarginDiagram extends StatelessWidget {
  final MarginSettingsNotifier notifier;
  const _MarginDiagram({required this.notifier});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notifier,
        builder: (_, __) {
          final s = notifier.settings;
          const maxM = 80.0; // max margin for scaling visual
          const boxW = 80.0;
          const boxH = 100.0;

          return Center(
            child: SizedBox(
              width: boxW, height: boxH,
              child: Stack(children: [
                // Page outline
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.slate400),
                  ),
                ),
                // Content area (shrinks with margins)
                Positioned(
                  top: (s.top / maxM * 20).clamp(2, 30),
                  bottom: (s.bottom / maxM * 20).clamp(2, 30),
                  left: (s.left / maxM * 20).clamp(2, 30),
                  right: (s.right / maxM * 20).clamp(2, 30),
                  child: Container(
                    color: AppColors.slate100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (_) =>
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
                            child: Container(height: 3, color: AppColors.slate300),
                          ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}
  