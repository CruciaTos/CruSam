import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class BillRunsScreen extends StatefulWidget {
  const BillRunsScreen({super.key});

  @override
  State<BillRunsScreen> createState() => _BillRunsScreenState();
}

class _BillRunsScreenState extends State<BillRunsScreen> {
  bool _loading = false;
  String? _error;
  List<BillRun> _runs = [];
  int _total = 0;
  int _page = 1;
  final int _pageSize = 50;

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
      final res = await services.billing.listBillRuns(
        societyId,
        page: PageRequest(limit: _pageSize, offset: (_page - 1) * _pageSize),
      );
      if (mounted) {
        setState(() {
          _runs = res.rows;
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
      title: 'Bill Runs',
      subtitle: 'Batch generation and posting of member maintenance and utility bills',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/society/bill-runs/new'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Bill Run'),
        ),
      ],
      child: _error != null
          ? SocietyErrorView(message: _error!, onRetry: _load)
          : _loading && _runs.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : _runs.isEmpty
                  ? SocietyEmptyView(
                      icon: Icons.playlist_add_check_outlined,
                      title: 'No Bill Runs Found',
                      message: 'Generate periodic maintenance bills for all units at once.',
                      action: FilledButton.icon(
                        onPressed: () => context.go('/society/bill-runs/new'),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Bill Run'),
                      ),
                    )
                  : SocietyDataTable<BillRun>(
                      columns: [
                        SocietyColumn<BillRun>(
                          label: 'Period',
                          cell: (r) => Text('${r.periodFrom} to ${r.periodTo}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          width: 200,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Frequency',
                          cell: (r) => Text(r.frequency[0].toUpperCase() + r.frequency.substring(1)),
                          width: 120,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Bill Date',
                          cell: (r) => Text(r.billDate),
                          width: 120,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Due Date',
                          cell: (r) => Text(r.dueDate),
                          width: 120,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Bills',
                          cell: (r) => Text('${r.billCount}'),
                          numeric: true,
                          width: 80,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Total Amount',
                          cell: (r) => Text(formatPaise(r.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          numeric: true,
                          width: 140,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Status',
                          cell: (r) => StatusChip(status: r.status),
                          width: 110,
                        ),
                        SocietyColumn<BillRun>(
                          label: 'Action',
                          cell: (r) => TextButton(
                            child: const Text('View'),
                            onPressed: () => context.go('/society/bill-runs/${r.id}'),
                          ),
                          width: 90,
                        ),
                      ],
                      rows: _runs,
                      total: _total,
                      page: _page,
                      pageSize: _pageSize,
                      onPage: (p) {
                        setState(() => _page = p);
                        _load();
                      },
                      onRowTap: (r) => context.go('/society/bill-runs/${r.id}'),
                    ),
    );
  }
}
