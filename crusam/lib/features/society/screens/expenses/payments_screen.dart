import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../documents/pdf/payment_voucher_pdf.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _loading = true;
  String? _error;
  List<VendorPayment> _payments = [];
  String _statusFilter = '';

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
      final list = await services.expenses.listVendorPayments(
        societyId,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );

      if (mounted) {
        setState(() {
          _payments = list;
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

  Future<void> _printVoucher(VendorPayment p) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final society = await services.society.getSociety(societyId);

      Vendor? vendor;
      if (p.vendorId != null) {
        vendor = await services.expenses.getVendor(societyId, p.vendorId!);
      }

      final bytes = await PaymentVoucherPdf.generateBytes(
        society: society,
        payment: p,
        vendor: vendor,
      );

      await Printing.layoutPdf(onLayout: (_) => bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
      }
    }
  }

  void _showReverseDialog(VendorPayment p) {
    final reasonCtrl = TextEditingController();
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverse Payment ${p.paymentNo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to reverse payment ${p.paymentNo} for ${formatPaise(p.amountPaise)}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reversal Reason *'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              final societyId = SocietyContext.instance.societyId;
              if (societyId == null) return;
              try {
                final services = await SocietyServices.instance();
                await services.expenses.reversePayment(societyId, p.id, dateStr, reasonCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Vendor Payments',
      actions: [
        DropdownButton<String>(
          value: _statusFilter,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: '', child: Text('All Statuses')),
            DropdownMenuItem(value: 'posted', child: Text('Posted')),
            DropdownMenuItem(value: 'reversed', child: Text('Reversed')),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _statusFilter = v);
              _load();
            }
          },
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Record Payment'),
          onPressed: () async {
            await context.push('/society/payments/new');
            _load();
          },
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SocietyErrorView(message: _error!, onRetry: _load)
              : _payments.isEmpty
                  ? SocietyEmptyView(
                      icon: Icons.payments_outlined,
                      title: 'No payments found',
                      message: 'Record bank or cash payments made to vendors.',
                      action: FilledButton(
                        onPressed: () => context.push('/society/payments/new'),
                        child: const Text('Record First Payment'),
                      ),
                    )
                  : SocietyDataTable<VendorPayment>(
                      total: _payments.length,
                      columns: [
                        SocietyColumn<VendorPayment>(
                          label: 'Payment No',
                          cell: (p) => Text(p.paymentNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 140,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Date',
                          cell: (p) => Text(p.paymentDate),
                          width: 100,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Kind',
                          cell: (p) => Text(p.paymentKind.replaceAll('_', ' ').toUpperCase()),
                          width: 130,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Payee / Vendor',
                          cell: (p) => Text(p.vendorName ?? p.payeeName ?? p.expenseAccountName ?? '-'),
                          width: 170,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Mode',
                          cell: (p) => Text(p.mode.toUpperCase()),
                          width: 90,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Bank/Cash Account',
                          cell: (p) => Text(p.bankCashAccountName ?? '-'),
                          width: 160,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Amount',
                          numeric: true,
                          cell: (p) => Text(formatPaise(p.amountPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 120,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Status',
                          cell: (p) => StatusChip(status: p.status),
                          width: 100,
                        ),
                        SocietyColumn<VendorPayment>(
                          label: 'Actions',
                          cell: (p) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.print_outlined, size: 18),
                                tooltip: 'Print Voucher',
                                onPressed: () => _printVoucher(p),
                              ),
                              if (p.status == 'posted')
                                IconButton(
                                  icon: const Icon(Icons.undo, size: 18, color: Colors.red),
                                  tooltip: 'Reverse Payment',
                                  onPressed: () => _showReverseDialog(p),
                                ),
                            ],
                          ),
                          width: 90,
                        ),
                      ],
                      rows: _payments,
                    ),
    );
  }
}
