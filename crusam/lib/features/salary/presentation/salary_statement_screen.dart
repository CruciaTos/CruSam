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
import '../../../shared/widgets/full_screen_loader.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../services/salary_statement_excel_export_service.dart';
import '../services/salary_statement_pdf_service.dart';
import '../services/salary_disbursement_service.dart';
import '../services/salary_formula_engine.dart';
import '../models/salary_disbursement_model.dart';
import '../widgets/salary_statement_preview.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – matching the InvoicesScreen theme
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

  static const double radius   = 6.0;
  static const double cRadius  = 10.0;
  static const double padH     = 18.0;
  static const double padV     = 16.0;

  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );
}

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
  bool _generatingDisbursement = false;

  late final ScrollController _vScroll;
  late final ScrollController _hScroll;

  late final Map<int, double> _columnWidths;
  late final List<TextEditingController> _colCtrls;

  static const String _prefsKey = 'salary_statement_column_widths';

  // ── Track route visibility for MSW‑only refresh ──────────────────────────
  bool _isRouteCurrent = false;

  @override
  void initState() {
    super.initState();
    _vScroll = ScrollController();
    _hScroll = ScrollController();

    _columnWidths = _initializeColumnWidths();

    _colCtrls = List.generate(
      _columnWidths.length,
      (i) => TextEditingController(
          text: (_columnWidths[i] ??
                  SalaryStatementPreview.defaultColumnWidths[i] ??
                  60.0)
              .toStringAsFixed(0)),
    );

    _loadColumnWidths();

    if (_stateCtrl.employees.isEmpty) _stateCtrl.loadEmployees();
    _loadConfig();
  }

  Map<int, double> _initializeColumnWidths() {
    try {
      return Map.of(SalaryStatementPreview.defaultColumnWidths);
    } catch (e) {
      return {
        0: 26.0, 1: 124.0, 2: 84.0, 3: 92.0,
        4: 30.0, 5: 38.0, 6: 74.0, 7: 104.0,
        8: 50.0, 9: 50.0, 10: 38.0, 11: 54.0,
        12: 36.0, 13: 30.0, 14: 30.0, 15: 36.0,
        16: 50.0, 17: 56.0,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      final isCurrent = route.isCurrent;
      if (isCurrent && !_isRouteCurrent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            SalaryDataNotifier.instance.notifyListeners();
          }
        });
      }
      _isRouteCurrent = isCurrent;
    }
  }

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
        loaded.forEach((index, width) {
          _columnWidths[index] = width;
        });

        for (int i = 0; i < _colCtrls.length; i++) {
          final width = _columnWidths[i] ??
              SalaryStatementPreview.defaultColumnWidths[i] ??
              60.0;
          _colCtrls[i].text = width.toStringAsFixed(0);
        }
      });
    } catch (e) {
      debugPrint('Failed to load column widths: $e');
    }
  }

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
    showLoader(context, message: 'Generating salary statement PDF…');
    try {
      final daysMap = <int, int>{};
      for (final e in employees) {
        if (e.id != null) daysMap[e.id!] = n.getDays(e.id!);
      }

      await SalaryStatementPdfService.exportSalaryStatement(
        config: _config,
        employees: employees,
        monthName: n.monthName,
        year: n.year,
        isMsw: n.isMsw,
        mswAmount: n.mswAmount,
        isFeb: n.isFeb,
        daysMap: daysMap,
        daysInMonth: n.totalDays,
        columnWidths: Map.of(_columnWidths),
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
      if (mounted) hideLoader(context);
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
    showLoader(context, message: 'Exporting salary statement Excel…');
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
        mswAmount: n.mswAmount,
        isFeb: n.isFeb,
        daysMap: daysMap,
        daysInMonth: n.totalDays,
        columnWidths: Map.of(_columnWidths),
      );

      if (!mounted) return;
      if (path == null) {
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
      if (mounted) hideLoader(context);
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _generateDisbursement() async {
    if (_generatingDisbursement) return;

    final n = SalaryDataNotifier.instance;
    final employees = _stateCtrl.filteredEmployees;
    final filterCode = _stateCtrl.selectedCompanyCode;

    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No employees to disburse')),
      );
      return;
    }

    setState(() => _generatingDisbursement = true);
    showLoader(context, message: 'Generating salary disbursement…');

    try {
      final candidates = await SalaryDisbursementService.buildCandidateItems(
        employees: employees,
        salaryData: n,
        alreadyDisbursedIds: {},
      );

      if (candidates.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No employees qualify — check days entered and bank details.',
            ),
          ),
        );
        return;
      }

      final disbursement = await SalaryDisbursementService.createDisbursement(
        month: n.month,
        year: n.year,
        deptCode: filterCode,
        items: candidates,
      );

      final db = await DatabaseHelper.instance.database;
      final itemMaps = await db.query(
        'salary_disbursement_items',
        where: 'disbursement_id = ?',
        whereArgs: [disbursement.id!],
      );
      final persistedItems = itemMaps
          .map(SalaryDisbursementItemModel.fromDbMap)
          .toList();

      final String monthNameForFile = filterCode == 'All'
          ? n.monthName
          : '${n.monthName}_$filterCode';

      final path = await SalaryDisbursementService.generateExcel(
        disbursement: disbursement,
        items: persistedItems,
        config: _config,
        monthName: monthNameForFile,
      );

      if (path != null) {
        final updated = disbursement.copyWith(
          status: SalaryDisbursementStatus.exported,
          exportedAt: DateTime.now().toIso8601String(),
        );
        final rowMap = updated.toDbMap()..remove('id');
        await db.update(
          'salary_disbursements',
          rowMap,
          where: 'id = ?',
          whereArgs: [disbursement.id!],
        );
      }

      if (!mounted) return;
      final label = filterCode == 'All' ? 'all employees' : filterCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path != null
                ? 'Disbursement ($label) saved: $path'
                : 'Disbursement ($label) created.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Disbursement failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) hideLoader(context);
      if (mounted) setState(() => _generatingDisbursement = false);
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
                mswAmount: n.mswAmount,
                onCodeChanged: (c) => _stateCtrl.setCompanyCode(c ?? 'All'),
                generatingDisbursement: _generatingDisbursement,
                onGenerateDisbursement: _generateDisbursement,
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _stateCtrl.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Themed left pane ─────────────────────────────
                          SizedBox(
                            width: 272,
                            child: Container(
                              padding: const EdgeInsets.all(_Tok.padV),
                              decoration: BoxDecoration(
                                color: _Tok.surface,
                                border: Border.all(color: _Tok.border),
                                borderRadius: BorderRadius.circular(_Tok.cRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _LeftPane(
                                employees: employees,
                                isMsw: n.isMsw,
                                isFeb: n.isFeb,
                                daysMap: daysMap,
                                daysInMonth: n.totalDays,
                                colCtrls: _colCtrls,
                                onColChanged: (i, v) {
                                  setState(() => _columnWidths[i] = v);
                                  _saveColumnWidths();
                                },
                                mswAmount: n.mswAmount,
                                onColReset: () {
                                  setState(() {
                                    for (int i = 0;
                                        i < SalaryStatementPreview.columnLabels.length;
                                        i++) {
                                      _columnWidths[i] =
                                          SalaryStatementPreview.defaultColumnWidths[i] ??
                                              60.0;
                                      _colCtrls[i].text =
                                          _columnWidths[i]!.toStringAsFixed(0);
                                    }
                                  });
                                  _saveColumnWidths();
                                },
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: AppColors.slate200,
                          ),
                          Expanded(
                            child: employees.isEmpty
                                ? _EmptyState(
                                    hasEmployees: _stateCtrl.employees.isNotEmpty)
                                : _PreviewPane(
                                    config: _config,
                                    employees: employees,
                                    n: n,
                                    daysMap: daysMap,
                                    columnWidths: Map.of(_columnWidths),
                                    mswAmount: n.mswAmount,
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
// _Toolbar (now includes department code badge when a specific code is selected)
// ══════════════════════════════════════════════════════════════════════════════

class _Toolbar extends StatelessWidget {
  final String title;
  final String monthName;
  final int year;
  final bool isMsw;
  final double mswAmount;
  final bool isFeb;
  final List<EmployeeModel> employees;
  final bool exportingPdf;
  final bool exportingExcel;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final String selectedCode;
  final void Function(String?) onCodeChanged;
  final bool generatingDisbursement;
  final VoidCallback onGenerateDisbursement;

  const _Toolbar({
    required this.title,
    required this.monthName,
    required this.year,
    required this.isMsw,
    required this.mswAmount,
    required this.isFeb,
    required this.employees,
    required this.exportingPdf,
    required this.exportingExcel,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.selectedCode,
    required this.onCodeChanged,
    required this.generatingDisbursement,
    required this.onGenerateDisbursement,
  });

  @override
  Widget build(BuildContext context) {
    final disbLabel = selectedCode == 'All'
        ? 'Disbursement'
        : 'Disbursement ($selectedCode)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const SizedBox(width: AppSpacing.md),
            _MonthBadge(monthName: monthName, year: year),
            // ── Department code badge ──
            if (selectedCode != 'All') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.indigo600.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.indigo600.withOpacity(0.3)),
                ),
                child: Text(
                  selectedCode,
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.indigo400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (employees.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  label: 'MSW month  ₹${mswAmount.toStringAsFixed(0)} active',
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
                    icon:
                        const Icon(Icons.picture_as_pdf_outlined, size: 16),
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
            const SizedBox(width: 8),
            generatingDisbursement
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton.icon(
                    onPressed:
                        employees.isEmpty ? null : onGenerateDisbursement,
                    icon: const Icon(Icons.account_balance_outlined,
                        size: 16),
                    label: Text(disbLabel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.teal.shade700,
                      side: BorderSide(color: Colors.teal.shade400),
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

  static Widget _codeChip(String label, bool active, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.indigo600 : AppColors.slate800,
              border: Border.all(
                  color: active ? AppColors.indigo600 : AppColors.slate600),
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
// _LeftPane (now styled with _Tok tokens)
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPane extends StatefulWidget {
  final List<EmployeeModel> employees;
  final bool isMsw;
  final bool isFeb;
  final double mswAmount;
  final Map<int, int> daysMap;
  final int daysInMonth;
  final List<TextEditingController> colCtrls;
  final void Function(int, double) onColChanged;
  final VoidCallback onColReset;

  const _LeftPane({
    required this.employees,
    required this.isMsw,
    required this.isFeb,
    required this.mswAmount,
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

  double _earnedOther(EmployeeModel e) {
    final d = _days(e);
    if (d == 0 || widget.daysInMonth == 0) return 0;
    return e.otherCharges * d / widget.daysInMonth;
  }

  int _pf(EmployeeModel e) => SalaryFormulaEngine.pf(_earnedBasic(e)).round();

  int _esic(EmployeeModel e) => SalaryFormulaEngine.esic(
        fullGrossSalary: e.grossSalary,
        earnedGross: _earnedGross(e),
      ).round();

  int _msw() => widget.isMsw ? widget.mswAmount.round() : 0;

  int _pt(EmployeeModel e) => SalaryFormulaEngine.pt(
        earnedGross: _earnedGross(e),
        isFemale: e.gender.toUpperCase() == 'F',
        isFeb: widget.isFeb,
      ).round();

  int _td(EmployeeModel e) => _pf(e) + _esic(e) + _msw() + _pt(e);

  double _net(EmployeeModel e) {
    final eg = _earnedGross(e);
    return eg == 0 ? 0 : eg - _td(e);
  }

  @override
  Widget build(BuildContext context) {
    double sumBasic = 0, sumOther = 0, sumGross = 0, sumNet = 0;
    double sumEarnedBasic = 0, sumEarnedOther = 0, sumEarnedGross = 0;
    int sumPf = 0, sumEsic = 0, sumMsw = 0, sumPt = 0, sumTd = 0;
    int withDays = 0;

    for (final e in widget.employees) {
      sumBasic += e.basicCharges;
      sumOther += e.otherCharges;
      sumGross += e.grossSalary;
      sumEarnedBasic += _earnedBasic(e);
      sumEarnedOther += _earnedOther(e);
      sumEarnedGross += _earnedGross(e);
      sumPf += _pf(e);
      sumEsic += _esic(e);
      sumMsw += _msw();
      sumPt += _pt(e);
      sumTd += _td(e);
      sumNet += _net(e);
      if (_days(e) > 0) withDays++;
    }

    return ListView(
      children: [
        Text('Salary Aggregates',
            style: _Tok.tsCardTitle.copyWith(fontSize: 15)),
        const SizedBox(height: 16),
        _row('Employees', '${widget.employees.length}', _Tok.inkLight),
        _row(
            'With Days Entered',
            '$withDays / ${widget.employees.length}',
            withDays == widget.employees.length
                ? const Color(0xFF065F46)  // emerald
                : const Color(0xFF92400E)), // amber
        const SizedBox(height: 12),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 8),
        Text('Earnings',
            style: _Tok.tsMeta.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        _row('Total Basic', '₹${sumBasic.toStringAsFixed(0)}',
            _Tok.inkLight),
        _row('Total Other', '₹${sumOther.toStringAsFixed(0)}',
            _Tok.inkLight),
        _row('Total Gross', '₹${sumGross.toStringAsFixed(0)}',
            _Tok.inkLight, bold: true),
        const SizedBox(height: 12),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 8),
        Text('Earned Salary (Prorated)',
            style: _Tok.tsMeta.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        _row('Earned Basic', '₹${sumEarnedBasic.toStringAsFixed(0)}',
            _Tok.inkLight),
        _row('Earned Other', '₹${sumEarnedOther.toStringAsFixed(0)}',
            _Tok.inkLight),
        _row('Earned Gross', '₹${sumEarnedGross.toStringAsFixed(0)}',
            const Color(0xFF065F46), bold: true),
        const SizedBox(height: 12),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 8),
        Text('Deductions (Prorated)',
            style: _Tok.tsMeta.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        _row('PF (12% earned basic)', '₹$sumPf', Colors.red.shade400),
        _row('ESIC (0.75% earned)', '₹$sumEsic', Colors.red.shade400),
        if (widget.isMsw)
          _row('MSW', '₹$sumMsw', const Color(0xFF92400E)),
        _row('Prof. Tax', '₹$sumPt', Colors.red.shade400),
        const SizedBox(height: 8),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 4),
        _row('Total Deductions', '₹$sumTd', Colors.red.shade700, bold: true),
        const SizedBox(height: 12),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 8),
        _row('Net Payable', '₹${sumNet.toStringAsFixed(0)}',
            const Color(0xFF065F46), bold: true, fontSize: 14),
        if (withDays < widget.employees.length) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(_Tok.radius),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  size: 13, color: Color(0xFF92400E)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.employees.length - withDays} employee(s) have no days entered — deductions show as 0.',
                  style: _Tok.tsMeta.copyWith(
                    color: const Color(0xFF92400E),
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
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(_Tok.radius),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  size: 13, color: Color(0xFF92400E)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'MSW month — ₹${widget.mswAmount.toStringAsFixed(0)} deduction active',
                    style: _Tok.tsMeta.copyWith(
                        color: const Color(0xFF92400E),
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
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(_Tok.radius),
              border: Border.all(color: _Tok.border),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  size: 13, color: _Tok.inkLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'February — PT ₹300 for eligible employees',
                    style: _Tok.tsMeta.copyWith(
                        color: _Tok.inkLight,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(color: _Tok.divider),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _showColWidths = !_showColWidths),
          child: Row(
            children: [
              Text('Column Widths',
                  style: _Tok.tsLabel.copyWith(
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
                      style: _Tok.tsMeta.copyWith(
                          color: _Tok.inkLight)),
                ),
              const SizedBox(width: 4),
              Icon(
                _showColWidths
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: _Tok.inkMuted,
              ),
            ],
          ),
        ),
        if (_showColWidths) ...[
          const SizedBox(height: 8),
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
                      style: _Tok.tsMeta,
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
                        style: _Tok.tsInput.copyWith(fontSize: 12),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: 'px',
                          suffixStyle: _Tok.tsMeta,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 6),
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: _Tok.border),
                            borderRadius: BorderRadius.circular(_Tok.radius),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide:
                                const BorderSide(color: _Tok.inkLight),
                            borderRadius: BorderRadius.circular(_Tok.radius),
                          ),
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
            Text(label, style: _Tok.tsMeta),
            Text(value,
                style: _Tok.tsInput.copyWith(
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
  final double mswAmount;
  final ScrollController vScroll;
  final ScrollController hScroll;

  const _PreviewPane({
    required this.config,
    required this.employees,
    required this.n,
    required this.daysMap,
    required this.columnWidths,
    required this.mswAmount,
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

  double _previewWidth() {
    double w = 0;
    SalaryStatementPreview.defaultColumnWidths.forEach((k, defaultVal) {
      w += columnWidths[k] ?? defaultVal;
    });
    return w + 28 + 12;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewportConstraints) {
              final viewportW = viewportConstraints.maxWidth;
              final previewW = _previewWidth();
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
                                    mswAmount: n.mswAmount,
                                    applyMsw: n.applyMsw,
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
              style: AppTextStyles.h4.copyWith(color: AppColors.slate400),
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