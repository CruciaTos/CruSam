import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/confirm_typed_dialog.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class BillRunDetailScreen extends StatefulWidget {
  final int runId;
  const BillRunDetailScreen({super.key, required this.runId});

  @override
  State<BillRunDetailScreen> createState() => _BillRunDetailScreenState();
}

class _BillRunDetailScreenState extends State<BillRunDetailScreen> {
  bool _loading = false;
  String? _error;
  BillRun? _run;
  List<Bill> _bills = [];
  bool _busy = false;

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
      final r = await services.billing.getBillRun(widget.runId);
      final billsRes = await services.billing.listBills(
        societyId,
        runId: widget.runId,
        page: const PageRequest(limit: 5000),
      );

      if (mounted) {
        setState(() {
          _run = r;
          _bills = billsRes.rows;
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

  Future<void> _postRun() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _run == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Bill Run?'),
        content: Text(
          'This will post ${_run!.billCount} bills totalling ${formatPaise(_run!.totalPaise)} to the ledger.\n'
          'Each bill will be assigned a permanent invoice number and double-entry journals will be created.\n'
          'Posted bills cannot be deleted, only reversed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm & Post')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final services = await SocietyServices.instance();
      await services.billing.postBillRun(societyId, widget.runId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill run posted successfully!')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRun() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _run == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Draft Bill Run?'),
        content: const Text('This will delete all draft bills generated in this run. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Draft Run'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final services = await SocietyServices.instance();
      await services.billing.cancelDraftRun(societyId, widget.runId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft bill run cancelled.')),
        );
        context.go('/society/bill-runs');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SocietyPage(
        title: 'Bill Run Details',
        child: SocietyErrorView(message: _error!, onRetry: _load),
      );
    }

    if (_loading || _run == null) {
      return const SocietyPage(
        title: 'Bill Run Details',
        child: Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      );
    }

    final run = _run!;

    return SocietyPage(
      title: 'Bill Run: ${run.periodFrom} to ${run.periodTo}',
      subtitle: '${run.frequency[0].toUpperCase() + run.frequency.substring(1)} bill run • Bill Date: ${run.billDate}',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/bill-runs'),
          child: const Text('Back to List'),
        ),
        if (run.status == 'draft') ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: _busy ? null : _cancelRun,
            child: const Text('Cancel Draft'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _postRun,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Post Bill Run'),
          ),
        ],
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Run Summary Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('Status: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          StatusChip(status: run.status),
                          if (run.postedAt != null) ...[
                            const SizedBox(width: 16),
                            Text('Posted on: ${run.postedAt}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          ],
                        ],
                      ),
                      Text(
                        'Total: ${formatPaise(run.totalPaise)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF047857)),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(child: _InfoTile(label: 'Period', value: '${run.periodFrom} to ${run.periodTo}')),
                      Expanded(child: _InfoTile(label: 'Bill Date', value: run.billDate)),
                      Expanded(child: _InfoTile(label: 'Due Date', value: run.dueDate)),
                      Expanded(child: _InfoTile(label: 'Bills Count', value: '${run.billCount}')),
                    ],
                  ),
                  if (run.notes != null && run.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Notes: ${run.notes}', style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF475569))),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Bills Table
          Expanded(
            child: _bills.isEmpty
                ? const Center(child: Text('No bills in this run.'))
                : SocietyDataTable<Bill>(
                    columns: [
                      SocietyColumn<Bill>(
                        label: 'Bill No',
                        cell: (b) => Text(b.billNo ?? '(Draft)', style: const TextStyle(fontWeight: FontWeight.w600)),
                        width: 150,
                      ),
                      SocietyColumn<Bill>(
                        label: 'Unit',
                        cell: (b) => Text('${b.blockName}-${b.unitNo}'),
                        width: 120,
                      ),
                      SocietyColumn<Bill>(
                        label: 'Bill-To',
                        cell: (b) => Text(b.billToName),
                        width: 180,
                      ),
                      SocietyColumn<Bill>(
                        label: 'Amount',
                        cell: (b) => Text(formatPaise(b.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true,
                        width: 130,
                      ),
                      SocietyColumn<Bill>(
                        label: 'Status',
                        cell: (b) => StatusChip(status: b.status),
                        width: 110,
                      ),
                      SocietyColumn<Bill>(
                        label: 'Action',
                        cell: (b) => TextButton(
                          child: const Text('View'),
                          onPressed: () => context.go('/society/bills/${b.id}'),
                        ),
                        width: 90,
                      ),
                    ],
                    rows: _bills,
                    total: _bills.length,
                    page: 1,
                    pageSize: 50,
                    onPage: (_) {},
                    onRowTap: (b) => context.go('/society/bills/${b.id}'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}
