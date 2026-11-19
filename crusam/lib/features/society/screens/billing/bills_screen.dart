import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/export_menu.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_filter_bar.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  bool _loading = false;
  String? _error;
  List<Bill> _bills = [];
  int _total = 0;
  int _page = 1;
  final int _pageSize = 50;

  String? _statusFilter;
  String? _kindFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final res = await services.billing.listBills(
        societyId,
        status: _statusFilter,
        billKind: _kindFilter,
        page: PageRequest(limit: _pageSize, offset: (_page - 1) * _pageSize),
      );
      if (mounted) {
        setState(() {
          _bills = res.rows;
          _total = res.total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Bills',
      subtitle: 'Member maintenance invoices, supplementary bills, and debit notes',
      actions: [
        ExportMenu(
          onExportExcel: () async {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel export ready.')));
          },
          onExportPdf: () async {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bulk PDF ready.')));
          },
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => context.go('/society/bills/new'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Manual Bill'),
        ),
      ],
      filters: Row(
        children: [
          DropdownButton<String?>(
            value: _statusFilter,
            hint: const Text('All Statuses'),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Statuses')),
              DropdownMenuItem(value: 'draft', child: Text('Draft')),
              DropdownMenuItem(value: 'posted', child: Text('Posted')),
              DropdownMenuItem(value: 'reversed', child: Text('Reversed')),
            ],
            onChanged: (v) {
              setState(() {
                _statusFilter = v;
                _page = 1;
              });
              _load();
            },
          ),
          const SizedBox(width: 16),
          DropdownButton<String?>(
            value: _kindFilter,
            hint: const Text('All Kinds'),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Kinds')),
              DropdownMenuItem(value: 'regular', child: Text('Regular')),
              DropdownMenuItem(value: 'manual', child: Text('Manual')),
              DropdownMenuItem(value: 'debit_note', child: Text('Debit Note')),
              DropdownMenuItem(value: 'supplementary', child: Text('Supplementary')),
            ],
            onChanged: (v) {
              setState(() {
                _kindFilter = v;
                _page = 1;
              });
              _load();
            },
          ),
        ],
      ),
      child: _error != null
          ? SocietyErrorView(message: _error!, onRetry: _load)
          : _loading && _bills.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : _bills.isEmpty
                  ? SocietyEmptyView(
                      icon: Icons.receipt_long_outlined,
                      title: 'No Bills Found',
                      message: 'Post a Bill Run or create a Manual Bill.',
                      action: FilledButton(
                        onPressed: () => context.go('/society/bills/new'),
                        child: const Text('Create Manual Bill'),
                      ),
                    )
                  : SocietyDataTable<Bill>(
                      columns: [
                        SocietyColumn<Bill>(
                          label: 'Bill No',
                          cell: (b) => Text(b.billNo ?? '(Draft)', style: const TextStyle(fontWeight: FontWeight.w600)),
                          width: 150,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Date',
                          cell: (b) => Text(b.billDate),
                          width: 110,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Due Date',
                          cell: (b) => Text(b.dueDate),
                          width: 110,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Unit',
                          cell: (b) => Text('${b.blockName}-${b.unitNo}'),
                          width: 100,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Bill-To',
                          cell: (b) => Text(b.billToName),
                          width: 160,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Kind',
                          cell: (b) => Text(b.billKind.replaceAll('_', ' ')),
                          width: 110,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Total Amount',
                          cell: (b) => Text(formatPaise(b.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          numeric: true,
                          width: 130,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Status',
                          cell: (b) => StatusChip(status: b.status),
                          width: 100,
                        ),
                        SocietyColumn<Bill>(
                          label: 'Action',
                          cell: (b) => TextButton(
                            child: const Text('View'),
                            onPressed: () => context.go('/society/bills/${b.id}'),
                          ),
                          width: 80,
                        ),
                      ],
                      rows: _bills,
                      total: _total,
                      page: _page,
                      pageSize: _pageSize,
                      onPage: (p) {
                        setState(() => _page = p);
                        _load();
                      },
                      onRowTap: (b) => context.go('/society/bills/${b.id}'),
                    ),
    );
  }
}
