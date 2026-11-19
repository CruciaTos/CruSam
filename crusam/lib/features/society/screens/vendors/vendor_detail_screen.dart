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

class VendorDetailScreen extends StatefulWidget {
  final int vendorId;
  const VendorDetailScreen({super.key, required this.vendorId});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;

  VendorDetail? _detail;
  List<ExpenseBill> _bills = [];
  List<VendorPayment> _payments = [];
  VendorStatement? _statement;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
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
      final detail = await services.expenses.vendorDetail(societyId, widget.vendorId);
      final bills = await services.expenses.listExpenseBills(societyId, vendorId: widget.vendorId);
      final payments = await services.expenses.listVendorPayments(societyId, vendorId: widget.vendorId);

      final now = DateTime.now();
      final from = '${now.year}-04-01';
      final to = '${now.year + 1}-03-31';
      final stmt = await services.expenses.vendorStatement(societyId, widget.vendorId, from, to);

      if (mounted) {
        setState(() {
          _detail = detail;
          _bills = bills;
          _payments = payments;
          _statement = stmt;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _detail == null) {
      return Scaffold(body: SocietyErrorView(message: _error ?? 'Vendor not found', onRetry: _load));
    }

    final v = _detail!.vendor;

    return SocietyPage(
      title: '${v.name} (${v.vendorCode ?? "No code"})',
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Vendor'),
          onPressed: () async {
            await context.push('/society/vendors/${widget.vendorId}/edit');
            _load();
          },
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('New Bill'),
          onPressed: () async {
            await context.push('/society/expenses/new?vendorId=${widget.vendorId}');
            _load();
          },
        ),
      ],
      child: Column(
        children: [
          // KPI summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _buildKpi('Total Billed', formatPaise(_detail!.totalBilledPaise)),
                _buildKpi('Total Paid', formatPaise(_detail!.totalPaidPaise)),
                _buildKpi('Advances', formatPaise(_detail!.advancePaise)),
                _buildKpi(
                  'Current Balance',
                  formatPaise(_detail!.balancePaise),
                  isBold: true,
                  color: _detail!.balancePaise > 0 ? Colors.red.shade700 : Colors.green.shade700,
                ),
                _buildKpi('Open Bills', _detail!.openBillsCount.toString()),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: 'Profile'),
              Tab(text: 'Statement'),
              Tab(text: 'Bills'),
              Tab(text: 'Payments'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildProfileTab(v),
                _buildStatementTab(),
                _buildBillsTab(),
                _buildPaymentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String value, {bool isBold = false, Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab(Vendor v) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contact & Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildRow('Contact Person', v.contactName ?? '-'),
                  _buildRow('Phone', v.phone ?? '-'),
                  _buildRow('Email', v.email ?? '-'),
                  _buildRow('Address', v.address ?? '-'),
                  _buildRow('PAN', v.pan ?? '-'),
                  _buildRow('GSTIN', v.gstin ?? '-'),
                  _buildRow('Default Expense Head', v.defaultExpenseAccountName ?? '-'),
                  _buildRow('Applicable TDS', v.tdsSectionCode != null ? '${v.tdsSectionCode} (${((v.tdsRateBp ?? 0) / 100)}%)' : 'None'),
                  _buildRow('Bank Account', v.bankAccountNo != null ? '${v.bankAccountNo} (${v.ifsc ?? ""})' : '-'),
                  _buildRow('Payee Name', v.payeeName ?? '-'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildStatementTab() {
    if (_statement == null || _statement!.rows.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions found',
        message: 'No ledger transactions recorded for this vendor.',
      );
    }
    return SocietyDataTable<VendorStatementRow>(
      total: _statement!.rows.length,
      columns: [
        SocietyColumn<VendorStatementRow>(
          label: 'Date',
          cell: (r) => Text(r.date),
          width: 100,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Type',
          cell: (r) => Text(r.type),
          width: 100,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Ref No',
          cell: (r) => Text(r.refNo),
          width: 130,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Description',
          cell: (r) => Text(r.description),
          width: 200,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Debit (Payment)',
          numeric: true,
          cell: (r) => Text(r.debitPaise > 0 ? formatPaise(r.debitPaise) : '-'),
          width: 120,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Credit (Bill)',
          numeric: true,
          cell: (r) => Text(r.creditPaise > 0 ? formatPaise(r.creditPaise) : '-'),
          width: 120,
        ),
        SocietyColumn<VendorStatementRow>(
          label: 'Balance',
          numeric: true,
          cell: (r) => Text(formatPaise(r.balancePaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
        ),
      ],
      rows: _statement!.rows,
    );
  }

  Widget _buildBillsTab() {
    if (_bills.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.receipt_outlined,
        title: 'No bills recorded',
        message: 'No expense bills found for this vendor.',
      );
    }
    return SocietyDataTable<ExpenseBill>(
      total: _bills.length,
      columns: [
        SocietyColumn<ExpenseBill>(
          label: 'Voucher No',
          cell: (b) => Text(b.voucherNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 130,
        ),
        SocietyColumn<ExpenseBill>(
          label: 'Bill No',
          cell: (b) => Text(b.vendorBillNo),
          width: 120,
        ),
        SocietyColumn<ExpenseBill>(
          label: 'Posting Date',
          cell: (b) => Text(b.postDate),
          width: 100,
        ),
        SocietyColumn<ExpenseBill>(
          label: 'Subtotal',
          numeric: true,
          cell: (b) => Text(formatPaise(b.subtotalPaise)),
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
          cell: (b) => Text(formatPaise(b.balancePaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 110,
        ),
        SocietyColumn<ExpenseBill>(
          label: 'Status',
          cell: (b) => StatusChip(status: b.status),
          width: 100,
        ),
      ],
      rows: _bills,
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.payments_outlined,
        title: 'No payments recorded',
        message: 'No payments found for this vendor.',
      );
    }
    return SocietyDataTable<VendorPayment>(
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
          width: 120,
        ),
        SocietyColumn<VendorPayment>(
          label: 'Mode',
          cell: (p) => Text(p.mode.toUpperCase()),
          width: 90,
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
      ],
      rows: _payments,
    );
  }
}
