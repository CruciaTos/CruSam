import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  String _search = '';
  int _page = 0;
  static const int _pageSize = 50;

  PageResult<Person>? _result;
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final res = await services.member.listPeople(
        societyId,
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
      title: 'Members & Residents',
      subtitle: '${_result?.total ?? 0} registered people',
      actions: [
        ExportMenu(
          onExportPdf: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Members export ready')),
            );
          },
          onExportExcel: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Members export ready')),
            );
          },
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Add Member'),
          onPressed: () async {
            await context.push('/society/members/new');
            _loadPeople();
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
              child: Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Search by name, phone or email...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _search = val;
                          _page = 0;
                        });
                        _loadPeople();
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
              child: SocietyErrorView(message: _error!, onRetry: _loadPeople),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _result == null || _result!.rows.isEmpty
                    ? SocietyEmptyView(
                        icon: Icons.people_outline,
                        title: 'No members found',
                        message: 'No members match your search criteria.',
                        action: FilledButton(
                          onPressed: () => context.push('/society/members/new'),
                          child: const Text('Add Member'),
                        ),
                      )
                    : SocietyDataTable<Person>(
                        columns: [
                          SocietyColumn(
                            label: 'Full Name',
                            cell: (p) => InkWell(
                              onTap: () async {
                                await context.push('/society/members/${p.id}');
                                _loadPeople();
                              },
                              child: Text(
                                p.fullName,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Phone',
                            width: 140,
                            cell: (p) => Text(p.phone ?? '-'),
                          ),
                          SocietyColumn(
                            label: 'Email',
                            cell: (p) => Text(p.email ?? '-'),
                          ),
                          SocietyColumn(
                            label: 'Assigned Units',
                            cell: (p) => Wrap(
                              spacing: 6,
                              children: p.assignedUnits.map((u) {
                                return Chip(
                                  label: Text(u, style: const TextStyle(fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
                            ),
                          ),
                          SocietyColumn(
                            label: 'PAN',
                            width: 130,
                            cell: (p) => Text(p.pan ?? '-'),
                          ),
                          SocietyColumn(
                            label: 'Status',
                            width: 100,
                            cell: (p) => StatusChip(
                              status: p.isActive ? 'active' : 'draft',
                              label: p.isActive ? 'Active' : 'Inactive',
                            ),
                          ),
                          SocietyColumn(
                            label: 'Actions',
                            width: 80,
                            cell: (p) => IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () async {
                                await context.push('/society/members/${p.id}');
                                _loadPeople();
                              },
                            ),
                          ),
                        ],
                        rows: _result!.rows,
                        total: _result!.total,
                        page: _page,
                        pageSize: _pageSize,
                        onPage: (newPage) {
                          setState(() => _page = newPage);
                          _loadPeople();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
