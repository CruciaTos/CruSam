import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/money_field.dart';

class PaymentFormScreen extends StatefulWidget {
  final int? initialVendorId;
  const PaymentFormScreen({super.key, this.initialVendorId});

  @override
  State<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends State<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  String _paymentKind = 'against_bills'; // 'against_bills', 'advance', 'direct_expense'
  List<VendorRow> _vendors = [];
  List<Account> _bankAccounts = [];
  List<Account> _expenseAccounts = [];

  int? _selectedVendorId;
  int? _selectedExpenseAccountId;
  int? _selectedBankAccountId;

  String _paymentDate = DateTime.now().toIso8601String().substring(0, 10);
  int _amountPaise = 0;
  String _mode = 'neft';
  final _instNoCtrl = TextEditingController();
  final _payeeCtrl = TextEditingController();
  final _narrationCtrl = TextEditingController();

  List<OpenExpenseBill> _openBills = [];
  final Map<int, int> _allocations = {}; // billId -> allocatedPaise

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
      final bankAccounts = allAccounts.where((a) => a.accountKind == 'bank' || a.accountKind == 'cash').toList();
      final expenseAccounts = allAccounts.where((a) => a.accountType == 'expense').toList();

      if (mounted) {
        setState(() {
          _vendors = vendors;
          _bankAccounts = bankAccounts;
          _expenseAccounts = expenseAccounts;

          if (bankAccounts.isNotEmpty) _selectedBankAccountId = bankAccounts.first.id;
          if (expenseAccounts.isNotEmpty) _selectedExpenseAccountId = expenseAccounts.first.id;

          if (widget.initialVendorId != null) {
            _selectedVendorId = widget.initialVendorId;
          } else if (vendors.isNotEmpty) {
            _selectedVendorId = vendors.first.vendor.id;
          }

          _loading = false;
        });

        if (_selectedVendorId != null) {
          _loadOpenBills(_selectedVendorId!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadOpenBills(int vendorId) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final vMatch = _vendors.where((vr) => vr.vendor.id == vendorId);
    if (vMatch.isNotEmpty) {
      _payeeCtrl.text = vMatch.first.vendor.payeeName ?? vMatch.first.vendor.name;
    }

    try {
      final services = await SocietyServices.instance();
      final bills = await services.expenses.getOpenExpenseBills(societyId, vendorId);
      if (mounted) {
        setState(() {
          _openBills = bills;
          _allocations.clear();
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  void _autoAllocate() {
    var remaining = _amountPaise;
    setState(() {
      _allocations.clear();
      for (final ob in _openBills) {
        if (remaining <= 0) break;
        final alloc = remaining < ob.duePaise ? remaining : ob.duePaise;
        _allocations[ob.bill.id] = alloc;
        remaining -= alloc;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_amountPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount must be positive')));
      return;
    }
    if (_selectedBankAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select bank/cash account')));
      return;
    }

    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    List<VendorPaymentAllocationDraft>? allocDrafts;
    if (_paymentKind == 'against_bills' && _allocations.isNotEmpty) {
      allocDrafts = _allocations.entries
          .where((e) => e.value > 0)
          .map((e) => VendorPaymentAllocationDraft(expenseBillId: e.key, allocatedPaise: e.value))
          .toList();
    }

    setState(() => _saving = true);
    try {
      final services = await SocietyServices.instance();
      await services.expenses.postPayment(
        societyId,
        VendorPaymentDraft(
          paymentKind: _paymentKind,
          vendorId: _paymentKind == 'direct_expense' ? null : _selectedVendorId,
          expenseAccountId: _paymentKind == 'direct_expense' ? _selectedExpenseAccountId : null,
          paymentDate: _paymentDate,
          amountPaise: _amountPaise,
          mode: _mode,
          instrumentNo: _instNoCtrl.text.trim().isEmpty ? null : _instNoCtrl.text.trim(),
          payeeName: _payeeCtrl.text.trim().isEmpty ? null : _payeeCtrl.text.trim(),
          bankCashAccountId: _selectedBankAccountId!,
          narration: _narrationCtrl.text.trim().isEmpty ? null : _narrationCtrl.text.trim(),
          allocations: allocDrafts,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment posted successfully')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting payment: $e')));
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
      title: 'Record Vendor Payment',
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => context.pop(), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: const Text('Post Payment'),
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
                shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _paymentKind,
                              decoration: const InputDecoration(labelText: 'Payment Kind *'),
                              items: const [
                                DropdownMenuItem(value: 'against_bills', child: Text('Against Expense Bills')),
                                DropdownMenuItem(value: 'advance', child: Text('Vendor Advance')),
                                DropdownMenuItem(value: 'direct_expense', child: Text('Direct Expense (No Bill)')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _paymentKind = v;
                                    _allocations.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (_paymentKind != 'direct_expense')
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                initialValue: _selectedVendorId,
                                decoration: const InputDecoration(labelText: 'Vendor *'),
                                items: _vendors
                                    .map((vr) => DropdownMenuItem(value: vr.vendor.id, child: Text(vr.vendor.name)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _selectedVendorId = v);
                                    _loadOpenBills(v);
                                  }
                                },
                              ),
                            ),
                          if (_paymentKind == 'direct_expense')
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                initialValue: _selectedExpenseAccountId,
                                decoration: const InputDecoration(labelText: 'Expense Head *'),
                                items: _expenseAccounts
                                    .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} - ${a.name}')))
                                    .toList(),
                                onChanged: (v) => setState(() => _selectedExpenseAccountId = v),
                              ),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: _paymentDate,
                              decoration: const InputDecoration(labelText: 'Payment Date *'),
                              onChanged: (v) => _paymentDate = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MoneyField(
                              label: 'Payment Amount *',
                              value: _amountPaise,
                              onChanged: (v) {
                                setState(() => _amountPaise = v ?? 0);
                                if (_paymentKind == 'against_bills') _autoAllocate();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _mode,
                              decoration: const InputDecoration(labelText: 'Mode *'),
                              items: const [
                                DropdownMenuItem(value: 'neft', child: Text('NEFT / RTGS')),
                                DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                              ],
                              onChanged: (v) => setState(() => _mode = v ?? 'neft'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedBankAccountId,
                              decoration: const InputDecoration(labelText: 'Paid From (Bank/Cash) *'),
                              items: _bankAccounts
                                  .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedBankAccountId = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _instNoCtrl,
                              decoration: const InputDecoration(labelText: 'Cheque / Ref / UTR No'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _payeeCtrl,
                              decoration: const InputDecoration(labelText: 'Payee Name'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _narrationCtrl,
                              decoration: const InputDecoration(labelText: 'Narration / Remarks'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (_paymentKind == 'against_bills')
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Open Bills & Settlement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            TextButton.icon(
                              icon: const Icon(Icons.auto_fix_high),
                              label: const Text('Auto Allocate FIFO'),
                              onPressed: _autoAllocate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_openBills.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('No open bills for this vendor. Any payment made will be retained as vendor advance.',
                                style: TextStyle(color: Colors.grey)),
                          )
                        else
                          Table(
                            columnWidths: const {
                              0: FlexColumnWidth(2),
                              1: FlexColumnWidth(2),
                              2: FlexColumnWidth(2),
                              3: FlexColumnWidth(2),
                              4: FlexColumnWidth(3),
                            },
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: Colors.grey.shade100),
                                children: const [
                                  Padding(padding: EdgeInsets.all(8), child: Text('Voucher', style: TextStyle(fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(8), child: Text('Bill No', style: TextStyle(fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(8), child: Text('Total Payable', style: TextStyle(fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(8), child: Text('Due Balance', style: TextStyle(fontWeight: FontWeight.bold))),
                                  Padding(padding: EdgeInsets.all(8), child: Text('Allocate', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                              ),
                              ..._openBills.map((ob) {
                                final alloc = _allocations[ob.bill.id] ?? 0;
                                return TableRow(
                                  children: [
                                    Padding(padding: const EdgeInsets.all(8), child: Text(ob.bill.voucherNo)),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(ob.bill.vendorBillNo)),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(formatPaise(ob.bill.payablePaise))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(formatPaise(ob.duePaise), style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: SizedBox(
                                        height: 40,
                                        child: MoneyField(
                                          label: 'Allocate',
                                          value: alloc,
                                          onChanged: (v) {
                                            setState(() {
                                              if (v != null && v > 0) {
                                                _allocations[ob.bill.id] = v;
                                              } else {
                                                _allocations.remove(ob.bill.id);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
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
