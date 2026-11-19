import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../documents/pdf/credit_note_pdf.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  List<CreditNote> _creditNotes = [];
  List<Bill> _debitNotes = [];
  List<UnitRow> _units = [];
  List<ChargeHead> _heads = [];
  Society? _society;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      final soc = await services.society.getSociety(societyId);
      final cnRes = await services.collection.listCreditNotes(societyId);
      final dnRes = await services.billing.listBills(
        societyId,
        billKind: 'debit_note',
        page: const PageRequest(limit: 500),
      );
      final uRes = await services.member.listUnits(societyId, page: const PageRequest(limit: 5000));
      final heads = await services.billing.listChargeHeads(societyId);

      if (mounted) {
        setState(() {
          _society = soc;
          _creditNotes = cnRes.rows;
          _debitNotes = dnRes.rows;
          _units = uRes.rows;
          _heads = heads;
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

  Future<void> _printCreditNote(CreditNote note) async {
    if (_society == null) return;
    try {
      final services = await SocietyServices.instance();
      final allocs = await services.collection.listAllocations(
        _society!.id,
        sourceType: 'credit_note',
        sourceId: note.id,
      );
      final bytes = await CreditNotePdf.generateBytes(
        society: _society!,
        note: note,
        allocations: allocs,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'CreditNote_${note.noteNo.replaceAll('/', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _openNewCreditNoteDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    int? selUnitId = _units.isNotEmpty ? _units.first.id : null;
    int? selHeadId;
    String scope = 'general';

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: today);
    final amtCtrl = TextEditingController();
    final cgstCtrl = TextEditingController(text: '0.00');
    final sgstCtrl = TextEditingController(text: '0.00');
    final reasonCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Issue Member Credit Note'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selUnitId,
                    decoration: const InputDecoration(labelText: 'Unit / Flat *', border: OutlineInputBorder()),
                    items: _units.map((u) {
                      return DropdownMenuItem<int>(
                        value: u.id,
                        child: Text('${u.blockName}-${u.unitNo}'),
                      );
                    }).toList(),
                    onChanged: (v) => setDlgState(() => selUnitId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD) *', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: scope,
                          decoration: const InputDecoration(labelText: 'Scope', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'general', child: Text('General')),
                            DropdownMenuItem(value: 'head', child: Text('Specific Head')),
                          ],
                          onChanged: (v) {
                            if (v != null) setDlgState(() => scope = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (scope == 'head') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selHeadId,
                      decoration: const InputDecoration(labelText: 'Charge Head', border: OutlineInputBorder()),
                      items: _heads.map((h) {
                        return DropdownMenuItem<int>(value: h.id, child: Text(h.name));
                      }).toList(),
                      onChanged: (v) => setDlgState(() => selHeadId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amtCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Credit Amount (Rs.) *', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: cgstCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'CGST (Rs.)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: sgstCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'SGST (Rs.)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Reason for Credit *', border: OutlineInputBorder()),
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
                if (selUnitId == null) return;
                final amt = parseRupeesToPaise(amtCtrl.text);
                if (amt == null || amt <= 0) return;
                final cgst = parseRupeesToPaise(cgstCtrl.text) ?? 0;
                final sgst = parseRupeesToPaise(sgstCtrl.text) ?? 0;

                try {
                  final services = await SocietyServices.instance();
                  await services.collection.createCreditNote(
                    societyId,
                    CreditNoteDraft(
                      unitId: selUnitId!,
                      noteDate: dateCtrl.text.trim(),
                      scope: scope,
                      chargeHeadId: selHeadId,
                      amountPaise: amt,
                      cgstPaise: cgst,
                      sgstPaise: sgst,
                      reason: reasonCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Issue Credit Note'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credit Note issued successfully.')),
      );
      _load();
    }
  }

  Future<void> _reverseCreditNote(CreditNote note) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateCtrl = TextEditingController(text: today);
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reverse Credit Note ${note.noteNo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(labelText: 'Reversal Date (YYYY-MM-DD) *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason for Reversal *', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final services = await SocietyServices.instance();
        await services.collection.reverseCreditNote(
          societyId,
          note.id,
          dateCtrl.text.trim(),
          reasonCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credit Note reversed successfully.')),
          );
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reversal failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Credit & Debit Notes',
      subtitle: 'Issue adjustments and member debit/credit notes',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/society/bills/new?kind=debit_note'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Debit Note'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _openNewCreditNoteDialog,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Credit Note'),
        ),
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Credit Notes (${_creditNotes.length})'),
              Tab(text: 'Debit Notes (${_debitNotes.length})'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null
                    ? SocietyErrorView(message: _error!, onRetry: _load)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildCreditNotesTable(),
                          _buildDebitNotesTable(),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditNotesTable() {
    if (_creditNotes.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.note_outlined,
        title: 'No credit notes issued',
        message: 'No credit notes have been issued yet.',
      );
    }

    return SocietyDataTable<CreditNote>(
      total: _creditNotes.length,
      columns: [
        SocietyColumn<CreditNote>(
          label: 'Note No',
          cell: (n) => Text(n.noteNo, style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 170,
        ),
        SocietyColumn<CreditNote>(
          label: 'Date',
          cell: (n) => Text(n.noteDate),
          width: 100,
        ),
        SocietyColumn<CreditNote>(
          label: 'Unit',
          cell: (n) => Text('${n.blockName}-${n.unitNo}'),
          width: 100,
        ),
        SocietyColumn<CreditNote>(
          label: 'Reason',
          cell: (n) => Text(n.reason, overflow: TextOverflow.ellipsis),
          width: 180,
        ),
        SocietyColumn<CreditNote>(
          label: 'Amount',
          cell: (n) => Text(formatInr(n.amountPaise)),
          width: 110,
          numeric: true,
        ),
        SocietyColumn<CreditNote>(
          label: 'Total',
          cell: (n) => Text(formatInr(n.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
          numeric: true,
        ),
        SocietyColumn<CreditNote>(
          label: 'Status',
          cell: (n) => StatusChip(status: n.status),
          width: 100,
        ),
        SocietyColumn<CreditNote>(
          label: 'Actions',
          cell: (n) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.print, size: 18),
                tooltip: 'Print PDF',
                onPressed: () => _printCreditNote(n),
              ),
              if (!n.isReversed)
                IconButton(
                  icon: const Icon(Icons.undo, size: 18, color: Colors.red),
                  tooltip: 'Reverse',
                  onPressed: () => _reverseCreditNote(n),
                ),
            ],
          ),
          width: 100,
        ),
      ],
      rows: _creditNotes,
    );
  }

  Widget _buildDebitNotesTable() {
    if (_debitNotes.isEmpty) {
      return const SocietyEmptyView(
        icon: Icons.note_outlined,
        title: 'No debit notes issued',
        message: 'No debit notes have been issued yet.',
      );
    }

    return SocietyDataTable<Bill>(
      total: _debitNotes.length,
      columns: [
        SocietyColumn<Bill>(
          label: 'Note No',
          cell: (b) => Text(b.billNo ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 170,
        ),
        SocietyColumn<Bill>(
          label: 'Date',
          cell: (b) => Text(b.billDate),
          width: 100,
        ),
        SocietyColumn<Bill>(
          label: 'Unit',
          cell: (b) => Text('${b.blockName}-${b.unitNo}'),
          width: 100,
        ),
        SocietyColumn<Bill>(
          label: 'Bill To',
          cell: (b) => Text(b.billToName),
          width: 180,
        ),
        SocietyColumn<Bill>(
          label: 'Total',
          cell: (b) => Text(formatInr(b.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
          width: 120,
          numeric: true,
        ),
        SocietyColumn<Bill>(
          label: 'Status',
          cell: (b) => StatusChip(status: b.status),
          width: 100,
        ),
        SocietyColumn<Bill>(
          label: 'Actions',
          cell: (b) => TextButton(
            onPressed: () => context.go('/society/bills/${b.id}'),
            child: const Text('View'),
          ),
          width: 80,
        ),
      ],
      rows: _debitNotes,
      onRowTap: (b) => context.go('/society/bills/${b.id}'),
    );
  }
}
