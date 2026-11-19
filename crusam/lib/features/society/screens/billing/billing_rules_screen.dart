import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_date.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/member_models.dart';
import '../../shared/widgets/money_field.dart';
import '../../shared/widgets/percent_field.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_date_field.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class BillingRulesScreen extends StatefulWidget {
  const BillingRulesScreen({super.key});

  @override
  State<BillingRulesScreen> createState() => _BillingRulesScreenState();
}

class _BillingRulesScreenState extends State<BillingRulesScreen> {
  List<BillingRule> _rules = [];
  List<ChargeHead> _heads = [];
  List<UnitType> _types = [];
  List<MeterType> _meterTypes = [];

  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      final rules = await services.billing.listRules(societyId, includeInactive: true);
      final heads = await services.billing.listChargeHeads(societyId);
      final types = await services.member.listUnitTypes(societyId);
      final meterTypes = await services.billing.listMeterTypes(societyId);

      if (mounted) {
        setState(() {
          _rules = rules;
          _heads = heads;
          _types = types;
          _meterTypes = meterTypes;
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

  Future<void> _showRuleDialog([BillingRule? existing]) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_heads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create at least one charge head first.')),
      );
      return;
    }

    int selectedHeadId = existing?.chargeHeadId ?? _heads.first.id;
    int? selectedTypeId = existing?.unitTypeId;
    String ruleType = existing?.ruleType ?? 'area_and_fixed';

    int rate1Paise = existing?.rate1Paise ?? 0;
    int rate2Paise = existing?.rate2Paise ?? 0;
    int fixedPaise = existing?.fixedPaise ?? 0;
    int percentBp = existing?.percentBp ?? 0;
    List<int> baseHeadIds = List<int>.from(existing?.baseHeadIds ?? []);
    int? meterTypeId = existing?.meterTypeId ?? (_meterTypes.isNotEmpty ? _meterTypes.first.id : null);
    String? occupancy = existing?.occupancyFilter;
    String effFrom = existing?.effectiveFrom ?? todayIso();
    String? effTo = existing?.effectiveTo;
    bool isActive = existing?.isActive ?? true;

    final formKey = GlobalKey<FormState>();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Billing Rule' : 'Edit Billing Rule'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: selectedHeadId,
                          decoration: const InputDecoration(labelText: 'Charge Head *'),
                          isExpanded: true,
                          items: _heads.map((h) => DropdownMenuItem(value: h.id, child: Text(h.name))).toList(),
                          onChanged: (v) => setDlgState(() => selectedHeadId = v ?? _heads.first.id),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int?>(
                          initialValue: selectedTypeId,
                          decoration: const InputDecoration(labelText: 'Applies to Unit Type'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Unit Types (General Rule)')),
                            ..._types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                          ],
                          onChanged: (v) => setDlgState(() => selectedTypeId = v),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: ruleType,
                          decoration: const InputDecoration(labelText: 'Rule Formula Type *'),
                          items: const [
                            DropdownMenuItem(value: 'area_and_fixed', child: Text('Area Rate & Fixed Amount')),
                            DropdownMenuItem(value: 'percent_of_heads', child: Text('Percentage of Other Heads')),
                            DropdownMenuItem(value: 'metered_slab', child: Text('Metered Consumption Slabs')),
                          ],
                          onChanged: (v) => setDlgState(() => ruleType = v ?? 'area_and_fixed'),
                        ),
                        const SizedBox(height: 16),

                        // Form fields per rule type
                        if (ruleType == 'area_and_fixed') ...[
                          Row(
                            children: [
                              Expanded(
                                child: MoneyField(
                                  label: 'Rate per sq ft (Area 1)',
                                  value: rate1Paise,
                                  onChanged: (v) => setDlgState(() => rate1Paise = v ?? 0),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MoneyField(
                                  label: 'Fixed Charge / Month',
                                  value: fixedPaise,
                                  onChanged: (v) => setDlgState(() => fixedPaise = v ?? 0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MoneyField(
                            label: 'Rate per sq ft (Area 2 - Optional)',
                            value: rate2Paise,
                            onChanged: (v) => setDlgState(() => rate2Paise = v ?? 0),
                          ),
                        ] else if (ruleType == 'percent_of_heads') ...[
                          PercentField(
                            label: 'Percentage Rate (%)',
                            value: percentBp,
                            onChanged: (v) => setDlgState(() => percentBp = v ?? 0),
                          ),
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Calculate percentage over these base heads:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._heads.where((h) => h.id != selectedHeadId).map((h) {
                            final isChecked = baseHeadIds.contains(h.id);
                            return CheckboxListTile(
                              title: Text(h.name, style: const TextStyle(fontSize: 13)),
                              value: isChecked,
                              dense: true,
                              onChanged: (val) {
                                setDlgState(() {
                                  if (val == true) {
                                    baseHeadIds.add(h.id);
                                  } else {
                                    baseHeadIds.remove(h.id);
                                  }
                                });
                              },
                            );
                          }),
                        ] else if (ruleType == 'metered_slab') ...[
                          DropdownButtonFormField<int>(
                            initialValue: meterTypeId,
                            decoration: const InputDecoration(labelText: 'Meter Type *'),
                            isExpanded: true,
                            items: _meterTypes.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))).toList(),
                            onChanged: (v) => setDlgState(() => meterTypeId = v),
                          ),
                        ],

                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: occupancy,
                          decoration: const InputDecoration(labelText: 'Occupancy Condition'),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('All Occupancy Statuses')),
                            DropdownMenuItem(value: 'owner_occupied', child: Text('Owner Occupied Only')),
                            DropdownMenuItem(value: 'tenanted', child: Text('Tenanted Only')),
                            DropdownMenuItem(value: 'vacant', child: Text('Vacant Only')),
                          ],
                          onChanged: (v) => setDlgState(() => occupancy = v),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SocietyDateField(
                                label: 'Effective From *',
                                value: effFrom,
                                onChanged: (v) {
                                  if (v != null) setDlgState(() => effFrom = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SocietyDateField(
                                label: 'Effective To',
                                value: effTo ?? '',
                                onChanged: (v) => setDlgState(() => effTo = v?.isNotEmpty == true ? v : null),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Active'),
                          value: isActive,
                          onChanged: (v) => setDlgState(() => isActive = v),
                        ),
                      ],
                    ),
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
        final draft = BillingRuleDraft(
          chargeHeadId: selectedHeadId,
          unitTypeId: selectedTypeId,
          ruleType: ruleType,
          rate1Paise: rate1Paise,
          rate2Paise: rate2Paise,
          fixedPaise: fixedPaise,
          percentBp: percentBp,
          baseHeadIds: baseHeadIds,
          occupancyFilter: occupancy,
          meterTypeId: ruleType == 'metered_slab' ? meterTypeId : null,
          effectiveFrom: effFrom,
          effectiveTo: effTo,
          isActive: isActive,
        );

        if (existing == null) {
          await services.billing.createRule(societyId, draft);
        } else {
          await services.billing.updateRule(societyId, existing.id, draft);
        }
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Billing Rules',
      subtitle: '${_rules.length} configured rules',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Billing Rule'),
          onPressed: () => _showRuleDialog(),
        ),
      ],
      child: _error != null
          ? SocietyErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? SocietyEmptyView(
                  icon: Icons.rule_outlined,
                  title: 'No billing rules',
                  message: 'Create billing rules to automate member bill calculations.',
                  action: FilledButton(
                    onPressed: () => _showRuleDialog(),
                    child: const Text('Add Rule'),
                  ),
                )
              : SocietyDataTable<BillingRule>(
                  columns: [
                    SocietyColumn(
                      label: 'Charge Head',
                      cell: (r) => Text(
                        r.chargeHeadName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SocietyColumn(
                      label: 'Unit Type',
                      cell: (r) => Text(r.unitTypeName ?? 'All Types'),
                    ),
                    SocietyColumn(
                      label: 'Formula',
                      cell: (r) {
                        if (r.ruleType == 'area_and_fixed') {
                          final parts = <String>[];
                          if (r.rate1Paise > 0) parts.add('${formatInr(r.rate1Paise)}/sq ft');
                          if (r.fixedPaise > 0) parts.add('${formatInr(r.fixedPaise)} fixed');
                          return Text(parts.join(' + '));
                        } else if (r.ruleType == 'percent_of_heads') {
                          return Text('${(r.percentBp / 100).toStringAsFixed(2)}% of base heads');
                        } else {
                          return Text('Metered: ${r.meterTypeName ?? ""}');
                        }
                      },
                    ),
                    SocietyColumn(
                      label: 'Occupancy',
                      cell: (r) => Text(r.occupancyFilter?.replaceAll('_', ' ') ?? 'All'),
                    ),
                    SocietyColumn(
                      label: 'Effective Period',
                      cell: (r) => Text(
                        '${formatDisplayDate(r.effectiveFrom)} - ${r.effectiveTo != null ? formatDisplayDate(r.effectiveTo!) : "Ongoing"}',
                      ),
                    ),
                    SocietyColumn(
                      label: 'Status',
                      width: 100,
                      cell: (r) => StatusChip(
                        status: r.isActive ? 'active' : 'draft',
                        label: r.isActive ? 'Active' : 'Inactive',
                      ),
                    ),
                    SocietyColumn(
                      label: 'Actions',
                      width: 80,
                      cell: (r) => IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showRuleDialog(r),
                      ),
                    ),
                  ],
                  rows: _rules,
                  total: _rules.length,
                  page: 0,
                  pageSize: _rules.length.clamp(1, 100),
                  onPage: (_) {},
                ),
    );
  }
}
