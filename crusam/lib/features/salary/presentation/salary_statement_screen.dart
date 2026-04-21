import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../shared/utils/title_utils.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../../vouchers/services/pdf_export_service.dart';
import '../services/salary_statement_excel_export_service.dart';
import '../widgets/salary_statement_preview.dart';

class SalaryStatementScreen extends StatefulWidget {
  const SalaryStatementScreen({super.key});

  @override
  State<SalaryStatementScreen> createState() => _SalaryStatementScreenState();
}

class _SalaryStatementScreenState extends State<SalaryStatementScreen> {
  final _stateCtrl = SalaryStateController.instance;
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting = false;
  bool _exportingExcel = false;

  // Scroll controllers — one vertical, one horizontal
  late final ScrollController _vScroll;
  late final ScrollController _hScroll;

  // Column width overrides (index → width in px)
  // Now covers indices 0–20 (added Total Days @ 12, Days Present @ 13)
  late final Map<int, double> _columnWidths;

  // Text controllers for the column-width fields
  late final List<TextEditingController> _colCtrls;

  static const String _prefsKey = 'salary_statement_column_widths';

  @override
  void initState() {
    super.initState();
    _vScroll = ScrollController();
    _hScroll = ScrollController();

    // 1. Start with default widths
    _columnWidths = _initializeColumnWidths();

    // 2. Create text controllers using the current widths
    _colCtrls = List.generate(
      _columnWidths.length,
      (i) => TextEditingController(
          text: (_columnWidths[i] ??
                  SalaryStatementPreview.defaultColumnWidths[i] ??
                  60.0)
              .toStringAsFixed(0)),
    );

    // 3. Load persisted widths and update both the map and controllers
    _loadColumnWidths();

    if (_stateCtrl.employees.isEmpty) _stateCtrl.loadEmployees();
    _loadConfig();
  }

  /// Attempts to copy default widths; falls back to a built-in map if static
  /// is uninitialized. Now covers 0–20 (21 columns).
  Map<int, double> _initializeColumnWidths() {
    try {
      return Map.of(SalaryStatementPreview.defaultColumnWidths);
    } catch (e) {
      // Fallback default column widths
      return {
        0: 26.0,
        1: 124.0,
        2: 84.0,
        3: 92.0,
        4: 30.0,
        5: 38.0,
        6: 74.0,
        7: 104.0,
        8: 50.0,
        9: 50.0,
        10: 38.0,
        11: 54.0,
        12: 34.0, // Total Days
        13: 34.0, // Days Present
        14: 36.0,
        15: 30.0,
        16: 48.0,
        17: 30.0,
        18: 36.0,
        19: 50.0,
        20: 56.0,
      };
    }
  }

