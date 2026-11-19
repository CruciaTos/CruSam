import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/export_menu.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_filter_bar.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  List<Block> _blocks = [];
  List<UnitType> _types = [];

  int? _selectedBlockId;
  int? _selectedTypeId;
  String? _selectedOccupancy;
  String _search = '';

  int _page = 0;
  static const int _pageSize = 50;

  PageResult<UnitRow>? _result;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFilters();
    _loadUnits();
  }

  Future<void> _loadFilters() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final blocks = await services.member.listBlocks(societyId);
      final types = await services.member.listUnitTypes(societyId);
      if (mounted) {
        setState(() {
          _blocks = blocks;
          _types = types;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadUnits() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final res = await services.member.listUnits(
        societyId,
        blockId: _selectedBlockId,
        unitTypeId: _selectedTypeId,
        occupancy: _selectedOccupancy,
        search: _search,
        page: PageRequest(limit: _pageSize, offset: _page * _pageSize),
      );

      if (mounted) {
        setState(() {
          _result = res;
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

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Units',
      subtitle: '${_result?.total ?? 0} total units',
      actions: [
        ExportMenu(
          onExportPdf: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Units list export ready')),
            );
          },
          onExportExcel: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Units list export ready')),
            );
          },
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Unit'),
          onPressed: () async {
            await context.push('/society/units/new');
            _loadUnits();
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Bar
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Search unit or block...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _search = val;
                          _page = 0;
                        });
                        _loadUnits();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedBlockId,
                      decoration: const InputDecoration(labelText: 'Block', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Blocks')),
                        ..._blocks.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedBlockId = val;
                          _page = 0;
                        });
                        _loadUnits();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<int?>(
                      initialValue: _selectedTypeId,
                      decoration: const InputDecoration(labelText: 'Unit Type', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Types')),
                        ..._types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedTypeId = val;
                          _page = 0;
                        });
                        _loadUnits();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _selectedOccupancy,
                      decoration: const InputDecoration(labelText: 'Occupancy', isDense: true),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Occupancy')),
                        DropdownMenuItem(value: 'owner_occupied', child: Text('Owner Occupied')),
                        DropdownMenuItem(value: 'tenanted', child: Text('Tenanted')),
                        DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedOccupancy = val;
                          _page = 0;
                        });
                        _loadUnits();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SocietyErrorView(message: _error!, onRetry: _loadUnits),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _result == null || _result!.rows.isEmpty
                    ? SocietyEmptyView(
                        icon: Icons.meeting_room_outlined,
                        title: 'No units found',
                        message: 'No units matched your filter criteria or none have been added yet.',
                        action: FilledButton(
                          onPressed: () => context.push('/society/units/new'),
                          child: const Text('Add First Unit'),
                        ),
                      )
                    : SocietyDataTable<UnitRow>(
                        columns: [
                          SocietyColumn(
                            label: 'Block',
                            width: 100,
                            cell: (u) => Text(u.blockName),
                          ),
                          SocietyColumn(
                            label: 'Unit No',
                            width: 110,
                            cell: (u) => InkWell(
                              onTap: () => context.push('/society/units/${u.id}'),
                              child: Text(
                                u.unitNo,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Type',
                            width: 110,
                            cell: (u) => Text(u.unitTypeName),
                          ),
                          SocietyColumn(
                            label: 'Primary Contact',
                            cell: (u) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  u.primaryContactName ?? '-',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                if (u.primaryContactPhone != null)
                                  Text(
                                    u.primaryContactPhone!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SocietyColumn(
                            label: 'Bill To',
                            cell: (u) => Text(u.billToName ?? '-'),
                          ),
                          SocietyColumn(
                            label: 'Area (sq ft)',
                            numeric: true,
                            width: 120,
                            cell: (u) => Text(
                              u.area1Centi > 0
                                  ? (u.area1Centi / 100.0).toStringAsFixed(2)
                                  : '-',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Occupancy',
                            width: 140,
                            cell: (u) {
                              String label;
                              String statusKey;
                              switch (u.occupancy) {
                                case 'owner_occupied':
                                  statusKey = 'active';
                                  label = 'Owner Occupied';
                                  break;
                                case 'tenanted':
                                  statusKey = 'open';
                                  label = 'Tenanted';
                                  break;
                                case 'vacant':
                                default:
                                  statusKey = 'draft';
                                  label = 'Vacant';
                                  break;
                              }
                              return StatusChip(status: statusKey, label: label);
                            },
                          ),
                          SocietyColumn(
                            label: 'Status',
                            width: 90,
                            cell: (u) => StatusChip(
                              status: u.isActive ? 'active' : 'draft',
                              label: u.isActive ? 'Active' : 'Inactive',
                            ),
                          ),
                        ],
                        rows: _result!.rows,
                        total: _result!.total,
                        page: _page,
                        pageSize: _pageSize,
                        onPage: (newPage) {
                          setState(() => _page = newPage);
                          _loadUnits();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
