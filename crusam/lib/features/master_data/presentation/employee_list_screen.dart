import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../data/models/employee_model.dart';
import '../notifiers/employee_notifier.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});
  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final _notifier = EmployeeNotifier();
  final _search   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notifier.load();
  }

  @override
  void dispose() {
    _notifier.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _goToForm([EmployeeModel? emp]) async {
    await context.push('/employees/form', extra: emp?.toMap());
    _notifier.load();
  }

  Future<void> _confirmDelete(EmployeeModel emp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Delete "${emp.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && emp.id != null) await _notifier.delete(emp.id!);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _notifier,
    builder: (ctx, _) => Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onChanged: _notifier.search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or PF No...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _search.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () { _search.clear(); _notifier.search(''); })
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              ElevatedButton.icon(
                onPressed: () => _goToForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Employee'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_notifier.isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_notifier.filtered.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _notifier.employees.isEmpty ? 'No employees yet. Tap Add to create one.' : 'No results found.',
                  style: AppTextStyles.small,
                ),
              ),
            )
          else
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Sr.')),
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('PF No.')),
                        DataColumn(label: Text('UAN No.')),
                        DataColumn(label: Text('Code')),
                        DataColumn(label: Text('IFSC')),
                        DataColumn(label: Text('Account No.')),
                        DataColumn(label: Text('Bank')),
                        DataColumn(label: Text('Branch')),
                        DataColumn(label: Text('Zone')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: _notifier.filtered.map((e) => DataRow(cells: [
                        DataCell(Text(e.srNo.toString())),
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(e.name, style: AppTextStyles.bodySemi.copyWith(fontSize: 13)),
                            Text(e.code, style: AppTextStyles.small),
                          ],
                        )),
                        DataCell(Text(e.pfNo)),
                        DataCell(Text(e.uanNo)),
                        DataCell(Text(e.code)),
                        DataCell(Text(e.ifscCode, style: AppTextStyles.monoSm)),
                        DataCell(Text(e.accountNumber, style: AppTextStyles.monoSm)),
                        DataCell(Text(e.bankDetails)),
                        DataCell(Text(e.branch)),
                        DataCell(Text(e.zone)),
                        DataCell(Row(children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 17, color: AppColors.indigo600),
                            onPressed: () => _goToForm(e),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                            onPressed: () => _confirmDelete(e),
                            tooltip: 'Delete',
                          ),
                        ])),
                      ])).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}