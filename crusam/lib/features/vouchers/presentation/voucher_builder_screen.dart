import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../notifiers/voucher_notifier.dart';
import '../widgets/voucher_row_widget.dart';
import '../widgets/calculations_card.dart';
import '../widgets/bank_split_card.dart';
import '../widgets/invoice_preview_dialog.dart';

class VoucherBuilderScreen extends StatefulWidget {
  const VoucherBuilderScreen({super.key});
  @override
  State<VoucherBuilderScreen> createState() => _VoucherBuilderScreenState();
}

class _VoucherBuilderScreenState extends State<VoucherBuilderScreen> {
  final _notifier = VoucherNotifier();

  @override
  void initState() {
    super.initState();
    _notifier.loadDependencies();
  }

  @override
  void dispose() {
    _notifier.dispose();
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
      if (_notifier.isLoading) return const Center(child: CircularProgressIndicator());
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
                Expanded(child: BankSplitCard(
                  idbiToOther: _notifier.idbiToOther,
                  idbiToIdbi:  _notifier.idbiToIdbi,
                  baseTotal:   _notifier.baseTotal,
                )),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: CalculationsCard(
                  baseTotal:  _notifier.baseTotal,
                  cgst:       _notifier.cgst,
                  sgst:       _notifier.sgst,
                  roundOff:   _notifier.roundOff,
                  finalTotal: _notifier.finalTotal,
                )),
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

class _MetadataCard extends StatelessWidget {
  final VoucherNotifier notifier;
  const _MetadataCard({required this.notifier});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _labelField('Voucher Title', child:
            TextField(
              onChanged: (v) => notifier.update((c) => c.copyWith(title: v)),
              decoration: const InputDecoration(hintText: 'e.g. Exp. MAR-2026 aarti'),
            ),
          )),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _labelField('Department Code', child:
            DropdownButtonFormField<String>(
              initialValue: notifier.current.deptCode,
              onChanged: (v) { if (v != null) notifier.update((c) => c.copyWith(deptCode: v)); },
              items: AppConstants.deptCodes.map((d) =>
                  DropdownMenuItem(value: d, child: Text(d))).toList(),
              decoration: const InputDecoration(),
            ),
          )),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _labelField('Date', child:
            TextField(
              controller: TextEditingController(text: notifier.current.date),
              readOnly: true,
              onTap: () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(notifier.current.date) ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100),
                );
                if (p != null) notifier.update((c) => c.copyWith(date: p.toIso8601String().split('T').first));
              },
              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 16)),
            ),
          )),
        ]),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(child: _labelField('Client Name', child:
            TextField(
              onChanged: (v) => notifier.update((c) => c.copyWith(clientName: v)),
              controller: TextEditingController(text: notifier.current.clientName),
            ),
          )),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _labelField('Client GSTIN', child:
            TextField(
              onChanged: (v) => notifier.update((c) => c.copyWith(clientGstin: v)),
              controller: TextEditingController(text: notifier.current.clientGstin),
            ),
          )),
        ]),
        const SizedBox(height: AppSpacing.md),
        _labelField('Item Description (for Invoice)', child:
          DropdownButtonFormField<String>(
            initialValue: notifier.current.itemDescription,
            isExpanded: true,
            onChanged: (v) { if (v != null) notifier.update((c) => c.copyWith(itemDescription: v)); },
            items: AppConstants.itemDescriptions.map((d) =>
                DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
            decoration: const InputDecoration(),
          ),
        ),
      ],
    ),
  );

  static Widget _labelField(String label, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate700)),
      const SizedBox(height: 6),
      child,
    ],
  );
}

class _RowsTable extends StatelessWidget {
  final VoucherNotifier notifier;
  const _RowsTable({required this.notifier});

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
                TableRow(
                  decoration: const BoxDecoration(
                    color: AppColors.slate50,
                    border: Border(
                      top: BorderSide(color: AppColors.slate200),
                      bottom: BorderSide(color: AppColors.slate200),
                    ),
                  ),
                  children: ['#','Employee Name','Amount','From Date','To Date','Auto-filled Details','']
                      .map((h) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            child: Text(h, style: AppTextStyles.label),
                          ))
                      .toList(),
                ),
                ...notifier.current.rows.asMap().entries.map((e) => buildVoucherRow(
                  index:             e.key,
                  row:               e.value,
                  employees:         notifier.employees,
                  onSelectEmployee:  (empId) => notifier.selectEmployee(e.value.id, empId),
                  onAmountChanged:   (amt)   => notifier.updateRow(e.value.id, (r) => r.copyWith(amount: amt)),
                  onFromDateChanged: (d)     => notifier.updateRow(e.value.id, (r) => r.copyWith(fromDate: d)),
                  onToDateChanged:   (d)     => notifier.updateRow(e.value.id, (r) => r.copyWith(toDate: d)),
                  onRemove:                  () => notifier.removeRow(e.value.id),
                )),
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
        onPressed: () {},
        icon: const Icon(Icons.save_outlined, size: 16),
        label: const Text('Save as Draft'),
      ),
      OutlinedButton.icon(
        onPressed: onSave,
        icon: const Icon(Icons.save, size: 16),
        label: const Text('Save Invoice'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.emerald700,
          side: const BorderSide(color: AppColors.emerald100),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => InvoicePreviewDialog.show(context, notifier.enriched, notifier.config, PreviewType.invoice),
        icon: const Icon(Icons.description_outlined, size: 16),
        label: const Text('Preview Invoice'),
      ),
      OutlinedButton.icon(
        onPressed: () => InvoicePreviewDialog.show(context, notifier.enriched, notifier.config, PreviewType.bank),
        icon: const Icon(Icons.account_balance_outlined, size: 16),
        label: const Text('Preview Bank Sheet'),
      ),
      ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.file_download_outlined, size: 16),
        label: const Text('Finalise & Export'),
      ),
    ],
  );
}