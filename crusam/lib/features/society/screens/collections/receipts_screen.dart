import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  bool _loading = true;
  String? _error;
  List<Receipt> _receipts = [];
  int _total = 0;
  String _statusFilter = '';

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
      final res = await services.collection.listReceipts(
        societyId,
        status: _statusFilter.isEmpty ? null : _statusFilter,
        page: const PageRequest(limit: 100),
      );

      if (mounted) {
        setState(() {
          _receipts = res.rows;
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
      title: 'Member Receipts',
      subtitle: '$_total receipts recorded',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/society/import'),
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Import Receipts'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => context.go('/society/receipts/new'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Record Receipt'),
        ),
      ],
      filters: Row(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '', label: Text('All')),
              ButtonSegment(value: 'posted', label: Text('Posted')),
              ButtonSegment(value: 'reversed', label: Text('Reversed')),
            ],
            selected: {_statusFilter},
            onSelectionChanged: (set) {
              setState(() => _statusFilter = set.first);
              _load();
            },
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return SocietyErrorView(message: _error!, onRetry: _load);
    }
    if (_receipts.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.receipt_long,
        title: 'No receipts found',
        message: 'No member receipts match the selected filters.',
      );
    }

    return SocietyDataTable<Receipt>(
      total: _total,
      columns: [
        SocietyColumn<Receipt>(
          label: 'Receipt No',
          cell: (r) => Text(r.receiptNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 170,
        ),
        SocietyColumn<Receipt>(
          label: 'Date',
          cell: (r) => Text(r.receiptDate),
          width: 100,
        ),
        SocietyColumn<Receipt>(
          label: 'Unit',
          cell: (r) => Text('${r.blockName}-${r.unitNo}'),
          width: 100,
        ),
        SocietyColumn<Receipt>(
          label: 'Payer',
          cell: (r) => Text(r.payerName, overflow: TextOverflow.ellipsis),
          width: 180,
        ),
        SocietyColumn<Receipt>(
          label: 'Amount',
          cell: (r) => Text(formatInr(r.amountPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
          numeric: true,
        ),
        SocietyColumn<Receipt>(
          label: 'TDS',
          cell: (r) => Text(r.tdsPaise > 0 ? formatInr(r.tdsPaise) : '-'),
          width: 100,
          numeric: true,
        ),
        SocietyColumn<Receipt>(
          label: 'Mode',
          cell: (r) => Text(r.mode.toUpperCase()),
          width: 90,
        ),
        SocietyColumn<Receipt>(
          label: 'Status',
          cell: (r) => StatusChip(status: r.status),
          width: 100,
        ),
        SocietyColumn<Receipt>(
          label: 'Actions',
          cell: (r) => TextButton(
            onPressed: () => context.go('/society/receipts/${r.id}'),
            child: const Text('View'),
          ),
          width: 80,
        ),
      ],
      rows: _receipts,
      onRowTap: (r) => context.go('/society/receipts/${r.id}'),
    );
  }
}
