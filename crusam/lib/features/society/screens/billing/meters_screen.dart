import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/confirm_typed_dialog.dart';
import '../../shared/widgets/money_field.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_date_field.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class MetersScreen extends StatefulWidget {
  const MetersScreen({super.key});

  @override
  State<MetersScreen> createState() => _MetersScreenState();
}

class _MetersScreenState extends State<MetersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = false;
  String? _error;

  List<MeterType> _meterTypes = [];
  List<Meter> _meters = [];
  List<Map<String, dynamic>> _readings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
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
      final billing = services.billing;
      final mTypes = await billing.listMeterTypes(societyId, includeInactive: true);
      final mList = await billing.listMeters(societyId, includeInactive: true);
      final rList = await billing.listMeterReadings(societyId);

      if (mounted) {
        setState(() {
          _meterTypes = mTypes;
          _meters = mList;
          _readings = rList;
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

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Meter Readings',
      subtitle: 'Manage meter types, slabs, unit meters, and period readings',
      actions: [
        if (_tabController.index == 0)
          FilledButton.icon(
            onPressed: () => _openMeterTypeDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Meter Type'),
          )
        else if (_tabController.index == 1)
          FilledButton.icon(
            onPressed: () => _openMeterDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Unit Meter'),
          )
        else
          FilledButton.icon(
            onPressed: () => _openReadingDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Record Reading'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFB45309),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFFB45309),
            tabs: const [
              Tab(text: 'Types & Slabs'),
              Tab(text: 'Unit Meters'),
              Tab(text: 'Readings Grid'),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            SocietyErrorView(message: _error!, onRetry: _load)
          else if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTypesTab(),
                  _buildMetersTab(),
                  _buildReadingsTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypesTab() {
    if (_meterTypes.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.speed_outlined,
        title: 'No Meter Types',
        message: 'Create a meter type (e.g. Water, Electricity) with slab pricing.',
        action: FilledButton(
          onPressed: () => _openMeterTypeDialog(),
          child: const Text('Add Meter Type'),
        ),
      );
    }

    return ListView.builder(
      itemCount: _meterTypes.length,
      itemBuilder: (context, idx) {
        final mt = _meterTypes[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      mt.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Row(
                      children: [
                        StatusChip(status: mt.isActive ? 'active' : 'inactive'),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit Meter Type',
                          onPressed: () => _openMeterTypeDialog(mt),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  'Charge Head: ${mt.chargeHeadName ?? mt.chargeHeadId}  |  '
                  'Calculation: ${mt.isCumulative ? "Cumulative (per tier)" : "Non-cumulative (entire consumption)"}  |  '
                  'Min: ${formatPaise(mt.minimumPaise)}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Slabs:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                      children: [
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Seq', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Up to Units', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Rate / Unit', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                    ...mt.slabs.map((s) => TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${s.seq}')),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(s.upToMilli == null ? 'Above (Remaining)' : '${s.upToMilli! / 1000.0} units'),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(formatPaise(s.ratePaise)),
                            ),
                          ],
                        )),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetersTab() {
    if (_meters.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.electric_meter_outlined,
        title: 'No Unit Meters',
        message: 'Assign meters to units to bill them based on consumption.',
        action: FilledButton(
          onPressed: () => _openMeterDialog(),
          child: const Text('Add Unit Meter'),
        ),
      );
    }

    return SocietyDataTable<Meter>(
      columns: [
        SocietyColumn<Meter>(
          label: 'Unit',
          cell: (m) => Text('${m.blockName}-${m.unitNo}'),
          width: 120,
        ),
        SocietyColumn<Meter>(
          label: 'Meter Type',
          cell: (m) => Text(m.meterTypeName),
          width: 150,
        ),
        SocietyColumn<Meter>(
          label: 'Meter No',
          cell: (m) => Text(m.meterNo ?? '-'),
          width: 140,
        ),
        SocietyColumn<Meter>(
          label: 'Opening Reading',
          cell: (m) => Text('${m.openingReadingMilli / 1000.0}'),
          numeric: true,
          width: 140,
        ),
        SocietyColumn<Meter>(
          label: 'Last Reading',
          cell: (m) => Text(m.lastReadingMilli != null ? '${m.lastReadingMilli! / 1000.0}' : '-'),
          numeric: true,
          width: 130,
        ),
        SocietyColumn<Meter>(
          label: 'Last Reading Date',
          cell: (m) => Text(m.lastReadingDate ?? '-'),
          width: 140,
        ),
        SocietyColumn<Meter>(
          label: 'Status',
          cell: (m) => StatusChip(status: m.isActive ? 'active' : 'inactive'),
          width: 100,
        ),
      ],
      rows: _meters,
      total: _meters.length,
      page: 1,
      pageSize: 50,
      onPage: (_) {},
    );
  }

  Widget _buildReadingsTab() {
    if (_readings.isEmpty) {
      return SocietyEmptyView(
        icon: Icons.speed_outlined,
        title: 'No Meter Readings Recorded',
        message: 'Record periodic meter readings to calculate consumption for bills.',
        action: FilledButton(
          onPressed: () => _openReadingDialog(),
          child: const Text('Record Reading'),
        ),
      );
    }

    return SocietyDataTable<Map<String, dynamic>>(
      columns: [
        SocietyColumn<Map<String, dynamic>>(
          label: 'Unit',
          cell: (r) => Text('${r["block_name"] ?? ""}-${r["unit_no"] ?? ""}'),
          width: 110,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Meter',
          cell: (r) => Text('${r["meter_type_name"]} (${r["meter_no"] ?? "-"})'),
          width: 160,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Period',
          cell: (r) => Text('${r["period_from"]} to ${r["period_to"]}'),
          width: 180,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Previous',
          cell: (r) {
            final prev = (r["previous_reading_milli"] as num?)?.toDouble() ?? 0;
            return Text((prev / 1000.0).toStringAsFixed(2));
          },
          numeric: true,
          width: 110,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Current',
          cell: (r) {
            final curr = (r["reading_milli"] as num?)?.toDouble() ?? 0;
            return Text((curr / 1000.0).toStringAsFixed(2));
          },
          numeric: true,
          width: 110,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Consumption',
          cell: (r) {
            final curr = (r["reading_milli"] as num?)?.toInt() ?? 0;
            final prev = (r["previous_reading_milli"] as num?)?.toInt() ?? 0;
            final diff = curr - prev;
            final isNeg = diff < 0;
            return Text(
              '${(diff / 1000.0).toStringAsFixed(2)} ${r["unit_label"] ?? ""}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isNeg ? const Color(0xFFDC2626) : null,
              ),
            );
          },
          numeric: true,
          width: 140,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Reading Date',
          cell: (r) => Text(r["reading_date"] as String? ?? ''),
          width: 120,
        ),
        SocietyColumn<Map<String, dynamic>>(
          label: 'Error',
          cell: (r) {
            final curr = (r["reading_milli"] as num?)?.toInt() ?? 0;
            final prev = (r["previous_reading_milli"] as num?)?.toInt() ?? 0;
            if (curr < prev) {
              return const StatusChip(status: 'failed', label: 'Negative');
            }
            return const StatusChip(status: 'resolved', label: 'Valid');
          },
          width: 100,
        ),
      ],
      rows: _readings,
      total: _readings.length,
      page: 1,
      pageSize: 50,
      onPage: (_) {},
    );
  }

  Future<void> _openMeterTypeDialog([MeterType? existing]) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final services = await SocietyServices.instance();
    final heads = await services.billing.listChargeHeads(societyId);
    if (heads.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please create a Charge Head first.')),
        );
      }
      return;
    }

    if (!mounted) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int chargeHeadId = existing?.chargeHeadId ?? heads.first.id;
    bool isCumulative = existing?.isCumulative ?? true;
    int minPaise = existing?.minimumPaise ?? 0;

    final slabs = existing != null
        ? List<MeterSlabDraft>.from(existing.slabs.map((s) => MeterSlabDraft(
              seq: s.seq,
              upToMilli: s.upToMilli,
              ratePaise: s.ratePaise,
            )))
        : <MeterSlabDraft>[
            const MeterSlabDraft(seq: 1, upToMilli: null, ratePaise: 500),
          ];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(existing == null ? 'Add Meter Type' : 'Edit Meter Type'),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Meter Type Name *', hintText: 'e.g. Water Meter'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: chargeHeadId,
                    decoration: const InputDecoration(labelText: 'Charge Head *'),
                    items: heads.map((h) => DropdownMenuItem(value: h.id, child: Text(h.name))).toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => chargeHeadId = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MoneyField(
                          label: 'Minimum Charge',
                          value: minPaise,
                          onChanged: (v) => setDlgState(() => minPaise = v ?? 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Cumulative Slabs', style: TextStyle(fontSize: 14)),
                          value: isCumulative,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDlgState(() => isCumulative = v ?? true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Slabs & Rates', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Slab'),
                        onPressed: () {
                          setDlgState(() {
                            final seq = slabs.length + 1;
                            slabs.add(MeterSlabDraft(seq: seq, upToMilli: null, ratePaise: 500));
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(slabs.length, (idx) {
                    final slab = slabs[idx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text('Slab ${slab.seq}:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: slab.upToMilli != null ? '${slab.upToMilli! / 1000.0}' : '',
                              decoration: const InputDecoration(labelText: 'Up To Qty (blank = ∞)', isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final d = double.tryParse(v);
                                slabs[idx] = MeterSlabDraft(
                                  seq: slab.seq,
                                  upToMilli: d != null ? (d * 1000).round() : null,
                                  ratePaise: slab.ratePaise,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: (slab.ratePaise / 100.0).toStringAsFixed(2),
                              decoration: const InputDecoration(labelText: 'Rate ₹/unit', isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final p = parseRupeesToPaise(v) ?? 0;
                                slabs[idx] = MeterSlabDraft(
                                  seq: slab.seq,
                                  upToMilli: slab.upToMilli,
                                  ratePaise: p,
                                );
                              },
                            ),
                          ),
                          if (slabs.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => setDlgState(() => slabs.removeAt(idx)),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final draft = MeterTypeDraft(
                  name: nameCtrl.text.trim(),
                  chargeHeadId: chargeHeadId,
                  isCumulative: isCumulative,
                  minimumPaise: minPaise,
                  slabs: slabs,
                );
                try {
                  if (existing == null) {
                    await services.billing.createMeterType(societyId, draft);
                  } else {
                    await services.billing.updateMeterType(societyId, existing.id, draft);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  Future<void> _openMeterDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_meterTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a Meter Type first.')),
      );
      return;
    }

    final services = await SocietyServices.instance();
    final unitsRes = await services.member.listUnits(societyId, page: const PageRequest(limit: 5000));
    final units = unitsRes.rows;
    if (units.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add Units first.')),
        );
      }
      return;
    }

    if (!mounted) return;

    int selectedUnitId = units.first.id;
    int selectedMeterTypeId = _meterTypes.first.id;
    final meterNoCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Unit Meter'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedUnitId,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                  items: units
                      .map((u) => DropdownMenuItem(value: u.id, child: Text('${u.blockName}-${u.unitNo}')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedUnitId = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selectedMeterTypeId,
                  decoration: const InputDecoration(labelText: 'Meter Type *'),
                  items: _meterTypes
                      .map((mt) => DropdownMenuItem(value: mt.id, child: Text(mt.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedMeterTypeId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: meterNoCtrl,
                  decoration: const InputDecoration(labelText: 'Meter Serial No', hintText: 'e.g. MTR-001'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: openingCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Opening Reading', hintText: '0'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final opening = (double.tryParse(openingCtrl.text.trim()) ?? 0.0);
                final openingMilli = (opening * 1000).round();
                final draft = MeterDraft(
                  unitId: selectedUnitId,
                  meterTypeId: selectedMeterTypeId,
                  meterNo: meterNoCtrl.text.trim().isEmpty ? null : meterNoCtrl.text.trim(),
                  openingReadingMilli: openingMilli,
                );
                try {
                  await services.billing.createMeter(societyId, draft);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  Future<void> _openReadingDialog() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_meters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add Unit Meters first.')),
      );
      return;
    }

    final services = await SocietyServices.instance();
    if (!mounted) return;
    int selectedMeterId = _meters.first.id;
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final periodFrom = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final periodTo = today;

    final fromCtrl = TextEditingController(text: periodFrom);
    final toCtrl = TextEditingController(text: periodTo);
    final dateCtrl = TextEditingController(text: today);
    final readingCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Record Meter Reading'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedMeterId,
                  decoration: const InputDecoration(labelText: 'Meter *'),
                  items: _meters
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text('${m.blockName}-${m.unitNo} (${m.meterTypeName})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedMeterId = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fromCtrl,
                        decoration: const InputDecoration(labelText: 'Period From (YYYY-MM-DD) *'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: toCtrl,
                        decoration: const InputDecoration(labelText: 'Period To (YYYY-MM-DD) *'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(labelText: 'Reading Date (YYYY-MM-DD) *'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: readingCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Current Reading *', hintText: 'e.g. 150.50'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final val = double.tryParse(readingCtrl.text.trim());
                if (val == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter a valid reading.')));
                  return;
                }
                final milli = (val * 1000).round();
                try {
                  await services.billing.addMeterReading(
                    societyId,
                    selectedMeterId,
                    fromCtrl.text.trim(),
                    toCtrl.text.trim(),
                    dateCtrl.text.trim(),
                    milli,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }
}
