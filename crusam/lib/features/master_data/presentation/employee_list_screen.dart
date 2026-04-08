import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../data/models/employee_model.dart';
import '../services/employee_excel_import_service.dart';
import '../notifiers/employee_notifier.dart';
import 'employee_form_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});
  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final _notifier = EmployeeNotifier();
  final _search   = TextEditingController();
  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  bool _showHorizontalScrollbar = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _notifier.load();
  }

  @override
  void dispose() {
    _notifier.dispose();
    _search.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _toggleHorizontalScrollbar(bool visible) {
    if (_showHorizontalScrollbar == visible || !mounted) return;
    setState(() => _showHorizontalScrollbar = visible);
  }

  Widget _doubleTapToEdit(EmployeeModel e, Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onDoubleTap: () => _goToForm(e),
    child: child,
  );

  Future<void> _goToForm([EmployeeModel? emp]) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black45,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: EmployeeFormScreen(employee: emp?.toMap()),
      ),
    );
    _notifier.load();
  }

  Future<void> _onImportExcel() async {
    if (_isImporting) return;

    setState(() => _isImporting = true);

    try {
      final result = await EmployeeExcelImportService.importFromFile();

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Preview'),
          content: Text(
            'Valid: ${result.validCount}\n'
            'Duplicates (in file): ${result.duplicateCount}\n'
            'Invalid: ${result.invalidCount}\n\n'
            'Proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final inserted = await _notifier.importEmployees(result.validEmployees);

      if (!mounted) return;

      final skipped =
          (result.validEmployees.length - inserted) + result.duplicateCount + result.invalidCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported: $inserted, Skipped: $skipped')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import failed')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
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
                    style: AppTextStyles.input,
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
                onPressed: _isImporting ? null : _onImportExcel,
                icon: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(_isImporting ? 'Importing...' : 'Import Excel'),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final table = ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _verticalScrollController,
                          child: DataTable(
                            horizontalMargin: 16,
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
                            ],
                            rows: _notifier.filtered.map((e) => DataRow(cells: [
                              DataCell(_doubleTapToEdit(e, Text(e.srNo.toString()))),
                              DataCell(_doubleTapToEdit(
                                e,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(e.name, style: AppTextStyles.bodySemi.copyWith(fontSize: 13)),
                                    Text(e.code, style: AppTextStyles.small),
                                  ],
                                ),
                              )),
                              DataCell(_doubleTapToEdit(e, Text(e.pfNo))),
                              DataCell(_doubleTapToEdit(e, Text(e.uanNo))),
                              DataCell(_doubleTapToEdit(e, Text(e.code))),
                              DataCell(_doubleTapToEdit(
                                e,
                                Text(e.ifscCode, style: AppTextStyles.monoSm),
                              )),
                              DataCell(_doubleTapToEdit(
                                e,
                                Text(e.accountNumber, style: AppTextStyles.monoSm),
                              )),
                              DataCell(_doubleTapToEdit(e, Text(e.bankDetails))),
                              DataCell(_doubleTapToEdit(e, Text(e.branch))),
                              DataCell(_doubleTapToEdit(e, Text(e.zone))),
                            ])).toList(),
                          ),
                        ),
                      ),
                    );

                    return Column(
                      children: [
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Double-tap an employee row to edit or delete',
                              style: AppTextStyles.small,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: MouseRegion(
                            onEnter: (_) => _toggleHorizontalScrollbar(true),
                            onExit: (_) => _toggleHorizontalScrollbar(false),
                            child: Scrollbar(
                              controller: _horizontalScrollController,
                              thumbVisibility: _showHorizontalScrollbar,
                              trackVisibility: false,
                              thickness: 8,
                              radius: const Radius.circular(8),
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: table,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}