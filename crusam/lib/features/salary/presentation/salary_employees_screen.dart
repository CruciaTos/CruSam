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

  // ── Read month/year from the notifier so the selection persists
  // ── when navigating between tabs. Only fall back to now() if the
  // ── notifier has never been set (i.e. first ever launch).
  late int _month = SalaryDataNotifier.instance.month;
  final int _year = SalaryDataNotifier.instance.year;

  final Map<int, FocusNode> _daysFocusNodes = {};

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
    _ctrl.addListener(_syncFocusNodes);
    _ctrl.loadEmployees();
    // Do NOT call setMonthYear here — the notifier already holds the
    // correct value. Only sync local _month from it in case it differs.
    _month = SalaryDataNotifier.instance.month;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncFocusNodes);
    for (final f in _daysFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes() {
    if (!mounted) return;
    final liveIds = _ctrl.employees
        .where((e) => e.id != null)
        .map((e) => e.id!)
        .toSet();

    final staleIds = _daysFocusNodes.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in staleIds) {
      _daysFocusNodes.remove(id)?.dispose();
    }

    for (final id in liveIds) {
      _daysFocusNodes[id] ??= FocusNode();
    }

    setState(() {});
  }

  void _onMonthChange(int month) {
    final newTotal = DateTime(_year, month + 1, 0).day;
    setState(() {
      _month = month;
      final liveIds = _ctrl.employees
          .where((e) => e.id != null)
          .map((e) => e.id!)
          .toSet();
      for (final id in liveIds) {
        final c = SalaryDataNotifier.instance.getOrCreateController(id);
        final v = int.tryParse(c.text) ?? 0;
        if (v > newTotal) c.text = newTotal.toString();
      }
    });
    SalaryDataNotifier.instance.setMonthYear(month, _year);
  }

  List<EmployeeModel> get _displayEmployees => _ctrl.filteredEmployees;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) {
      final employees = _displayEmployees;
      final code = _ctrl.selectedCompanyCode;
      final title = code == 'All' ? 'Employee Salary' : 'Employee Salary - $code';

      final daysCtrls = {
        for (final e in employees)
          if (e.id != null)
            e.id!: SalaryDataNotifier.instance.getOrCreateController(e.id!),
      };

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          children: [
            _Toolbar(
              title:          title,
              month:          _month,
              months:         _months,
              isMsw:          _isMsw,
              isFeb:          _isFeb,
              codes:          const ['F&B', 'I&L', 'P&S', 'A&P'],
              selectedCode:   _ctrl.selectedCompanyCode,
              onMonthChanged: _onMonthChange,
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
                  daysCtrls:      daysCtrls,
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

// ─── Smooth Month Dropdown ────────────────────────────────────────────────────
class SmoothDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) display;
  final ValueChanged<T> onChanged;
  final double width;
  final int maxVisibleItems;

  const SmoothDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
    required this.width,
    this.maxVisibleItems = 4,
  });

  @override
  Widget build(BuildContext context) {
    const double itemHeight = 48.0;
    final double maxHeight = maxVisibleItems * itemHeight;

    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 50),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.slate400.withOpacity(0.3)),
      ),
      constraints: BoxConstraints(
        minWidth: width,
        maxHeight: maxHeight,
      ),
      itemBuilder: (context) {
        return items.map((item) {
          return PopupMenuItem<T>(
            value: item,
            height: itemHeight,
            child: Text(
              display(item),
              style: AppTextStyles.input.copyWith(color: Colors.white),
            ),
          );
        }).toList();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slate400),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              display(value),
              style: AppTextStyles.input.copyWith(color: Colors.white),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.slate400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  final String title;
  final int month;
  final List<String> months;
  final bool isMsw;
  final bool isFeb;
  final List<String> codes;
  final String selectedCode;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<String> onCodeChanged;

  const _Toolbar({
    required this.title,
    required this.month,
    required this.months,
    required this.isMsw,
    required this.isFeb,
    required this.codes,
    required this.selectedCode,
    required this.onMonthChanged,
    required this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: title + month dropdown
        Row(
          children: [
            Text(title, style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const Spacer(),
            SmoothDropdown<int>(
              value: month,
              items: List.generate(12, (i) => i + 1),
              display: (m) => months[m - 1],
              onChanged: onMonthChanged,
              width: 150,
              maxVisibleItems: 4,
            ),
          ],
        ),

        // Row 2: MSW / February badges (only if any are active)
        if (isMsw || isFeb) ...[
          const SizedBox(height: 6),   // gap between dropdown and badges
          Row(
            children: [
              const Spacer(),
              if (isMsw)
                _badge('MSW month — ₹6 deduction active', AppColors.amber100, AppColors.amber700),
              if (isMsw && isFeb)
                const SizedBox(width: 8),   // horizontal gap between two badges
              if (isFeb)
                _badge('February — PT ₹300 for eligible', AppColors.indigo50, AppColors.indigo600),
            ],
          ),
        ],

        // Company code chips
        if (codes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('All', selectedCode == 'All', () => onCodeChanged('All')),
                ...codes.map((c) => _chip(c, selectedCode == c, () => onCodeChanged(c))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.indigo600 : const Color(0xFF1E293B),
          border: Border.all(color: active ? AppColors.indigo600 : AppColors.slate400),
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