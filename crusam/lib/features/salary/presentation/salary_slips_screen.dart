import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../shared/utils/title_utils.dart';
import '../../../shared/widgets/full_screen_loader.dart'; // Added
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
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late PageController _pageController;
  int _currentPage = 0;

  static const List<String> _allCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  @override
  void initState() {
    super.initState();
    if (_stateCtrl.employees.isEmpty) _stateCtrl.loadEmployees();
    _loadConfig();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  List<EmployeeModel> get _filteredEmployees {
    var list = _stateCtrl.filteredEmployees;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(q) ||
              e.pfNo.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<List<EmployeeModel>> get _employeePairs {
    final list = _filteredEmployees;
    final pairs = <List<EmployeeModel>>[];
    for (int i = 0; i < list.length; i += 2) {
      final pair = [list[i]];
      if (i + 1 < list.length) pair.add(list[i + 1]);
      pairs.add(pair);
    }
    return pairs;
  }

  Set<int> get _currentPageIds {
    final pairs = _employeePairs;
    if (pairs.isEmpty || _currentPage >= pairs.length) return {};
    return pairs[_currentPage]
        .map((e) => e.id ?? -1)
        .where((id) => id != -1)
        .toSet();
  }

  void _jumpToEmployee(EmployeeModel emp) {
    final pairs = _employeePairs;
    for (int i = 0; i < pairs.length; i++) {
      if (pairs[i].any((e) => e.id == emp.id)) {
        _pageController.animateToPage(i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
        break;
      }
    }
  }

  Future<void> _exportAllSlipsPdf() async {
    if (_exporting) return;
    final employees = _filteredEmployees;
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No employees to export')));
      return;
    }
    setState(() => _exporting = true);
    showLoader(context, message: 'Generating salary slips…'); // Added
    try {
      final n = SalaryDataNotifier.instance;
      await SalaryPdfExportService.exportSalarySlips(
        config: _config,
        employees: employees,
        monthName: n.monthName,
        year: n.year,
        daysInMonth: n.totalDays,
        isMsw: n.isMsw,
        isFeb: n.isFeb,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red.shade700));
    } finally {
      hideLoader(context); // Added
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_stateCtrl, SalaryDataNotifier.instance]),
      builder: (context, _) {
        final n = SalaryDataNotifier.instance;
        final pairs = _employeePairs;
        final code = _stateCtrl.selectedCompanyCode;
        final title = getTitle('Salary Slips', code == 'All' ? null : code);
        final highlightedIds = _currentPageIds;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: AppTextStyles.h3),
                      const SizedBox(width: AppSpacing.md),
                      _MonthBadge(monthName: n.monthName, year: n.year),
                      const Spacer(),
                      if (_exporting)
                        const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        OutlinedButton.icon(
                          onPressed: _exportAllSlipsPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined,
                              size: 16),
                          label: Text(
                              'Download All${pairs.isNotEmpty ? ' (${pairs.length} pages)' : ''}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade400),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CodeFilter(
                    codes: _allCodes,
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 268,
                      color: Colors.grey[200],
                      child: _EmployeePanel(
                        employees: _filteredEmployees,
                        highlightedIds: highlightedIds,
                        searchCtrl: _searchCtrl,
                        searchQuery: _searchQuery,
                        onSearchChanged: (v) =>
                            setState(() => _searchQuery = v),
                        onSearchCleared: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        onSelect: (emp) {
                          setState(() => _selectedEmployee = emp);
                          _jumpToEmployee(emp);
                        },
                        getDays: (emp) => n.getDays(emp.id ?? 0),
                      ),
                    ),
                    Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        color: AppColors.slate200),
                    Expanded(
                      child: pairs.isEmpty
                          ? const _EmptyState()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Page ${_currentPage + 1} of ${pairs.length}',
                                        style: AppTextStyles.small.copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_back_ios,
                                            size: 16),
                                        onPressed: _currentPage > 0
                                            ? () =>
                                                _pageController.previousPage(
                                                    duration: const Duration(
                                                        milliseconds: 300),
                                                    curve: Curves.easeInOut)
                                            : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 16),
                                        onPressed: _currentPage <
                                                pairs.length - 1
                                            ? () => _pageController.nextPage(
                                                duration: const Duration(
                                                    milliseconds: 300),
                                                curve: Curves.easeInOut)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: PageView.builder(
                                    controller: _pageController,
                                    itemCount: pairs.length,
                                    onPageChanged: (index) =>
                                        setState(() => _currentPage = index),
                                    itemBuilder: (context, index) =>
                                        _ScrollablePage(
                                      pair: pairs[index],
                                      config: _config,
                                      n: n,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

// ── Scrollable wrapper ────────────────────────────────────────────────────────
class _ScrollablePage extends StatefulWidget {
  final List<EmployeeModel> pair;
  final CompanyConfigModel config;
  final SalaryDataNotifier n;
  const _ScrollablePage(
      {required this.pair, required this.config, required this.n});
  @override
  State<_ScrollablePage> createState() => _ScrollablePageState();
}

class _ScrollablePageState extends State<_ScrollablePage> {
  final _scrollCtrl = ScrollController();
  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SalarySlipPairPage(
              employees: widget.pair,
              config: widget.config,
              getDays: (id) => n.getDays(id),
              month: n.monthName,
              year: n.year.toString(),
              daysInMonth: n.totalDays,
              isMsw: n.isMsw,
              isFeb: n.isFeb,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Employee panel

class _EmployeePanel extends StatelessWidget {
  final List<EmployeeModel> employees;
  final Set<int> highlightedIds;
  final TextEditingController searchCtrl;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final VoidCallback onSearchCleared;
  final void Function(EmployeeModel) onSelect;
  final int Function(EmployeeModel) getDays;

  const _EmployeePanel({
    required this.employees,
    required this.highlightedIds,
    required this.searchCtrl,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onSelect,
    required this.getDays,
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
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: AppTextStyles.input,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: onSearchCleared)
                      : null,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
                '${employees.length} employee${employees.length == 1 ? '' : 's'}',
                style: AppTextStyles.small),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off_outlined,
                        size: 32, color: AppColors.slate300),
                    const SizedBox(height: 8),
                    Text('No employees found', style: AppTextStyles.small),
                  ]))
                : _buildList(),
          ),
        ],
      );

  Widget _buildList() {
    final items = <Widget>[];
    int i = 0;
    while (i < employees.length) {
      final emp = employees[i];
      final thisHighlighted = highlightedIds.contains(emp.id);
      final next = (i + 1 < employees.length) ? employees[i + 1] : null;
      final nextHighlighted =
          next != null && highlightedIds.contains(next.id);

      if (thisHighlighted && nextHighlighted) {
        // Two consecutive highlighted employees → one unified box
        items.add(_GroupedEmpTile(
          first: emp,
          second: next,
          firstDays: getDays(emp),
          secondDays: getDays(next),
          onTapFirst: () => onSelect(emp),
          onTapSecond: () => onSelect(next),
        ));
        i += 2;
      } else {
        items.add(_EmpTile(
          employee: emp,
          isSelected: thisHighlighted,
          days: getDays(emp),
          onTap: () => onSelect(emp),
        ));
        i += 1;
      }
    }
    return ListView(padding: EdgeInsets.zero, children: items);
  }
}

