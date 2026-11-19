import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/bank_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  bool _isLoading = true;
  String? _error;
  List<BankTransfer> _transfers = [];

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  Future<void> _loadTransfers() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final transfers = await services.bank.listTransfers(societyId);
      if (mounted) {
        setState(() {
          _transfers = transfers;
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

  void _showNewTransferDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final accounts = await services.bank.listBankAccounts(societyId);
    if (accounts.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('At least two bank or cash accounts are required to transfer.')),
        );
      }
      return;
    }

    if (!mounted) return;

    int? fromAccId = accounts.first.bankAccount.id;
    int? toAccId = accounts.length > 1 ? accounts[1].bankAccount.id : accounts.first.bankAccount.id;
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final narrationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('New Bank / Cash Transfer'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: fromAccId,
                    decoration: const InputDecoration(labelText: 'From Account *'),
                    items: accounts.map((a) => DropdownMenuItem(
                      value: a.bankAccount.id,
                      child: Text('${a.bankAccount.bankName} (${formatPaise(a.balancePaise)})'),
                    )).toList(),
                    onChanged: (v) => setDlgState(() => fromAccId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: toAccId,
                    decoration: const InputDecoration(labelText: 'To Account *'),
                    items: accounts.map((a) => DropdownMenuItem(
                      value: a.bankAccount.id,
                      child: Text('${a.bankAccount.bankName} (${formatPaise(a.balancePaise)})'),
                    )).toList(),
                    onChanged: (v) => setDlgState(() => toAccId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(labelText: 'Transfer Date (YYYY-MM-DD) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount (INR) *', hintText: '0.00'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'Reference / Cheque No'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: narrationCtrl,
                    decoration: const InputDecoration(labelText: 'Narration / Description'),
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
                if (fromAccId == null || toAccId == null) return;
                if (fromAccId == toAccId) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('From and To accounts must be different')),
                  );
                  return;
                }
                final rupees = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final paise = (rupees * 100).round();
                if (paise <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Amount must be greater than zero')),
                  );
                  return;
                }

                try {
                  await services.bank.postTransfer(
                    societyId,
                    BankTransferDraft(
                      fromAccountId: fromAccId!,
                      toAccountId: toAccId!,
                      transferDate: dateCtrl.text.trim(),
                      amountPaise: paise,
                      instrumentNo: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                      narration: narrationCtrl.text.trim().isEmpty ? null : narrationCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadTransfers();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Record Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReverseDialog(BankTransfer transfer) {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final reasonCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverse Transfer ${transfer.transferNo}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Are you sure you want to reverse transfer ${transfer.transferNo} of ${formatPaise(transfer.amountPaise)}?'),
              const SizedBox(height: 16),
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(labelText: 'Reversal Date (YYYY-MM-DD) *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reversal Reason *'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) return;
              try {
                final services = await SocietyServices.instance();
                await services.bank.reverseTransfer(
                  societyId,
                  transfer.id,
                  dateCtrl.text.trim(),
                  reasonCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadTransfers();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Reverse Transfer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Bank & Cash Transfers',
      actions: [
        FilledButton.icon(
          onPressed: _showNewTransferDialog,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('New Transfer'),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadTransfers);
    if (_transfers.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.swap_horiz_outlined,
        title: 'No Transfers',
        message: 'No bank or cash transfers recorded yet.',
        action: FilledButton(
          onPressed: _showNewTransferDialog,
          child: const Text('New Transfer'),
        ),
      );
    }

    return SocietyDataTable<BankTransfer>(
      columns: [
        SocietyColumn(
          label: 'Transfer No',
          cell: (t) => Text(t.transferNo, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        SocietyColumn(
          label: 'Date',
          cell: (t) => Text(t.transferDate),
        ),
        SocietyColumn(
          label: 'From Account',
          cell: (t) => Text(t.fromAccountName ?? 'Account ${t.fromAccountId}'),
        ),
        SocietyColumn(
          label: 'To Account',
          cell: (t) => Text(t.toAccountName ?? 'Account ${t.toAccountId}'),
        ),
        SocietyColumn(
          label: 'Amount',
          numeric: true,
          cell: (t) => Text(formatPaise(t.amountPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        SocietyColumn(
          label: 'Status',
          cell: (t) => Text(
            t.status.toUpperCase(),
            style: TextStyle(
              color: t.status == 'posted' ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SocietyColumn(
          label: 'Actions',
          cell: (t) => t.status == 'posted'
              ? TextButton(
                  onPressed: () => _showReverseDialog(t),
                  child: Text('Reverse', style: TextStyle(color: Colors.red.shade700)),
                )
              : const Text('-'),
        ),
      ],
      rows: _transfers,
      total: _transfers.length,
    );
  }
}
