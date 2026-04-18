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
import '../notifiers/voucher_column_widths_notifier.dart';
import '../notifiers/bank_column_widths_notifier.dart';
import '../services/pdf_export_service.dart';
import 'tax_invoice_preview.dart';
import 'voucher_pdf_preview.dart';
import 'bank_disbursement_preview.dart';
import 'package:crusam/data/models/bank_column_widths_model.dart'; 
import 'package:crusam/data/models/voucher_column_widths_model.dart';

export 'voucher_pdf_preview.dart'     show VoucherColWidths;
export 'bank_disbursement_preview.dart' show BankColWidths;

enum PreviewType   { invoice, bank }
enum _MarginTarget { taxInvoice, voucherPdf }
enum _ActivePanel  { none, margins, columns }

class InvoicePreviewDialog extends StatefulWidget {
  final VoucherNotifier    notifier;
  final CompanyConfigModel config;
  final PreviewType        type;

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
          notifier: notifier, config: config, type: type,
        ),
      );

  @override
  State<InvoicePreviewDialog> createState() => _InvoicePreviewDialogState();
}

class _InvoicePreviewDialogState extends State<InvoicePreviewDialog> {
  bool _exporting = false;

  // Margin notifiers
  final MarginSettingsNotifier _marginNotifier1 = MarginSettingsNotifier();
  final MarginSettingsNotifier _marginNotifier2 = MarginSettingsNotifier();
  _MarginTarget _marginTarget = _MarginTarget.taxInvoice;

  // Column width notifiers — load from database
  late final VoucherColumnWidthsNotifier _voucherColWidthsNotifier;
  late final BankColumnWidthsNotifier _bankColWidthsNotifier;

  _ActivePanel _activePanel = _ActivePanel.none;

  @override
  void initState() {
    super.initState();
    _marginNotifier1.load();
    _marginNotifier2.load();
    
    // Initialize column width notifiers
    _voucherColWidthsNotifier = VoucherColumnWidthsNotifier();
    _bankColWidthsNotifier = BankColumnWidthsNotifier();
    
    _voucherColWidthsNotifier.load();
    _bankColWidthsNotifier.load();
  }

  @override
  void dispose() {
    _marginNotifier1.dispose();
    _marginNotifier2.dispose();
    _voucherColWidthsNotifier.dispose();
    _bankColWidthsNotifier.dispose();
    super.dispose();
  }

  MarginSettingsNotifier get _activeMarginNotifier =>
      _marginTarget == _MarginTarget.taxInvoice ? _marginNotifier1 : _marginNotifier2;

  void _togglePanel(_ActivePanel panel) =>
      setState(() => _activePanel = _activePanel == panel ? _ActivePanel.none : panel);