  @override
  void dispose() {
    _vScroll.dispose();
    _hScroll.dispose();
    for (final c in _colCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ----------------------------------------------------------------------
  // PERSISTENCE METHODS
  // ----------------------------------------------------------------------

  /// Loads saved column widths from SharedPreferences and applies them.
  Future<void> _loadColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_prefsKey);
      if (jsonString == null) return;

      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      final Map<int, double> loaded = {};
      decoded.forEach((key, value) {
        final index = int.tryParse(key);
        if (index != null && value is num) {
          loaded[index] = value.toDouble();
        }
      });

      if (loaded.isEmpty) return;

      setState(() {
        // Merge loaded widths into the current map
        loaded.forEach((index, width) {
          _columnWidths[index] = width;
        });

        // Update the text controllers to reflect the loaded values
        for (int i = 0; i < _colCtrls.length; i++) {
          final width = _columnWidths[i] ??
              SalaryStatementPreview.defaultColumnWidths[i] ??
              60.0;
          _colCtrls[i].text = width.toStringAsFixed(0);
        }
      });
    } catch (e) {
      debugPrint('Failed to load column widths: $e');
      // Silently fall back to defaults
    }
  }

  /// Persists the current column widths to SharedPreferences.
  Future<void> _saveColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, double> toSave = {};
      _columnWidths.forEach((index, width) {
        toSave[index.toString()] = width;
      });
      await prefs.setString(_prefsKey, jsonEncode(toSave));
    } catch (e) {
      debugPrint('Failed to save column widths: $e');
    }
  }

  // ----------------------------------------------------------------------
  // CONFIG & EXPORT
  // ----------------------------------------------------------------------

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    final n = SalaryDataNotifier.instance;
    final employees = _stateCtrl.filteredEmployees;

    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No employees to export')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final daysMap = <int, int>{};
      for (final e in employees) {
        if (e.id != null) daysMap[e.id!] = n.getDays(e.id!);
      }

      await PdfExportService.exportWidgets(
        context: context,
        pages: SalaryStatementPreview.buildPdfPages(
          config: _config,
          employees: employees,
          monthName: n.monthName,
          year: n.year,
          isMsw: n.isMsw,
          isFeb: n.isFeb,
          daysMap: daysMap,
          daysInMonth: n.totalDays,
          columnWidths: Map.of(_columnWidths),
        ),
        fileNameSlug: 'salary_statement_${n.monthName.toLowerCase()}_${n.year}',
        filePrefix: 'salary_statement',
        shareSubject: 'Salary Statement',
        assetPathsToPrecache: [],
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_exportingExcel) return;

    final n = SalaryDataNotifier.instance;
    final employees = _stateCtrl.filteredEmployees;

    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No employees to export')),
      );
      return;
    }

    setState(() => _exportingExcel = true);
    try {
      final daysMap = <int, int>{};
      for (final e in employees) {
        if (e.id != null) daysMap[e.id!] = n.getDays(e.id!);
      }

      final path = await ExcelExportService.exportSalaryStatement(
        config: _config,
        employees: employees,
        monthName: n.monthName,
        year: n.year,
        isMsw: n.isMsw,
        isFeb: n.isFeb,
        daysMap: daysMap,
        daysInMonth: n.totalDays,
        columnWidths: Map.of(_columnWidths),
      );

      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel saved to $path'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        throw Exception('Failed to save Excel file');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel export failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_stateCtrl, SalaryDataNotifier.instance]),
      builder: (context, _) {
        final n = SalaryDataNotifier.instance;
        final employees = _stateCtrl.filteredEmployees;
        final code = _stateCtrl.selectedCompanyCode;
        final title = getTitle('Salary Statement', code == 'All' ? null : code);

        final daysMap = <int, int>{};
        for (final e in employees) {
          if (e.id != null) daysMap[e.id!] = n.getDays(e.id!);
        }

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Toolbar ─────────────────────────────────────────────────
              _Toolbar(
                title: title,
                monthName: n.monthName,
                year: n.year,
                isMsw: n.isMsw,
                isFeb: n.isFeb,
                employees: employees,
                exportingPdf: _exporting,
                exportingExcel: _exportingExcel,
                onExportPdf: _exportPdf,
                onExportExcel: _exportExcel,
                selectedCode: code,
                onCodeChanged: (c) => _stateCtrl.setCompanyCode(c ?? 'All'),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Body ────────────────────────────────────────────────────
              Expanded(
                child: _stateCtrl.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Left pane ──────────────────────────────────
                          SizedBox(
                            width: 272,
                            child: Container(
                              color: Colors.grey[200],
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: _LeftPane(
                                employees: employees,
                                isMsw: n.isMsw,
                                isFeb: n.isFeb,
                                daysMap: daysMap,
                                daysInMonth: n.totalDays,
                                colCtrls: _colCtrls,
                                onColChanged: (i, v) {
                                  setState(() => _columnWidths[i] = v);
                                  _saveColumnWidths(); // persist after change
                                },
                                onColReset: () {
                                  setState(() {
                                    for (int i = 0;
                                        i <
                                            SalaryStatementPreview
                                                .columnLabels.length;
                                        i++) {
                                      _columnWidths[i] =
                                          SalaryStatementPreview
                                                  .defaultColumnWidths[i] ??
                                              60.0;
                                      _colCtrls[i].text =
                                          _columnWidths[i]!.toStringAsFixed(0);
                                    }
                                  });
                                  _saveColumnWidths(); // persist after reset
                                },
                              ),
                            ),
                          ),

                          // ── Divider ────────────────────────────────────
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: AppColors.slate200,
                          ),

                          // ── Preview pane ───────────────────────────────
                          Expanded(
                            child: employees.isEmpty
                                ? _EmptyState(
                                    hasEmployees:
                                        _stateCtrl.employees.isNotEmpty)
                                : _PreviewPane(
                                    config: _config,
                                    employees: employees,
                                    n: n,
                                    daysMap: daysMap,
                                    columnWidths: Map.of(_columnWidths),
                                    vScroll: _vScroll,
                                    hScroll: _hScroll,
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

// ══════════════════════════════════════════════════════════════════════════════
// _Toolbar
// ══════════════════════════════════════════════════════════════════════════════

class _Toolbar extends StatelessWidget {
  final String title;
  final String monthName;
  final int year;
  final bool isMsw;
  final bool isFeb;
  final List<EmployeeModel> employees;
  final bool exportingPdf;
  final bool exportingExcel;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final String selectedCode;
  final void Function(String?) onCodeChanged;

  const _Toolbar({
    required this.title,
    required this.monthName,
    required this.year,
    required this.isMsw,
    required this.isFeb,
    required this.employees,
    required this.exportingPdf,
    required this.exportingExcel,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.selectedCode,
    required this.onCodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: AppTextStyles.h3),
            const SizedBox(width: AppSpacing.md),
            _MonthBadge(monthName: monthName, year: year),
            const Spacer(),
            if (employees.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.indigo600.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.indigo600.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${employees.length} employee${employees.length == 1 ? '' : 's'}',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.indigo400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            if (isMsw) ...[
              _FlagBadge(
                  label: 'MSW month  ₹6 active',
                  bg: AppColors.amber100,
                  fg: AppColors.amber700),
              const SizedBox(width: 8),
            ],
            if (isFeb) ...[
              _FlagBadge(
                  label: 'Feb — PT ₹300',
                  bg: AppColors.indigo50,
                  fg: AppColors.indigo600),
              const SizedBox(width: 8),
            ],
            exportingPdf
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton.icon(
                    onPressed: onExportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Download PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400),
                    ),
                  ),
            const SizedBox(width: 8),
            exportingExcel
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton.icon(
                    onPressed: onExportExcel,
                    icon: const Icon(Icons.table_chart_outlined, size: 16),
                    label: const Text('Export Excel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade400),
                    ),
                  ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _codeChip(
                  'All', selectedCode == 'All', () => onCodeChanged(null)),
              ...['F&B', 'I&L', 'P&S', 'A&P'].map((c) =>
                  _codeChip(c, selectedCode == c, () => onCodeChanged(c))),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _codeChip(
          String label, bool active, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.indigo600
                  : AppColors.slate800,
              border: Border.all(
                  color: active
                      ? AppColors.indigo600
                      : AppColors.slate600),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.slate400,
                )),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// _LeftPane  — aggregates  +  column-width adjustments
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPane extends StatefulWidget {
  final List<EmployeeModel> employees;
  final bool isMsw;
  final bool isFeb;
  final Map<int, int> daysMap;
  final int daysInMonth;
  final List<TextEditingController> colCtrls;
  final void Function(int, double) onColChanged;
  final VoidCallback onColReset;

  const _LeftPane({
    required this.employees,
    required this.isMsw,
    required this.isFeb,
    required this.daysMap,
    required this.daysInMonth,
    required this.colCtrls,
    required this.onColChanged,
    required this.onColReset,
  });

  @override
  State<_LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends State<_LeftPane> {
  bool _showColWidths = false;

  // ── Statutory helpers (prorated) ──────────────────────────────────────────
  int _days(EmployeeModel e) => widget.daysMap[e.id ?? -1] ?? 0;

  double _earnedGross(EmployeeModel e) {
    final d = _days(e);
    if (d == 0 || widget.daysInMonth == 0) return 0;
    return e.grossSalary * d / widget.daysInMonth;
  }

  double _earnedBasic(EmployeeModel e) {
    final d = _days(e);
    if (d == 0 || widget.daysInMonth == 0) return 0;
    return e.basicCharges * d / widget.daysInMonth;
  }

  int _pf(EmployeeModel e) {
    final eb = _earnedBasic(e);
    return eb == 0 ? 0 : (eb * 0.12).round();
  }

  int _esic(EmployeeModel e) {
    if (e.grossSalary >= 21000) return 0;
    final eg = _earnedGross(e);
    return eg == 0 ? 0 : (eg * 0.0075).ceil();
  }

  int _msw() => widget.isMsw ? 6 : 0;

  int _pt(EmployeeModel e) {
    final eg = _earnedGross(e);
    if (eg == 0) return 0;
    final f = e.gender.toUpperCase() == 'F';
    if (f) return eg < 25000 ? 0 : (widget.isFeb ? 300 : 200);
    if (eg < 7500) return 0;
    if (eg < 10000) return 175;
    return widget.isFeb ? 300 : 200;
  }

  int _td(EmployeeModel e) => _pf(e) + _esic(e) + _msw() + _pt(e);

  double _net(EmployeeModel e) {
    final eg = _earnedGross(e);
    return eg == 0 ? 0 : eg - _td(e);
  }

  @override
  Widget build(BuildContext context) {
    // Aggregate
    double sumBasic = 0, sumOther = 0, sumGross = 0, sumNet = 0;
    int sumPf = 0, sumEsic = 0, sumMsw = 0, sumPt = 0, sumTd = 0;
    int withDays = 0;
    int sumDaysPresent = 0;

    for (final e in widget.employees) {
      sumBasic += e.basicCharges;
      sumOther += e.otherCharges;
      sumGross += e.grossSalary;
      sumPf += _pf(e);
      sumEsic += _esic(e);
      sumMsw += _msw();
      sumPt += _pt(e);
      sumTd += _td(e);
      sumNet += _net(e);
      if (_days(e) > 0) withDays++;
      sumDaysPresent += _days(e);
    }

    return ListView(
      children: [
        // ── Salary Aggregates ──────────────────────────────────────────────
        Text('Salary Aggregates', style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.lg),

        _row('Employees', '${widget.employees.length}', AppColors.indigo600),
        _row('With Days Entered', '$withDays / ${widget.employees.length}',
            withDays == widget.employees.length
                ? AppColors.emerald700
                : AppColors.amber700),
        _row('Total Days (month)', '${widget.daysInMonth}', AppColors.slate600),
        _row('Total Days Present', '$sumDaysPresent', AppColors.emerald700),
        const Divider(height: AppSpacing.lg),

        Text('Earnings',
            style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
        const SizedBox(height: AppSpacing.sm),
        _row('Total Basic', '₹${sumBasic.toStringAsFixed(0)}', AppColors.indigo600),
        _row('Total Other', '₹${sumOther.toStringAsFixed(0)}', AppColors.indigo600),
        _row('Total Gross', '₹${sumGross.toStringAsFixed(0)}', AppColors.indigo600, bold: true),
        const Divider(height: AppSpacing.lg),

        Text('Deductions (Prorated)',
            style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
        const SizedBox(height: AppSpacing.sm),
        _row('PF (12% earned basic)', '₹$sumPf', Colors.red.shade400),
        _row('ESIC (0.75% earned)', '₹$sumEsic', Colors.red.shade400),
        if (widget.isMsw)
          _row('MSW', '₹$sumMsw', AppColors.amber700),
        _row('Prof. Tax', '₹$sumPt', Colors.red.shade400),
        const Divider(height: AppSpacing.md),
        _row('Total Deductions', '₹$sumTd', Colors.red.shade700, bold: true),
        const Divider(height: AppSpacing.lg),

        _row('Net Payable', '₹${sumNet.toStringAsFixed(0)}',
            AppColors.emerald700, bold: true, fontSize: 14),

        if (withDays < widget.employees.length) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.amber100,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.amber700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.employees.length - withDays} employee(s) have no days entered — deductions show as 0.',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.amber700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ]),
          ),
        ],

        if (widget.isMsw) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.amber100,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.amber700),
              const SizedBox(width: 6),
              Expanded(
                child: Text('MSW month — ₹6 deduction active',
                    style: AppTextStyles.small.copyWith(
                        color: AppColors.amber700,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        ],
        if (widget.isFeb) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.indigo50,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.indigo600),
              const SizedBox(width: 6),
              Expanded(
                child: Text('February — PT ₹300 for eligible employees',
                    style: AppTextStyles.small.copyWith(
                        color: AppColors.indigo600,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),

        // ── Column Width Adjustments ───────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _showColWidths = !_showColWidths),
          child: Row(
            children: [
              Text('Column Widths',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.slate600,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              if (_showColWidths)
                TextButton(
                  onPressed: widget.onColReset,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Reset',
                      style: AppTextStyles.small.copyWith(
                          color: AppColors.indigo600)),
                ),
              const SizedBox(width: 4),
              Icon(
                _showColWidths
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.slate500,
              ),
            ],
          ),
        ),

        if (_showColWidths) ...[
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < widget.colCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      i < SalaryStatementPreview.columnLabels.length
                          ? SalaryStatementPreview.columnLabels[i]
                          : 'Col $i',
                      style: AppTextStyles.small.copyWith(
                        color: (i == 12 || i == 13)
                            ? AppColors.emerald700
                            : null,
                        fontWeight: (i == 12 || i == 13)
                            ? FontWeight.w600
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: TextField(
                        controller: widget.colCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: AppTextStyles.input.copyWith(fontSize: 12),
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: 'px',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          if (val != null && val >= 10) {
                            widget.onColChanged(i, val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static Widget _row(
    String label,
    String value,
    Color color, {
    bool bold = false,
    double fontSize = 12,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.small),
            Text(value,
                style: AppTextStyles.small.copyWith(
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  fontSize: bold ? fontSize : 12,
                )),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// _PreviewPane
// ══════════════════════════════════════════════════════════════════════════════

class _PreviewPane extends StatelessWidget {
  final CompanyConfigModel config;
  final List<EmployeeModel> employees;
  final SalaryDataNotifier n;
  final Map<int, int> daysMap;
  final Map<int, double> columnWidths;
  final ScrollController vScroll;
  final ScrollController hScroll;

  const _PreviewPane({
    required this.config,
    required this.employees,
    required this.n,
    required this.daysMap,
    required this.columnWidths,
    required this.vScroll,
    required this.hScroll,
  });

  static const _scrollbarTheme = ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(6),
    radius: Radius.circular(4),
    thumbColor: WidgetStatePropertyAll(AppColors.indigo500),
    trackColor: WidgetStatePropertyAll(Color(0x26536DFE)),
    trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
  );

  /// Computes the total rendered width of the preview from active column widths.
  double _previewWidth() {
    double w = 0;
    SalaryStatementPreview.defaultColumnWidths.forEach((k, defaultVal) {
      w += columnWidths[k] ?? defaultVal;
    });
    return w + 28 + 12; // page margins (14*2) + table border slack
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Scroll hint ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.slate800,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Row(children: [
            const Icon(Icons.open_with_outlined,
                size: 13, color: AppColors.slate400),
            const SizedBox(width: 6),
            Text(
              'Scroll to navigate  ·  Grey zeros = no days entered yet',
              style: AppTextStyles.small.copyWith(color: AppColors.slate400),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Scrollable content area ──────────────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewportConstraints) {
              final viewportW = viewportConstraints.maxWidth;
              final previewW  = _previewWidth();
              final scrollW = previewW > viewportW ? previewW : viewportW;

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1424),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.slate700, width: 0.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: ScrollbarTheme(
                    data: _scrollbarTheme,
                    child: Scrollbar(
                      controller: vScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: vScroll,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: ScrollbarTheme(
                          data: _scrollbarTheme,
                          child: Scrollbar(
                            controller: hScroll,
                            thumbVisibility: true,
                            trackVisibility: true,
                            child: SingleChildScrollView(
                              controller: hScroll,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: scrollW,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: SalaryStatementPreview(
                                    config: config,
                                    employees: employees,
                                    monthName: n.monthName,
                                    year: n.year,
                                    isMsw: n.isMsw,
                                    isFeb: n.isFeb,
                                    daysMap: daysMap,
                                    daysInMonth: n.totalDays,
                                    columnWidths: columnWidths,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Empty State
// ══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final bool hasEmployees;
  const _EmptyState({required this.hasEmployees});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_rows_outlined,
                size: 56, color: AppColors.slate300),
            const SizedBox(height: 16),
            Text(
              hasEmployees
                  ? 'No employees match the selected filter.'
                  : 'No employees in master data yet.',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.slate400),
            ),
            const SizedBox(height: 6),
            Text(
              hasEmployees
                  ? 'Try selecting "All" or a different code.'
                  : 'Add employees in Employee Master Data first.',
              style: AppTextStyles.small,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared badge widgets
// ══════════════════════════════════════════════════════════════════════════════

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
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_outlined,
              size: 13, color: AppColors.slate400),
          const SizedBox(width: 5),
          Text('$monthName $year',
              style: AppTextStyles.small.copyWith(
                color: AppColors.slate300,
                fontWeight: FontWeight.w500,
              )),
        ]),
      );
}

class _FlagBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _FlagBadge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );
}