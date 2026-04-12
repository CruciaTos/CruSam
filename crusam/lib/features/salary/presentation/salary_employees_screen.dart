import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import '../widgets/salary_entry_table.dart';

class SalaryEmployeesScreen extends StatefulWidget {
  const SalaryEmployeesScreen({super.key});
  @override
  State<SalaryEmployeesScreen> createState() => _SalaryEmployeesScreenState();
}

class _SalaryEmployeesScreenState extends State<SalaryEmployeesScreen> {
  List<EmployeeModel> _employees = [];
  bool _loading = true;

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;

  final Map<int, TextEditingController> _daysCtrls = {};
  final Map<int, FocusNode> _daysFocusNodes = {};           // ← NEW

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  bool get _isMsw  => _month == 6 || _month == 12;
  bool get _isFeb  => _month == 2;
  int  get _totalDays => DateTime(_year, _month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _daysCtrls.values) c.dispose();
    for (final f in _daysFocusNodes.values) f.dispose();    // ← NEW
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final maps = await DatabaseHelper.instance.getAllEmployees();
    final emps = maps
        .map(EmployeeModel.fromMap)
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
    for (final e in emps) {
      final id = e.id;
      if (id == null) continue;
      // Start empty — user fills in days present manually
      _daysCtrls[id]    ??= TextEditingController();         // ← CHANGED (was pre-filled)
      _daysFocusNodes[id] ??= FocusNode();                   // ← NEW
    }
    if (mounted) setState(() { _employees = emps; _loading = false; });
  }

  void _onMonthYearChange(int month, int year) {
    final newTotal = DateTime(year, month + 1, 0).day;
    setState(() {
      _month = month;
      _year  = year;
      // Only clamp values that exceed the new month's day-count; leave empty as-is
      for (final e in _employees) {
        final id = e.id;
        if (id == null) continue;
        final ctrl = _daysCtrls[id];
        if (ctrl == null) continue;
        final v = int.tryParse(ctrl.text) ?? 0;              // ← CHANGED (was ?? newTotal)
        if (v > newTotal) ctrl.text = newTotal.toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.pagePadding),
    child: Column(children: [
      _Toolbar(
        month: _month,
        year:  _year,
        months: _months,
        isMsw:  _isMsw,
        isFeb:  _isFeb,
        onMonthChanged: (v) => _onMonthYearChange(v, _year),
        onYearChanged:  (v) => _onMonthYearChange(_month, v),
      ),
      const SizedBox(height: AppSpacing.lg),
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_employees.isEmpty)
        Expanded(child: Center(child: Text('No employees found.', style: AppTextStyles.small)))
      else
        Expanded(
          child: SalaryEntryTable(
            employees:      _employees,
            month:          _month,
            year:           _year,
            totalDays:      _totalDays,
            isMsw:          _isMsw,
            isFeb:          _isFeb,
            daysCtrls:      _daysCtrls,
            daysFocusNodes: _daysFocusNodes,               // ← NEW
            onDaysChanged:  () => setState(() {}),
            monthName:      _months[_month - 1],
          ),
        ),
    ]),
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
    Text('Employee Salary', style: AppTextStyles.h3.copyWith(color: Colors.white)),
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
          return DropdownMenuItem(value: y, child: Text(y.toString(), style: AppTextStyles.input));
        }),
        onChanged: (v) { if (v != null) onYearChanged(v); },
      ),
    ),
    const SizedBox(width: AppSpacing.lg),
    if (isMsw)
      _badge('MSW month — ₹6 deduction active', AppColors.amber100, AppColors.amber700),
    if (isFeb) ...[
      const SizedBox(width: 8),
      _badge('February — PT ₹300 for eligible', AppColors.indigo50, AppColors.indigo600),
    ],
  ]);

  static Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
  );
}