  // ── Exports ────────────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final voucher = widget.notifier.enriched;
      final path = widget.type == PreviewType.invoice
          ? await ExcelExportService.exportTaxInvoice(voucher, widget.config)
          : await ExcelExportService.exportBankDisbursement(
              voucher,
              widget.config,
              idbiToOther: widget.notifier.idbiToOther,
              idbiToIdbi: widget.notifier.idbiToIdbi,
            );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path)],
        subject: widget.type == PreviewType.invoice ? 'Tax Invoice' : 'Bank Disbursement',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
          taxInvoiceMargins: _marginsFrom(_marginNotifier1),
          voucherMargins:    _marginsFrom(_marginNotifier2),
        );
      } else {
        await PdfExportService.exportBankDisbursement(
          context: context,
          voucher: voucher,
          config: widget.config,
          margins: _marginsFrom(_marginNotifier1),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e'),
            backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static EdgeInsets _marginsFrom(MarginSettingsNotifier n) => EdgeInsets.fromLTRB(
        n.settings.left, n.settings.top, n.settings.right, n.settings.bottom,
      );

  // ── Build ──────────────────────────────────────────────────────────────────
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
                  // ── Header ─────────────────────────────────────────────
                  _HeaderBar(
                    type:           widget.type,
                    exporting:      _exporting,
                    activePanel:    _activePanel,
                    onToggleMargins: () => _togglePanel(_ActivePanel.margins),
                    onToggleColumns: () => _togglePanel(_ActivePanel.columns),
                    onExportPdf:    _exportPdf,
                    onExportExcel:  _exportExcel,
                    onClose: () => Navigator.pop(context),
                  ),

                  // ── Body ───────────────────────────────────────────────
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Margin panel
                        if (_activePanel == _ActivePanel.margins)
                          ListenableBuilder(
                            listenable: _activeMarginNotifier,
                            builder: (_, __) => _MarginPanel(
                              notifier: _activeMarginNotifier,
                              showTargetSelector:
                                  widget.type == PreviewType.invoice,
                              target: _marginTarget,
                              onTargetChanged: (t) =>
                                  setState(() => _marginTarget = t),
                            ),
                          ),

                        // Column width panel — generic, fed different data
                        // depending on which preview type is active.
                        if (_activePanel == _ActivePanel.columns)
                          widget.type == PreviewType.invoice
                              ? ListenableBuilder(
                                  listenable: _voucherColWidthsNotifier,
                                  builder: (_, __) => _ColWidthPanel(
                                    entries: _voucherColWidthsNotifier.settings.entries,
                                    totalWidth: _voucherColWidthsNotifier.settings.totalWidth,
                                    onChanged: (i, v) => _updateVoucherColumnWidth(i, v),
                                    onReset: () => _voucherColWidthsNotifier.update(
                                      const VoucherColumnWidthsSettings(),
                                    ),
                                  ),
                                )
                              : ListenableBuilder(
                                  listenable: _bankColWidthsNotifier,
                                  builder: (_, __) => _ColWidthPanel(
                                    entries: _bankColWidthsNotifier.settings.entries,
                                    totalWidth: _bankColWidthsNotifier.settings.totalWidth,
                                    onChanged: (i, v) => _updateBankColumnWidth(i, v),
                                    onReset: () => _bankColWidthsNotifier.update(
                                      const BankColumnWidthsSettings(),
                                    ),
                                  ),
                                ),

                        // Preview area
                        Expanded(
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              _marginNotifier1,
                              _marginNotifier2,
                              _voucherColWidthsNotifier,
                              _bankColWidthsNotifier,
                            ]),
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
                                            config:  widget.config,
                                            margins: _marginsFrom(_marginNotifier1),
                                          ),
                                          const SizedBox(height: 32),
                                          VoucherPdfPreview(
                                            voucher:   voucher,
                                            config:    widget.config,
                                            colWidths: _voucherColumnWidthsToVoucherColWidths(
                                              _voucherColWidthsNotifier.settings,
                                            ),
                                            margins:   _marginsFrom(_marginNotifier2),
                                          ),
                                        ])
                                      : BankDisbursementPreview(
                                          voucher:   voucher,
                                          config:    widget.config,
                                          colWidths: _bankColumnWidthsToBankColWidths(
                                            _bankColWidthsNotifier.settings,
                                          ),
                                          margins:   _marginsFrom(_marginNotifier1),
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

  // Convert settings models to preview widget models
  VoucherColWidths _voucherColumnWidthsToVoucherColWidths(
    VoucherColumnWidthsSettings settings,
  ) =>
      VoucherColWidths(
        sr: settings.sr,
        debitAc: settings.debitAc,
        ifsc: settings.ifsc,
        creditAc: settings.creditAc,
        code: settings.code,
        name: settings.name,
        place: settings.place,
        from: settings.from,
        to: settings.to,
        amount: settings.amount,
      );

  BankColWidths _bankColumnWidthsToBankColWidths(
    BankColumnWidthsSettings settings,
  ) =>
      BankColWidths(
        amount: settings.amount,
        debitAc: settings.debitAc,
        ifsc: settings.ifsc,
        creditAc: settings.creditAc,
        code: settings.code,
        beneficiary: settings.beneficiary,
        place: settings.place,
        bank: settings.bank,
        debitName: settings.debitName,
      );

  // Update methods that save to database
  void _updateVoucherColumnWidth(int index, double value) {
    final current = _voucherColWidthsNotifier.settings;
    final updated = current.copyWith(
      sr: index == 0 ? value : current.sr,
      debitAc: index == 1 ? value : current.debitAc,
      ifsc: index == 2 ? value : current.ifsc,
      creditAc: index == 3 ? value : current.creditAc,
      code: index == 4 ? value : current.code,
      name: index == 5 ? value : current.name,
      place: index == 6 ? value : current.place,
      bank: index == 7 ? value : current.bank,
      from: index == 8 ? value : current.from,
      to: index == 9 ? value : current.to,
      amount: index == 10 ? value : current.amount,
    );
    _voucherColWidthsNotifier.update(updated);
  }

  void _updateBankColumnWidth(int index, double value) {
    final current = _bankColWidthsNotifier.settings;
    final updated = current.copyWith(
      amount: index == 0 ? value : current.amount,
      debitAc: index == 1 ? value : current.debitAc,
      ifsc: index == 2 ? value : current.ifsc,
      creditAc: index == 3 ? value : current.creditAc,
      code: index == 4 ? value : current.code,
      beneficiary: index == 5 ? value : current.beneficiary,
      place: index == 6 ? value : current.place,
      bank: index == 7 ? value : current.bank,
      debitName: index == 8 ? value : current.debitName,
    );
    _bankColWidthsNotifier.update(updated);
  }
}

