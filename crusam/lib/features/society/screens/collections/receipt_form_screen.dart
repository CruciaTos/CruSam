import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_page.dart';

class ReceiptFormScreen extends StatefulWidget {
  final int? initialUnitId;
  const ReceiptFormScreen({super.key, this.initialUnitId});

  @override
  State<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends State<ReceiptFormScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<UnitRow> _units = [];
  int? _selectedUnitId;

  List<Map<String, Object?>> _bankAccounts = [];
  int? _selectedBankAccountId;

  final _dateController = TextEditingController();
  final _amountController = TextEditingController();
  final _tdsController = TextEditingController();
  final _payerController = TextEditingController();
  final _modeController = TextEditingController(text: 'cheque');
  final _instNoController = TextEditingController();
  final _instBankController = TextEditingController();
  final _narrationController = TextEditingController();

  String _receiptKind = 'bill';
  bool _customAllocations = false;
  List<OpenBillLine> _openLines = [];
  final Map<int, TextEditingController> _allocControllers = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateController.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _selectedUnitId = widget.initialUnitId;
    _load();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _amountController.dispose();
    _tdsController.dispose();
    _payerController.dispose();
    _modeController.dispose();
    _instNoController.dispose();
    _instBankController.dispose();
    _narrationController.dispose();
    for (final c in _allocControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final unitsRes = await services.member.listUnits(
        societyId,
        page: const PageRequest(limit: 5000),
      );

      final bAccRows = await services.db.rawQuery('''
        SELECT ba.account_id, ba.bank_name, a.name as account_name
        FROM bank_accounts ba
        JOIN accounts a ON ba.account_id = a.id
        WHERE ba.society_id = ? AND ba.is_active = 1
        ORDER BY ba.account_type ASC, a.name ASC
      ''', [societyId]);

      if (mounted) {
        setState(() {
          _units = unitsRes.rows;
          _bankAccounts = bAccRows;
          if (_bankAccounts.isNotEmpty) {
            _selectedBankAccountId = _bankAccounts.first['account_id'] as int;
          }
          _loading = false;
        });

        if (_selectedUnitId != null) {
          _onUnitSelected(_selectedUnitId!);
        }
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

  Future<void> _onUnitSelected(int unitId) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _selectedUnitId = unitId;
    });

    final u = _units.firstWhere((x) => x.id == unitId);
    if (_payerController.text.trim().isEmpty) {
      _payerController.text = u.billToName ?? u.primaryContactName ?? '';
    }

