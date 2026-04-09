import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/voucher_model.dart';
import '../../../shared/widgets/app_card.dart';
import '../notifiers/item_description_notifier.dart';
import '../notifiers/voucher_notifier.dart';
import '../widgets/voucher_row_widget.dart' as voucher_row_widget;
import '../widgets/calculations_card.dart';
import '../widgets/bank_split_card.dart';
import '../widgets/invoice_preview_dialog.dart';
import '../widgets/item_description_field.dart';

class VoucherBuilderScreen extends StatefulWidget {
  const VoucherBuilderScreen({super.key});
  @override
  State<VoucherBuilderScreen> createState() => _VoucherBuilderScreenState();
}

class _VoucherBuilderScreenState extends State<VoucherBuilderScreen> {
  final _notifier = VoucherNotifier.instance;

  @override
  void initState() {
    super.initState();
    _notifier.loadDependencies();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _saveVoucher() async {
    if (_notifier.current.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a voucher title')),
      );
      return;
    }
    final ok = await _notifier.saveVoucher();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Invoice saved successfully' : 'Error saving invoice')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _notifier,
        builder: (ctx, _) {
          if (_notifier.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MetadataCard(notifier: _notifier),
                const SizedBox(height: AppSpacing.xl),
                _RowsTable(notifier: _notifier),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BankSplitCard(
                        idbiToOther: _notifier.idbiToOther,
                        idbiToIdbi: _notifier.idbiToIdbi,
                        baseTotal: _notifier.baseTotal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: CalculationsCard(
                        baseTotal: _notifier.baseTotal,
                        cgst: _notifier.cgst,
                        sgst: _notifier.sgst,
                        roundOff: _notifier.roundOff,
                        finalTotal: _notifier.finalTotal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _ActionButtons(notifier: _notifier, onSave: _saveVoucher),
              ],
            ),
          );
        },
      );
}

// ── Metadata Card ─────────────────────────────────────────────────────────────

class _MetadataCard extends StatefulWidget {
  final VoucherNotifier notifier;
  const _MetadataCard({required this.notifier});

  @override
  State<_MetadataCard> createState() => _MetadataCardState();
}

class _MetadataCardState extends State<_MetadataCard> {
  late final TextEditingController _titleCtrl = TextEditingController();
  late final TextEditingController _dateCtrl  = TextEditingController();
  late final TextEditingController _clientCtrl = TextEditingController();
  late final TextEditingController _gstnCtrl   = TextEditingController();
  late final TextEditingController _addressCtrl = TextEditingController();
  late final ItemDescriptionNotifier _descNotifier = ItemDescriptionNotifier();

  @override
  void initState() {
    super.initState();
    _syncFromNotifier(widget.notifier.current);
    _descNotifier.load();
    widget.notifier.addListener(_onVoucherChanged);
  }