// ── Header bar ─────────────────────────────────────────────────────────────────
class _HeaderBar extends StatelessWidget {
  final PreviewType  type;
  final bool         exporting;
  final _ActivePanel activePanel;
  final VoidCallback onToggleMargins;
  final VoidCallback onToggleColumns;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final VoidCallback onClose;

  const _HeaderBar({
    required this.type,
    required this.exporting,
    required this.activePanel,
    required this.onToggleMargins,
    required this.onToggleColumns,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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

            // Adjust margins
            _PanelToggleButton(
              icon:    Icons.format_indent_increase,
              tooltip: 'Adjust Margins',
              active:  activePanel == _ActivePanel.margins,
              onTap:   onToggleMargins,
            ),

            const SizedBox(width: 4),

            // Column widths — shown for both preview types
            _PanelToggleButton(
              icon:    Icons.view_column_outlined,
              tooltip: 'Column Widths',
              active:  activePanel == _ActivePanel.columns,
              onTap:   onToggleColumns,
            ),

            const SizedBox(width: 8),

            if (exporting)
              const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              OutlinedButton.icon(
                onPressed: onExportPdf,
                icon:  const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Save PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade400),
                ),
              ),
            ],

            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onClose,
              icon:  const Icon(Icons.close, size: 16),
              label: const Text('Close'),
            ),
          ],
        ),
      );
}

class _PanelToggleButton extends StatelessWidget {
  final IconData    icon;
  final String      tooltip;
  final bool        active;
  final VoidCallback onTap;

  const _PanelToggleButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: 18,
            color: active ? AppColors.indigo600 : AppColors.slate500),
        tooltip: tooltip,
        onPressed: onTap,
        style: active
            ? IconButton.styleFrom(
                backgroundColor: AppColors.indigo50,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
              )
            : null,
      );
}

// ── Generic column-width panel ─────────────────────────────────────────────────
// Decoupled from any specific widths class. The parent passes:
//   • entries    — ordered (label, currentWidth) list
//   • totalWidth — sum of all current widths (for the indicator line)
//   • onChanged  — called with (columnIndex, newValue) on every keystroke
//   • onReset    — resets to defaults (parent rebuilds with const defaults)
class _ColWidthPanel extends StatefulWidget {
  final List<(String, double)>          entries;
  final double                          totalWidth;
  final void Function(int, double)      onChanged;
  final VoidCallback                    onReset;

  const _ColWidthPanel({
    required this.entries,
    required this.totalWidth,
    required this.onChanged,
    required this.onReset,
  });

  @override
  State<_ColWidthPanel> createState() => _ColWidthPanelState();
}

class _ColWidthPanelState extends State<_ColWidthPanel> {
  late List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = _buildCtrls(widget.entries);
  }

  List<TextEditingController> _buildCtrls(List<(String, double)> entries) =>
      entries.map((e) => TextEditingController(text: e.$2.toStringAsFixed(0))).toList();

  @override
  void didUpdateWidget(covariant _ColWidthPanel old) {
    super.didUpdateWidget(old);
    // When entries count changes (switching invoice ↔ bank), rebuild controllers.
    if (old.entries.length != widget.entries.length) {
      for (final c in _ctrls) c.dispose();
      _ctrls = _buildCtrls(widget.entries);
      return;
    }
    // Sync values if a reset happened externally (text unchanged by user).
    for (var i = 0; i < widget.entries.length; i++) {
      final newText = widget.entries[i].$2.toStringAsFixed(0);
      if (_ctrls[i].text != newText) _ctrls[i].text = newText;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  void _onReset() {
    widget.onReset();
    // Controllers are synced in didUpdateWidget after the parent rebuilds.
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 168,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.slate200)),
          color: AppColors.slate50,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: AppColors.slate200))),
              child: Row(children: [
                Expanded(
                    child: Text('Column Widths', style: AppTextStyles.label)),
                Tooltip(
                  message: 'Reset to defaults',
                  child: InkWell(
                    onTap: _onReset,
                    borderRadius: BorderRadius.circular(4),
                    child: const Icon(Icons.restart_alt,
                        size: 15, color: AppColors.slate400),
                  ),
                ),
              ]),
            ),

            // Total width indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Total: ${widget.totalWidth.toStringAsFixed(0)} px',
                style: AppTextStyles.small.copyWith(
                  color: AppColors.slate500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            // One row per column
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: widget.entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final label = widget.entries[i].$1;
                  return Row(children: [
                    SizedBox(
                      width: 68,
                      child: Text(label,
                          style: AppTextStyles.small,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _ctrls[i],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: AppTextStyles.input,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: 'px',
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v);
                            if (val != null && val >= 10)
                              widget.onChanged(i, val);
                          },
                        ),
                      ),
                    ),
                  ]);
                },
              ),
            ),
          ],
        ),
      );
}

