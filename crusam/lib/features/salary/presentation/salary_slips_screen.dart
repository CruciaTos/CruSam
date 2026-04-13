import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import '../widgets/salary_slip_preview.dart';

class SalarySlipsScreen extends StatefulWidget {
  const SalarySlipsScreen({super.key});

  @override
  State<SalarySlipsScreen> createState() => _SalarySlipsScreenState();
}

class _SalarySlipsScreenState extends State<SalarySlipsScreen> {
  final _employeeNotifier = EmployeeNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();

  String?        _selectedCode;     // null = All
  EmployeeModel? _selectedEmployee;
  final _searchCtrl  = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _employeeNotifier.load();
    _loadConfig();
  }

  @override
  void dispose() {
    _employeeNotifier.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  // ── Derived lists ──────────────────────────────────────────────────────────

  List<String> get _codes {
    return _employeeNotifier.employees
        .map((e) => e.code.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<EmployeeModel> get _filteredEmployees {
    var list = _employeeNotifier.employees
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
    if (_selectedCode != null) {
      list = list.where((e) => e.code == _selectedCode).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.pfNo.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  // ── Salary computation ─────────────────────────────────────────────────────

  _SlipCalc _calc(EmployeeModel emp) {
    final n     = SalaryDataNotifier.instance;
    final days  = n.getDays(emp.id ?? 0);
    final total = n.totalDays;

    final eBasic = total == 0 ? 0.0 : emp.basicCharges * days / total;
    final eOther = total == 0 ? 0.0 : emp.otherCharges * days / total;
    final eGross = eBasic + eOther;

    final pf             = (eBasic * 0.12).round();
    final esicApplicable = emp.grossSalary > 21000;
    final esic           = esicApplicable ? (eGross * 0.0075).ceil() : 0;
    final msw            = n.isMsw ? 6 : 0;

    final isFemale = emp.gender.toUpperCase() == 'F';
    int pt;
    if (isFemale) {
      pt = eGross < 25000 ? 0 : (n.isFeb ? 300 : 200);
    } else {
      if (eGross < 7500)       pt = 0;
      else if (eGross < 10000) pt = 175;
      else                     pt = n.isFeb ? 300 : 200;
    }

    return _SlipCalc(
      days:       days,
      totalDays:  total,
      pf:         pf.toDouble(),
      esic:       esic.toDouble(),
      msw:        msw.toDouble(),
      pt:         pt.toDouble(),
    );
  }

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
        'F&B' => 'Food & Beverage',
        'I&L' => 'Infrastructure & Logistics',
        'P&S' => 'Projects & Services',
        'AP'  => 'Administration & Projects',
        _     => code,
      };

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _employeeNotifier,
        SalaryDataNotifier.instance,
      ]),
      builder: (context, _) {
        final dataNotifier = SalaryDataNotifier.instance;
        final filtered     = _filteredEmployees;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            children: [
              // ── Toolbar ──────────────────────────────────────────────────
              _Toolbar(
                codes:        _codes,
                selectedCode: _selectedCode,
                monthName:    dataNotifier.monthName,
                year:         dataNotifier.year,
                onCodeChanged: (code) => setState(() {
                  _selectedCode = code;
                  // Deselect employee if no longer visible after filter change.
                  if (_selectedEmployee != null &&
                      code != null &&
                      _selectedEmployee!.code != code) {
                    _selectedEmployee = null;
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              // ── Main area ────────────────────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: employee list
                    SizedBox(
                      width: 268,
                      child: _EmployeePanel(
                        employees:       filtered,
                        selectedEmployee: _selectedEmployee,
                        searchCtrl:      _searchCtrl,
                        searchQuery:     _searchQuery,
                        onSearchChanged: (v) =>
                            setState(() => _searchQuery = v),
                        onSearchCleared: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        onSelect: (emp) =>
                            setState(() => _selectedEmployee = emp),
                        getDays: (emp) =>
                            dataNotifier.getDays(emp.id ?? 0),
                      ),
                    ),
                    // Divider
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: AppColors.slate200,
                    ),
                    // Right: slip preview
                    Expanded(
                      child: _selectedEmployee != null
                          ? _PreviewPanel(
                              key:        ValueKey(_selectedEmployee!.id),
                              employee:   _selectedEmployee!,
                              config:     _config,
                              calc:       _calc(_selectedEmployee!),
                              month:      dataNotifier.monthName,
                              year:       dataNotifier.year.toString(),
                              department: _codeToDept(_selectedEmployee!.code),
                            )
                          : const _EmptyState(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Data class ─────────────────────────────────────────────────────────────────

class _SlipCalc {
  final int    days;
  final int    totalDays;
  final double pf;
  final double esic;
  final double msw;
  final double pt;
  const _SlipCalc({
    required this.days,
    required this.totalDays,
    required this.pf,
    required this.esic,
    required this.msw,
    required this.pt,
  });
}

// ── Toolbar ────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final List<String>      codes;
  final String?           selectedCode;
  final String            monthName;
  final int               year;
  final void Function(String?) onCodeChanged;

  const _Toolbar({
    required this.codes,
    required this.selectedCode,
    required this.monthName,
    required this.year,
    required this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Salary Slips', style: AppTextStyles.h3),
        const SizedBox(width: AppSpacing.md),
        // Month/year badge sourced from SalaryDataNotifier (live)
        _MonthBadge(monthName: monthName, year: year),
        const Spacer(),
        if (codes.isNotEmpty)
          _CodeFilter(
            codes:    codes,
            selected: selectedCode,
            onChanged: onCodeChanged,
          ),
      ],
    );
  }
}

// ── Month badge ────────────────────────────────────────────────────────────────

class _MonthBadge extends StatelessWidget {
  final String monthName;
  final int    year;
  const _MonthBadge({required this.monthName, required this.year});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.slate800,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_outlined,
                size: 13, color: AppColors.slate400),
            const SizedBox(width: 5),
            Text(
              '$monthName $year',
              style: AppTextStyles.small.copyWith(
                color: AppColors.slate300,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

// ── Code filter chips ──────────────────────────────────────────────────────────

class _CodeFilter extends StatelessWidget {
  final List<String>      codes;
  final String?           selected;
  final void Function(String?) onChanged;

  const _CodeFilter({
    required this.codes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Filter:', style: AppTextStyles.small.copyWith(color: AppColors.slate500)),
        const SizedBox(width: 8),
        Wrap(
          spacing: 6,
          children: [
            _FilterChip(label: 'All', value: null, selected: selected, onTap: onChanged),
            ...codes.map(
              (c) => _FilterChip(label: c, value: c, selected: selected, onTap: onChanged),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String  label;
  final String? value;
  final String? selected;
  final void Function(String?) onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  bool get _active => selected == value;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _active ? AppColors.indigo600 : AppColors.white,
          border: Border.all(
            color: _active ? AppColors.indigo600 : AppColors.slate300,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _active
              ? [
                  BoxShadow(
                    color: AppColors.indigo600.withOpacity(0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _active ? Colors.white : AppColors.slate600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ── Employee panel (left) ──────────────────────────────────────────────────────

class _EmployeePanel extends StatelessWidget {
  final List<EmployeeModel>    employees;
  final EmployeeModel?         selectedEmployee;
  final TextEditingController  searchCtrl;
  final String                 searchQuery;
  final void Function(String)  onSearchChanged;
  final VoidCallback           onSearchCleared;
  final void Function(EmployeeModel) onSelect;
  final int  Function(EmployeeModel) getDays;

  const _EmployeePanel({
    required this.employees,
    required this.selectedEmployee,
    required this.searchCtrl,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSelect,
    required this.getDays,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        SizedBox(
          height: 38,
          child: TextField(
            controller: searchCtrl,
            onChanged:  onSearchChanged,
            style:      AppTextStyles.input,
            decoration: InputDecoration(
              hintText:   'Search employees…',
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense:    true,
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: onSearchCleared,
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Count label
        Text(
          '${employees.length} employee${employees.length == 1 ? '' : 's'}',
          style: AppTextStyles.small,
        ),
        const SizedBox(height: AppSpacing.xs),
        // List
        Expanded(
          child: employees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_outlined,
                          size: 32, color: AppColors.slate300),
                      const SizedBox(height: 8),
                      Text('No employees found', style: AppTextStyles.small),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: employees.length,
                  itemBuilder: (context, i) {
                    final emp = employees[i];
                    return _EmpTile(
                      employee:   emp,
                      isSelected: selectedEmployee?.id == emp.id,
                      days:       getDays(emp),
                      onTap:      () => onSelect(emp),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Employee tile ──────────────────────────────────────────────────────────────

class _EmpTile extends StatelessWidget {
  final EmployeeModel employee;
  final bool          isSelected;
  final int           days;
  final VoidCallback  onTap;

  const _EmpTile({
    required this.employee,
    required this.isSelected,
    required this.days,
    required this.onTap,
  });

  String get _initials {
    final parts = employee.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.indigo600.withOpacity(0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo500.withOpacity(0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Avatar circle
            CircleAvatar(
              radius: 15,
              backgroundColor:
                  isSelected ? AppColors.indigo600 : AppColors.slate200,
              child: Text(
                _initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.slate600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Name + code
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    employee.name,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? AppColors.indigo600
                          : AppColors.slate800,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    employee.code.isEmpty ? '—' : employee.code,
                    style: AppTextStyles.small.copyWith(
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.indigo500
                          : AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
            // Days badge (only when days > 0)
            if (days > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.emerald100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${days}d',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Preview panel (right) ──────────────────────────────────────────────────────

class _PreviewPanel extends StatelessWidget {
  final EmployeeModel      employee;
  final CompanyConfigModel config;
  final _SlipCalc          calc;
  final String             month;
  final String             year;
  final String             department;

  const _PreviewPanel({
    super.key,
    required this.employee,
    required this.config,
    required this.calc,
    required this.month,
    required this.year,
    required this.department,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mini header strip above the A4 preview
        _PreviewHeader(employee: employee, calc: calc),
        const SizedBox(height: AppSpacing.sm),
        // Scrollable A4 preview
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: SalarySlipPreview(
                  config:           config,
                  employeeName:     employee.name,
                  employeeCode:     employee.code,
                  designation:      'Technician',
                  department:       department,
                  pfNo:             employee.pfNo,
                  uanNo:            employee.uanNo,
                  bankName:         employee.bankDetails,
                  accountNo:        employee.accountNumber,
                  ifscCode:         employee.ifscCode,
                  month:            month,
                  year:             year,
                  daysInMonth:      calc.totalDays,
                  daysPresent:      calc.days,
                  basicSalary:      employee.basicCharges,
                  otherAllowances:  employee.otherCharges,
                  pfDeduction:      calc.pf,
                  esicDeduction:    calc.esic,
                  mswDeduction:     calc.msw,
                  ptDeduction:      calc.pt,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Preview mini-header ────────────────────────────────────────────────────────

class _PreviewHeader extends StatelessWidget {
  final EmployeeModel employee;
  final _SlipCalc     calc;
  const _PreviewHeader({required this.employee, required this.calc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Name
        Flexible(
          child: Text(
            employee.name,
            style: AppTextStyles.h4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Code badge
        _pill(
          label: employee.code.isEmpty ? '—' : employee.code,
          bg:    AppColors.slate100,
          fg:    AppColors.slate600,
        ),
        if (calc.totalDays > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          // Days present badge
          _pill(
            label: '${calc.days} / ${calc.totalDays} days',
            bg:    calc.days > 0
                ? AppColors.emerald50
                : AppColors.slate100,
            fg:    calc.days > 0
                ? AppColors.emerald700
                : AppColors.slate500,
          ),
          if (calc.days == 0) ...[
            const SizedBox(width: 6),
            Text(
              '← enter days in Employee Salary first',
              style: AppTextStyles.small
                  .copyWith(color: AppColors.slate400, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ],
    );
  }

  static Widget _pill({
    required String label,
    required Color  bg,
    required Color  fg,
  }) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   11,
            fontWeight: FontWeight.w600,
            color:      fg,
          ),
        ),
      );
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: AppColors.slate300),
          const SizedBox(height: 16),
          Text(
            'Select an employee',
            style: AppTextStyles.h4.copyWith(color: AppColors.slate400),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a name from the list to view\ntheir salary slip.',
            style: AppTextStyles.small,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}