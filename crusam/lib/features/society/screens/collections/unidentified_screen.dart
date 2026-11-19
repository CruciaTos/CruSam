import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class UnidentifiedScreen extends StatefulWidget {
  const UnidentifiedScreen({super.key});

  @override
  State<UnidentifiedScreen> createState() => _UnidentifiedScreenState();
}

class _UnidentifiedScreenState extends State<UnidentifiedScreen> {
  bool _loading = true;
  String? _error;
  List<UnidentifiedReceipt> _receipts = [];
  List<UnitRow> _units = [];
  List<Map<String, Object?>> _bankAccounts = [];
  String _statusFilter = 'open';

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
      final res = await services.collection.listUnidentified(
        societyId,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      final uRes = await services.member.listUnits(societyId, page: const PageRequest(limit: 5000));
      final bAccRows = await services.db.rawQuery('''
        SELECT ba.account_id, ba.bank_name, a.name as account_name
        FROM bank_accounts ba
        JOIN accounts a ON ba.account_id = a.id
        WHERE ba.society_id = ? AND ba.is_active = 1
        ORDER BY ba.account_type ASC, a.name ASC
      ''', [societyId]);

      if (mounted) {
        setState(() {
          _receipts = res.rows;
          _units = uRes.rows;
          _bankAccounts = bAccRows;
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

  Future<void> _openRecordDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: today);
    final amtCtrl = TextEditingController();
    final modeCtrl = TextEditingController(text: 'neft');
    final instCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final narrCtrl = TextEditingController();
    int? selBankAccId = _bankAccounts.isNotEmpty ? _bankAccounts.first['account_id'] as int : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Record Unidentified Deposit'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dateCtrl,
                    decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD) *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (Rs.) *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selBankAccId,
                    decoration: const InputDecoration(labelText: 'Bank Account *', border: OutlineInputBorder()),
                    items: _bankAccounts.map((b) {
                      final id = b['account_id'] as int;
                      final name = (b['bank_name'] as String?) ?? (b['account_name'] as String);
                      return DropdownMenuItem<int>(value: id, child: Text(name));
                    }).toList(),
                    onChanged: (v) => setDlgState(() => selBankAccId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: modeCtrl.text,
                          decoration: const InputDecoration(labelText: 'Mode', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'neft', child: Text('NEFT / RTGS')),
                            DropdownMenuItem(value: 'upi', child: Text('UPI / QR')),
                            DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                            DropdownMenuItem(value: 'cash', child: Text('Cash')),
                            DropdownMenuItem(value: 'other', child: Text('Other')),
                          ],
                          onChanged: (v) {
                            if (v != null) modeCtrl.text = v;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: instCtrl,
                          decoration: const InputDecoration(labelText: 'UTR / Cheque No', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankCtrl,
                    decoration: const InputDecoration(labelText: 'Remitter Bank', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: narrCtrl,
                    decoration: const InputDecoration(labelText: 'Notes / Remarks', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amt = parseRupeesToPaise(amtCtrl.text);
                if (amt == null || amt <= 0 || selBankAccId == null) return;

                try {
                  final services = await SocietyServices.instance();
                  await services.collection.createUnidentified(
                    societyId,
                    UnidentifiedReceiptDraft(
                      receiptDate: dateCtrl.text.trim(),
                      amountPaise: amt,
                      mode: modeCtrl.text.trim(),
                      instrumentNo: instCtrl.text.trim(),
                      instrumentBank: bankCtrl.text.trim(),
                      bankCashAccountId: selBankAccId!,
                      narration: narrCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unidentified deposit recorded successfully.')),
      );
      _load();
    }
  }

  Future<void> _openResolveDialog(UnidentifiedReceipt unrec) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    int? selUnitId = _units.isNotEmpty ? _units.first.id : null;
    final payerCtrl = TextEditingController(text: _units.isNotEmpty ? (_units.first.billToName ?? '') : '');
    final dateCtrl = TextEditingController(text: unrec.receiptDate);

    final resolved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Resolve ${unrec.referenceNo}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deposit: ${formatInr(unrec.amountPaise)} on ${unrec.receiptDate} (${unrec.mode.toUpperCase()})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selUnitId,
                  decoration: const InputDecoration(labelText: 'Credit to Unit *', border: OutlineInputBorder()),
                  items: _units.map((u) {
                    return DropdownMenuItem<int>(
                      value: u.id,
                      child: Text('${u.blockName}-${u.unitNo}'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDlgState(() {
                        selUnitId = v;
                        final u = _units.firstWhere((x) => x.id == v);
                        payerCtrl.text = u.billToName ?? u.primaryContactName ?? '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: payerCtrl,
                  decoration: const InputDecoration(labelText: 'Member / Payer Name *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(labelText: 'Receipt Date *', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selUnitId == null || payerCtrl.text.trim().isEmpty) return;

                try {
                  final services = await SocietyServices.instance();
                  await services.collection.resolveUnidentified(
                    societyId: societyId,
                    unidentifiedId: unrec.id,
                    unitId: selUnitId!,
                    payerName: payerCtrl.text.trim(),
                    receiptDate: dateCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Resolve & Create Receipt'),
            ),
          ],
        ),
      ),
    );

    if (resolved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unidentified deposit successfully resolved to unit.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Unidentified Receipts',
      subtitle: 'Direct bank credits awaiting member identification',
      actions: [
        FilledButton.icon(
          onPressed: _openRecordDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Record Unidentified'),
        ),
      ],
      filters: Row(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Open Unresolved')),
              ButtonSegment(value: 'resolved', label: Text('Resolved')),
              ButtonSegment(value: '', label: Text('All')),
            ],
            selected: {_statusFilter},
            onSelectionChanged: (set) {
              setState(() => _statusFilter = set.first);
              _load();
            },
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return SocietyErrorView(message: _error!, onRetry: _load);
    }
    if (_receipts.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.question_mark_outlined,
        title: 'No unidentified receipts',
        message: 'No unidentified receipts match the selected filters.',
      );
    }

    return SocietyDataTable<UnidentifiedReceipt>(
      total: _receipts.length,
      columns: [
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Ref No',
          cell: (u) => Text(u.referenceNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 170,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Date',
          cell: (u) => Text(u.receiptDate),
          width: 100,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Amount',
          cell: (u) => Text(formatInr(u.amountPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
          numeric: true,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Mode',
          cell: (u) => Text(u.mode.toUpperCase()),
          width: 90,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Bank Account',
          cell: (u) => Text(u.bankCashAccountName ?? '-'),
          width: 160,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'UTR / Details',
          cell: (u) => Text(u.instrumentNo ?? u.narration ?? '-'),
          width: 160,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Status',
          cell: (u) => StatusChip(status: u.status),
          width: 100,
        ),
        SocietyColumn<UnidentifiedReceipt>(
          label: 'Actions',
          cell: (u) => u.isOpen
              ? FilledButton.tonal(
                  onPressed: () => _openResolveDialog(u),
                  child: const Text('Resolve'),
                )
              : (u.resolvedReceiptId != null
                  ? TextButton(
                      onPressed: () => context.go('/society/receipts/${u.resolvedReceiptId}'),
                      child: const Text('View Receipt'),
                    )
                  : const SizedBox.shrink()),
          width: 130,
        ),
      ],
      rows: _receipts,
    );
  }
}
