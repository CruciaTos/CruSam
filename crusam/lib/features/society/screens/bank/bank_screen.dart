import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/bank_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  bool _isLoading = true;
  String? _error;
  List<BankAccountRow> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final accounts = await services.bank.listBankAccounts(societyId);
      if (mounted) {
        setState(() {
          _accounts = accounts;
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

  void _showAddAccountDialog() {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final bankNameCtrl = TextEditingController();
    final branchCtrl = TextEditingController();
    final accNoCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    String accType = 'current';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Bank / Cash Account'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: bankNameCtrl,
                    decoration: const InputDecoration(labelText: 'Bank Name *', hintText: 'e.g. HDFC Bank, Cash Box'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: accType,
                    decoration: const InputDecoration(labelText: 'Account Type *'),
                    items: const [
                      DropdownMenuItem(value: 'savings', child: Text('Savings Account')),
                      DropdownMenuItem(value: 'current', child: Text('Current Account')),
                      DropdownMenuItem(value: 'cash', child: Text('Cash Box / Petty Cash')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlgState(() => accType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: accNoCtrl,
                    decoration: const InputDecoration(labelText: 'Account Number', hintText: 'Optional for cash'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branchCtrl,
                    decoration: const InputDecoration(labelText: 'Branch'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ifscCtrl,
                    decoration: const InputDecoration(labelText: 'IFSC Code'),
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
                if (bankNameCtrl.text.trim().isEmpty) return;
                try {
                  final services = await SocietyServices.instance();
                  await services.bank.createBankAccount(
                    societyId,
                    BankAccountDraft(
                      bankName: bankNameCtrl.text.trim(),
                      branch: branchCtrl.text.trim().isEmpty ? null : branchCtrl.text.trim(),
                      accountNumber: accNoCtrl.text.trim().isEmpty ? null : accNoCtrl.text.trim(),
                      ifsc: ifscCtrl.text.trim().isEmpty ? null : ifscCtrl.text.trim(),
                      accountType: accType,
                    ),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadAccounts();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Save Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBankBookDialog(BankAccountRow row) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final now = DateTime.now();
      final fromDate = '${now.year}-04-01';
      final toDate = '${now.year + 1}-03-31';

      final lines = await services.bank.bankBook(
        societyId,
        BankBookFilter(
          bankAccountId: row.bankAccount.id,
          fromDate: fromDate,
          toDate: toDate,
        ),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Bank Book - ${row.bankAccount.bankName}'),
          content: SizedBox(
            width: 800,
            height: 500,
            child: lines.isEmpty
                ? const Center(child: Text('No transactions recorded for this account.'))
                : ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final item = lines[i];
                      return ListTile(
                        dense: true,
                        title: Row(
                          children: [
                            Text(item.entryDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text(item.entryNo, style: const TextStyle(color: Colors.grey)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item.narration.isEmpty ? (item.contraAccountName ?? '') : item.narration)),
                          ],
                        ),
                        trailing: Text(
                          item.debitPaise > 0 ? '+${formatPaise(item.debitPaise)}' : '-${formatPaise(item.creditPaise)}',
                          style: TextStyle(
                            color: item.debitPaise > 0 ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading book: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Bank & Cash Accounts',
      actions: [
        FilledButton.icon(
          onPressed: _showAddAccountDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add Account'),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadAccounts);
    if (_accounts.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.account_balance_outlined,
        title: 'No Bank Accounts',
        message: 'Add a society bank or cash account to begin.',
        action: FilledButton(
          onPressed: _showAddAccountDialog,
          child: const Text('Add Account'),
        ),
      );
    }

    return SocietyDataTable<BankAccountRow>(
      columns: [
        SocietyColumn(
          label: 'Code',
          cell: (r) => Text(r.account.code, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        SocietyColumn(
          label: 'Bank / Cash Name',
          cell: (r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r.bankAccount.bankName, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (r.bankAccount.branch != null && r.bankAccount.branch!.isNotEmpty)
                Text(r.bankAccount.branch!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
        SocietyColumn(
          label: 'Account Number',
          cell: (r) => Text(r.bankAccount.accountNumber ?? '-'),
        ),
        SocietyColumn(
          label: 'Type',
          cell: (r) => Chip(
            label: Text(r.bankAccount.accountType.toUpperCase(), style: const TextStyle(fontSize: 10)),
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        SocietyColumn(
          label: 'Ledger Balance',
          numeric: true,
          cell: (r) => Text(
            formatPaise(r.balancePaise),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: r.balancePaise >= 0 ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
        ),
        SocietyColumn(
          label: 'Status',
          cell: (r) => Text(r.bankAccount.isActive ? 'Active' : 'Inactive'),
        ),
        SocietyColumn(
          label: 'Actions',
          cell: (r) => TextButton.icon(
            onPressed: () => _showBankBookDialog(r),
            icon: const Icon(Icons.menu_book_outlined, size: 16),
            label: const Text('Bank Book'),
          ),
        ),
      ],
      rows: _accounts,
      total: _accounts.length,
    );
  }
}
