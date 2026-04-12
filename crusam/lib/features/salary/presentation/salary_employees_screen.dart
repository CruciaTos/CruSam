import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';
import '../../../features/master_data/notifiers/employee_notifier.dart';
import '../widgets/salary_entry_table.dart';

class SalaryEmployeesScreen extends StatefulWidget {
  const SalaryEmployeesScreen({super.key});
  @override
  State<SalaryEmployeesScreen> createState() => _SalaryEmployeesScreenState();
}

class _SalaryEmployeesScreenState extends State<SalaryEmployeesScreen> {
  // Shared notifier — same source of truth as Employee Master Data
  final _employeeNotifier = EmployeeNotifier();

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;

  // Keyed by employee DB id so controllers survive list re-sorts / filters
  final Map<int, TextEditingController> _daysCtrls     = {};
  final Map<int, FocusNode>             _daysFocusNodes = {};

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  bool get _isMsw    => _month == 6 || _month == 12;
  bool get _isFeb    => _month == 2;
  int  get _totalDays => DateTime(_year, _month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    _employeeNotifier.addListener(_syncControllers);
    _employeeNotifier.load();
  }

  @override
  void dispose() {
    _employeeNotifier.removeListener(_syncControllers);
    _employeeNotifier.dispose();
    for (final c in _daysCtrls.values)      c.dispose();
    for (final f in _daysFocusNodes.values) f.dispose();
    super.dispose();
  }

  /// Called whenever the notifier's employee list changes (load, add, edit,
  /// delete). Creates controllers for new employees and removes stale ones.
  void _syncControllers() {
    if (!mounted) return;

    final liveIds = _employeeNotifier.employees
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toSet();

    // Remove controllers for deleted employees
    final staleIds = _daysCtrls.keys
        .where((id) => !liveIds.contains(id))
        .toList();
    for (final id in staleIds) {
      _daysCtrls.remove(id)?.dispose();
      _daysFocusNodes.remove(id)?.dispose();
    }

    // Add controllers for new employees (existing ones are untouched — days
    // already entered by the user are preserved)
    for (final id in liveIds) {
      _daysCtrls[id]      ??= TextEditingController();
      _daysFocusNodes[id] ??= FocusNode();
    }

    setState(() {});
  }

  void _onMonthYearChange(int month, int year) {
    final newTotal = DateTime(year, month + 1, 0).day;
    setState(() {
      _month = month;
      _year  = year;
      // Clamp any value that now exceeds the new month's total; leave empty as-is
      for (final ctrl in _daysCtrls.values) {
        final v = int.tryParse(ctrl.text) ?? 0;
        if (v > newTotal) ctrl.text = newTotal.toString();
      }
    });
  }

  /// Only employees with a non-empty name, preserving master-data sort order.
  List<EmployeeModel> get _activeEmployees => _employeeNotifier.employees
      .where((e) => e.name.trim().isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _employeeNotifier,
        builder: (context, _) {
          final employees = _activeEmployees;

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              children: [
                _Toolbar(
                  month:          _month,
                  year:           _year,
                  months:         _months,
                  isMsw:          _isMsw,
                  isFeb:          _isFeb,
                  onMonthChanged: (v) => _onMonthYearChange(v, _year),
                  onYearChanged:  (v) => _onMonthYearChange(_month, v),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_employeeNotifier.isLoading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (employees.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline,
                              size: 48, color: AppColors.slate300),
                          const SizedBox(height: 12),
                          Text('No employees found.',
                              style: AppTextStyles.small),
                          const SizedBox(height: 8),
                          Text(
                            'Add employees in Employee Master Data first.',
                            style: AppTextStyles.small
                                .copyWith(color: AppColors.slate400),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SalaryEntryTable(
                      employees:      employees,
                      month:          _month,
                      year:           _year,
                      totalDays:      _totalDays,
                      isMsw:          _isMsw,
                      isFeb:          _isFeb,
                      daysCtrls:      _daysCtrls,
                      daysFocusNodes: _daysFocusNodes,
                      onDaysChanged:  () => setState(() {}),
                      monthName:      _months[_month - 1],
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

// ── Toolbar ───────────────────────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  final int    month;
  final int    year;
  final List<String> months;
  final bool   isMsw;
  final bool   isFeb;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;

  const _Toolbar({
    required this.month,
    required this.year,
    required this.months,
    required this.isMsw,
    required this.isFeb,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Text('Employee Salary',
        style: AppTextStyles.h3.copyWith(color: Colors.white)),
    const Spacer(),
    SizedBox(
      width: 150, height: 40,
      child: DropdownButtonFormField<int>(
        value: month,
        style: AppTextStyles.input,
        decoration: const InputDecoration(
          labelText: 'Month', isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: List.generate(12, (i) => DropdownMenuItem(
          value: i + 1,
          child: Text(months[i], style: AppTextStyles.input),
        )),
        onChanged: (v) { if (v != null) onMonthChanged(v); },
      ),
    ),
    const SizedBox(width: AppSpacing.md),
    SizedBox(
      width: 100, height: 40,
      child: DropdownButtonFormField<int>(
        value: year,
        style: AppTextStyles.input,
        decoration: const InputDecoration(
          labelText: 'Year', isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: List.generate(6, (i) {
          final y = DateTime.now().year - 1 + i;
          return DropdownMenuItem(
              value: y,
              child: Text(y.toString(), style: AppTextStyles.input));
        }),
        onChanged: (v) { if (v != null) onYearChanged(v); },
      ),
    ),
    const SizedBox(width: AppSpacing.lg),
    if (isMsw)
      _badge('MSW month — ₹6 deduction active',
          AppColors.amber100, AppColors.amber700),
    if (isFeb) ...[
      const SizedBox(width: 8),
      _badge('February — PT ₹300 for eligible',
          AppColors.indigo50, AppColors.indigo600),
    ],
  ]);

  static Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
  );
}