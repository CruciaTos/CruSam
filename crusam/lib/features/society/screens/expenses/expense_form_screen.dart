import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/money_field.dart';

class _ExpLineItem {
  int accountId;
  String description = '';
  String hsnSac = '';
  int amountPaise = 0;
  int gstRateBp;

  _ExpLineItem({
    required this.accountId,
    this.gstRateBp = 0,
  });
}

class ExpenseFormScreen extends StatefulWidget {
  final int? initialVendorId;
  const ExpenseFormScreen({super.key, this.initialVendorId});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  List<VendorRow> _vendors = [];
  List<Account> _expenseAccounts = [];
  List<TdsSection> _tdsSections = [];

  int? _selectedVendorId;
  final _billNoCtrl = TextEditingController();
  String _billDate = DateTime.now().toIso8601String().substring(0, 10);
  String _postDate = DateTime.now().toIso8601String().substring(0, 10);
  String _dueDate = DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10);
  final _narrationCtrl = TextEditingController();
  final _payeeCtrl = TextEditingController();

  int? _selectedTdsSectionId;
  int? _tdsRateBp;
  int? _customTdsPaise;

  final List<_ExpLineItem> _lines = [];

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
      final vendors = await services.expenses.listVendors(societyId);
      final allAccounts = await services.ledger.listAccounts(societyId);
      final expenseAccounts = allAccounts.where((a) => a.accountType == 'expense').toList();
      final tdsSections = await services.expenses.listTdsSections(societyId);

      if (mounted) {
        setState(() {
          _vendors = vendors;
          _expenseAccounts = expenseAccounts;
          _tdsSections = tdsSections;

          if (widget.initialVendorId != null) {
            _selectedVendorId = widget.initialVendorId;
          } else if (vendors.isNotEmpty) {
            _selectedVendorId = vendors.first.vendor.id;
          }

          if (_selectedVendorId != null) {
            _applyVendorDefaults(_selectedVendorId!);
          } else if (expenseAccounts.isNotEmpty) {
            _lines.add(_ExpLineItem(accountId: expenseAccounts.first.id));
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

  void _applyVendorDefaults(int vendorId) {
    final vMatch = _vendors.where((vr) => vr.vendor.id == vendorId);
    if (vMatch.isEmpty) return;
    final v = vMatch.first.vendor;

    _payeeCtrl.text = v.payeeName ?? v.name;
    _selectedTdsSectionId = v.tdsSectionId;
    _tdsRateBp = v.tdsRateBp;

    if (_lines.isEmpty) {
      final defaultAccId = v.defaultExpenseAccountId ?? (_expenseAccounts.isNotEmpty ? _expenseAccounts.first.id : 0);
      if (defaultAccId > 0) {
        _lines.add(_ExpLineItem(
          accountId: defaultAccId,
          gstRateBp: v.defaultGstRateBp ?? 0,
        ));
      }
    }
  }

  int get _subtotalPaise => _lines.fold(0, (sum, l) => sum + l.amountPaise);
  int get _gstPaise => _lines.fold(0, (sum, l) => sum + percentOf(l.amountPaise, l.gstRateBp));
  int get _totalPaise => _subtotalPaise + _gstPaise;

  int get _calculatedTdsPaise {
    if (_customTdsPaise != null) return _customTdsPaise!;
    if (_tdsRateBp != null && _tdsRateBp! > 0) {
      return percentOf(_subtotalPaise, _tdsRateBp!);
    }
    return 0;
  }

  int get _payablePaise => _totalPaise - _calculatedTdsPaise;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a vendor')));
      return;
    }
    if (_billNoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter vendor bill number')));
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
      await services.expenses.postExpenseBill(
        societyId,
        ExpenseBillDraft(
          vendorId: _selectedVendorId!,
          vendorBillNo: _billNoCtrl.text.trim(),
          billDate: _billDate,
          postDate: _postDate,
          dueDate: _dueDate,
          lines: _lines
              .map((l) => ExpenseLineDraft(
                    accountId: l.accountId,
                    description: l.description.isEmpty ? null : l.description,
                    hsnSac: l.hsnSac.isEmpty ? null : l.hsnSac,
                    amountPaise: l.amountPaise,
                    gstRateBp: l.gstRateBp,
                  ))
              .toList(),
          tdsSectionId: _selectedTdsSectionId,
          tdsRateBp: _tdsRateBp,
          customTdsPaise: _customTdsPaise,
          payeeName: _payeeCtrl.text.trim().isEmpty ? null : _payeeCtrl.text.trim(),
          narration: _narrationCtrl.text.trim().isEmpty ? null : _narrationCtrl.text.trim(),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense bill posted successfully')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting bill: $e')));
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
      title: 'New Expense Bill',
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
          label: const Text('Post Expense Bill'),
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
                      const Text('Bill & Vendor Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedVendorId,
                              decoration: const InputDecoration(labelText: 'Vendor *'),
                              items: _vendors
                                  .map((vr) => DropdownMenuItem(value: vr.vendor.id, child: Text('${vr.vendor.name} (${vr.vendor.vendorCode ?? "No code"})')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _selectedVendorId = v;
                                    _applyVendorDefaults(v);
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _billNoCtrl,
                              decoration: const InputDecoration(labelText: 'Vendor Bill No *'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: _billDate,
                              decoration: const InputDecoration(labelText: 'Bill Date (YYYY-MM-DD) *'),
                              onChanged: (v) => _billDate = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _postDate,
                              decoration: const InputDecoration(labelText: 'Posting Date (YYYY-MM-DD) *'),
                              onChanged: (v) => _postDate = v,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _dueDate,
                              decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD)'),
                              onChanged: (v) => _dueDate = v,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _payeeCtrl,
                              decoration: const InputDecoration(labelText: 'Payee Name'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _narrationCtrl,
                        decoration: const InputDecoration(labelText: 'Narration / Notes'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Lines
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
                          const Text('Expense Lines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Line'),
                            onPressed: () {
                              if (_expenseAccounts.isNotEmpty) {
                                setState(() {
                                  _lines.add(_ExpLineItem(accountId: _expenseAccounts.first.id));
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
                                  decoration: const InputDecoration(labelText: 'Expense Head', isDense: true),
                                  items: _expenseAccounts
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
                                onPressed: _lines.length > 1 ? () => setState(() => _lines.removeAt(idx)) : null,
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 24),

                      // TDS section
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedTdsSectionId,
                              decoration: const InputDecoration(labelText: 'TDS Section', isDense: true),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('None (0%)')),
                                ..._tdsSections.map((ts) => DropdownMenuItem(value: ts.id, child: Text('${ts.code} - ${ts.name}'))),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _selectedTdsSectionId = v;
                                  if (v != null) {
                                    final sel = _tdsSections.firstWhere((ts) => ts.id == v);
                                    _tdsRateBp = sel.defaultRateBp;
                                  } else {
                                    _tdsRateBp = null;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              initialValue: _tdsRateBp != null ? (_tdsRateBp! / 100).toString() : '',
                              decoration: const InputDecoration(labelText: 'TDS %', isDense: true),
                              onChanged: (v) {
                                final d = double.tryParse(v);
                                if (d != null) setState(() => _tdsRateBp = (d * 100).round());
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: MoneyField(
                              label: 'TDS Amount',
                              value: _calculatedTdsPaise,
                              onChanged: (v) => setState(() => _customTdsPaise = v),
                            ),
                          ),
                        ],
                      ),

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
                              const SizedBox(height: 4),
                              Text('Total Bill: ${formatPaise(_totalPaise)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('TDS Deducted: -${formatPaise(_calculatedTdsPaise)}', style: const TextStyle(fontSize: 14, color: Colors.orange)),
                              const SizedBox(height: 8),
                              Text(
                                'Net Payable: ${formatPaise(_payablePaise)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
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
