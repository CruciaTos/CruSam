import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/society_models.dart';
import '../../data/models/statement_models.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class FinancialStatementsScreen extends StatefulWidget {
  const FinancialStatementsScreen({super.key});

  @override
  State<FinancialStatementsScreen> createState() => _FinancialStatementsScreenState();
}

class _FinancialStatementsScreenState extends State<FinancialStatementsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isLoading = true;
  String? _error;

  List<FinancialYear> _years = [];
  FinancialYear? _selectedFy;
  String _fromDate = '${DateTime.now().year}-04-01';
  String _toDate = '${DateTime.now().year + 1}-03-31';

  IncomeExpenditureStatement? _ie;
  BalanceSheetStatement? _bs;
  ReceiptsPaymentsStatement? _rp;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadYears();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadYears() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final years = await services.society.listFinancialYears(societyId);
      final active = years.where((y) => y.isOpen).isNotEmpty ? years.firstWhere((y) => y.isOpen) : (years.isNotEmpty ? years.first : null);

      if (mounted) {
        setState(() {
          _years = years;
          _selectedFy = active;
          if (active != null) {
            _fromDate = active.startDate;
            _toDate = active.endDate;
          }
        });
        _loadStatements();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStatements() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final ie = await services.financialStatements.incomeAndExpenditure(societyId, _fromDate, _toDate);
      final bs = await services.financialStatements.balanceSheet(societyId, _toDate);
      final rp = await services.financialStatements.receiptsAndPayments(societyId, _fromDate, _toDate);

      if (mounted) {
        setState(() {
          _ie = ie;
          _bs = bs;
          _rp = rp;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Financial Statements',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadStatements);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Year & Date Filter Bar
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Financial Year: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedFy?.id,
                  items: _years.map((y) => DropdownMenuItem(
                    value: y.id,
                    child: Text('FY ${y.code} (${y.isOpen ? "Open" : "Closed"})'),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      final sel = _years.firstWhere((y) => y.id == v);
                      setState(() {
                        _selectedFy = sel;
                        _fromDate = sel.startDate;
                        _toDate = sel.endDate;
                      });
                      _loadStatements();
                    }
                  },
                ),
                const SizedBox(width: 24),
                const Text('From: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: _fromDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _fromDate = v.trim());
                      _loadStatements();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                const Text('To / As of: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: _toDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _toDate = v.trim());
                      _loadStatements();
                    },
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh Statements',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadStatements,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        TabBar(
          controller: _tabCtrl,
          labelColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'Income & Expenditure'),
            Tab(text: 'Balance Sheet'),
            Tab(text: 'Receipts & Payments'),
          ],
        ),
        const SizedBox(height: 12),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildIncomeExpenditureTab(),
              _buildBalanceSheetTab(),
              _buildReceiptsPaymentsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Income & Expenditure Tab
  // -------------------------------------------------------------
  Widget _buildIncomeExpenditureTab() {
    final ie = _ie;
    if (ie == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Card(
            elevation: 0,
            color: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _kpi('Total Income', formatPaise(ie.totalIncomePaise), color: Colors.green.shade800),
                  const Text('-', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  _kpi('Total Expenditure', formatPaise(ie.totalExpensePaise), color: Colors.red.shade800),
                  const Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  _kpi(
                    ie.isSurplus ? 'Net Surplus' : 'Net Deficit',
                    formatPaise(ie.netSurplusDeficitPaise.abs()),
                    color: ie.isSurplus ? Colors.teal.shade800 : Colors.amber.shade900,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Two-column layout: Expenditure on Left, Income on Right (Standard Indian Society Format)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Expenditure side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('EXPENDITURE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        if (ie.expenseGroups.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('No expenditure in this period.'))
                        else
                          ...ie.expenseGroups.map((grp) => _buildGroupSection(grp)),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL EXPENDITURE', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(ie.totalExpensePaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Income side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('INCOME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        if (ie.incomeGroups.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('No income in this period.'))
                        else
                          ...ie.incomeGroups.map((grp) => _buildGroupSection(grp)),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL INCOME', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(ie.totalIncomePaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Balance Sheet Tab
  // -------------------------------------------------------------
  Widget _buildBalanceSheetTab() {
    final bs = _bs;
    if (bs == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Card(
            elevation: 0,
            color: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _kpi('Total Liabilities & Funds', formatPaise(bs.totalLiabilitiesPaise), color: Colors.blue.shade900),
                  _kpi('Total Assets', formatPaise(bs.totalAssetsPaise), color: Colors.blue.shade900),
                  _kpi(
                    bs.isBalanced ? 'Status' : 'Difference',
                    bs.isBalanced ? 'BALANCED' : formatPaise(bs.differencePaise.abs()),
                    color: bs.isBalanced ? Colors.green.shade800 : Colors.red.shade800,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Two-column layout: Liabilities on Left, Assets on Right (Indian Format)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Liabilities side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('LIABILITIES & FUNDS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        ...bs.liabilityGroups.map((grp) => _buildGroupSection(grp)),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL LIABILITIES & FUNDS', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(bs.totalLiabilitiesPaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Assets side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('ASSETS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        ...bs.assetGroups.map((grp) => _buildGroupSection(grp)),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL ASSETS', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(bs.totalAssetsPaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Receipts & Payments Tab
  // -------------------------------------------------------------
  Widget _buildReceiptsPaymentsTab() {
    final rp = _rp;
    if (rp == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Card(
            elevation: 0,
            color: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _kpi('Opening Bank & Cash', formatPaise(rp.openingBalancePaise)),
                  const Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  _kpi('Total Receipts', formatPaise(rp.totalReceiptsPaise), color: Colors.green.shade800),
                  const Text('-', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  _kpi('Total Payments', formatPaise(rp.totalPaymentsPaise), color: Colors.red.shade800),
                  const Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  _kpi('Closing Bank & Cash', formatPaise(rp.closingBalancePaise), color: Colors.blue.shade900, isBold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Receipts side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('RECEIPTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        if (rp.receipts.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('No receipts in this period.'))
                        else
                          ...rp.receipts.map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(r.name),
                                Text(formatPaise(r.amountPaise), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL RECEIPTS', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(rp.totalReceiptsPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Payments side
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('PAYMENTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Divider(height: 16),
                        if (rp.payments.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Text('No payments in this period.'))
                        else
                          ...rp.payments.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(p.name),
                                Text(formatPaise(p.amountPaise), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL PAYMENTS', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(formatPaise(rp.totalPaymentsPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(StatementGroup grp) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(grp.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
              Text(formatPaise(grp.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          ...grp.lines.map((l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                Text(formatPaise(l.amountPaise), style: const TextStyle(fontSize: 12)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, {Color? color, bool isBold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
