import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';
import '../../documents/pdf/member_bill_pdf.dart';
import '../../shared/widgets/reverse_dialog.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class BillDetailScreen extends StatefulWidget {
  final int billId;
  const BillDetailScreen({super.key, required this.billId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  bool _loading = false;
  String? _error;
  Bill? _bill;
  Society? _society;

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
      final b = await services.billing.getBill(widget.billId);
      final soc = await services.society.getSociety(societyId);

      if (mounted) {
        setState(() {
          _bill = b;
          _society = soc;
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

  Future<void> _printPdf() async {
    if (_bill == null || _society == null) return;

    final bytes = await MemberBillPdf.generatePdf(society: _society!, bill: _bill!);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: '${_bill!.billNo ?? "bill"}.pdf',
    );
  }

  Future<void> _reverseBill() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _bill == null) return;

    final result = await ReverseDialog.show(
      context,
      documentTitle: 'Bill ${_bill!.billNo ?? ""}',
      isReceipt: false,
    );

    if (result == null) return;

    try {
      final services = await SocietyServices.instance();
      await services.billing.reverseBill(
        societyId,
        _bill!.id,
        result.date,
        result.reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill reversed successfully.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SocietyPage(
        title: 'Bill Details',
        child: SocietyErrorView(message: _error!, onRetry: _load),
      );
    }

    if (_loading || _bill == null) {
      return const SocietyPage(
        title: 'Bill Details',
        child: Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      );
    }

    final bill = _bill!;

    return SocietyPage(
      title: 'Bill: ${bill.billNo ?? "(Draft)"}',
      subtitle: '${bill.billKind.replaceAll("_", " ").toUpperCase()} • Unit ${bill.blockName}-${bill.unitNo}',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/bills'),
          child: const Text('Back to Bills'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _printPdf,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print / PDF'),
        ),
        if (bill.status == 'posted') ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: _reverseBill,
            icon: const Icon(Icons.undo_outlined, size: 18),
            label: const Text('Reverse Bill'),
          ),
        ],
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bill Overview Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            StatusChip(status: bill.status),
                            if (bill.status == 'reversed') ...[
                              const SizedBox(width: 12),
                              Text(
                                'Reason: ${bill.reversalReason ?? "-"}',
                                style: const TextStyle(color: Color(0xFFDC2626), fontStyle: FontStyle.italic),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'Total: ${formatPaise(bill.totalPaise)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF047857)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(child: _InfoTile(label: 'Unit', value: '${bill.blockName}-${bill.unitNo}')),
                        Expanded(child: _InfoTile(label: 'Bill-To Member', value: bill.billToName)),
                        Expanded(child: _InfoTile(label: 'Bill Date', value: bill.billDate)),
                        Expanded(child: _InfoTile(label: 'Due Date', value: bill.dueDate)),
                      ],
                    ),
                    if (bill.periodFrom != null && bill.periodTo != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _InfoTile(label: 'Period', value: '${bill.periodFrom} to ${bill.periodTo}')),
                          if (bill.journalEntryId != null)
                            Expanded(
                              child: InkWell(
                                onTap: () => context.go('/society/journals/${bill.journalEntryId}'),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Journal Entry', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'View Journal #${bill.journalEntryId}',
                                      style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          const Spacer(),
                          const Spacer(),
                        ],
                      ),
                    ],
                    if (bill.comment != null && bill.comment!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Narration: ${bill.comment}', style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF475569))),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Line Items Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Itemized Charges', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(4),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(2),
                        4: FlexColumnWidth(2),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                          children: [
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Particulars / Head', style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Base Amount', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('GST', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                            Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Line Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        ...bill.lines.map((line) {
                          final gst = line.cgstPaise + line.sgstPaise + line.igstPaise;
                          return TableRow(
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                            children: [
                              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('${line.lineNo}')),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.chargeHeadName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (line.description != null && line.description!.isNotEmpty)
                                      Text(line.description!, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(formatPaise(line.amountPaise), textAlign: TextAlign.right)),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(gst > 0 ? formatPaise(gst) : '-', textAlign: TextAlign.right)),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(formatPaise(line.payablePaise), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                            ],
                          );
                        }),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 250,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SummaryLine(label: 'Subtotal:', value: formatPaise(bill.subtotalPaise)),
                              if (bill.cgstPaise > 0) _SummaryLine(label: 'CGST:', value: formatPaise(bill.cgstPaise)),
                              if (bill.sgstPaise > 0) _SummaryLine(label: 'SGST:', value: formatPaise(bill.sgstPaise)),
                              if (bill.roundOffPaise != 0) _SummaryLine(label: 'Round Off:', value: formatPaise(bill.roundOffPaise)),
                              const Divider(height: 12),
                              _SummaryLine(
                                label: 'Total Payable:',
                                value: formatPaise(bill.totalPaise),
                                isBold: true,
                              ),
                            ],
                          ),
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

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  const _SummaryLine({required this.label, required this.value, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
