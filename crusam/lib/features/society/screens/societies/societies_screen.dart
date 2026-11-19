import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/shared/widgets/society_data_table.dart';
import 'package:crusam/features/society/shared/widgets/society_filter_bar.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';
import 'package:crusam/features/society/shared/widgets/status_chip.dart';

class SocietiesScreen extends StatefulWidget {
  const SocietiesScreen({super.key});

  @override
  State<SocietiesScreen> createState() => _SocietiesScreenState();
}

class _SocietiesScreenState extends State<SocietiesScreen> {
  List<SocietySummary> _all = [];
  List<SocietySummary> _filtered = [];
  bool _loading = true;
  String _search = '';
  final Map<int, int> _unitCounts = {};
  final Map<int, String> _registrationNos = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final list = await services.society.listSocieties(includeInactive: true);

      _unitCounts.clear();
      _registrationNos.clear();
      for (final s in list) {
        final soc = await services.society.getSociety(s.id);
        _registrationNos[s.id] = soc.registrationNo ?? '';

        final countRows = await services.db.rawQuery(
          'SELECT COUNT(*) as cnt FROM units WHERE society_id = ? AND is_active = 1',
          [s.id],
        );
        _unitCounts[s.id] = (countRows.first['cnt'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _all = list;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    if (_search.isEmpty) {
      _filtered = List.from(_all);
    } else {
      final q = _search.toLowerCase();
      _filtered = _all.where((s) {
        return s.name.toLowerCase().contains(q) ||
            (s.city?.toLowerCase().contains(q) ?? false) ||
            (_registrationNos[s.id]?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Societies',
      subtitle: 'Manage housing societies, registrations and accounts',
      allowAllSocieties: true,
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Society'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          onPressed: () => context.go('/society/societies/new'),
        ),
      ],
      filters: SocietyFilterBar(
        searchHint: 'Search by name, city, registration...',
        onSearch: (q) {
          setState(() {
            _search = q;
            _applyFilter();
          });
        },
      ),
      child: SocietyDataTable<SocietySummary>(
        columns: [
          SocietyColumn<SocietySummary>(
            label: 'Society Name',
            cell: (s) => Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SocietyColumn<SocietySummary>(
            label: 'City',
            cell: (s) => Text(s.city ?? '—'),
          ),
          SocietyColumn<SocietySummary>(
            label: 'Registration No',
            cell: (s) => Text(_registrationNos[s.id] ?? '—'),
          ),
          SocietyColumn<SocietySummary>(
            label: 'Units',
            numeric: true,
            cell: (s) => Text('${_unitCounts[s.id] ?? 0}'),
          ),
          SocietyColumn<SocietySummary>(
            label: 'Active FY',
            cell: (s) => Text(s.activeFyCode ?? '—'),
          ),
          SocietyColumn<SocietySummary>(
            label: 'Status',
            cell: (s) => StatusChip(status: s.isActive ? 'active' : 'closed'),
          ),
          SocietyColumn<SocietySummary>(
            label: 'Actions',
            cell: (s) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit details',
                  onPressed: () => context.go('/society/societies/${s.id}'),
                ),
                IconButton(
                  icon: const Icon(Icons.login, size: 18, color: Color(0xFF3B82F6)),
                  tooltip: 'Switch to this society',
                  onPressed: () async {
                    await SocietyContext.instance.selectSociety(s.id);
                    if (context.mounted) {
                      context.go('/society/overview');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
        rows: _filtered,
        total: _filtered.length,
        loading: _loading,
        onRowTap: (s) => context.go('/society/societies/${s.id}'),
      ),
    );
  }
}
