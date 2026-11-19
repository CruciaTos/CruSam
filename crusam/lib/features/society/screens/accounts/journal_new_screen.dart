import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/shared/widgets/money_field.dart';
import 'package:crusam/features/society/shared/widgets/society_date_field.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';

class _LineItem {
  int? accountId;
  int debitPaise = 0;
  int creditPaise = 0;
  int? unitId;
  int? vendorId;
  int? partyId;
  String? note;
}

class JournalNewScreen extends StatefulWidget {
  const JournalNewScreen({super.key});

  @override
  State<JournalNewScreen> createState() => _JournalNewScreenState();
}

class _JournalNewScreenState extends State<JournalNewScreen> {
  String _date = todayIso();
  final TextEditingController _narrationCtrl = TextEditingController();
  final List<_LineItem> _lines = [
    _LineItem(),
    _LineItem(),
  ];

  List<Account> _accounts = [];
  bool _loading = true;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _narrationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final accs = await services.ledger.chartOfAccounts(societyId);
      final flat = <Account>[];
      for (final g in accs) {
        flat.addAll(g.accounts.where((a) => a.isActive));
      }
      if (mounted) {
        setState(() {
          _accounts = flat;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalDebit => _lines.fold(0, (sum, l) => sum + l.debitPaise);
  int get _totalCredit => _lines.fold(0, (sum, l) => sum + l.creditPaise);
  int get _difference => (_totalDebit - _totalCredit).abs();
  bool get _canPost =>
      _totalDebit > 0 &&
      _totalDebit == _totalCredit &&
      _lines.length >= 2 &&
      !_lines.any((l) => l.accountId == null || (l.debitPaise == 0 && l.creditPaise == 0));

  Future<void> _post() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_narrationCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Narration is required');
      return;
    }

    setState(() {
      _posting = true;
      _error = null;
    });

    try {
      final draftLines = _lines.map((l) {
        return JournalLineDraft(
          accountId: l.accountId!,
          debitPaise: l.debitPaise,
          creditPaise: l.creditPaise,
          unitId: l.unitId,
          vendorId: l.vendorId,
          partyId: l.partyId,
          note: l.note,
        );
      }).toList();

      final draft = JournalDraft(
        societyId: societyId,
        entryDate: _date,
        sourceType: 'manual',
        narration: _narrationCtrl.text.trim(),
        lines: draftLines,
      );

      final services = await SocietyServices.instance();
      final posted = await services.ledger.postManual(draft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Posted journal entry ${posted.entryNo}')),
        );
        context.go('/society/journals');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is SocietyException ? e.message : e.toString();
          _posting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'New Journal Entry',
      subtitle: 'Post a manual adjustment or double-entry transaction',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/journals'),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Post Journal'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          onPressed: _canPost && !_posting ? _post : null,
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(_error!, style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 200,
                            child: SocietyDateField(
                              label: 'Entry Date *',
                              value: _date,
                              onChanged: (val) {
                                if (val != null) setState(() => _date = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _narrationCtrl,
                              maxLength: 500,
                              decoration: const InputDecoration(
                                labelText: 'Narration / Description *',
                                hintText: 'Enter reason or explanation for this journal...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
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
                          Row(
                            children: [
                              const Text('Journal Lines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Line'),
                                onPressed: () {
                                  setState(() => _lines.add(_LineItem()));
                                },
                              ),
                            ],
                          ),
                          const Divider(color: Color(0xFFE2E8F0), height: 20),
                          for (var idx = 0; idx < _lines.length; idx++) _buildLineRow(idx),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text('Total Debit: ${formatInr(_totalDebit)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 24),
                                Text('Total Credit: ${formatInr(_totalCredit)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 24),
                                Text(
                                  _difference == 0 && _totalDebit > 0
                                      ? 'Balanced ✓'
                                      : 'Difference: ${formatInr(_difference)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _difference == 0 && _totalDebit > 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildLineRow(int index) {
    final line = _lines[index];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${index + 1}.', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: line.accountId,
              decoration: const InputDecoration(
                labelText: 'Account *',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              items: _accounts.map((a) {
                return DropdownMenuItem<int>(
                  value: a.id,
                  child: Text('${a.code} - ${a.name}', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) => setState(() => line.accountId = val),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: MoneyField(
              hint: 'Debit',
              value: line.debitPaise > 0 ? line.debitPaise : null,
              onChanged: (val) {
                setState(() {
                  line.debitPaise = val ?? 0;
                  if (line.debitPaise > 0) line.creditPaise = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: MoneyField(
              hint: 'Credit',
              value: line.creditPaise > 0 ? line.creditPaise : null,
              onChanged: (val) {
                setState(() {
                  line.creditPaise = val ?? 0;
                  if (line.creditPaise > 0) line.debitPaise = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              decoration: const InputDecoration(
                hintText: 'Line note...',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => line.note = val,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
            onPressed: _lines.length > 2
                ? () {
                    setState(() => _lines.removeAt(index));
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