  @override
  void didUpdateWidget(covariant _MetadataCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.removeListener(_onVoucherChanged);
      _syncFromNotifier(widget.notifier.current);
      widget.notifier.addListener(_onVoucherChanged);
    }
  }

  void _syncFromNotifier(VoucherModel c) {
    if (_titleCtrl.text   != c.title)         _titleCtrl.text   = c.title;
    if (_dateCtrl.text    != c.date)          _dateCtrl.text    = c.date;
    if (_clientCtrl.text  != c.clientName)    _clientCtrl.text  = c.clientName;
    if (_gstnCtrl.text    != c.clientGstin)   _gstnCtrl.text    = c.clientGstin;
    if (_addressCtrl.text != c.clientAddress) _addressCtrl.text = c.clientAddress;
  }

  void _onVoucherChanged() {
    final c = widget.notifier.current;
    if (_titleCtrl.text != c.title || _dateCtrl.text != c.date ||
        _clientCtrl.text != c.clientName || _gstnCtrl.text != c.clientGstin ||
        _addressCtrl.text != c.clientAddress) {
      _syncFromNotifier(c);
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onVoucherChanged);
    _titleCtrl.dispose(); _dateCtrl.dispose(); _clientCtrl.dispose();
    _gstnCtrl.dispose();  _addressCtrl.dispose(); _descNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: Title (flex 4) | Dept (flex 2) | Date (flex 2) ──────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: _lf('Voucher Title',
                  TextField(
                    controller: _titleCtrl,
                    onChanged: (v) => widget.notifier.update((c) => c.copyWith(title: v)),
                    style: AppTextStyles.input,
                    decoration: const InputDecoration(hintText: 'e.g. Exp. MAR-2026 aarti'),
                  ),
                )),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _lf('Department Code',
                  DropdownButtonFormField<String>(
                    key: ValueKey(widget.notifier.current.deptCode),
                    value: widget.notifier.current.deptCode,
                    style: AppTextStyles.input,
                    onChanged: (v) { if (v != null) widget.notifier.update((c) => c.copyWith(deptCode: v)); },
                    items: AppConstants.deptCodes
                        .map((d) => DropdownMenuItem(value: d, child: Text(d, style: AppTextStyles.input)))
                        .toList(),
                    decoration: const InputDecoration(),
                  ),
                )),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _lf('Date',
                  TextField(
                    controller: _dateCtrl,
                    style: AppTextStyles.input,
                    readOnly: true,
                    onTap: () async {
                      final p = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(widget.notifier.current.date) ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (!mounted) return;
                      if (p != null) widget.notifier.update((c) => c.copyWith(date: p.toIso8601String().split('T').first));
                    },
                    decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 16)),
                  ),
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Row 2: Client Name (flex 3) | GSTIN (flex 2) ─────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _lf('Client Name',
                  TextField(
                    controller: _clientCtrl,
                    onChanged: (v) => widget.notifier.update((c) => c.copyWith(clientName: v)),
                    style: AppTextStyles.input,
                  ),
                )),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: _lf('Client GSTIN',
                  TextField(
                    controller: _gstnCtrl,
                    onChanged: (v) => widget.notifier.update((c) => c.copyWith(clientGstin: v)),
                    style: AppTextStyles.input,
                  ),
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Row 3: Address (full width) ───────────────────────────────
            _lf('Client Address',
              TextField(
                controller: _addressCtrl,
                onChanged: (v) => widget.notifier.update((c) => c.copyWith(clientAddress: v)),
                style: AppTextStyles.input,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Row 4: Item Description ───────────────────────────────────
            _lf('Item Description (for Invoice)',
              ItemDescriptionField(
                value: widget.notifier.current.itemDescription,
                onChanged: (v) => widget.notifier.update((c) => c.copyWith(itemDescription: v)),
                notifier: _descNotifier,
              ),
            ),
          ],
        ),
      );

  static Widget _lf(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.smallMedium.copyWith(
              color: AppColors.slate600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

// ── Rows Table ────────────────────────────────────────────────────────────────

class _RowsTable extends StatelessWidget {
  final VoucherNotifier notifier;
  const _RowsTable({required this.notifier});

  static const _headers = ['#', 'Employee Name', 'Amount', 'From Date', 'To Date', 'Auto-filled Details', ''];

  // ── column flex ratios (index → flex int OR null for fixed px) ────────────
  // We compute widths via LayoutBuilder so every pixel is used.
  // Fixed cols: # = 36, delete = 44
  // Flex cols share the remainder in ratio 3.2 : 1.4 : 1.6 : 1.6 : 3.0
  static const _fixedLeft  = 36.0;
  static const _fixedRight = 44.0;
  static const _flex       = [3.0, 2.0, 1.6, 1.6, 3.0]; // emp, amt, fr, to, auto

  Map<int, TableColumnWidth> _colWidths(double totalWidth) {
    final available = totalWidth - _fixedLeft - _fixedRight;
    final sum = _flex.fold(0.0, (a, b) => a + b);
    final widths = _flex.map((f) => available * f / sum).toList();
    return {
      0: const FixedColumnWidth(_fixedLeft),
      1: FixedColumnWidth(widths[0]),
      2: FixedColumnWidth(widths[1]),
      3: FixedColumnWidth(widths[2]),
      4: FixedColumnWidth(widths[3]),
      5: FixedColumnWidth(widths[4]),
      6: const FixedColumnWidth(_fixedRight),
    };
  }

  TableRow _headerRow(Map<int, TableColumnWidth> _) => TableRow(
        decoration: const BoxDecoration(
          color: AppColors.slate50,
          border: Border(
            bottom: BorderSide(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),),
          
        ),
        children: _headers.map((h) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(h, style: AppTextStyles.label.copyWith(
                  color: AppColors.slate500, fontWeight: FontWeight.w700)),
            )).toList(growable: false),
      );

  List<TableRow> _dataRows() {
    final counts = <String, int>{};
    for (final r in notifier.current.rows) {
      if (r.employeeId.isNotEmpty) counts[r.employeeId] = (counts[r.employeeId] ?? 0) + 1;
    }
    return List.generate(notifier.current.rows.length, (i) {
      final row = notifier.current.rows[i];
      final dup = row.employeeId.isNotEmpty && (counts[row.employeeId] ?? 0) > 1;
      return voucher_row_widget.buildVoucherRow(
        index: i,
        row: row,
        employees: notifier.employees,
        onSelectEmployee: (id) => notifier.selectEmployee(row.id, id),
        onAmountChanged: (a) => notifier.updateRow(row.id, (r) => r.copyWith(amount: a)),
        onFromDateChanged: (d) => notifier.updateRow(row.id, (r) => r.copyWith(fromDate: d)),
        onToDateChanged: (d) => notifier.updateRow(row.id, (r) => r.copyWith(toDate: d)),
        onRemove: () => notifier.removeRow(row.id),
        highlight: dup,
      );
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),
          
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radius - 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header bar ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  border: const Border(bottom: BorderSide(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5)),
                  
                  ),
                child: Row(children: [
                  Text('Labour Disbursement Details',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '${notifier.current.rows.length} row${notifier.current.rows.length == 1 ? '' : 's'}',
                    style: AppTextStyles.small,
                  ),
                ]),
              ),
              // ── Full-width Table via LayoutBuilder ──────────────────────
              LayoutBuilder(builder: (ctx, constraints) {
                final colWidths = _colWidths(constraints.maxWidth);
                return Table(
                  columnWidths: colWidths,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    _headerRow(colWidths),
                    ..._dataRows(),
                  ],
                );
              }),
              // ── Empty state ─────────────────────────────────────────────
              if (notifier.current.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(children: [
                    Icon(Icons.table_rows_outlined, size: 36, color: AppColors.slate300),
                    const SizedBox(height: 8),
                    Text('No rows yet.', style: AppTextStyles.small),
                  ]),
                ),
              // ── Add Row CTA ─────────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.slate200)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: TextButton.icon(
                    onPressed: notifier.addRow,
                    icon: const Icon(Icons.add_circle_outline, size: 17, color: AppColors.indigo600),
                    label: Text('+ Add Row',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.indigo600,
                          fontWeight: FontWeight.w600,
                        )),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      backgroundColor: AppColors.indigo50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Action Buttons ────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final VoucherNotifier notifier;
  final VoidCallback onSave;
  const _ActionButtons({required this.notifier, required this.onSave});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dc) => AlertDialog(
                  title: const Text('Discard Draft'),
                  content: const Text('This will clear all current progress. Cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(dc, true),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF11083D)),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await notifier.discardDraft();
                });
              }
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Discard Draft'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFAE3E3)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Save as Draft'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.emerald100),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => InvoicePreviewDialog.show(context, notifier, notifier.config, PreviewType.invoice),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Preview Invoice'),
          ),
          OutlinedButton.icon(
            onPressed: () => InvoicePreviewDialog.show(context, notifier, notifier.config, PreviewType.bank),
            icon: const Icon(Icons.account_balance_outlined, size: 16),
            label: const Text('Preview Bank Sheet'),
          ),
          ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('Finalise & Export'),
          ),
        ],
      );
}