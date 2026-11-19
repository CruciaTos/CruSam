import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_date.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../documents/pdf/unit_statement_pdf.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_date_field.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class UnitDetailScreen extends StatefulWidget {
  final int unitId;
  const UnitDetailScreen({super.key, required this.unitId});

  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Society? _society;
  UnitRow? _unit;
  List<UnitPerson> _assignments = [];
  List<UnitStatementRow> _statementRows = [];
  List<Bill> _bills = [];
  List<Receipt> _receipts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final s = await services.society.getSociety(societyId);
      final u = await services.member.getUnit(widget.unitId);
      final list = await services.member.listUnitPeople(societyId, widget.unitId);
      final stRows = await services.collection.getUnitStatement(societyId, widget.unitId);
      final billsRes = await services.billing.listBills(societyId, unitId: widget.unitId, page: const PageRequest(limit: 500));
      final rcptRes = await services.collection.listReceipts(societyId, unitId: widget.unitId, page: const PageRequest(limit: 500));

      if (mounted) {
        setState(() {
          _society = s;
          _unit = u;
          _assignments = list;
          _statementRows = stRows;
          _bills = billsRes.rows;
          _receipts = rcptRes.rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _printStatement() async {
    if (_society == null || _unit == null) return;
    try {
      final pdfBytes = await UnitStatementPdf.generateBytes(
        society: _society!,
        unit: _unit!,
        rows: _statementRows,
      );
      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes,
        name: 'Unit_Statement_${_unit!.unitNo}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  Future<void> _showAssignDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final peopleRes = await services.member.listPeople(societyId);
    final people = peopleRes.rows;

    if (people.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add members in Members screen first.')),
        );
      }
      return;
    }

    int? selectedPersonId = people.first.id;
    String role = 'tenant';
    bool isPrimary = false;
    bool isBillTo = false;
    final shareCertController = TextEditingController();
    String fromDate = todayIso();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Text('Assign Person to Unit'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedPersonId,
                      decoration: const InputDecoration(labelText: 'Person / Member *'),
                      isExpanded: true,
                      items: people.map((p) {
                        return DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.fullName} (${p.phone ?? "No phone"})'),
                        );
                      }).toList(),
                      onChanged: (v) => setDlgState(() => selectedPersonId = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role *'),
                      items: const [
                        DropdownMenuItem(value: 'owner', child: Text('Owner')),
                        DropdownMenuItem(value: 'co_owner', child: Text('Co-Owner')),
                        DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
                        DropdownMenuItem(value: 'nominee', child: Text('Nominee')),
                      ],
                      onChanged: (v) => setDlgState(() => role = v ?? 'tenant'),
                    ),
                    const SizedBox(height: 16),
                    SocietyDateField(
                      label: 'Effective From Date *',
                      value: fromDate,
                      onChanged: (v) {
                        if (v != null) setDlgState(() => fromDate = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: shareCertController,
                      decoration: const InputDecoration(labelText: 'Share Certificate No (optional)'),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Set as Primary Contact'),
                      value: isPrimary,
                      onChanged: (v) => setDlgState(() => isPrimary = v ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Set as Bill To Contact'),
                      value: isBillTo,
                      onChanged: (v) => setDlgState(() => isBillTo = v ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Assign'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && selectedPersonId != null && mounted) {
      try {
        final draft = UnitPersonDraft(
          unitId: widget.unitId,
          personId: selectedPersonId!,
          role: role,
          isPrimaryContact: isPrimary,
          isBillTo: isBillTo,
          shareCertificateNo: shareCertController.text.trim().isEmpty ? null : shareCertController.text.trim(),
          fromDate: fromDate,
        );
        await services.member.assignPerson(societyId, draft);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  Future<void> _showTransferOwnershipDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final peopleRes = await services.member.listPeople(societyId);
    final people = peopleRes.rows;

    if (people.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add members in Members screen first.')),
        );
      }
      return;
    }

    int? selectedPersonId = people.first.id;
    final shareCertController = TextEditingController();
    String transferDate = todayIso();
    bool setPrimary = true;
    bool setBillTo = true;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Text('Transfer Ownership'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will end previous active owner and co-owner assignments for this unit and register the new owner.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: selectedPersonId,
                      decoration: const InputDecoration(labelText: 'New Owner *'),
                      isExpanded: true,
                      items: people.map((p) {
                        return DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.fullName} (${p.phone ?? "No phone"})'),
                        );
                      }).toList(),
                      onChanged: (v) => setDlgState(() => selectedPersonId = v),
                    ),
                    const SizedBox(height: 16),
                    SocietyDateField(
                      label: 'Transfer Date *',
                      value: transferDate,
                      onChanged: (v) {
                        if (v != null) setDlgState(() => transferDate = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: shareCertController,
                      decoration: const InputDecoration(labelText: 'New Share Certificate No'),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Set as Primary Contact'),
                      value: setPrimary,
                      onChanged: (v) => setDlgState(() => setPrimary = v ?? true),
                    ),
                    CheckboxListTile(
                      title: const Text('Set as Bill To'),
                      value: setBillTo,
                      onChanged: (v) => setDlgState(() => setBillTo = v ?? true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Complete Transfer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && selectedPersonId != null && mounted) {
      try {
        final draft = OwnershipTransferDraft(
          unitId: widget.unitId,
          newOwnerPersonId: selectedPersonId!,
          transferDate: transferDate,
          shareCertificateNo: shareCertController.text.trim().isEmpty ? null : shareCertController.text.trim(),
          setAsPrimaryContact: setPrimary,
          setAsBillTo: setBillTo,
        );
        await services.member.transferOwnership(societyId, draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ownership transferred successfully')),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
        }
      }
    }
  }

  Future<void> _endAssignment(UnitPerson p) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    String toDate = todayIso();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text('End Assignment for ${p.personFullName}'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SocietyDateField(
                      label: 'End Date *',
                      value: toDate,
                      onChanged: (v) {
                        if (v != null) setDlgState(() => toDate = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm End'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        final services = await SocietyServices.instance();
        await services.member.endAssignment(societyId, p.id, toDate);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SocietyPage(
        title: 'Unit Details',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_unit == null) {
      return SocietyPage(
        title: 'Unit Not Found',
        child: SocietyErrorView(
          message: 'The requested unit could not be found.',
          onRetry: _loadData,
        ),
      );
    }

    final u = _unit!;

    return SocietyPage(
      title: 'Unit ${u.blockName} - ${u.unitNo}',
      subtitle: '${u.unitTypeName} • ${u.occupancy.replaceAll('_', ' ').toUpperCase()}',
      actions: [
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Transfer Ownership'),
          onPressed: _showTransferOwnershipDialog,
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Assign Person'),
          onPressed: _showAssignDialog,
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit Unit',
          onPressed: () async {
            await context.push('/society/units/${u.id}/edit');
            _loadData();
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.black54,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'People & History'),
              Tab(text: 'Statement'),
              Tab(text: 'Bills'),
              Tab(text: 'Receipts'),
            ],
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SocietyErrorView(message: _error!, onRetry: _loadData),
            ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Overview Tab
                SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Unit Info
                      Expanded(
                        flex: 3,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Property Information',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const Divider(height: 24),
                                _infoRow('Block / Wing', u.blockName),
                                _infoRow('Unit Number', u.unitNo),
                                _infoRow('Unit Type', u.unitTypeName),
                                _infoRow(
                                  'Built-up Area',
                                  u.area1Centi > 0
                                      ? '${(u.area1Centi / 100.0).toStringAsFixed(2)} sq ft'
                                      : 'Not specified',
                                ),
                                _infoRow(
                                  'Carpet Area',
                                  u.area2Centi > 0
                                      ? '${(u.area2Centi / 100.0).toStringAsFixed(2)} sq ft'
                                      : 'Not specified',
                                ),
                                _infoRow('Floor', u.floorNo ?? 'Not specified'),
                                _infoRow('Occupancy Status', u.occupancy.replaceAll('_', ' ')),
                                _infoRow('Status', u.isActive ? 'Active' : 'Inactive'),
                                if (u.notes != null && u.notes!.isNotEmpty)
                                  _infoRow('Notes', u.notes!),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Contacts summary
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.contact_phone_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Primary Contact',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      u.primaryContactName ?? 'No primary contact assigned',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                    if (u.primaryContactPhone != null) ...[
                                      const SizedBox(height: 4),
                                      Text(u.primaryContactPhone!, style: const TextStyle(color: Colors.black54)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.receipt_long_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Bill-To Contact',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      u.billToName ?? 'No bill-to recipient assigned',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // People / History Tab
                _assignments.isEmpty
                    ? SocietyEmptyView(
                        icon: Icons.people_outline,
                        title: 'No people assigned',
                        message: 'No owners, tenants, or nominees are currently assigned to this unit.',
                        action: FilledButton.icon(
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Assign Person'),
                          onPressed: _showAssignDialog,
                        ),
                      )
                    : SocietyDataTable<UnitPerson>(
                        columns: [
                          SocietyColumn(
                            label: 'Name',
                            cell: (p) => Text(
                              p.personFullName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Role',
                            width: 110,
                            cell: (p) => Text(p.role.replaceAll('_', ' ')),
                          ),
                          SocietyColumn(
                            label: 'Phone / Email',
                            cell: (p) => Text('${p.personPhone ?? "-"} / ${p.personEmail ?? "-"}'),
                          ),
                          SocietyColumn(
                            label: 'Primary',
                            width: 90,
                            cell: (p) => p.isPrimaryContact
                                ? const StatusChip(status: 'active', label: 'Yes')
                                : const Text('-'),
                          ),
                          SocietyColumn(
                            label: 'Bill To',
                            width: 90,
                            cell: (p) => p.isBillTo
                                ? const StatusChip(status: 'open', label: 'Yes')
                                : const Text('-'),
                          ),
                          SocietyColumn(
                            label: 'From Date',
                            width: 110,
                            cell: (p) => Text(formatDisplayDate(p.fromDate)),
                          ),
                          SocietyColumn(
                            label: 'To Date',
                            width: 110,
                            cell: (p) => Text(p.toDate != null ? formatDisplayDate(p.toDate!) : 'Present'),
                          ),
                          SocietyColumn(
                            label: 'Actions',
                            width: 90,
                            cell: (p) => p.isCurrent
                                ? IconButton(
                                    icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.red),
                                    tooltip: 'End Assignment',
                                    onPressed: () => _endAssignment(p),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                        rows: _assignments,
                        total: _assignments.length,
                        page: 0,
                        pageSize: _assignments.length.clamp(1, 100),
                        onPage: (_) {},
                      ),

                // Statement Tab
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Print Statement (PDF)'),
                          onPressed: _statementRows.isEmpty ? null : _printStatement,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _statementRows.isEmpty
                          ? const SocietyEmptyView(
                              icon: Icons.receipt_long_outlined,
                              title: 'No transactions',
                              message: 'No bills or receipts found for this unit.',
                            )
                          : SocietyDataTable<UnitStatementRow>(
                              columns: [
                                SocietyColumn(
                                  label: 'Date',
                                  width: 100,
                                  cell: (r) => Text(formatDisplayDate(r.date)),
                                ),
                                SocietyColumn(
                                  label: 'Doc Type',
                                  width: 110,
                                  cell: (r) => Text(r.docType.replaceAll('_', ' ').toUpperCase()),
                                ),
                                SocietyColumn(
                                  label: 'Ref / Doc No',
                                  width: 130,
                                  cell: (r) => Text(
                                    r.docNo,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Particulars',
                                  cell: (r) => Text(r.description),
                                ),
                                SocietyColumn(
                                  label: 'Debit (₹)',
                                  width: 110,
                                  numeric: true,
                                  cell: (r) => Text(
                                    r.debitPaise > 0 ? formatPaise(r.debitPaise) : '-',
                                    style: TextStyle(
                                      color: r.debitPaise > 0 ? Colors.red.shade700 : null,
                                      fontWeight: r.debitPaise > 0 ? FontWeight.w600 : null,
                                    ),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Credit (₹)',
                                  width: 110,
                                  numeric: true,
                                  cell: (r) => Text(
                                    r.creditPaise > 0 ? formatPaise(r.creditPaise) : '-',
                                    style: TextStyle(
                                      color: r.creditPaise > 0 ? Colors.green.shade700 : null,
                                      fontWeight: r.creditPaise > 0 ? FontWeight.w600 : null,
                                    ),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Balance (₹)',
                                  width: 120,
                                  numeric: true,
                                  cell: (r) => Text(
                                    formatPaise(r.runningBalancePaise),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: r.runningBalancePaise > 0
                                          ? Colors.red.shade700
                                          : (r.runningBalancePaise < 0 ? Colors.green.shade700 : null),
                                    ),
                                  ),
                                ),
                              ],
                              rows: _statementRows,
                              total: _statementRows.length,
                              page: 0,
                              pageSize: _statementRows.length.clamp(1, 1000),
                              onPage: (_) {},
                            ),
                    ),
                  ],
                ),

                // Bills Tab
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('New Manual Bill'),
                          onPressed: () async {
                            await context.push('/society/bills/manual?unitId=${widget.unitId}');
                            _loadData();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _bills.isEmpty
                          ? const SocietyEmptyView(
                              icon: Icons.receipt_outlined,
                              title: 'No bills found',
                              message: 'No bills have been generated for this unit yet.',
                            )
                          : SocietyDataTable<Bill>(
                              columns: [
                                SocietyColumn(
                                  label: 'Bill No',
                                  width: 140,
                                  cell: (b) => InkWell(
                                    onTap: () async {
                                      await context.push('/society/bills/${b.id}');
                                      _loadData();
                                    },
                                    child: Text(
                                      b.billNo ?? '-',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Bill Date',
                                  width: 110,
                                  cell: (b) => Text(formatDisplayDate(b.billDate)),
                                ),
                                SocietyColumn(
                                  label: 'Due Date',
                                  width: 110,
                                  cell: (b) => Text(formatDisplayDate(b.dueDate)),
                                ),
                                SocietyColumn(
                                  label: 'Period',
                                  cell: (b) => Text(b.periodFrom != null && b.periodTo != null
                                      ? '${formatDisplayDate(b.periodFrom!)} - ${formatDisplayDate(b.periodTo!)}'
                                      : '-'),
                                ),
                                SocietyColumn(
                                  label: 'Net Amount',
                                  width: 120,
                                  numeric: true,
                                  cell: (b) => Text(
                                    formatPaise(b.totalPaise),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Status',
                                  width: 100,
                                  cell: (b) => StatusChip(status: b.status),
                                ),
                              ],
                              rows: _bills,
                              total: _bills.length,
                              page: 0,
                              pageSize: _bills.length.clamp(1, 100),
                              onPage: (_) {},
                            ),
                    ),
                  ],
                ),

                // Receipts Tab
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Record Receipt'),
                          onPressed: () async {
                            await context.push('/society/receipts/new?unitId=${widget.unitId}');
                            _loadData();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _receipts.isEmpty
                          ? const SocietyEmptyView(
                              icon: Icons.payments_outlined,
                              title: 'No receipts found',
                              message: 'No payments have been recorded for this unit yet.',
                            )
                          : SocietyDataTable<Receipt>(
                              columns: [
                                SocietyColumn(
                                  label: 'Receipt No',
                                  width: 140,
                                  cell: (r) => InkWell(
                                    onTap: () async {
                                      await context.push('/society/receipts/${r.id}');
                                      _loadData();
                                    },
                                    child: Text(
                                      r.receiptNo,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Date',
                                  width: 110,
                                  cell: (r) => Text(formatDisplayDate(r.receiptDate)),
                                ),
                                SocietyColumn(
                                  label: 'Payment Mode',
                                  width: 120,
                                  cell: (r) => Text(r.mode.replaceAll('_', ' ').toUpperCase()),
                                ),
                                SocietyColumn(
                                  label: 'Reference No',
                                  cell: (r) => Text(r.instrumentNo ?? '-'),
                                ),
                                SocietyColumn(
                                  label: 'Amount (₹)',
                                  width: 120,
                                  numeric: true,
                                  cell: (r) => Text(
                                    formatPaise(r.amountPaise),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Status',
                                  width: 100,
                                  cell: (r) => StatusChip(status: r.status),
                                ),
                              ],
                              rows: _receipts,
                              total: _receipts.length,
                              page: 0,
                              pageSize: _receipts.length.clamp(1, 100),
                              onPage: (_) {},
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
