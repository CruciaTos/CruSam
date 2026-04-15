import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../services/salary_pdf_export_service.dart';
import '../widgets/salary_slip_preview.dart';

class SalarySlipsScreen extends StatefulWidget {
  const SalarySlipsScreen({super.key});
  @override
  State<SalarySlipsScreen> createState() => _SalarySlipsScreenState();
}

class _SalarySlipsScreenState extends State<SalarySlipsScreen> {
  final _stateCtrl = SalaryStateController.instance;
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting = false;

  EmployeeModel? _selectedEmployee;
  final _searchCtrl  = TextEditingController();
  String _searchQuery = '';

  // ── Always show all four company codes regardless of what's in the DB ────────
  static const List<String> _allCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  @override
  void initState() {
    super.initState();
    if (_stateCtrl.employees.isEmpty) _stateCtrl.loadEmployees();
    _loadConfig();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) setState(() => _config = CompanyConfigModel.fromMap(map));
  }

  List<EmployeeModel> get _filteredEmployees {
    var list = _stateCtrl.filteredEmployees;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) =>
          e.name.toLowerCase().contains(q) ||
          e.pfNo.toLowerCase().contains(q)).toList();
    }
    // Sort alphabetically by name (case-insensitive)
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  _SlipCalc _calc(EmployeeModel emp) {
    final n     = SalaryDataNotifier.instance;
    final days  = n.getDays(emp.id ?? 0);
    final total = n.totalDays;
    final eBasic = total == 0 ? 0.0 : emp.basicCharges * days / total;
    final eOther = total == 0 ? 0.0 : emp.otherCharges * days / total;
    final eGross = eBasic + eOther;
    final pf     = (eBasic * 0.12).round();
    final esicApplicable = emp.grossSalary >= 21000;
    final esic   = esicApplicable ? (eGross * 0.0075).ceil() : 0;
    final msw    = n.isMsw ? 6 : 0;
    final isFemale = emp.gender.toUpperCase() == 'F';
    int pt;
    if (isFemale) {
      pt = eGross < 25000 ? 0 : (n.isFeb ? 300 : 200);
    } else {
      if (eGross < 7500)       pt = 0;
      else if (eGross < 10000) pt = 175;
      else                     pt = n.isFeb ? 300 : 200;
    }
    return _SlipCalc(days: days, totalDays: total,
        pf: pf.toDouble(), esic: esic.toDouble(),
        msw: msw.toDouble(), pt: pt.toDouble());
  }

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
    'F&B'       => 'Food & Beverage',
    'I&L'       => 'Infrastructure & Logistics',
    'P&S'       => 'Projects & Services',
    'A&P'       => 'Administration & Projects',
    _           => code,
  };

  Future<void> _exportAllSlipsPdf() async {
    if (_exporting) return;
    final employees = _filteredEmployees;
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No employees to export')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final n = SalaryDataNotifier.instance;
      await SalaryPdfExportService.exportSalarySlips(
        config:      _config,
        employees:   employees,
        monthName:   n.monthName,
        year:        n.year,
        daysInMonth: n.totalDays,
        isMsw:       n.isMsw,
        isFeb:       n.isFeb,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_stateCtrl, SalaryDataNotifier.instance]),
      builder: (context, _) {
        final n        = SalaryDataNotifier.instance;
        final filtered = _filteredEmployees;
        final code     = _stateCtrl.selectedCompanyCode;
        final title    = code == 'All' ? 'Salary Slips' : 'Salary Slips - $code';

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            children: [
              // Toolbar (Column version)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First row: Title, Month badge, and Download button
                  Row(
                    children: [
                      Text(title, style: AppTextStyles.h3),
                      const SizedBox(width: AppSpacing.md),
                      _MonthBadge(monthName: n.monthName, year: n.year),
                      const Spacer(),
                      // Download all slips button
                      if (_exporting)
                        const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        OutlinedButton.icon(
                          onPressed: _exportAllSlipsPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                          label: Text('Download All${filtered.isNotEmpty ? ' (${filtered.length})' : ''}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade400),
                          ),
                        ),
                    ],
                  ),
                  // Second row: Company code filter chips
                  const SizedBox(height: AppSpacing.sm),
                  _CodeFilter(
                    codes:    _allCodes,
                    selected: code,
                    onChanged: (c) {
                      _stateCtrl.setCompanyCode(c ?? 'All');
                      if (_selectedEmployee != null &&
                          (c ?? 'All') != 'All' &&
                          _selectedEmployee!.code != c) {
                        setState(() => _selectedEmployee = null);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Left panel — grey background
                  Container(
                    width: 268,
                    color: Colors.grey[200],
                    child: _EmployeePanel(
                      employees:        filtered,
                      selectedEmployee: _selectedEmployee,
                      searchCtrl:       _searchCtrl,
                      searchQuery:      _searchQuery,
                      onSearchChanged:  (v) => setState(() => _searchQuery = v),
                      onSearchCleared:  () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                      onSelect:         (emp) => setState(() => _selectedEmployee = emp),
                      getDays:          (emp) => n.getDays(emp.id ?? 0),
                    ),
                  ),
                  Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: AppColors.slate200),
                  Expanded(
                    child: _selectedEmployee != null
                        ? _PreviewPanel(
                            key:        ValueKey(_selectedEmployee!.id),
                            employee:   _selectedEmployee!,
                            config:     _config,
                            calc:       _calc(_selectedEmployee!),
                            month:      n.monthName,
                            year:       n.year.toString(),
                            department: _codeToDept(_selectedEmployee!.code),
                          )
                        : const _EmptyState(),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SlipCalc {
  final int    days, totalDays;
  final double pf, esic, msw, pt;
  const _SlipCalc({required this.days, required this.totalDays,
      required this.pf, required this.esic, required this.msw, required this.pt});
}

class _MonthBadge extends StatelessWidget {
  final String monthName; final int year;
  const _MonthBadge({required this.monthName, required this.year});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: AppColors.slate800, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.slate700, width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.calendar_month_outlined, size: 13, color: AppColors.slate400),
      const SizedBox(width: 5),
      Text('$monthName $year',
          style: AppTextStyles.small.copyWith(color: AppColors.slate300, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ── Code filter — always shows All + F&B + I&L + P&S + A&P ──────────────────
class _CodeFilter extends StatelessWidget {
  final List<String> codes;
  final String       selected;
  final void Function(String?) onChanged;
  const _CodeFilter({required this.codes, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _chip('All', null, selected, onChanged),
        ...codes.map((c) => _chip(c, c, selected, onChanged)),
      ],
    ),
  );

  static Widget _chip(String label, String? value, String selected,
      void Function(String?) onTap) {
    final active = selected == (value ?? 'All');
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.indigo600 : AppColors.slate800,
            border: Border.all(
              color: active ? AppColors.indigo600 : AppColors.slate600,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.slate400,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeePanel extends StatelessWidget {
  final List<EmployeeModel>         employees;
  final EmployeeModel?              selectedEmployee;
  final TextEditingController       searchCtrl;
  final String                      searchQuery;
  final void Function(String)       onSearchChanged;
  final VoidCallback                onSearchCleared;
  final void Function(EmployeeModel) onSelect;
  final int  Function(EmployeeModel) getDays;

  const _EmployeePanel({
    required this.employees, required this.selectedEmployee,
    required this.searchCtrl, required this.searchQuery,
    required this.onSearchChanged, required this.onSearchCleared,
    required this.onSelect, required this.getDays,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: 38,
          child: TextField(
            controller: searchCtrl, onChanged: onSearchChanged, style: AppTextStyles.input,
            decoration: InputDecoration(
              hintText: 'Search employees…',
              prefixIcon: const Icon(Icons.search, size: 16),
              isDense: true,
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 14), onPressed: onSearchCleared)
                  : null,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('${employees.length} employee${employees.length == 1 ? '' : 's'}',
            style: AppTextStyles.small),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: employees.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off_outlined, size: 32, color: AppColors.slate300),
                const SizedBox(height: 8),
                Text('No employees found', style: AppTextStyles.small),
              ]))
            : ListView.builder(
                itemCount: employees.length,
                itemBuilder: (_, i) {
                  final emp = employees[i];
                  return _EmpTile(
                    employee: emp, isSelected: selectedEmployee?.id == emp.id,
                    days: getDays(emp), onTap: () => onSelect(emp),
                  );
                },
              ),
      ),
    ],
  );
}

class _EmpTile extends StatelessWidget {
  final EmployeeModel employee;
  final bool          isSelected;
  final int           days;
  final VoidCallback  onTap;

  const _EmpTile({required this.employee, required this.isSelected,
      required this.days, required this.onTap});

  String get _initials {
    final parts = employee.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.indigo600.withOpacity(0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isSelected ? AppColors.indigo500.withOpacity(0.35) : Colors.transparent),
      ),
      child: Row(children: [
        CircleAvatar(radius: 15,
          backgroundColor: isSelected ? AppColors.indigo600 : AppColors.slate200,
          child: Text(_initials, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.slate600))),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(employee.name,
                style: AppTextStyles.body.copyWith(fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.indigo600 : AppColors.slate800),
                overflow: TextOverflow.ellipsis),
            Text(employee.code.isEmpty ? '—' : employee.code,
                style: AppTextStyles.small.copyWith(fontSize: 11,
                    color: isSelected ? AppColors.indigo500 : AppColors.slate400)),
          ],
        )),
        if (days > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppColors.emerald100, borderRadius: BorderRadius.circular(8)),
            child: Text('${days}d',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.emerald700)),
          ),
      ]),
    ),
  );
}

