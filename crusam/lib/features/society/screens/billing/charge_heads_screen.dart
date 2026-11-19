import 'package:flutter/material.dart';

import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/percent_field.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/status_chip.dart';

class ChargeHeadsScreen extends StatefulWidget {
  const ChargeHeadsScreen({super.key});

  @override
  State<ChargeHeadsScreen> createState() => _ChargeHeadsScreenState();
}

class _ChargeHeadsScreenState extends State<ChargeHeadsScreen> {
  List<ChargeHead> _heads = [];
  List<Account> _accounts = [];
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
      final heads = await services.billing.listChargeHeads(societyId, includeInactive: true);
      final tree = await services.ledger.chartOfAccounts(societyId);
      final flat = <Account>[];
      for (final g in tree) {
        flat.addAll(g.accounts);
      }
      flat.sort((a, b) => a.code.compareTo(b.code));

      if (mounted) {
        setState(() {
          _heads = heads;
          _accounts = flat;
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

  Future<void> _showHeadDialog([ChargeHead? existing]) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int? selectedAccountId = existing?.accountId ?? (_accounts.isNotEmpty ? _accounts.first.id : null);
    String headKind = existing?.headKind ?? 'charge';
    bool isInterestBearing = existing?.isInterestBearing ?? true;
    bool isGst = existing?.isGstApplicable ?? false;
    int? gstBp = existing?.defaultGstRateBp;
    final hsnCtrl = TextEditingController(text: existing?.hsnSac ?? '');
    final sortCtrl = TextEditingController(text: (existing?.sortOrder ?? 0).toString());
    bool isActive = existing?.isActive ?? true;

    final formKey = GlobalKey<FormState>();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Charge Head' : 'Edit Charge Head'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: 'Charge Head Name *'),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: selectedAccountId,
                          decoration: const InputDecoration(labelText: 'GL Account *'),
                          isExpanded: true,
                          items: _accounts.map((a) {
                            return DropdownMenuItem(
                              value: a.id,
                              child: Text('${a.code} - ${a.name}'),
                            );
                          }).toList(),
                          onChanged: (v) => setDlgState(() => selectedAccountId = v),
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          title: const Text('Interest Bearing'),
                          subtitle: const Text('Late payment interest accrues if unpaid'),
                          value: isInterestBearing,
                          onChanged: (v) => setDlgState(() => isInterestBearing = v ?? true),
                        ),
                        CheckboxListTile(
                          title: const Text('GST Applicable'),
                          value: isGst,
                          onChanged: (v) => setDlgState(() => isGst = v ?? false),
                        ),
                        if (isGst) ...[
                          const SizedBox(height: 8),
                          PercentField(
                            label: 'Default GST Rate (%)',
                            value: gstBp,
                            onChanged: (val) => setDlgState(() => gstBp = val),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: hsnCtrl,
                            decoration: const InputDecoration(labelText: 'HSN / SAC Code'),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: sortCtrl,
                          decoration: const InputDecoration(labelText: 'Sort Order'),
                          keyboardType: TextInputType.number,
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

    if (confirmed == true && selectedAccountId != null && mounted) {
      try {
        final services = await SocietyServices.instance();
        final draft = ChargeHeadDraft(
          name: nameCtrl.text.trim(),
          accountId: selectedAccountId!,
          headKind: headKind,
          isInterestBearing: isInterestBearing,
          isGstApplicable: isGst,
          defaultGstRateBp: isGst ? gstBp : null,
          hsnSac: isGst && hsnCtrl.text.trim().isNotEmpty ? hsnCtrl.text.trim() : null,
          sortOrder: int.tryParse(sortCtrl.text.trim()) ?? 0,
          isActive: isActive,
        );

        if (existing == null) {
          await services.billing.createChargeHead(societyId, draft);
        } else {
          await services.billing.updateChargeHead(societyId, existing.id, draft);
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
      title: 'Charge Heads',
      subtitle: '${_heads.length} defined billing heads',
      actions: [
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Charge Head'),
          onPressed: () => _showHeadDialog(),
        ),
      ],
      child: _error != null
          ? SocietyErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Center(child: CircularProgressIndicator())
          : _heads.isEmpty
              ? SocietyEmptyView(
                  icon: Icons.list_alt_outlined,
                  title: 'No charge heads',
                  message: 'Define charge heads to configure billing rules.',
                  action: FilledButton(
                    onPressed: () => _showHeadDialog(),
                    child: const Text('Add First Head'),
                  ),
                )
              : SocietyDataTable<ChargeHead>(
                  columns: [
                    SocietyColumn(
                      label: 'Name',
                      cell: (h) => Text(
                        h.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SocietyColumn(
                      label: 'GL Account',
                      cell: (h) => Text('${h.accountCode ?? ""} - ${h.accountName ?? ""}'),
                    ),
                    SocietyColumn(
                      label: 'Interest Bearing',
                      width: 130,
                      cell: (h) => h.isInterestBearing
                          ? const StatusChip(status: 'active', label: 'Yes')
                          : const Text('No'),
                    ),
                    SocietyColumn(
                      label: 'GST Applicable',
                      width: 130,
                      cell: (h) {
                        if (!h.isGstApplicable) return const Text('No');
                        final bp = h.defaultGstRateBp ?? 0;
                        return Text('Yes (${(bp / 100).toStringAsFixed(1)}%)');
                      },
                    ),
                    SocietyColumn(
                      label: 'Sort Order',
                      width: 90,
                      numeric: true,
                      cell: (h) => Text(h.sortOrder.toString()),
                    ),
                    SocietyColumn(
                      label: 'Status',
                      width: 100,
                      cell: (h) => StatusChip(
                        status: h.isActive ? 'active' : 'draft',
                        label: h.isActive ? 'Active' : 'Inactive',
                      ),
                    ),
                    SocietyColumn(
                      label: 'Actions',
                      width: 80,
                      cell: (h) => IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showHeadDialog(h),
                      ),
                    ),
                  ],
                  rows: _heads,
                  total: _heads.length,
                  page: 0,
                  pageSize: _heads.length.clamp(1, 100),
                  onPage: (_) {},
                ),
    );
  }
}
