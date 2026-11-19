import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/bank_models.dart';
import '../../documents/pdf/reconciliation_pdf.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isLoading = true;
  String? _error;
  List<BankAccountRow> _bankAccounts = [];
  int? _selectedBankAccountId;
  String _asOfDate = DateTime.now().toIso8601String().substring(0, 10);
  ReconciliationView? _view;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final accounts = await services.bank.listBankAccounts(societyId);

      _bankAccounts = accounts;
      if (_bankAccounts.isNotEmpty && _selectedBankAccountId == null) {
        _selectedBankAccountId = _bankAccounts.first.bankAccount.id;
      }

      if (_selectedBankAccountId != null) {
        final view = await services.bank.reconciliation(
          societyId,
          _selectedBankAccountId!,
          _asOfDate,
        );
        _view = view;
      }

      if (mounted) {
        setState(() {
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

  Future<void> _toggleClearance(BankBookRow item) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      if (item.isCleared) {
        await services.bank.unclearLine(societyId, item.journalLineId);
      } else {
        await services.bank.clearLine(societyId, item.journalLineId, _asOfDate);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating clearance: $e')));
      }
    }
  }

  Future<void> _exportPdf() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _view == null) return;

    try {
      final services = await SocietyServices.instance();
      final society = await services.society.getSociety(societyId);

      final pdfBytes = await ReconciliationPdf.generateBytes(
        society: society,
        view: _view!,
      );

      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes,
        name: 'Bank_Reconciliation_${_view!.bankAccount.bankName}_$_asOfDate.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Bank Reconciliation',
      actions: [
        if (_view != null)
          FilledButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
          ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadData);
    if (_bankAccounts.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.account_balance_outlined,
        title: 'No Bank Accounts',
        message: 'Add bank accounts first before performing reconciliation.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar
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
                const Text('Bank Account: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedBankAccountId,
                  items: _bankAccounts.map((a) => DropdownMenuItem(
                    value: a.bankAccount.id,
                    child: Text('${a.bankAccount.bankName} (${a.bankAccount.accountNumber ?? ""})'),
                  )).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedBankAccountId = v);
                      _loadData();
                    }
                  },
                ),
                const SizedBox(width: 24),
                const Text('As of Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    initialValue: _asOfDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _asOfDate = v.trim());
                      _loadData();
                    },
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Formula Banner Summary
        if (_view != null) ...[
          Card(
            elevation: 0,
            color: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _kpiItem('Balance as per Book', formatPaise(_view!.summary.bookBalancePaise)),
                      const Text('-', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      _kpiItem('Uncleared Receipts', formatPaise(_view!.summary.unclearedReceiptsPaise), color: Colors.amber.shade900),
                      const Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      _kpiItem('Uncleared Payments', formatPaise(_view!.summary.unclearedPaymentsPaise), color: Colors.blue.shade900),
                      const Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      _kpiItem('Expected Statement', formatPaise(_view!.summary.expectedStatementBalancePaise), isBold: true),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text('Actual Statement Balance: ${formatPaise(_view!.summary.statementBalancePaise)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'Difference: ${formatPaise(_view!.summary.differencePaise)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _view!.summary.differencePaise == 0 ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          TabBar(
            controller: _tabCtrl,
            labelColor: Theme.of(context).primaryColor,
            tabs: [
              Tab(text: 'Book Transactions (${_view!.bookItems.length})'),
              Tab(text: 'Imported Statement Lines (${_view!.statementLines.length})'),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildBookItemsTab(),
                _buildStatementLinesTab(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _kpiItem(String label, String value, {Color? color, bool isBold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBookItemsTab() {
    final items = _view?.bookItems ?? [];
    if (items.isEmpty) {
      return const Center(child: Text('No book transactions found for this account.'));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, index) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final item = items[i];
        return ListTile(
          dense: true,
          leading: Checkbox(
            value: item.isCleared,
            onChanged: (_) => _toggleClearance(item),
          ),
          title: Row(
            children: [
              Text(item.entryDate, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(item.entryNo, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              Expanded(child: Text(item.narration.isEmpty ? (item.contraAccountName ?? '') : item.narration)),
            ],
          ),
          subtitle: item.clearedDate != null
              ? Text('Cleared on: ${item.clearedDate}', style: TextStyle(color: Colors.green.shade700, fontSize: 11))
              : const Text('Uncleared', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
          trailing: Text(
            item.debitPaise > 0 ? '+${formatPaise(item.debitPaise)}' : '-${formatPaise(item.creditPaise)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.debitPaise > 0 ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatementLinesTab() {
    final items = _view?.statementLines ?? [];
    if (items.isEmpty) {
      return const Center(child: Text('No imported statement lines found for this period.'));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, index) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final item = items[i];
        return ListTile(
          dense: true,
          title: Row(
            children: [
              Text(item.lineDate, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (item.reference != null && item.reference!.isNotEmpty)
                Text('[${item.reference}] ', style: const TextStyle(color: Colors.grey)),
              Expanded(child: Text(item.description ?? '-')),
            ],
          ),
          trailing: Text(
            item.depositPaise > 0 ? '+${formatPaise(item.depositPaise)}' : '-${formatPaise(item.withdrawalPaise)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.depositPaise > 0 ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        );
      },
    );
  }
}
