import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/collection_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  bool _loading = true;
  String? _error;
  List<UnitDueSummary> _allDues = [];
  List<UnitDueSummary> _filteredDues = [];

  final _searchController = TextEditingController();
  final _asOfController = TextEditingController();
  bool _overdueOnly = false;

  int _totalDues = 0;
  int _totalAdvance = 0;
  int _netDue = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _asOfController.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _asOfController.dispose();
    super.dispose();
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
      final dues = await services.collection.getDuesSummary(
        societyId,
        asOfDate: _asOfController.text.trim(),
      );

      var totDues = 0;
      var totAdv = 0;
      var net = 0;

      for (final d in dues) {
        if (d.netDuePaise > 0) totDues += d.netDuePaise;
        if (d.advancePaise > 0) totAdv += d.advancePaise;
        net += d.netDuePaise;
      }

      if (mounted) {
        setState(() {
          _allDues = dues;
          _totalDues = totDues;
          _totalAdvance = totAdv;
          _netDue = net;
          _loading = false;
        });
        _applyFilters();
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

  void _applyFilters() {
    final term = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredDues = _allDues.where((d) {
        if (_overdueOnly && d.netDuePaise <= 0) return false;
        if (term.isNotEmpty) {
          final unitMatch = '${d.blockName}-${d.unitNo}'.toLowerCase().contains(term);
          final nameMatch = (d.ownerName ?? '').toLowerCase().contains(term);
          if (!unitMatch && !nameMatch) return false;
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Member Dues & Ageing',
      subtitle: 'Track outstanding maintenance dues and ageing buckets',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
      ],
      filters: Row(
        children: [
          SizedBox(
            width: 160,
            child: TextField(
              controller: _asOfController,
              decoration: const InputDecoration(
                labelText: 'As of Date',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search unit or member',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _applyFilters(),
            ),
          ),
          const SizedBox(width: 16),
          FilterChip(
            label: const Text('Overdue Only'),
            selected: _overdueOnly,
            onSelected: (v) {
              setState(() => _overdueOnly = v);
              _applyFilters();
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildSummaryCard('Total Receivables', formatInr(_totalDues), Colors.red.shade800),
              const SizedBox(width: 12),
              _buildSummaryCard('Total Advances', formatInr(_totalAdvance), Colors.orange.shade800),
              const SizedBox(width: 12),
              _buildSummaryCard(
                'Net Outstanding Balance',
                formatInr(_netDue),
                _netDue > 0 ? Colors.red.shade900 : Colors.green.shade900,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return SocietyErrorView(message: _error!, onRetry: _load);
    }
    if (_filteredDues.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.payments_outlined,
        title: 'No dues found',
        message: 'No unit dues match the selected criteria.',
      );
    }

    return SocietyDataTable<UnitDueSummary>(
      total: _filteredDues.length,
      columns: [
        SocietyColumn<UnitDueSummary>(
          label: 'Unit',
          cell: (d) => Text('${d.blockName}-${d.unitNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 110,
        ),
        SocietyColumn<UnitDueSummary>(
          label: 'Member / Bill-to',
          cell: (d) => Text(d.ownerName ?? '-', overflow: TextOverflow.ellipsis),
          width: 180,
        ),
        SocietyColumn<UnitDueSummary>(
          label: 'Net Due',
          cell: (d) => Text(
            formatInr(d.netDuePaise),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: d.netDuePaise > 0 ? Colors.red.shade800 : Colors.green.shade800,
            ),
          ),
          width: 120,
          numeric: true,
        ),
        SocietyColumn<UnitDueSummary>(
          label: '0-30 Days',
          cell: (d) => Text(d.age0to30Paise > 0 ? formatInr(d.age0to30Paise) : '-'),
          width: 100,
          numeric: true,
        ),
        SocietyColumn<UnitDueSummary>(
          label: '31-60 Days',
          cell: (d) => Text(d.age31to60Paise > 0 ? formatInr(d.age31to60Paise) : '-'),
          width: 100,
          numeric: true,
        ),
        SocietyColumn<UnitDueSummary>(
          label: '61-90 Days',
          cell: (d) => Text(d.age61to90Paise > 0 ? formatInr(d.age61to90Paise) : '-'),
          width: 100,
          numeric: true,
        ),
        SocietyColumn<UnitDueSummary>(
          label: '> 90 Days',
          cell: (d) => Text(
            d.age90PlusPaise > 0 ? formatInr(d.age90PlusPaise) : '-',
            style: TextStyle(color: d.age90PlusPaise > 0 ? Colors.red : null),
          ),
          width: 100,
          numeric: true,
        ),
        SocietyColumn<UnitDueSummary>(
          label: 'Actions',
          cell: (d) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => context.go('/society/units/${d.unitId}'),
                child: const Text('Statement'),
              ),
              IconButton(
                icon: const Icon(Icons.receipt, size: 16),
                tooltip: 'Record Receipt',
                onPressed: () => context.go('/society/receipts/new?unitId=${d.unitId}'),
              ),
            ],
          ),
          width: 140,
        ),
      ],
      rows: _filteredDues,
      onRowTap: (d) => context.go('/society/units/${d.unitId}'),
    );
  }
}
