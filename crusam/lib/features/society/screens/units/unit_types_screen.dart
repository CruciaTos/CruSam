import 'package:flutter/material.dart';

import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/member_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class UnitTypesScreen extends StatefulWidget {
  const UnitTypesScreen({super.key});

  @override
  State<UnitTypesScreen> createState() => _UnitTypesScreenState();
}

class _UnitTypesScreenState extends State<UnitTypesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<UnitType> _types = [];
  List<Block> _blocks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      final types = await services.member.listUnitTypes(societyId, includeInactive: true);
      final blocks = await services.member.listBlocks(societyId, includeInactive: true);

      if (mounted) {
        setState(() {
          _types = types;
          _blocks = blocks;
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

  Future<void> _showTypeDialog([UnitType? existing]) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    final sortController = TextEditingController(text: (existing?.sortOrder ?? 0).toString());
    bool isActive = existing?.isActive ?? true;

    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Unit Type' : 'Edit Unit Type'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name (e.g. 2BHK) *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: sortController,
                        decoration: const InputDecoration(labelText: 'Sort Order'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Active'),
                        value: isActive,
                        onChanged: (v) => setDlgState(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('Save'),
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
        final draft = UnitTypeDraft(
          name: nameController.text.trim(),
          sortOrder: int.tryParse(sortController.text.trim()) ?? 0,
          isActive: isActive,
        );

        if (existing == null) {
          await services.member.createUnitType(societyId, draft);
        } else {
          await services.member.updateUnitType(societyId, existing.id, draft);
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _showBlockDialog([Block? existing]) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    bool isActive = existing?.isActive ?? true;

    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Block' : 'Edit Block'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Block Name (e.g. Wing A) *'),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Active'),
                        value: isActive,
                        onChanged: (v) => setDlgState(() => isActive = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: const Text('Save'),
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
        final draft = BlockDraft(
          name: nameController.text.trim(),
          isActive: isActive,
        );

        if (existing == null) {
          await services.member.createBlock(societyId, draft);
        } else {
          await services.member.updateBlock(societyId, existing.id, draft);
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Unit Types & Blocks',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(_tabController.index == 0 ? 'New Unit Type' : 'New Block'),
          onPressed: () {
            if (_tabController.index == 0) {
              _showTypeDialog();
            } else {
              _showBlockDialog();
            }
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
              Tab(text: 'Unit Types'),
              Tab(text: 'Blocks / Wings'),
            ],
            onTap: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SocietyErrorView(message: _error!, onRetry: _loadData),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Unit Types Tab
                      _types.isEmpty
                          ? SocietyEmptyView(
                              icon: Icons.category_outlined,
                              title: 'No unit types defined',
                              message: 'Create unit types like 1BHK, 2BHK, Penthouse, Shop, etc.',
                              action: FilledButton(
                                onPressed: () => _showTypeDialog(),
                                child: const Text('Add Unit Type'),
                              ),
                            )
                          : SocietyDataTable<UnitType>(
                              columns: [
                                SocietyColumn(
                                  label: 'Name',
                                  cell: (t) => Text(
                                    t.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Sort Order',
                                  width: 120,
                                  cell: (t) => Text(t.sortOrder.toString()),
                                ),
                                SocietyColumn(
                                  label: 'Status',
                                  width: 120,
                                  cell: (t) => StatusChip(
                                    status: t.isActive ? 'active' : 'draft',
                                    label: t.isActive ? 'Active' : 'Inactive',
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Actions',
                                  width: 90,
                                  cell: (t) => IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _showTypeDialog(t),
                                  ),
                                ),
                              ],
                              rows: _types,
                              total: _types.length,
                              page: 0,
                              pageSize: _types.length.clamp(1, 100),
                              onPage: (_) {},
                            ),

                      // Blocks Tab
                      _blocks.isEmpty
                          ? SocietyEmptyView(
                              icon: Icons.apartment_outlined,
                              title: 'No blocks defined',
                              message: 'Create wings or blocks like Wing A, Tower 1, etc.',
                              action: FilledButton(
                                onPressed: () => _showBlockDialog(),
                                child: const Text('Add Block'),
                              ),
                            )
                          : SocietyDataTable<Block>(
                              columns: [
                                SocietyColumn(
                                  label: 'Block / Wing Name',
                                  cell: (b) => Text(
                                    b.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Status',
                                  width: 120,
                                  cell: (b) => StatusChip(
                                    status: b.isActive ? 'active' : 'draft',
                                    label: b.isActive ? 'Active' : 'Inactive',
                                  ),
                                ),
                                SocietyColumn(
                                  label: 'Actions',
                                  width: 90,
                                  cell: (b) => IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () => _showBlockDialog(b),
                                  ),
                                ),
                              ],
                              rows: _blocks,
                              total: _blocks.length,
                              page: 0,
                              pageSize: _blocks.length.clamp(1, 100),
                              onPage: (_) {},
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