// ── Shared constants ──────────────────────────────────────────────────────────
const _kHighlightBg = Color(0x17516CF5);       // indigo600 @ ~9 %
const _kHighlightBorder = Color(0x5A7C9FF0);   // indigo500 @ ~35 %
const _kDividerColor = Color(0x337C9FF0);      // indigo500 @ ~20 %
const _kRadius = Radius.circular(8);
const _kBorderRadius = BorderRadius.all(_kRadius);

// ── Grouped tile: two rows, one box, ink ripples clipped properly ─────────────
class _GroupedEmpTile extends StatelessWidget {
  final EmployeeModel first;
  final EmployeeModel second;
  final int firstDays;
  final int secondDays;
  final VoidCallback onTapFirst;
  final VoidCallback onTapSecond;

  const _GroupedEmpTile({
    required this.first,
    required this.second,
    required this.firstDays,
    required this.secondDays,
    required this.onTapFirst,
    required this.onTapSecond,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: const BoxDecoration(
        color: _kHighlightBg,
        borderRadius: _kBorderRadius,
        border: Border.fromBorderSide(
            BorderSide(color: _kHighlightBorder, width: 1)),
      ),
      // ClipRRect keeps InkWell splash inside the rounded corners
      child: ClipRRect(
        borderRadius: _kBorderRadius,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onTapFirst,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: _EmpRow(employee: first, days: firstDays),
                ),
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: _kDividerColor,
                indent: 8,
                endIndent: 8,
              ),
              InkWell(
                onTap: onTapSecond,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: _EmpRow(employee: second, days: secondDays),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Single tile ───────────────────────────────────────────────────────────────
class _EmpTile extends StatelessWidget {
  final EmployeeModel employee;
  final bool isSelected;
  final int days;
  final VoidCallback onTap;

  const _EmpTile({
    required this.employee,
    required this.isSelected,
    required this.days,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          decoration: BoxDecoration(
            color: isSelected ? _kHighlightBg : Colors.transparent,
            borderRadius: _kBorderRadius,
            border: Border.all(
              color: isSelected ? _kHighlightBorder : Colors.transparent,
            ),
          ),
          child: ClipRRect(
            borderRadius: _kBorderRadius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: _EmpRow(
                      employee: employee,
                      days: days,
                      isSelected: isSelected),
                ),
              ),
            ),
          ),
        ),
      );
}

// ── Row content shared by both tile types ─────────────────────────────────────
class _EmpRow extends StatelessWidget {
  final EmployeeModel employee;
  final int days;
  final bool isSelected;

  const _EmpRow({
    required this.employee,
    required this.days,
    this.isSelected = true, // grouped tiles are always highlighted
  });

  String get _initials {
    final parts = employee.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  employee.name,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.indigo600
                        : AppColors.slate800,
                  ),
                  overflow: TextOverflow.ellipsis,
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
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Remaining helpers (unchanged)

class _MonthBadge extends StatelessWidget {
  final String monthName;
  final int year;
  const _MonthBadge({required this.monthName, required this.year});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: AppColors.slate800,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.slate700, width: 0.5)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_outlined,
                size: 13, color: AppColors.slate400),
            const SizedBox(width: 5),
            Text('$monthName $year',
                style: AppTextStyles.small.copyWith(
                    color: AppColors.slate300, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

class _CodeFilter extends StatelessWidget {
  final List<String> codes;
  final String selected;
  final void Function(String?) onChanged;
  const _CodeFilter(
      {required this.codes, required this.selected, required this.onChanged});

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
                color: active ? AppColors.indigo600 : AppColors.slate600),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: AppColors.slate300),
            const SizedBox(height: 16),
            Text('Select an employee',
                style: AppTextStyles.h4.copyWith(color: AppColors.slate400)),
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