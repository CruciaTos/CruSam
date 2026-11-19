import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/other_income_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/money_field.dart';

class OtherIncomeScreen extends StatefulWidget {
  const OtherIncomeScreen({super.key});

  @override
  State<OtherIncomeScreen> createState() => _OtherIncomeScreenState();
}

class _OtherIncomeScreenState extends State<OtherIncomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  String? _error;

  List<OtherInvoice> _invoices = [];
  List<OtherReceipt> _receipts = [];
  List<PartyRow> _parties = [];

  // Statement Tab state
  int? _selectedPartyId;
  PartyStatement? _statement;
  bool _loadingStatement = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final invs = await services.otherIncome.listInvoices(societyId);
      final rcts = await services.otherIncome.listReceipts(societyId);
      final prts = await services.otherIncome.listParties(societyId);

      if (mounted) {
        setState(() {
          _invoices = invs;
          _receipts = rcts;
          _parties = prts;
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

  Future<void> _loadStatement(int partyId) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _loadingStatement = true);
    try {
      final services = await SocietyServices.instance();
      final now = DateTime.now();
      final from = '${now.year}-04-01';
      final to = '${now.year + 1}-03-31';
      final stmt = await services.otherIncome.partyStatement(societyId, partyId, from, to);
      if (mounted) {
        setState(() {
          _selectedPartyId = partyId;
          _statement = stmt;
          _loadingStatement = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading statement: $e')));
        setState(() => _loadingStatement = false);
      }
    }
  }

  void _showAddPartyDialog() {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final panCtrl = TextEditingController();
    final gstinCtrl = TextEditingController();
    final stateCtrl = TextEditingController(text: 'MH');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Party'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Party / Tenant Name *')),
              const SizedBox(height: 12),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact Person')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: panCtrl, decoration: const InputDecoration(labelText: 'PAN'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: gstinCtrl, decoration: const InputDecoration(labelText: 'GSTIN'))),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 70,
                    child: TextField(controller: stateCtrl, decoration: const InputDecoration(labelText: 'State')),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final societyId = SocietyContext.instance.societyId;
              if (societyId == null) return;
              try {
                final services = await SocietyServices.instance();
                await services.otherIncome.saveParty(
                  societyId,
                  PartyDraft(
                    name: nameCtrl.text.trim(),
                    contactName: contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    pan: panCtrl.text.trim().isEmpty ? null : panCtrl.text.trim(),
                    gstin: gstinCtrl.text.trim().isEmpty ? null : gstinCtrl.text.trim(),
                    stateCode: stateCtrl.text.trim().isEmpty ? null : stateCtrl.text.trim(),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddReceiptDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final bankAccounts = await services.ledger.listAccounts(societyId);
    final bankCashAccounts = bankAccounts.where((a) => a.accountKind == 'bank' || a.accountKind == 'cash').toList();

    if (_parties.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a party first')));
      return;
    }
    if (bankCashAccounts.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No bank/cash accounts found')));
      return;
    }

    int selectedPartyId = _parties.first.party.id;
    int selectedBankId = bankCashAccounts.first.id;
    int amountPaise = 0;
    String mode = 'neft';
    final instCtrl = TextEditingController();
    final narrationCtrl = TextEditingController();
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Record Other Receipt'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedPartyId,
                  decoration: const InputDecoration(labelText: 'Party *'),
                  items: _parties.map((p) => DropdownMenuItem(value: p.party.id, child: Text(p.party.name))).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedPartyId = v);
                  },
                ),
                const SizedBox(height: 12),
                MoneyField(
                  label: 'Amount *',
                  value: amountPaise,
                  onChanged: (v) => setDlgState(() => amountPaise = v ?? 0),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: mode,
                        decoration: const InputDecoration(labelText: 'Mode *'),
                        items: const [
                          DropdownMenuItem(value: 'neft', child: Text('NEFT / RTGS')),
                          DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                          DropdownMenuItem(value: 'upi', child: Text('UPI')),
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        ],
                        onChanged: (v) {
                          if (v != null) setDlgState(() => mode = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedBankId,
                        decoration: const InputDecoration(labelText: 'Deposit To *'),
                        items: bankCashAccounts.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                        onChanged: (v) {
                          if (v != null) setDlgState(() => selectedBankId = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: instCtrl, decoration: const InputDecoration(labelText: 'Reference / Instrument No')),
                const SizedBox(height: 12),
                TextField(controller: narrationCtrl, decoration: const InputDecoration(labelText: 'Narration / Notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (amountPaise <= 0) return;
                try {
                  await services.otherIncome.postReceipt(
                    societyId,
                    OtherReceiptDraft(
                      partyId: selectedPartyId,
                      receiptDate: dateStr,
                      amountPaise: amountPaise,
                      mode: mode,
                      instrumentNo: instCtrl.text.trim().isEmpty ? null : instCtrl.text.trim(),
                      bankCashAccountId: selectedBankId,
                      narration: narrationCtrl.text.trim().isEmpty ? null : narrationCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadAll();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Record Receipt'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Other Income',
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add Party'),
          onPressed: _showAddPartyDialog,
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_card_outlined),
          label: const Text('Record Receipt'),
          onPressed: _showAddReceiptDialog,
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('New Invoice'),
          onPressed: () async {
            await context.push('/society/other-income/invoices/new');
            _loadAll();
          },
        ),
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: 'Invoices'),
              Tab(text: 'Receipts'),
              Tab(text: 'Parties'),
              Tab(text: 'Statements'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? SocietyErrorView(message: _error!, onRetry: _loadAll)
                    : TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _buildInvoicesTab(),
                          _buildReceiptsTab(),
                          _buildPartiesTab(),
                          _buildStatementsTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesTab() {
    if (_invoices.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.receipt_outlined,
        title: 'No other income invoices',
        message: 'Create invoices for hall booking, stall rent, tower rent, etc.',
      );
    }
    return SocietyDataTable<OtherInvoice>(
      total: _invoices.length,
      columns: [
        SocietyColumn<OtherInvoice>(
          label: 'Invoice No',
          cell: (inv) => Text(inv.invoiceNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 140,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Party',
          cell: (inv) => Text(inv.partyName ?? '-'),
          width: 160,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Date',
          cell: (inv) => Text(inv.invoiceDate),
          width: 100,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Due Date',
          cell: (inv) => Text(inv.dueDate),
          width: 100,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Subtotal',
          numeric: true,
          cell: (inv) => Text(formatPaise(inv.subtotalPaise)),
          width: 110,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'GST',
          numeric: true,
          cell: (inv) => Text(formatPaise(inv.cgstPaise + inv.sgstPaise + inv.igstPaise)),
          width: 100,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Total',
          numeric: true,
          cell: (inv) => Text(formatPaise(inv.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
        ),
        SocietyColumn<OtherInvoice>(
          label: 'Status',
          cell: (inv) => StatusChip(status: inv.status),
          width: 100,
        ),
      ],
      rows: _invoices,
    );
  }

  Widget _buildReceiptsTab() {
    if (_receipts.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.add_card_outlined,
        title: 'No other receipts',
        message: 'Record payments received from non-member parties.',
      );
    }
    return SocietyDataTable<OtherReceipt>(
      total: _receipts.length,
      columns: [
        SocietyColumn<OtherReceipt>(
          label: 'Receipt No',
          cell: (r) => Text(r.receiptNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 140,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Party',
          cell: (r) => Text(r.partyName ?? '-'),
          width: 160,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Date',
          cell: (r) => Text(r.receiptDate),
          width: 100,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Mode',
          cell: (r) => Text(r.mode.toUpperCase()),
          width: 90,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Account',
          cell: (r) => Text(r.bankCashAccountName ?? '-'),
          width: 150,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Amount',
          numeric: true,
          cell: (r) => Text(formatPaise(r.amountPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
        ),
        SocietyColumn<OtherReceipt>(
          label: 'Status',
          cell: (r) => StatusChip(status: r.status),
          width: 100,
        ),
      ],
      rows: _receipts,
    );
  }

  Widget _buildPartiesTab() {
    if (_parties.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.people_outline,
        title: 'No parties added',
        message: 'Add advertising agencies, telecom vendors, or event organizers.',
      );
    }
    return SocietyDataTable<PartyRow>(
      total: _parties.length,
      columns: [
        SocietyColumn<PartyRow>(
          label: 'Party Name',
          cell: (p) => Text(p.party.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 180,
        ),
        SocietyColumn<PartyRow>(
          label: 'Contact',
          cell: (p) => Text(p.party.contactName ?? '-'),
          width: 140,
        ),
        SocietyColumn<PartyRow>(
          label: 'Phone',
          cell: (p) => Text(p.party.phone ?? '-'),
          width: 120,
        ),
        SocietyColumn<PartyRow>(
          label: 'GSTIN',
          cell: (p) => Text(p.party.gstin ?? '-'),
          width: 140,
        ),
        SocietyColumn<PartyRow>(
          label: 'Billed',
          numeric: true,
          cell: (p) => Text(formatPaise(p.totalInvoicedPaise)),
          width: 110,
        ),
        SocietyColumn<PartyRow>(
          label: 'Received',
          numeric: true,
          cell: (p) => Text(formatPaise(p.totalPaidPaise)),
          width: 110,
        ),
        SocietyColumn<PartyRow>(
          label: 'Balance',
          numeric: true,
          cell: (p) => Text(formatPaise(p.balancePaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
        ),
      ],
      rows: _parties,
    );
  }

  Widget _buildStatementsTab() {
    if (_parties.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.account_balance_outlined,
        title: 'No parties available',
        message: 'Add a party to view their ledger statement.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedPartyId,
                  decoration: const InputDecoration(labelText: 'Select Party'),
                  items: _parties.map((p) => DropdownMenuItem(value: p.party.id, child: Text(p.party.name))).toList(),
                  onChanged: (v) {
                    if (v != null) _loadStatement(v);
                  },
                ),
              ),
              const SizedBox(width: 16),
              if (_statement != null)
                Text(
                  'Closing Balance: ${formatPaise(_statement!.closingBalancePaise)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingStatement
              ? const Center(child: CircularProgressIndicator())
              : _statement == null || _statement!.rows.isEmpty
                  ? const SocietyEmptyView(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions found',
                      message: 'Select a party to view their ledger statement.',
                    )
                  : SocietyDataTable<PartyStatementRow>(
                      total: _statement!.rows.length,
                      columns: [
                        SocietyColumn<PartyStatementRow>(
                          label: 'Date',
                          cell: (r) => Text(r.date),
                          width: 100,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Type',
                          cell: (r) => Text(r.type),
                          width: 100,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Ref No',
                          cell: (r) => Text(r.refNo),
                          width: 130,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Description',
                          cell: (r) => Text(r.description),
                          width: 200,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Debit',
                          numeric: true,
                          cell: (r) => Text(r.debitPaise > 0 ? formatPaise(r.debitPaise) : '-'),
                          width: 110,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Credit',
                          numeric: true,
                          cell: (r) => Text(r.creditPaise > 0 ? formatPaise(r.creditPaise) : '-'),
                          width: 110,
                        ),
                        SocietyColumn<PartyStatementRow>(
                          label: 'Balance',
                          numeric: true,
                          cell: (r) => Text(formatPaise(r.balancePaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 120,
                        ),
                      ],
                      rows: _statement!.rows,
                    ),
        ),
      ],
    );
  }
}
