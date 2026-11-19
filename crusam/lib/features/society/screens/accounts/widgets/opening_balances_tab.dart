import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/shared/widgets/money_field.dart';
import 'package:crusam/features/society/shared/widgets/society_date_field.dart';

class OpeningBalancesTab extends StatefulWidget {
  final int societyId;
  const OpeningBalancesTab({super.key, required this.societyId});

  @override
  State<OpeningBalancesTab> createState() => _OpeningBalancesTabState();
}

class _OpeningBalancesTabState extends State<OpeningBalancesTab> {
  bool _loading = true;
  String _asOfDate = todayIso();
  List<Account> _accounts = [];
  final Map<int, int> _debits = {};
  final Map<int, int> _credits = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final soc = await services.society.getSociety(widget.societyId);
      _asOfDate = soc.booksStartDate;

      final accs = await services.ledger.chartOfAccounts(widget.societyId);
      final flat = <Account>[];
      for (final g in accs) {
        flat.addAll(g.accounts);
      }

      if (mounted) {
        setState(() {
          _accounts = flat;
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

  int get _totalDebit => _debits.values.fold(0, (a, b) => a + b);
  int get _totalCredit => _credits.values.fold(0, (a, b) => a + b);
  int get _difference => (_totalDebit - _totalCredit).abs();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final drafts = <OpeningBalanceDraft>[];
      for (final a in _accounts) {
        final d = _debits[a.id] ?? 0;
        final c = _credits[a.id] ?? 0;
        if (d > 0 || c > 0) {
          drafts.add(OpeningBalanceDraft(
            accountId: a.id,
            debitPaise: d,
            creditPaise: c,
            asOfDate: _asOfDate,
          ));
        }
      }

      final services = await SocietyServices.instance();
      await services.ledger.saveOpeningBalances(widget.societyId, drafts);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening balances saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is SocietyException ? e.message : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
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
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 220,
                child: SocietyDateField(
                  label: 'Opening Balance Date',
                  value: _asOfDate,
                  onChanged: (val) {
                    if (val != null) setState(() => _asOfDate = val);
                  },
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Debit: ₹${(_totalDebit / 100).toStringAsFixed(2)}  |  Credit: ₹${(_totalCredit / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _totalDebit == _totalCredit
                        ? 'Balanced'
                        : 'Difference ₹${(_difference / 100).toStringAsFixed(2)} will balance to Opening Balance Adjustment',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _totalDebit == _totalCredit ? const Color(0xFF15803D) : const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save Opening Balances'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              itemCount: _accounts.length,
              separatorBuilder: (context, index) => const Divider(color: Color(0xFFF1F5F9), height: 1),
              itemBuilder: (context, idx) {
                final acc = _accounts[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(acc.code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          acc.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: MoneyField(
                          hint: 'Debit',
                          value: _debits[acc.id],
                          onChanged: (val) {
                            setState(() {
                              if (val != null && val > 0) {
                                _debits[acc.id] = val;
                                _credits.remove(acc.id);
                              } else {
                                _debits.remove(acc.id);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: MoneyField(
                          hint: 'Credit',
                          value: _credits[acc.id],
                          onChanged: (val) {
                            setState(() {
                              if (val != null && val > 0) {
                                _credits[acc.id] = val;
                                _debits.remove(acc.id);
                              } else {
                                _credits.remove(acc.id);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
