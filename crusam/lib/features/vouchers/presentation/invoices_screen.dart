import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<VoucherModel> _vouchers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vMaps = await DatabaseHelper.instance.getAllVouchers();
    final loaded = <VoucherModel>[];
    for (final v in vMaps) {
      final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
      loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
    }
    if (mounted) setState(() { _vouchers = loaded; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.pagePadding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            child: AppCard(
              padding: EdgeInsets.zero,
              child: _vouchers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Text('No invoices generated yet.\nFinalise a voucher to create one.',
                            textAlign: TextAlign.center),
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
                              icon: const Icon(Icons.description_outlined, size: 17, color: AppColors.slate400),
                              onPressed: () {},
                              tooltip: 'View',
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