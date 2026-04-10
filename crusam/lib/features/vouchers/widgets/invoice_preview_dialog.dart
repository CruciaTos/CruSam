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

// Which preview the margin panel is currently targeting
enum _MarginTarget { taxInvoice, voucherPdf }

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
  final MarginSettingsNotifier _marginNotifier1 = MarginSettingsNotifier(); // TaxInvoice
  final MarginSettingsNotifier _marginNotifier2 = MarginSettingsNotifier(); // VoucherPdf
  bool _showMarginPanel = false;
  _MarginTarget _marginTarget = _MarginTarget.taxInvoice;

  @override
  void initState() {
    super.initState();
    _marginNotifier1.load();
    _marginNotifier2.load();
  }

  @override
  void dispose() {
    _marginNotifier1.dispose();
    _marginNotifier2.dispose();
    super.dispose();
  }

  MarginSettingsNotifier get _activeMarginNotifier =>
      _marginTarget == _MarginTarget.taxInvoice ? _marginNotifier1 : _marginNotifier2;

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
                            _showMarginPanel
                                ? Icons.margin
                                : Icons.format_indent_increase,
                            size: 18,
                            color: _showMarginPanel
                                ? AppColors.indigo600
                                : AppColors.slate500,
                          ),
                          tooltip: 'Adjust Margins',
                          onPressed: () =>
                              setState(() => _showMarginPanel = !_showMarginPanel),
                        ),
                        const SizedBox(width: 8),
                        _exporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton.icon(
                                onPressed: _exportPdf,
                                icon: const Icon(Icons.picture_as_pdf_outlined,
                                    size: 16),
                                label: const Text('Save PDF'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade400),
                                ),
                              ),
                        const SizedBox(width: 8),
                        _exporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : OutlinedButton.icon(
                                onPressed: _exportExcel,
                                icon: const Icon(Icons.table_chart_outlined,
                                    size: 16),
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
                            listenable: _activeMarginNotifier,
                            builder: (_, __) => _MarginPanel(
                              notifier: _activeMarginNotifier,
                              // Only show target selector for invoice type (has 2 pages)
                              showTargetSelector: widget.type == PreviewType.invoice,
                              target: _marginTarget,
                              onTargetChanged: (t) =>
                                  setState(() => _marginTarget = t),
                            ),
                          ),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: Listenable.merge(
                                [_marginNotifier1, _marginNotifier2]),
                            builder: (_, __) => SingleChildScrollView(
                              padding: const EdgeInsets.all(AppSpacing.xxl),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 800),
                                  child: widget.type == PreviewType.invoice
                                      ? Column(children: [
                                          TaxInvoicePreview(
                                            voucher: voucher,
                                            config: widget.config,
                                            margins: EdgeInsets.fromLTRB(
                                              _marginNotifier1.settings.left,
                                              _marginNotifier1.settings.top,
                                              _marginNotifier1.settings.right,
                                              _marginNotifier1.settings.bottom,
                                            ),
                                          ),
                                          const SizedBox(height: 32),
                                          VoucherPdfPreview(
                                            voucher: voucher,
                                            config: widget.config,
                                            margins: EdgeInsets.fromLTRB(
                                              _marginNotifier2.settings.left,
                                              _marginNotifier2.settings.top,
                                              _marginNotifier2.settings.right,
                                              _marginNotifier2.settings.bottom,
                                            ),
                                          ),
                                        ])
                                      : BankDisbursementPreview(
                                          voucher: voucher,
                                          config: widget.config,
                                          margins: EdgeInsets.fromLTRB(
                                            _marginNotifier1.settings.left,
                                            _marginNotifier1.settings.top,
                                            _marginNotifier1.settings.right,
                                            _marginNotifier1.settings.bottom,
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
      final voucher = widget.notifier.enriched;

      if (widget.type == PreviewType.invoice) {
        await PdfExportService.exportInvoiceBundle(
          context: context,
          voucher: voucher,
          config: widget.config,
          taxInvoiceMargins: EdgeInsets.fromLTRB(
            _marginNotifier1.settings.left,
            _marginNotifier1.settings.top,
            _marginNotifier1.settings.right,
            _marginNotifier1.settings.bottom,
          ),
          voucherMargins: EdgeInsets.fromLTRB(
            _marginNotifier2.settings.left,
            _marginNotifier2.settings.top,
            _marginNotifier2.settings.right,
            _marginNotifier2.settings.bottom,
          ),
        );
      } else {
        await PdfExportService.exportBankDisbursement(
          context: context,
          voucher: voucher,
          config: widget.config,
          margins: EdgeInsets.fromLTRB(
            _marginNotifier1.settings.left,
            _marginNotifier1.settings.top,
            _marginNotifier1.settings.right,
            _marginNotifier1.settings.bottom,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF export failed: $e'),
            backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

// ── Margin Panel ──────────────────────────────────────────────────────────────

class _MarginPanel extends StatefulWidget {
  final MarginSettingsNotifier notifier;
  final bool showTargetSelector;
  final _MarginTarget target;
  final void Function(_MarginTarget) onTargetChanged;

  const _MarginPanel({
    required this.notifier,
    required this.showTargetSelector,
    required this.target,
    required this.onTargetChanged,
  });

  @override
  State<_MarginPanel> createState() => _MarginPanelState();
}

class _MarginPanelState extends State<_MarginPanel> {
  late Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = _buildCtrls(widget.notifier.settings);
  }

  Map<String, TextEditingController> _buildCtrls(MarginSettings s) => {
        'top': TextEditingController(text: s.top.toStringAsFixed(1)),
        'bottom': TextEditingController(text: s.bottom.toStringAsFixed(1)),
        'left': TextEditingController(text: s.left.toStringAsFixed(1)),
        'right': TextEditingController(text: s.right.toStringAsFixed(1)),
      };

  void _disposeCtrls() {
    for (final c in _ctrls.values) c.dispose();
  }

  // When target switches, rebuild controllers from the new notifier's settings
  @override
  void didUpdateWidget(covariant _MarginPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      _disposeCtrls();
      _ctrls = _buildCtrls(widget.notifier.settings);
    }
  }

  @override
  void dispose() {
    _disposeCtrls();
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

            // ── Target selector (only shown for invoice type) ─────────
            if (widget.showTargetSelector) ...[
              _TargetSelector(
                current: widget.target,
                onChanged: widget.onTargetChanged,
              ),
              const SizedBox(height: 12),
            ],

            _MarginDiagram(notifier: widget.notifier),
            const SizedBox(height: 16),
            for (final side in ['top', 'bottom', 'left', 'right']) ...[
              Text(
                side[0].toUpperCase() + side.substring(1),
                style: AppTextStyles.small,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _ctrls[side],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: AppTextStyles.input,
                  decoration:
                      const InputDecoration(isDense: true, suffixText: 'px'),
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

// ── Target Selector widget ────────────────────────────────────────────────────

class _TargetSelector extends StatelessWidget {
  final _MarginTarget current;
  final void Function(_MarginTarget) onChanged;

  const _TargetSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Column(
          children: [
            _tile(
              label: 'Tax Invoice',
              sub: 'Bill',
              target: _MarginTarget.taxInvoice,
            ),
            const Divider(height: 1, thickness: 1, color: AppColors.slate200),
            _tile(
              label: 'Voucher',
              sub: 'Expenses Statement',
              target: _MarginTarget.voucherPdf,
            ),
          ],
        ),
      );

  Widget _tile({
    required String label,
    required String sub,
    required _MarginTarget target,
  }) {
    final selected = current == target;
    return InkWell(
      onTap: () => onChanged(target),
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo50 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 14,
              color: selected ? AppColors.indigo600 : AppColors.slate400,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.indigo600
                          : AppColors.slate700,
                    ),
                  ),
                  Text(
                    sub,
                    style: AppTextStyles.small.copyWith(
                      fontSize: 10,
                      color: AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Margin Diagram ────────────────────────────────────────────────────────────

class _MarginDiagram extends StatelessWidget {
  final MarginSettingsNotifier notifier;
  const _MarginDiagram({required this.notifier});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notifier,
        builder: (_, __) {
          final s = notifier.settings;
          const maxM = 80.0;
          const boxW = 80.0;
          const boxH = 100.0;

          return Center(
            child: SizedBox(
              width: boxW,
              height: boxH,
              child: Stack(children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.slate400),
                  ),
                ),
                Positioned(
                  top: (s.top / maxM * 20).clamp(2, 30),
                  bottom: (s.bottom / maxM * 20).clamp(2, 30),
                  left: (s.left / maxM * 20).clamp(2, 30),
                  right: (s.right / maxM * 20).clamp(2, 30),
                  child: Container(
                    color: AppColors.slate100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        4,
                        (_) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 3),
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