// ── Margin panel ───────────────────────────────────────────────────────────────
class _MarginPanel extends StatefulWidget {
  final MarginSettingsNotifier       notifier;
  final bool                         showTargetSelector;
  final _MarginTarget                target;
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
        'top':    TextEditingController(text: s.top.toStringAsFixed(1)),
        'bottom': TextEditingController(text: s.bottom.toStringAsFixed(1)),
        'left':   TextEditingController(text: s.left.toStringAsFixed(1)),
        'right':  TextEditingController(text: s.right.toStringAsFixed(1)),
      };

  void _disposeCtrls() { for (final c in _ctrls.values) c.dispose(); }

  @override
  void didUpdateWidget(covariant _MarginPanel old) {
    super.didUpdateWidget(old);
    if (old.notifier != widget.notifier) {
      _disposeCtrls();
      _ctrls = _buildCtrls(widget.notifier.settings);
    }
  }

  @override
  void dispose() { _disposeCtrls(); super.dispose(); }

  void _apply() => widget.notifier.update(MarginSettings(
        top:    double.tryParse(_ctrls['top']!.text)    ?? 24,
        bottom: double.tryParse(_ctrls['bottom']!.text) ?? 24,
        left:   double.tryParse(_ctrls['left']!.text)   ?? 24,
        right:  double.tryParse(_ctrls['right']!.text)  ?? 24,
      ));

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
            if (widget.showTargetSelector) ...[
              _TargetSelector(
                current:   widget.target,
                onChanged: widget.onTargetChanged,
              ),
              const SizedBox(height: 12),
            ],
            _MarginDiagram(notifier: widget.notifier),
            const SizedBox(height: 16),
            for (final side in ['top', 'bottom', 'left', 'right']) ...[
              Text(side[0].toUpperCase() + side.substring(1),
                  style: AppTextStyles.small),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: TextField(
                  controller: _ctrls[side],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: AppTextStyles.input,
                  decoration: const InputDecoration(
                      isDense: true, suffixText: 'px'),
                  onChanged: (_) => _apply(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _TargetSelector extends StatelessWidget {
  final _MarginTarget                current;
  final void Function(_MarginTarget) onChanged;
  const _TargetSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Column(children: [
          _tile('Tax Invoice', 'Bill',               _MarginTarget.taxInvoice),
          const Divider(height: 1, thickness: 1, color: AppColors.slate200),
          _tile('Voucher',     'Expenses Statement', _MarginTarget.voucherPdf),
        ]),
      );

  Widget _tile(String label, String sub, _MarginTarget target) {
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
        child: Row(children: [
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
                  Text(label,
                      style: AppTextStyles.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? AppColors.indigo600
                            : AppColors.slate700,
                      )),
                  Text(sub,
                      style: AppTextStyles.small.copyWith(
                          fontSize: 10, color: AppColors.slate400)),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _MarginDiagram extends StatelessWidget {
  final MarginSettingsNotifier notifier;
  const _MarginDiagram({required this.notifier});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: notifier,
        builder: (_, __) {
          final s = notifier.settings;
          const maxM = 80.0, boxW = 80.0, boxH = 100.0;
          return Center(
            child: SizedBox(
              width: boxW, height: boxH,
              child: Stack(children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.slate400),
                  ),
                ),
                Positioned(
                  top:    (s.top    / maxM * 20).clamp(2, 30),
                  bottom: (s.bottom / maxM * 20).clamp(2, 30),
                  left:   (s.left   / maxM * 20).clamp(2, 30),
                  right:  (s.right  / maxM * 20).clamp(2, 30),
                  child: Container(
                    color: AppColors.slate100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        4,
                        (_) => Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 3),
                          child: Container(
                              height: 3, color: AppColors.slate300),
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