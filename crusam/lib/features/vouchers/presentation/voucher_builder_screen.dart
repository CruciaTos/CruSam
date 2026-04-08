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
    // DO NOT dispose the singleton notifier here
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

class _MetadataCard extends StatefulWidget {
  final VoucherNotifier notifier;
  const _MetadataCard({required this.notifier});

  @override
  State<_MetadataCard> createState() => _MetadataCardState();
}

class _MetadataCardState extends State<_MetadataCard> {
  late final TextEditingController _titleCtrl = TextEditingController();
  late final TextEditingController _dateCtrl = TextEditingController();
  late final TextEditingController _clientCtrl = TextEditingController();
  late final TextEditingController _gstnCtrl = TextEditingController();
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

  void _syncFromNotifier(VoucherModel current) {
    if (_titleCtrl.text != current.title) _titleCtrl.text = current.title;
    if (_dateCtrl.text != current.date) _dateCtrl.text = current.date;
    if (_clientCtrl.text != current.clientName) _clientCtrl.text = current.clientName;
    if (_gstnCtrl.text != current.clientGstin) _gstnCtrl.text = current.clientGstin;
    if (_addressCtrl.text != current.clientAddress) {
      _addressCtrl.text = current.clientAddress;
    }
  }

  void _onVoucherChanged() {
    final current = widget.notifier.current;
    if (_titleCtrl.text != current.title ||
        _dateCtrl.text != current.date ||
        _clientCtrl.text != current.clientName ||
        _gstnCtrl.text != current.clientGstin ||
        _addressCtrl.text != current.clientAddress) {
      _syncFromNotifier(current);
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onVoucherChanged);
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _clientCtrl.dispose();
    _gstnCtrl.dispose();
    _addressCtrl.dispose();
    _descNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _labelField(
                    'Voucher Title',
                    child: TextField(
                      controller: _titleCtrl,
                      onChanged: (v) =>
                          widget.notifier.update((c) => c.copyWith(title: v)),
                      style: AppTextStyles.input,
                      decoration:
                          const InputDecoration(hintText: 'e.g. Exp. MAR-2026 aarti'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _labelField(
                    'Department Code',
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(widget.notifier.current.deptCode),
                      // FIX: was `initialValue` which is not a valid parameter
                      value: widget.notifier.current.deptCode,
                      style: AppTextStyles.input,
                      onChanged: (v) {
                        if (v != null) {
                          widget.notifier.update((c) => c.copyWith(deptCode: v));
                        }
                      },
                      items: AppConstants.deptCodes
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text(d, style: AppTextStyles.input),
                              ))
                          .toList(),
                      decoration: const InputDecoration(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _labelField(
                    'Date',
                    child: TextField(
                      controller: _dateCtrl,
                      style: AppTextStyles.input,
                      readOnly: true,
                      onTap: () async {
                        final p = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(widget.notifier.current.date) ??
                                  DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (!mounted) return;
                        if (p != null) {
                          widget.notifier.update(
                            (c) => c.copyWith(
                                date: p.toIso8601String().split('T').first),
                          );
                        }
                      },
                      decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.calendar_today, size: 16)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _labelField(
                    'Client Name',
                    child: TextField(
                      onChanged: (v) => widget.notifier
                          .update((c) => c.copyWith(clientName: v)),
                      controller: _clientCtrl,
                      style: AppTextStyles.input,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _labelField(
                    'Client GSTIN',
                    child: TextField(
                      onChanged: (v) => widget.notifier
                          .update((c) => c.copyWith(clientGstin: v)),
                      controller: _gstnCtrl,
                      style: AppTextStyles.input,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _labelField(
                    'Client Address',
                    child: TextField(
                      controller: _addressCtrl,
                      onChanged: (v) => widget.notifier
                          .update((c) => c.copyWith(clientAddress: v)),
                      style: AppTextStyles.input,
                      maxLines: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _labelField(
              'Item Description (for Invoice)',
              child: ItemDescriptionField(
                value: widget.notifier.current.itemDescription,
                onChanged: (v) => widget.notifier
                    .update((c) => c.copyWith(itemDescription: v)),
                notifier: _descNotifier,
              ),
            ),
          ],
        ),
      );

  static Widget _labelField(String label, {required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate700)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class _RowsTable extends StatelessWidget {
  final VoucherNotifier notifier;
  const _RowsTable({required this.notifier});

  static const _headers = <String>[
    '#',
    'Employee Name',
    'Amount',
    'From Date',
    'To Date',
    'Auto-filled Details',
    '',
  ];

  TableRow _buildHeaderRow() => TableRow(
        decoration: const BoxDecoration(
          color: AppColors.slate50,
          border: Border(
            top: BorderSide(color: AppColors.slate200),
            bottom: BorderSide(color: AppColors.slate200),
          ),
        ),
        children: _headers
            .map((header) => Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Text(header, style: AppTextStyles.label),
                ))
            .toList(growable: false),
      );

  List<TableRow> _buildDataRows() => List<TableRow>.generate(
        notifier.current.rows.length,
        (index) {
          final row = notifier.current.rows[index];
          return voucher_row_widget.buildVoucherRow(
            index: index,
            row: row,
            employees: notifier.employees,
            onSelectEmployee: (empId) => notifier.selectEmployee(row.id, empId),
            onAmountChanged: (amt) =>
                notifier.updateRow(row.id, (r) => r.copyWith(amount: amt)),
            onFromDateChanged: (date) =>
                notifier.updateRow(row.id, (r) => r.copyWith(fromDate: date)),
            onToDateChanged: (date) =>
                notifier.updateRow(row.id, (r) => r.copyWith(toDate: date)),
            onRemove: () => notifier.removeRow(row.id),
          );
        },
        growable: false,
      );

  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 900),
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(40),
                    1: FixedColumnWidth(230),
                    2: FixedColumnWidth(100),
                    3: FixedColumnWidth(130),
                    4: FixedColumnWidth(130),
                    5: FlexColumnWidth(),
                    6: FixedColumnWidth(48),
                  },
                  children: [
                    _buildHeaderRow(),
                    ..._buildDataRows(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextButton.icon(
                onPressed: notifier.addRow,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Row'),
              ),
            ),
          ],
        ),
      );
}

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
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Discard Draft'),
                  content: const Text(
                    'This will clear all current progress. Cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: TextButton.styleFrom(foregroundColor: const Color.fromARGB(255, 17, 14, 61)),
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
              side: const BorderSide(color: Color.fromARGB(255, 250, 227, 227)),
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
            onPressed: () => InvoicePreviewDialog.show(
                context, notifier, notifier.config, PreviewType.invoice),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Preview Invoice'),
          ),
          OutlinedButton.icon(
            onPressed: () => InvoicePreviewDialog.show(
                context, notifier, notifier.config, PreviewType.bank),
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