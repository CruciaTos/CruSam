import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/other_income_models.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/money_field.dart';

class _LineItem {
  int accountId;
  String description = '';
  String hsnSac = '';
  int amountPaise = 0;
  int gstRateBp = 0;

  _LineItem({
    required this.accountId,
  });
}

class OtherInvoiceFormScreen extends StatefulWidget {
  const OtherInvoiceFormScreen({super.key});

  @override
  State<OtherInvoiceFormScreen> createState() => _OtherInvoiceFormScreenState();
}

class _OtherInvoiceFormScreenState extends State<OtherInvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  List<PartyRow> _parties = [];
  List<Account> _incomeAccounts = [];

  int? _selectedPartyId;
  String _invoiceDate = DateTime.now().toIso8601String().substring(0, 10);
  String _dueDate = DateTime.now().add(const Duration(days: 15)).toIso8601String().substring(0, 10);
  final _narrationCtrl = TextEditingController();

  final List<_LineItem> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final parties = await services.otherIncome.listParties(societyId);
      final allAccounts = await services.ledger.listAccounts(societyId);
      final incomeAccounts = allAccounts.where((a) => a.accountType == 'income').toList();

      if (mounted) {
        setState(() {
          _parties = parties;
          _incomeAccounts = incomeAccounts;
          if (parties.isNotEmpty) _selectedPartyId = parties.first.party.id;
          if (incomeAccounts.isNotEmpty) {
            _lines.add(_LineItem(accountId: incomeAccounts.first.id));
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
        setState(() => _loading = false);
      }
    }
  }

  int get _subtotalPaise => _lines.fold(0, (sum, l) => sum + l.amountPaise);
  int get _gstPaise => _lines.fold(0, (sum, l) => sum + percentOf(l.amountPaise, l.gstRateBp));
  int get _totalPaise => _subtotalPaise + _gstPaise;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPartyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a party')));
      return;
    }
    if (_lines.isEmpty || _lines.any((l) => l.amountPaise <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All lines must have positive amounts')));
      return;
    }

    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _saving = true);
    try {
      final services = await SocietyServices.instance();
      await services.otherIncome.postInvoice(
        societyId,
        OtherInvoiceDraft(
          partyId: _selectedPartyId!,
          invoiceDate: _invoiceDate,
          dueDate: _dueDate,
          lines: _lines
              .map((l) => OtherInvoiceLineDraft(
                    accountId: l.accountId,
                    description: l.description.isEmpty ? null : l.description,
                    hsnSac: l.hsnSac.isEmpty ? null : l.hsnSac,
                    amountPaise: l.amountPaise,
                    gstRateBp: l.gstRateBp,
                  ))
              .toList(),
          narration: _narrationCtrl.text.trim().isEmpty ? null : _narrationCtrl.text.trim(),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice posted successfully')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting invoice: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SocietyPage(
      title: 'New Other Income Invoice',
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => context.pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: const Text('Post Invoice'),
          onPressed: _saving ? null : _submit,
        ),
      ],
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Invoice Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedPartyId,
                              decoration: const InputDecoration(labelText: 'Party / Tenant *'),
                              items: _parties.map((p) => DropdownMenuItem(value: p.party.id, child: Text(p.party.name))).toList(),
                              onChanged: (v) => setState(() => _selectedPartyId = v),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _invoiceDate,
                              decoration: const InputDecoration(labelText: 'Invoice Date (YYYY-MM-DD) *'),
                              onChanged: (v) => _invoiceDate = v,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _dueDate,
                              decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD) *'),
                              onChanged: (v) => _dueDate = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _narrationCtrl,
                        decoration: const InputDecoration(labelText: 'Narration / Description'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Invoice Lines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Line'),
                            onPressed: () {
                              if (_incomeAccounts.isNotEmpty) {
                                setState(() {
                                  _lines.add(_LineItem(accountId: _incomeAccounts.first.id));
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._lines.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final line = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<int>(
                                  initialValue: line.accountId,
                                  decoration: const InputDecoration(labelText: 'Income Account', isDense: true),
                                  items: _incomeAccounts
                                      .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} - ${a.name}')))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => line.accountId = v);
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
                                flex: 1,
                                child: TextFormField(
                                  initialValue: line.hsnSac,
                                  decoration: const InputDecoration(labelText: 'HSN/SAC', isDense: true),
                                  onChanged: (v) => line.hsnSac = v,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: MoneyField(
                                  label: 'Amount *',
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
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: _lines.length > 1
                                    ? () => setState(() => _lines.removeAt(idx))
                                    : null,
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 32),
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
                                'Total Invoice: ${formatPaise(_totalPaise)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
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
      ),
    );
  }
}
