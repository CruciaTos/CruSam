import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/bank_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class DepositsScreen extends StatefulWidget {
  const DepositsScreen({super.key});

  @override
  State<DepositsScreen> createState() => _DepositsScreenState();
}

class _DepositsScreenState extends State<DepositsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isLoading = true;
  String? _error;
  List<FixedDeposit> _allFds = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadFds();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFds() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final fds = await services.bank.listFixedDeposits(societyId);
      if (mounted) {
        setState(() {
          _allFds = fds;
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

  void _showNewFdDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final bankAccounts = await services.bank.listBankAccounts(societyId);

    if (!mounted) return;

    final bankNameCtrl = TextEditingController();
    final branchCtrl = TextEditingController();
    final fdNoCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '7.0');
    final startCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final maturityCtrl = TextEditingController(text: DateTime.now().add(const Duration(days: 365)).toIso8601String().substring(0, 10));
    int? fundingAccId = bankAccounts.isNotEmpty ? bankAccounts.first.bankAccount.id : null;
    bool autoRenew = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Open Fixed Deposit'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: bankNameCtrl,
                    decoration: const InputDecoration(labelText: 'Bank Name *', hintText: 'e.g. State Bank of India'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branchCtrl,
                    decoration: const InputDecoration(labelText: 'Branch Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fdNoCtrl,
                    decoration: const InputDecoration(labelText: 'FD Number / Receipt No *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: principalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Principal Amount (INR) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Interest Rate (% p.a.) *', hintText: '7.5'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: const InputDecoration(labelText: 'Start Date *'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maturityCtrl,
                          decoration: const InputDecoration(labelText: 'Maturity Date *'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (bankAccounts.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: fundingAccId,
                      decoration: const InputDecoration(labelText: 'Funding Bank Account'),
                      items: bankAccounts.map((a) => DropdownMenuItem(
                        value: a.bankAccount.id,
                        child: Text('${a.bankAccount.bankName} (${formatPaise(a.balancePaise)})'),
                      )).toList(),
                      onChanged: (v) => setDlgState(() => fundingAccId = v),
                    ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Auto-Renew on Maturity'),
                    value: autoRenew,
                    onChanged: (v) => setDlgState(() => autoRenew = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (bankNameCtrl.text.trim().isEmpty || fdNoCtrl.text.trim().isEmpty) return;
                final principal = (double.tryParse(principalCtrl.text.trim()) ?? 0.0) * 100;
                final ratePercent = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                final rateBp = (ratePercent * 100).round();

                if (fundingAccId == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please select funding bank account')));
                  return;
                }

                try {
                  await services.bank.openFixedDeposit(
                    societyId,
                    FixedDepositDraft(
                      bankName: branchCtrl.text.trim().isNotEmpty
                          ? '${bankNameCtrl.text.trim()} (${branchCtrl.text.trim()})'
                          : bankNameCtrl.text.trim(),
                      fdNo: fdNoCtrl.text.trim(),
                      principalPaise: principal.round(),
                      rateBp: rateBp,
                      startDate: startCtrl.text.trim(),
                      maturityDate: maturityCtrl.text.trim(),
                      bankCashAccountId: fundingAccId!,
                    ),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadFds();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Create FD'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDialog(FixedDeposit fd, String txnType) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final bankAccounts = await services.bank.listBankAccounts(societyId);

    if (!mounted) return;

    final isAccrual = txnType == 'interest_accrued';
    final isClose = txnType == 'close';
    final title = isAccrual ? 'Accrue Interest' : (isClose ? 'Close / Liquidate FD' : 'Receive Interest');

    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final amountCtrl = TextEditingController(text: isClose ? (fd.principalPaise / 100).toStringAsFixed(2) : '');
    final tdsCtrl = TextEditingController(text: '0.00');
    int? bankCashId = bankAccounts.isNotEmpty ? bankAccounts.first.bankAccount.id : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('$title - ${fd.fdNo}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(labelText: 'Transaction Date (YYYY-MM-DD) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isClose ? 'Total Payout Received (INR) *' : 'Interest Amount (INR) *',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tdsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'TDS Deducted (INR)', hintText: '0.00'),
                  ),
                  if (!isAccrual) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: bankCashId,
                      decoration: const InputDecoration(labelText: 'Deposit to Bank / Cash *'),
                      items: bankAccounts.map((a) => DropdownMenuItem(
                        value: a.bankAccount.id,
                        child: Text('${a.bankAccount.bankName} (${formatPaise(a.balancePaise)})'),
                      )).toList(),
                      onChanged: (v) => setDlgState(() => bankCashId = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = (double.tryParse(amountCtrl.text.trim()) ?? 0.0) * 100;
                final tds = (double.tryParse(tdsCtrl.text.trim()) ?? 0.0) * 100;
                if (amt <= 0) return;

                try {
                  await services.bank.postFdTransaction(
                    societyId,
                    FdTransactionDraft(
                      fdId: fd.id,
                      txnType: txnType,
                      txnDate: dateCtrl.text.trim(),
                      amountPaise: amt.round(),
                      tdsPaise: tds.round(),
                      bankCashAccountId: bankCashId,
                    ),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadFds();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Post Transaction'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Fixed Deposits',
      actions: [
        FilledButton.icon(
          onPressed: _showNewFdDialog,
          icon: const Icon(Icons.add),
          label: const Text('New Deposit'),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadFds);
    if (_allFds.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.savings_outlined,
        title: 'No Fixed Deposits',
        message: 'No fixed deposits have been created yet.',
        action: FilledButton(
          onPressed: _showNewFdDialog,
          child: const Text('New Deposit'),
        ),
      );
    }

    final activeFds = _allFds.where((f) => f.status == 'active').toList();
    final closedFds = _allFds.where((f) => f.status == 'closed').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabCtrl,
          labelColor: Theme.of(context).primaryColor,
          tabs: [
            Tab(text: 'Active Deposits (${activeFds.length})'),
            Tab(text: 'Closed Deposits (${closedFds.length})'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildFdTable(activeFds, isActiveTab: true),
              _buildFdTable(closedFds, isActiveTab: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFdTable(List<FixedDeposit> list, {required bool isActiveTab}) {
    if (list.isEmpty) {
      return Center(
        child: Text(isActiveTab ? 'No active deposits.' : 'No closed deposits.'),
      );
    }

    return SocietyDataTable<FixedDeposit>(
      columns: [
        SocietyColumn(
          label: 'FD Number',
          cell: (f) => Text(f.fdNo, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        SocietyColumn(
          label: 'Bank & Branch',
          cell: (f) => Text(f.bankName),
        ),
        SocietyColumn(
          label: 'Principal',
          numeric: true,
          cell: (f) => Text(formatPaise(f.principalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        SocietyColumn(
          label: 'Interest Rate',
          cell: (f) => Text('${(f.rateBp / 100).toStringAsFixed(2)}%'),
        ),
        SocietyColumn(
          label: 'Start Date',
          cell: (f) => Text(f.startDate),
        ),
        SocietyColumn(
          label: 'Maturity Date',
          cell: (f) => Text(f.maturityDate),
        ),
        SocietyColumn(
          label: 'Status',
          cell: (f) => Text(
            f.status.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: f.status == 'active' ? Colors.green.shade800 : Colors.grey,
            ),
          ),
        ),
        if (isActiveTab)
          SocietyColumn(
            label: 'Actions',
            cell: (f) => PopupMenuButton<String>(
              onSelected: (action) => _showTransactionDialog(f, action),
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'interest_accrued', child: Text('Accrue Interest')),
                PopupMenuItem(value: 'interest_received', child: Text('Receive Interest')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'close', child: Text('Close / Liquidate FD')),
              ],
            ),
          ),
      ],
      rows: list,
      total: list.length,
    );
  }
}