    try {
      final services = await SocietyServices.instance();
      final openLines = await services.db.rawQuery('''
        SELECT 
          b.id as bill_id,
          b.bill_no,
          b.bill_date,
          b.due_date,
          bl.id as bill_line_id,
          bl.line_no,
          bl.charge_head_id,
          ch.name as charge_head_name,
          ch.head_kind,
          ch.is_interest_bearing,
          bl.payable_paise,
          COALESCE((
            SELECT SUM(ba.allocated_paise)
            FROM bill_allocations ba
            WHERE ba.bill_line_id = bl.id AND ba.is_active = 1
          ), 0) as allocated_paise
        FROM bill_lines bl
        JOIN bills b ON bl.bill_id = b.id
        JOIN charge_heads ch ON bl.charge_head_id = ch.id
        WHERE b.society_id = ? AND b.unit_id = ? AND b.status = 'posted'
        ORDER BY b.due_date ASC, b.bill_date ASC, b.id ASC, 
          CASE WHEN ch.head_kind = 'interest' THEN 0 ELSE 1 END ASC, bl.line_no ASC
      ''', [societyId, unitId]);

      final parsedOpen = <OpenBillLine>[];
      for (final r in openLines) {
        final pay = (r['payable_paise'] as int?) ?? 0;
        final alloc = (r['allocated_paise'] as int?) ?? 0;
        if (pay > alloc) {
          parsedOpen.add(OpenBillLine(
            billId: r['bill_id'] as int,
            billNo: (r['bill_no'] as String?) ?? '',
            billDate: r['bill_date'] as String,
            dueDate: r['due_date'] as String,
            billLineId: r['bill_line_id'] as int,
            lineNo: r['line_no'] as int,
            chargeHeadId: r['charge_head_id'] as int,
            chargeHeadName: (r['charge_head_name'] as String?) ?? '',
            headKind: (r['head_kind'] as String?) ?? 'charge',
            isInterestBearing: (r['is_interest_bearing'] as int?) == 1,
            payablePaise: pay,
            allocatedPaise: alloc,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _openLines = parsedOpen;
          _allocControllers.clear();
          for (final ol in _openLines) {
            _allocControllers[ol.billLineId] = TextEditingController();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedUnitId == null) return;

    final amtPaise = parseRupeesToPaise(_amountController.text);
    if (amtPaise == null || amtPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid receipt amount greater than 0.')),
      );
      return;
    }

    final tdsPaise = parseRupeesToPaise(_tdsController.text) ?? 0;

    List<AllocationDraft>? customAllocs;
    if (_customAllocations && _receiptKind == 'bill') {
      customAllocs = [];
      for (final ol in _openLines) {
        final ctrl = _allocControllers[ol.billLineId];
        if (ctrl != null && ctrl.text.trim().isNotEmpty) {
          final allocP = parseRupeesToPaise(ctrl.text);
          if (allocP != null && allocP > 0) {
            customAllocs.add(AllocationDraft(billLineId: ol.billLineId, amountPaise: allocP));
          }
        }
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final draft = ReceiptDraft(
        receiptKind: _receiptKind,
        unitId: _selectedUnitId!,
        payerName: _payerController.text.trim(),
        receiptDate: _dateController.text.trim(),
        amountPaise: amtPaise,
        tdsPaise: tdsPaise,
        mode: _modeController.text.trim().toLowerCase(),
        instrumentNo: _instNoController.text.trim(),
        instrumentBank: _instBankController.text.trim(),
        bankCashAccountId: _selectedBankAccountId,
        narration: _narrationController.text.trim(),
        customAllocations: customAllocs,
      );

      final receipt = await services.collection.createReceipt(societyId, draft);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt ${receipt.receiptNo} created successfully!')),
        );
        context.go('/society/receipts/${receipt.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Record Member Receipt',
      subtitle: 'Issue a collection receipt and allocate against dues',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/receipts'),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Receipt'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        color: Colors.red.shade50,
                        child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                      ),
                    _buildBasicDetailsCard(),
                    const SizedBox(height: 16),
                    _buildPaymentDetailsCard(),
                    const SizedBox(height: 16),
                    if (_receiptKind == 'bill') _buildAllocationsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBasicDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receipt Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedUnitId,
                    decoration: const InputDecoration(labelText: 'Unit / Flat *', border: OutlineInputBorder()),
                    items: _units.map((u) {
                      return DropdownMenuItem<int>(
                        value: u.id,
                        child: Text('${u.blockName}-${u.unitNo} (${u.billToName ?? "No Bill-to"})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) _onUnitSelected(val);
                    },
                    validator: (val) => val == null ? 'Please select a unit' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _payerController,
                    decoration: const InputDecoration(labelText: 'Payer Name *', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(labelText: 'Receipt Date (YYYY-MM-DD) *', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _receiptKind,
                    decoration: const InputDecoration(labelText: 'Receipt Kind', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'bill', child: Text('Regular Bill Collection')),
                      DropdownMenuItem(value: 'advance', child: Text('Advance Collection')),
                      DropdownMenuItem(value: 'refundable_deposit', child: Text('Refundable Deposit')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _receiptKind = val);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment & Deposit Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount Received (Rs.) *',
                      border: OutlineInputBorder(),
                      prefixText: 'Rs. ',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _tdsController,
                    decoration: const InputDecoration(
                      labelText: 'TDS Deducted (Rs.)',
                      border: OutlineInputBorder(),
                      prefixText: 'Rs. ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _modeController.text,
                    decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                      DropdownMenuItem(value: 'neft', child: Text('NEFT / RTGS / IMPS')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI / QR')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) {
                      if (v != null) _modeController.text = v;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedBankAccountId,
                    decoration: const InputDecoration(labelText: 'Deposit To (Bank / Cash)', border: OutlineInputBorder()),
                    items: _bankAccounts.map((b) {
                      final id = b['account_id'] as int;
                      final name = (b['bank_name'] as String?) ?? (b['account_name'] as String);
                      return DropdownMenuItem<int>(value: id, child: Text(name));
                    }).toList(),
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
                    controller: _instNoController,
                    decoration: const InputDecoration(labelText: 'Cheque / Ref No', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _instBankController,
                    decoration: const InputDecoration(labelText: 'Drawee Bank Name', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _narrationController,
              decoration: const InputDecoration(labelText: 'Notes / Remarks', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllocationsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bill Settlement & Allocation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    const Text('Auto-allocate (FIFO)'),
                    Switch(
                      value: _customAllocations,
                      onChanged: (v) => setState(() => _customAllocations = v),
                    ),
                    const Text('Custom Allocation'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_openLines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No open bills for this unit. Entire receipt will remain as unallocated Advance.'),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(2),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('Bill No', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Head', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Remaining', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Allocated (Rs.)', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  for (final ol in _openLines)
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text(ol.billNo)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(ol.dueDate)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(ol.chargeHeadName)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(formatInr(ol.remainingPaise))),
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: _customAllocations
                              ? TextFormField(
                                  controller: _allocControllers[ol.billLineId],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    hintText: '0.00',
                                  ),
                                )
                              : const Text('Auto-allocated (FIFO)', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
