import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../notifiers/voucher_notifier.dart';
import '../widgets/invoice_preview_dialog.dart';
import 'package:go_router/go_router.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<VoucherModel> _vouchers = [];
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vMaps = await DatabaseHelper.instance.getAllVouchers();
    final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
    if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);
    final loaded = <VoucherModel>[];
    for (final v in vMaps) {
      final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
      loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
    }
    if (mounted) setState(() { _vouchers = loaded; _loading = false; });
  }

  Future<void> _deleteVoucher(VoucherModel v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Delete "${v.title.isEmpty ? "(Untitled)" : v.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && v.id != null) {
      await DatabaseHelper.instance.deleteVoucher(v.id!);
      await _load();
    }
  }

  void _editVoucher(BuildContext context, VoucherModel v) {
    // Confirm before overwriting any unsaved work in the builder
    final hasUnsavedWork = VoucherNotifier.instance.current.rows.isNotEmpty ||
        VoucherNotifier.instance.current.title.isNotEmpty;

    if (!hasUnsavedWork) {
      _loadIntoBuilder(context, v);
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Overwrite Current Draft?'),
        content: const Text(
          'The Voucher Builder has unsaved work.\n'
          'Loading this invoice will replace it. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.indigo600),
            child: const Text('Load Invoice'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) _loadIntoBuilder(context, v);
    });
  }

  void _loadIntoBuilder(BuildContext context, VoucherModel v) {
    // Push voucher into the singleton so VoucherBuilderScreen picks it up
    VoucherNotifier.instance.update((_) => v);
    context.go('/vouchers');
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.pagePadding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Generated Invoices', style: AppTextStyles.h3),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export List'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              clipBehavior: Clip.antiAlias, // ← THIS FIXES THE ROUNDED CORNERS
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: _vouchers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Text(
                          'No invoices generated yet.\nFinalise a voucher to create one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Bill No')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Voucher Ref')),
                          DataColumn(label: Text('Dept')),
                          DataColumn(label: Text('Amount'), numeric: true),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _vouchers.map((v) => DataRow(cells: [
                          DataCell(Text(
                            'AE-${v.id?.toString().padLeft(4, '0') ?? '----'}',
                            style: AppTextStyles.bodySemi.copyWith(color: AppColors.indigo600, fontSize: 13),
                          )),
                          DataCell(Text(v.date)),
                          DataCell(Text(v.title.isEmpty ? '(Untitled)' : v.title)),
                          DataCell(Text(v.deptCode)),
                          DataCell(Text(formatCurrency(v.finalTotal),
                              style: AppTextStyles.bodySemi.copyWith(fontSize: 13))),
                          DataCell(_StatusBadge(status: v.status)),
                          DataCell(Row(children: [
                            IconButton(
                              icon: const Icon(Icons.download_outlined, size: 17, color: AppColors.slate400),
                              onPressed: () {},
                              tooltip: 'Download',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.indigo600),
                              onPressed: () => _editVoucher(context, v),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.description_outlined, size: 17, color: AppColors.indigo600),
                              onPressed: () {
                                final previewNotifier = VoucherNotifier()..current = v;
                                InvoicePreviewDialog.show(
                                  context,
                                  previewNotifier,
                                  _config,
                                  PreviewType.invoice,
                                );
                              },
                              tooltip: 'View',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                              onPressed: () => _deleteVoucher(v),
                              tooltip: 'Delete',
                            ),
                          ])),
                        ])).toList(),
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final VoucherStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final saved = status == VoucherStatus.saved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: saved ? AppColors.emerald100 : AppColors.amber100,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: saved ? AppColors.emerald700 : AppColors.amber700),
      ),
    );
  }
}