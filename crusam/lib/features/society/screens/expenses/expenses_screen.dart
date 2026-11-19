import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _loading = true;
  String? _error;
  List<ExpenseBill> _bills = [];
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
      final list = await services.expenses.listExpenseBills(
        societyId,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );

      if (mounted) {
        setState(() {
          _bills = list;
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

  void _showReverseDialog(ExpenseBill bill) {
    final reasonCtrl = TextEditingController();
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverse Bill ${bill.voucherNo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to reverse bill ${bill.vendorBillNo} (${bill.vendorName})?'),
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
                await services.expenses.reverseExpenseBill(societyId, bill.id, dateStr, reasonCtrl.text.trim());
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
      title: 'Expense Bills',
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
          label: const Text('New Expense Bill'),
          onPressed: () async {
            await context.push('/society/expenses/new');
            _load();
          },
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SocietyErrorView(message: _error!, onRetry: _load)
              : _bills.isEmpty
                  ? SocietyEmptyView(
                      icon: Icons.receipt_outlined,
                      title: 'No expense bills found',
                      message: 'Record bills received from service vendors and contractors.',
                      action: FilledButton(
                        onPressed: () => context.push('/society/expenses/new'),
                        child: const Text('New Expense Bill'),
                      ),
                    )
                  : SocietyDataTable<ExpenseBill>(
                      total: _bills.length,
                      columns: [
                        SocietyColumn<ExpenseBill>(
                          label: 'Voucher No',
                          cell: (b) => Text(b.voucherNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 140,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Post Date',
                          cell: (b) => Text(b.postDate),
                          width: 100,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Vendor',
                          cell: (b) => Text(b.vendorName ?? '-'),
                          width: 160,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Bill No',
                          cell: (b) => Text(b.vendorBillNo),
                          width: 120,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Total',
                          numeric: true,
                          cell: (b) => Text(formatPaise(b.totalPaise)),
                          width: 110,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'TDS',
                          numeric: true,
                          cell: (b) => Text(formatPaise(b.tdsPaise)),
                          width: 100,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Payable',
                          numeric: true,
                          cell: (b) => Text(formatPaise(b.payablePaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 110,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Paid',
                          numeric: true,
                          cell: (b) => Text(formatPaise(b.paidPaise)),
                          width: 100,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Balance',
                          numeric: true,
                          cell: (b) => Text(
                            formatPaise(b.balancePaise),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: b.balancePaise > 0 ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                          width: 110,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Status',
                          cell: (b) => StatusChip(status: b.status),
                          width: 100,
                        ),
                        SocietyColumn<ExpenseBill>(
                          label: 'Actions',
                          cell: (b) => b.status == 'posted' && b.paidPaise == 0
                              ? IconButton(
                                  icon: const Icon(Icons.undo, size: 18, color: Colors.red),
                                  tooltip: 'Reverse Bill',
                                  onPressed: () => _showReverseDialog(b),
                                )
                              : const SizedBox(),
                          width: 80,
                        ),
                      ],
                      rows: _bills,
                    ),
    );
  }
}
