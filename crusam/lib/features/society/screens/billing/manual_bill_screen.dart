import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/money_field.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class _LineItemDraft {
  int chargeHeadId;
  String description = '';
  int amountPaise = 0;
  int gstRateBp;

  _LineItemDraft({
    required this.chargeHeadId,
    this.gstRateBp = 0,
  });
}

class ManualBillScreen extends StatefulWidget {
  final String? initialKind;
  final int? initialUnitId;
  const ManualBillScreen({super.key, this.initialKind, this.initialUnitId});

  @override
  State<ManualBillScreen> createState() => _ManualBillScreenState();
}

class _ManualBillScreenState extends State<ManualBillScreen> {
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  List<UnitRow> _units = [];
  List<ChargeHead> _heads = [];

  int? _selectedUnitId;
  late String _kind;
  late final TextEditingController _billDateCtrl;
  late final TextEditingController _dueDateCtrl;
  late final TextEditingController _commentCtrl;

  final List<_LineItemDraft> _lines = [];

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? 'manual';
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final due = '${now.year}-${now.month.toString().padLeft(2, '0')}-20';

    _billDateCtrl = TextEditingController(text: today);
    _dueDateCtrl = TextEditingController(text: due);
    _commentCtrl = TextEditingController();

    _load();
  }

  @override
  void dispose() {
    _billDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _commentCtrl.dispose();
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
      final uRes = await services.member.listUnits(societyId, page: const PageRequest(limit: 5000));
      final hList = await services.billing.listChargeHeads(societyId);

      if (mounted) {
        setState(() {
          _units = uRes.rows;
          _heads = hList;
          if (widget.initialUnitId != null) {
            _selectedUnitId = widget.initialUnitId;
          } else if (_units.isNotEmpty) {
            _selectedUnitId = _units.first.id;
          }
          if (_heads.isNotEmpty && _lines.isEmpty) {
            _lines.add(_LineItemDraft(
              chargeHeadId: _heads.first.id,
              gstRateBp: _heads.first.defaultGstRateBp ?? 0,
            ));
          }
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

  int get _subtotalPaise => _lines.fold(0, (sum, l) => sum + l.amountPaise);

  int get _gstPaise => _lines.fold(0, (sum, l) {
        if (l.gstRateBp <= 0) return sum;
        return sum + percentOf(l.amountPaise, l.gstRateBp);
      });

  int get _totalPaise => _subtotalPaise + _gstPaise;

  Future<void> _submit() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedUnitId == null) return;

    if (_lines.isEmpty || _lines.every((l) => l.amountPaise <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one line with an amount greater than zero.')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final billLines = _lines
          .where((l) => l.amountPaise > 0)
          .map((l) {
            final gst = l.gstRateBp > 0 ? percentOf(l.amountPaise, l.gstRateBp) : 0;
            return BillLineDraft(
              chargeHeadId: l.chargeHeadId,
              description: l.description.trim(),
              amountPaise: l.amountPaise,
              gstRateBp: l.gstRateBp,
              payablePaise: l.amountPaise + gst,
            );
          })
          .toList();

      final draft = ManualBillDraft(
        unitId: _selectedUnitId!,
        billDate: _billDateCtrl.text.trim(),
        dueDate: _dueDateCtrl.text.trim(),
        billKind: _kind,
        comment: _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
        lines: billLines,
      );

      final billId = await services.billing.postManualBill(societyId, draft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bill posted successfully!')),
        );
        context.go('/society/bills/$billId');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: _kind == 'debit_note' ? 'New Debit Note' : 'New Manual Bill',
      subtitle: 'Create and post an ad-hoc invoice or debit adjustment to member accounts',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/bills'),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: Text(_submitting ? 'Posting...' : 'Post Bill'),
        ),
      ],
      child: _error != null
          ? SocietyErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bill Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: _selectedUnitId,
                                      decoration: const InputDecoration(labelText: 'Unit *'),
                                      items: _units
                                          .map((u) => DropdownMenuItem(
                                                value: u.id,
                                                child: Text('${u.blockName}-${u.unitNo} (${u.billToName ?? "No bill-to"})'),
                                              ))
                                          .toList(),
                                      onChanged: (v) => setState(() => _selectedUnitId = v),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _kind,
                                      decoration: const InputDecoration(labelText: 'Bill Kind *'),
                                      items: const [
                                        DropdownMenuItem(value: 'manual', child: Text('Manual Bill')),
                                        DropdownMenuItem(value: 'debit_note', child: Text('Debit Note')),
                                        DropdownMenuItem(value: 'supplementary', child: Text('Supplementary')),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) setState(() => _kind = v);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _billDateCtrl,
                                      decoration: const InputDecoration(labelText: 'Bill Date (YYYY-MM-DD) *'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _dueDateCtrl,
                                      decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD) *'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _commentCtrl,
                                      decoration: const InputDecoration(labelText: 'Narration / Comment'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Lines Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Line Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  TextButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add Line'),
                                    onPressed: () {
                                      setState(() {
                                        _lines.add(_LineItemDraft(
                                          chargeHeadId: _heads.first.id,
                                          gstRateBp: _heads.first.defaultGstRateBp ?? 0,
                                        ));
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(_lines.length, (idx) {
                                final line = _lines[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButtonFormField<int>(
                                          initialValue: line.chargeHeadId,
                                          decoration: const InputDecoration(labelText: 'Charge Head', isDense: true),
                                          items: _heads
                                              .map((h) => DropdownMenuItem(value: h.id, child: Text(h.name)))
                                              .toList(),
                                          onChanged: (v) {
                                            if (v != null) {
                                              setState(() {
                                                line.chargeHeadId = v;
                                                final selHead = _heads.firstWhere((h) => h.id == v);
                                                line.gstRateBp = selHead.defaultGstRateBp ?? 0;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: TextFormField(
                                          initialValue: line.description,
                                          decoration: const InputDecoration(labelText: 'Description', isDense: true),
                                          onChanged: (v) => line.description = v,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: MoneyField(
                                          label: 'Amount',
                                          value: line.amountPaise,
                                          onChanged: (v) => setState(() => line.amountPaise = v ?? 0),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: DropdownButtonFormField<int>(
                                          initialValue: line.gstRateBp,
                                          decoration: const InputDecoration(labelText: 'GST Rate', isDense: true),
                                          items: const [
                                            DropdownMenuItem(value: 0, child: Text('0% (Nil)')),
                                            DropdownMenuItem(value: 500, child: Text('5%')),
                                            DropdownMenuItem(value: 1200, child: Text('12%')),
                                            DropdownMenuItem(value: 1800, child: Text('18%')),
                                            DropdownMenuItem(value: 2800, child: Text('28%')),
                                          ],
                                          onChanged: (v) {
                                            if (v != null) setState(() => line.gstRateBp = v);
                                          },
                                        ),
                                      ),
                                      if (_lines.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20),
                                          onPressed: () => setState(() => _lines.removeAt(idx)),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(height: 24),
                              // Totals Summary
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Subtotal: ${formatPaise(_subtotalPaise)}', style: const TextStyle(fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text('GST: ${formatPaise(_gstPaise)}', style: const TextStyle(fontSize: 14)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Total Payable: ${formatPaise(_totalPaise)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF047857)),
                                      ),
                                    ],
                                  ),
                                ],
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
}
