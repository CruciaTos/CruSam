import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/member_models.dart';
import '../../shared/widgets/area_field.dart';
import '../../shared/widgets/society_page.dart';

class UnitFormScreen extends StatefulWidget {
  final int? unitId;
  const UnitFormScreen({super.key, this.unitId});

  @override
  State<UnitFormScreen> createState() => _UnitFormScreenState();
}

class _UnitFormScreenState extends State<UnitFormScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Block> _blocks = [];
  List<UnitType> _types = [];
  bool _loading = true;
  bool _saving = false;

  int? _blockId;
  final _unitNoController = TextEditingController();
  int? _unitTypeId;
  int _area1Centi = 0;
  int _area2Centi = 0;
  final _floorController = TextEditingController();
  String _occupancy = 'owner_occupied';
  final _notesController = TextEditingController();
  bool _isActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _loading = true);

    try {
      final services = await SocietyServices.instance();
      final blocks = await services.member.listBlocks(societyId);
      final types = await services.member.listUnitTypes(societyId);

      UnitRow? unit;
      if (widget.unitId != null) {
        unit = await services.member.getUnit(widget.unitId!);
      }

      if (mounted) {
        setState(() {
          _blocks = blocks;
          _types = types;
          if (unit != null) {
            _blockId = unit.blockId;
            _unitNoController.text = unit.unitNo;
            _unitTypeId = unit.unitTypeId;
            _area1Centi = unit.area1Centi;
            _area2Centi = unit.area2Centi;
            _floorController.text = unit.floorNo ?? '';
            _occupancy = unit.occupancy;
            _notesController.text = unit.notes ?? '';
            _isActive = unit.isActive;
          } else {
            if (blocks.isNotEmpty) _blockId = blocks.first.id;
            if (types.isNotEmpty) _unitTypeId = types.first.id;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_blockId == null || _unitTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Block and Unit Type')),
      );
      return;
    }

    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _saving = true);

    try {
      final services = await SocietyServices.instance();
      final draft = UnitDraft(
        blockId: _blockId!,
        unitNo: _unitNoController.text.trim(),
        unitTypeId: _unitTypeId!,
        area1Centi: _area1Centi,
        area2Centi: _area2Centi,
        floorNo: _floorController.text.trim().isEmpty ? null : _floorController.text.trim(),
        occupancy: _occupancy,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        isActive: _isActive,
      );

      if (widget.unitId == null) {
        final newId = await services.member.createUnit(societyId, draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unit ${draft.unitNo} created successfully')),
          );
          context.go('/society/units/$newId');
        }
      } else {
        await services.member.updateUnit(societyId, widget.unitId!, draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unit ${draft.unitNo} updated')),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.unitId != null;

    return SocietyPage(
      title: isEdit ? 'Edit Unit' : 'New Unit',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              isEdit ? 'Update Unit Details' : 'Add Unit to Society',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Block & Unit No
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _blockId,
                                    decoration: const InputDecoration(labelText: 'Block / Wing *'),
                                    items: _blocks.map((b) {
                                      return DropdownMenuItem(value: b.id, child: Text(b.name));
                                    }).toList(),
                                    onChanged: (v) => setState(() => _blockId = v),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _unitNoController,
                                    decoration: const InputDecoration(labelText: 'Unit No * (e.g. 101)'),
                                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Unit Type & Floor
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _unitTypeId,
                                    decoration: const InputDecoration(labelText: 'Unit Type *'),
                                    items: _types.map((t) {
                                      return DropdownMenuItem(value: t.id, child: Text(t.name));
                                    }).toList(),
                                    onChanged: (v) => setState(() => _unitTypeId = v),
                                    validator: (v) => v == null ? 'Required' : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _floorController,
                                    decoration: const InputDecoration(labelText: 'Floor No (e.g. 1st)'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Areas
                            Row(
                              children: [
                                Expanded(
                                  child: AreaField(
                                    label: 'Built-up Area 1 (sq ft)',
                                    value: _area1Centi,
                                    onChanged: (val) => _area1Centi = val ?? 0,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: AreaField(
                                    label: 'Carpet Area 2 (sq ft)',
                                    value: _area2Centi,
                                    onChanged: (val) => _area2Centi = val ?? 0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Occupancy
                            DropdownButtonFormField<String>(
                              initialValue: _occupancy,
                              decoration: const InputDecoration(labelText: 'Occupancy Status *'),
                              items: const [
                                DropdownMenuItem(value: 'owner_occupied', child: Text('Owner Occupied')),
                                DropdownMenuItem(value: 'tenanted', child: Text('Tenanted')),
                                DropdownMenuItem(value: 'vacant', child: Text('Vacant')),
                              ],
                              onChanged: (v) => setState(() => _occupancy = v ?? 'owner_occupied'),
                            ),
                            const SizedBox(height: 16),

                            // Notes
                            TextFormField(
                              controller: _notesController,
                              decoration: const InputDecoration(labelText: 'Notes / Remarks'),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),

                            // Active switch
                            SwitchListTile(
                              title: const Text('Active Unit'),
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                            ),
                            const SizedBox(height: 24),

                            // Submit buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: _saving ? null : () => context.pop(),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: _saving ? null : _save,
                                  child: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text('Save Unit'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
