import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/society_models.dart';
import '../../documents/pdf/receipt_pdf.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final int receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _loading = true;
  String? _error;
  Receipt? _receipt;
  Society? _society;
  List<BillAllocation> _allocations = [];

  @override
  void initState() {
    super.initState();
    _load();
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
      final soc = await services.society.getSociety(societyId);
      final r = await services.collection.getReceipt(widget.receiptId);
      final allocs = await services.collection.listAllocations(
        societyId,
        sourceType: 'receipt',
        sourceId: widget.receiptId,
      );

      if (mounted) {
        setState(() {
          _society = soc;
          _receipt = r;
          _allocations = allocs;
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

  Future<void> _printReceipt() async {
    if (_society == null || _receipt == null) return;
    try {
      final bytes = await ReceiptPdf.generateBytes(
        society: _society!,
        receipt: _receipt!,
        allocations: _allocations,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Receipt_${_receipt!.receiptNo.replaceAll('/', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  Future<void> _openReverseDialog() async {
    if (_receipt == null) return;
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: today);
    final reasonCtrl = TextEditingController();
    String revKind = 'mistake';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Reverse Receipt ${_receipt!.receiptNo}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reversing a receipt cancels all its bill allocations and posts a mirror reversal entry. This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: revKind,
                  decoration: const InputDecoration(labelText: 'Reversal Reason Type', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'mistake', child: Text('Entered in Error / Mistake')),
                    DropdownMenuItem(value: 'bounced', child: Text('Cheque / Payment Bounced')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDlgState(() => revKind = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(labelText: 'Reversal Date (YYYY-MM-DD) *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Remarks / Notes *', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Confirm Reversal'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final services = await SocietyServices.instance();
        await services.collection.reverseReceipt(
          societyId,
          _receipt!.id,
          dateCtrl.text.trim(),
          reasonCtrl.text.trim(),
          reversalKind: revKind,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt reversed successfully.')),
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
    if (_loading) {
      return const SocietyPage(
        title: 'Receipt Details',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _receipt == null) {
      return SocietyPage(
        title: 'Receipt Details',
        child: Center(child: Text(_error ?? 'Receipt not found', style: const TextStyle(color: Colors.red))),
      );
    }

    final r = _receipt!;
    final isRev = r.isReversed;

    return SocietyPage(
      title: 'Receipt ${r.receiptNo}',
      subtitle: '${r.blockName}-${r.unitNo} • ${r.payerName}',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/society/receipts'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to Receipts'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _printReceipt,
          icon: const Icon(Icons.print, size: 16),
          label: const Text('Print Receipt'),
        ),
        const SizedBox(width: 8),
        if (!isRev)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: _openReverseDialog,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reverse Receipt'),
          ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusBanner(r),
            const SizedBox(height: 16),
                  _buildSummaryCards(r),
                  const SizedBox(height: 16),
                  _buildDetailsCard(r),
                  const SizedBox(height: 16),
                  _buildAllocationsCard(r),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner(Receipt r) {
    if (!r.isReversed) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This receipt was REVERSED (${r.reversalKind}): ${r.reversalReason ?? "No reason given"}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(Receipt r) {
    return Row(
      children: [
        _buildStatCard('Amount Received', formatInr(r.amountPaise), Colors.blueGrey.shade800),
        const SizedBox(width: 12),
        _buildStatCard('TDS Deducted', r.tdsPaise > 0 ? formatInr(r.tdsPaise) : '-', Colors.blueGrey.shade800),
        const SizedBox(width: 12),
        _buildStatCard('Total Credit', formatInr(r.totalPaise), Colors.green.shade800),
        const SizedBox(width: 12),
        _buildStatCard(
          'Unallocated Advance',
          r.unallocatedPaise > 0 ? formatInr(r.unallocatedPaise) : 'Nil',
          r.unallocatedPaise > 0 ? Colors.orange.shade800 : Colors.grey.shade700,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
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

  Widget _buildDetailsCard(Receipt r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receipt Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Unit / Flat', '${r.blockName}-${r.unitNo}'),
                      _row('Payer Name', r.payerName),
                      _row('Receipt Date', r.receiptDate),
                      _row('Receipt Kind', r.receiptKind.toUpperCase()),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Payment Mode', r.mode.toUpperCase()),
                      if (r.instrumentNo != null && r.instrumentNo!.isNotEmpty)
                        _row('Instrument No', r.instrumentNo!),
                      if (r.instrumentBank != null && r.instrumentBank!.isNotEmpty)
                        _row('Drawee Bank', r.instrumentBank!),
                      if (r.bankCashAccountName != null)
                        _row('Deposited To', r.bankCashAccountName!),
                      if (r.narration != null && r.narration!.isNotEmpty)
                        _row('Narration', r.narration!),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildAllocationsCard(Receipt r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bill Allocations', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_allocations.isEmpty)
              const Text('No bill allocations. Entire receipt is maintained as unallocated advance.', style: TextStyle(color: Colors.grey))
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1.5),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('Bill No', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Charge Head', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Allocation Date', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(8), child: Text('Amount (Rs.)', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  for (final a in _allocations)
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text(a.billNo ?? '-')),
                        Padding(padding: const EdgeInsets.all(8), child: Text(a.chargeHeadName ?? '-')),
                        Padding(padding: const EdgeInsets.all(8), child: Text(a.allocationDate)),
                        Padding(padding: const EdgeInsets.all(8), child: Text(formatInr(a.allocatedPaise))),
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