class _PreviewPanel extends StatelessWidget {
  final EmployeeModel      employee;
  final CompanyConfigModel config;
  final _SlipCalc          calc;
  final String             month, year, department;

  const _PreviewPanel({super.key, required this.employee, required this.config,
      required this.calc, required this.month, required this.year, required this.department});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Flexible(child: Text(employee.name, style: AppTextStyles.h4, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: AppSpacing.sm),
        _pill(employee.code.isEmpty ? '—' : employee.code, AppColors.slate100, AppColors.slate600),
        if (calc.totalDays > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          _pill('${calc.days} / ${calc.totalDays} days',
              calc.days > 0 ? AppColors.emerald50 : AppColors.slate100,
              calc.days > 0 ? AppColors.emerald700 : AppColors.slate500),
        ],
      ]),
      const SizedBox(height: AppSpacing.sm),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: SalarySlipPreview(
                config: config, employeeName: employee.name,
                employeeCode: employee.code, designation: 'Technician', department: department,
                pfNo: employee.pfNo, uanNo: employee.uanNo,
                bankName: employee.bankDetails, accountNo: employee.accountNumber,
                ifscCode: employee.ifscCode, month: month, year: year,
                daysInMonth: calc.totalDays, daysPresent: calc.days,
                basicSalary: employee.basicCharges, otherAllowances: employee.otherCharges,
                pfDeduction: calc.pf, esicDeduction: calc.esic,
                mswDeduction: calc.msw, ptDeduction: calc.pt,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  static Widget _pill(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext  context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.slate300),
      const SizedBox(height: 16),
      Text('Select an employee', style: AppTextStyles.h4.copyWith(color: AppColors.slate400)),
      const SizedBox(height: 6),
      Text('Choose a name from the list to view\ntheir salary slip.',
          style: AppTextStyles.small, textAlign: TextAlign.center),
    ]),
  );
}