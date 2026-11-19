import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/shared/widgets/reverse_dialog.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';
import 'package:crusam/features/society/shared/widgets/status_chip.dart';

class JournalDetailScreen extends StatefulWidget {
  final int entryId;
  const JournalDetailScreen({super.key, required this.entryId});

  @override
  State<JournalDetailScreen> createState() => _JournalDetailScreenState();
}

class _JournalDetailScreenState extends State<JournalDetailScreen> {
  bool _loading = true;
  JournalEntryDetail? _detail;

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
      final d = await services.ledger.entryDetail(societyId, widget.entryId);
      if (mounted) {
        setState(() {
          _detail = d;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reverse() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _detail == null) return;

    final result = await ReverseDialog.show(context, documentTitle: _detail!.entryNo);
    if (result != null) {
      try {
        final services = await SocietyServices.instance();
        await services.ledger.reverseManual(societyId, _detail!.id, result.date, result.reason);
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
      title: _detail != null ? 'Journal Entry ${_detail!.entryNo}' : 'Journal Entry Details',
      subtitle: 'Complete accounting entry lines, allocations and audit details',
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('All Journals'),
          onPressed: () => context.go('/society/journals'),
        ),
        if (_detail != null && _detail!.status == 'posted' && _detail!.sourceType == 'manual') ...[
          const SizedBox(width: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse Entry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: _reverse,
          ),
        ],
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('Entry not found'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(_detail!.entryNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 12),
                                  StatusChip(status: _detail!.status),
                                  const Spacer(),
                                  Text(formatDisplayDate(_detail!.entryDate), style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                                ],
                              ),
                              const Divider(color: Color(0xFFE2E8F0), height: 24),
                              Row(
                                children: [
                                  _metaItem('Source Type', _detail!.sourceType),
                                  if (_detail!.sourceId != null)
                                    _metaItem('Source ID', '#${_detail!.sourceId}'),
                                  if (_detail!.reversalOfId != null)
                                    _metaItem('Reversal Of', '#${_detail!.reversalOfId}'),
                                  if (_detail!.reversedById != null)
                                    _metaItem('Reversed By', '#${_detail!.reversedById}'),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Narration: ${_detail!.narration}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Lines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const Divider(color: Color(0xFFE2E8F0), height: 20),
                              DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                columns: const [
                                  DataColumn(label: Text('#')),
                                  DataColumn(label: Text('Account Code')),
                                  DataColumn(label: Text('Account Name')),
                                  DataColumn(label: Text('Entity / Reference')),
                                  DataColumn(numeric: true, label: Text('Debit')),
                                  DataColumn(numeric: true, label: Text('Credit')),
                                ],
                                rows: _detail!.lines.map((l) {
                                  final entityStr = l.unitNo != null
                                      ? 'Unit: ${l.unitNo}'
                                      : (l.vendorName != null
                                          ? 'Vendor: ${l.vendorName}'
                                          : (l.partyName != null ? 'Party: ${l.partyName}' : '—'));

                                  return DataRow(cells: [
                                    DataCell(Text('${l.lineNo}')),
                                    DataCell(Text(l.accountCode, style: const TextStyle(fontFamily: 'monospace'))),
                                    DataCell(Text(l.accountName)),
                                    DataCell(Text(entityStr)),
                                    DataCell(Text(l.debitPaise > 0 ? formatInr(l.debitPaise) : '—')),
                                    DataCell(Text(l.creditPaise > 0 ? formatInr(l.creditPaise) : '—')),
                                  ]);
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
        ],
      ),
    );
  }
}
