import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_empty_view.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  bool _loading = true;
  String? _error;
  List<VendorRow> _vendors = [];
  String _search = '';

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
      final list = await services.expenses.listVendors(
        societyId,
        filter: VendorFilter(search: _search.isEmpty ? null : _search),
      );

      if (mounted) {
        setState(() {
          _vendors = list;
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
      title: 'Vendors',
      actions: [
        SizedBox(
          width: 250,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search vendors...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) {
              _search = v;
              _load();
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Vendor'),
          onPressed: () async {
            await context.push('/society/vendors/new');
            _load();
          },
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SocietyErrorView(message: _error!, onRetry: _load)
              : _vendors.isEmpty
                  ? SocietyEmptyView(
                      icon: Icons.storefront_outlined,
                      title: 'No vendors found',
                      message: 'Add security, housekeeping, lift maintenance agencies and other vendors.',
                      action: FilledButton(
                        onPressed: () => context.push('/society/vendors/new'),
                        child: const Text('Add First Vendor'),
                      ),
                    )
                  : SocietyDataTable<VendorRow>(
                      total: _vendors.length,
                      columns: [
                        SocietyColumn<VendorRow>(
                          label: 'Code',
                          cell: (vr) => InkWell(
                            onTap: () => context.push('/society/vendors/${vr.vendor.id}'),
                            child: Text(vr.vendor.vendorCode ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                          width: 100,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Vendor Name',
                          cell: (vr) => InkWell(
                            onTap: () => context.push('/society/vendors/${vr.vendor.id}'),
                            child: Text(vr.vendor.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          width: 180,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Contact',
                          cell: (vr) => Text(vr.vendor.contactName ?? '-'),
                          width: 130,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Phone',
                          cell: (vr) => Text(vr.vendor.phone ?? '-'),
                          width: 120,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'GSTIN',
                          cell: (vr) => Text(vr.vendor.gstin ?? '-'),
                          width: 140,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Default Expense',
                          cell: (vr) => Text(vr.vendor.defaultExpenseAccountName ?? '-'),
                          width: 150,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Billed',
                          numeric: true,
                          cell: (vr) => Text(formatPaise(vr.billedPaise)),
                          width: 110,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Paid',
                          numeric: true,
                          cell: (vr) => Text(formatPaise(vr.paidPaise)),
                          width: 110,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Balance',
                          numeric: true,
                          cell: (vr) => Text(
                            formatPaise(vr.balancePaise),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: vr.balancePaise > 0 ? Colors.red.shade700 : Colors.green.shade700,
                            ),
                          ),
                          width: 120,
                        ),
                        SocietyColumn<VendorRow>(
                          label: 'Status',
                          cell: (vr) => StatusChip(status: vr.vendor.isActive ? 'active' : 'inactive'),
                          width: 100,
                        ),
                      ],
                      rows: _vendors,
                    ),
    );
  }
}
