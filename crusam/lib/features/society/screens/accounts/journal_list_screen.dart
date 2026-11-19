import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/shared/widgets/reverse_dialog.dart';
import 'package:crusam/features/society/shared/widgets/society_data_table.dart';
import 'package:crusam/features/society/shared/widgets/society_filter_bar.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';
import 'package:crusam/features/society/shared/widgets/status_chip.dart';

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  bool _loading = true;
  List<JournalEntryRow> _entries = [];
  int _total = 0;
  int _page = 0;
  String _search = '';
  String? _sourceTypeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final res = await services.ledger.listEntries(
        societyId,
        JournalFilter(sourceType: _sourceTypeFilter),
        PageRequest(limit: 50, offset: _page * 50, search: _search),
      );

      if (mounted) {
        setState(() {
          _entries = res.rows;
          _total = res.total;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onReverse(JournalEntryRow entry) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final result = await ReverseDialog.show(context, documentTitle: 'Journal Entry ${entry.entryNo}');
    if (result != null) {
      try {
        final services = await SocietyServices.instance();
        await services.ledger.reverseManual(societyId, entry.id, result.date, result.reason);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Journal entry reversed successfully')),
          );
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reversal failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Journal Entries',
      subtitle: 'Complete double-entry accounting records, manual journals and audit trail',
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Journal Entry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          onPressed: () => context.go('/society/journals/new'),
        ),
      ],
      filters: SocietyFilterBar(
        searchHint: 'Search entry no, narration...',
        onSearch: (q) {
          _search = q;
          _page = 0;
          _load();
        },
        filters: [
          DropdownButton<String?>(
            value: _sourceTypeFilter,
            hint: const Text('All Sources', style: TextStyle(fontSize: 13)),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Sources')),
              DropdownMenuItem(value: 'manual', child: Text('Manual')),
              DropdownMenuItem(value: 'member_bill', child: Text('Member Bill')),
              DropdownMenuItem(value: 'member_receipt', child: Text('Member Receipt')),
              DropdownMenuItem(value: 'expense_bill', child: Text('Expense Bill')),
              DropdownMenuItem(value: 'vendor_payment', child: Text('Vendor Payment')),
              DropdownMenuItem(value: 'opening', child: Text('Opening')),
              DropdownMenuItem(value: 'reversal', child: Text('Reversal')),
            ],
            onChanged: (val) {
              setState(() {
                _sourceTypeFilter = val;
                _page = 0;
              });
              _load();
            },
          ),
        ],
      ),
      child: SocietyDataTable<JournalEntryRow>(
        columns: [
          SocietyColumn<JournalEntryRow>(
            label: 'Entry No',
            cell: (r) => Text(r.entryNo, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Date',
            cell: (r) => Text(formatDisplayDate(r.entryDate)),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Source',
            cell: (r) => Text(r.sourceType),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Narration',
            cell: (r) => Text(r.narration, overflow: TextOverflow.ellipsis),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Debit Total',
            numeric: true,
            cell: (r) => Text(formatInr(r.debitTotalPaise)),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Status',
            cell: (r) => StatusChip(status: r.status),
          ),
          SocietyColumn<JournalEntryRow>(
            label: 'Actions',
            cell: (r) => r.status == 'posted' && r.sourceType == 'manual'
                ? IconButton(
                    icon: const Icon(Icons.undo, size: 18, color: Color(0xFFEF4444)),
                    tooltip: 'Reverse entry',
                    onPressed: () => _onReverse(r),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        rows: _entries,
        total: _total,
        page: _page,
        loading: _loading,
        onPage: (p) {
          _page = p;
          _load();
        },
        onRowTap: (r) => context.go('/society/journals/${r.id}'),
      ),
    );
  }
}
