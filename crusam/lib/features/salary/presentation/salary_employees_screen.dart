import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../widgets/salary_entry_table.dart';

class SalaryEmployeesScreen extends StatefulWidget {
  const SalaryEmployeesScreen({super.key});
  @override
  State<SalaryEmployeesScreen> createState() => _SalaryEmployeesScreenState();
}

class _SalaryEmployeesScreenState extends State<SalaryEmployeesScreen> {
  final _ctrl = SalaryStateController.instance;

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;

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
    _ctrl.addListener(_syncControllers);
    _ctrl.loadEmployees();
    SalaryDataNotifier.instance.setMonthYear(_month, _year);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncControllers);
    for (final c in _daysCtrls.values)      c.dispose();
    for (final f in _daysFocusNodes.values) f.dispose();
    super.dispose();
  }

  void _syncControllers() {
    if (!mounted) return;

    final liveIds = _ctrl.employees
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toSet();

    final staleIds = _daysCtrls.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in staleIds) {
      _daysCtrls.remove(id)?.dispose();
      _daysFocusNodes.remove(id)?.dispose();
    }

    for (final id in liveIds) {
      if (!_daysCtrls.containsKey(id)) {
        final c = TextEditingController();
        c.addListener(() {
          final d = int.tryParse(c.text) ?? 0;
          SalaryDataNotifier.instance.setDays(id, d);
          SalaryStateController.instance.notifyDaysChanged();
        });
        _daysCtrls[id] = c;
      }
      _daysFocusNodes[id] ??= FocusNode();
    }

    setState(() {});
  }

  void _onMonthYearChange(int month, int year) {
    final newTotal = DateTime(year, month + 1, 0).day;
    setState(() {
      _month = month;
      _year  = year;
      for (final c in _daysCtrls.values) {
        final v = int.tryParse(c.text) ?? 0;
        if (v > newTotal) c.text = newTotal.toString();
      }
    });
    SalaryDataNotifier.instance.setMonthYear(month, year);
  }

  List<EmployeeModel> get _displayEmployees => _ctrl.filteredEmployees;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) {
      final employees = _displayEmployees;
      final code = _ctrl.selectedCompanyCode;
      final title = code == 'All' ? 'Employee Salary' : 'Employee Salary - $code';

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          children: [
            _Toolbar(
              title:          title,
              month:          _month,
              year:           _year,
              months:         _months,
              isMsw:          _isMsw,
              isFeb:          _isFeb,
              codes:          _ctrl.companyCodes,
              selectedCode:   _ctrl.selectedCompanyCode,
              onMonthChanged: (v) => _onMonthYearChange(v, _year),
              onYearChanged:  (v) => _onMonthYearChange(_month, v),
              onCodeChanged:  (c) => _ctrl.setCompanyCode(c),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_ctrl.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (employees.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 48, color: AppColors.slate300),
                      const SizedBox(height: 12),
                      Text('No employees found.', style: AppTextStyles.small),
                      const SizedBox(height: 8),
                      Text('Add employees in Employee Master Data first.',
                          style: AppTextStyles.small.copyWith(color: AppColors.slate400)),
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
  final String title;
  final int    month;
  final int    year;
  final List<String> months;
  final bool   isMsw;
  final bool   isFeb;
  final List<String> codes;
  final String selectedCode;
  final ValueChanged<int>    onMonthChanged;
  final ValueChanged<int>    onYearChanged;
  final ValueChanged<String> onCodeChanged;

  const _Toolbar({
    required this.title,
    required this.month,
    required this.year,
    required this.months,
    required this.isMsw,
    required this.isFeb,
    required this.codes,
    required this.selectedCode,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(title, style: AppTextStyles.h3.copyWith(color: Colors.white)),
    const SizedBox(width: AppSpacing.md),
    // Code filter chips
    if (codes.isNotEmpty) ...[
      _chip('All', selectedCode == 'All', () => onCodeChanged('All')),
      ...codes.map((c) => _chip(c, selectedCode == c, () => onCodeChanged(c))),
      const SizedBox(width: AppSpacing.md),
    ],
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
          value: i + 1, child: Text(months[i], style: AppTextStyles.input),
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
          return DropdownMenuItem(value: y, child: Text(y.toString(), style: AppTextStyles.input));
        }),
        onChanged: (v) { if (v != null) onYearChanged(v); },
      ),
    ),
    const SizedBox(width: AppSpacing.lg),
    if (isMsw) _badge('MSW month — ₹6 deduction active', AppColors.amber100, AppColors.amber700),
    if (isFeb) ...[
      const SizedBox(width: 8),
      _badge('February — PT ₹300 for eligible', AppColors.indigo50, AppColors.indigo600),
    ],
  ]);

  static Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.indigo600 : AppColors.slate800,
          border: Border.all(color: active ? AppColors.indigo600 : AppColors.slate600),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.slate400,
        )),
      ),
    ),
  );

  static Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
  );
}