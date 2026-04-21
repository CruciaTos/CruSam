import 'package:flutter/material.dart';
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

  // ─── Explicit scroll controllers for the preview area ─────────────────────
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;

  static const List<String> _allCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();

    if (_stateCtrl.employees.isEmpty) {
      _stateCtrl.loadEmployees();
    }
    _loadConfig();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
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

    try {
      await PdfExportService.exportWidgets(
        context: context,
        pages: SalaryStatementPreview.buildPdfPages(
          config: _config,
          employees: employees,
          monthName: n.monthName,
          year: n.year,
          isMsw: n.isMsw,
          isFeb: n.isFeb,
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _stateCtrl,
        SalaryDataNotifier.instance,
      ]),
      builder: (context, _) {
        final n = SalaryDataNotifier.instance;
        final employees = _stateCtrl.filteredEmployees;
        final code = _stateCtrl.selectedCompanyCode;
        final title =
            getTitle('Salary Statement', code == 'All' ? null : code);

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Toolbar ────────────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: AppTextStyles.h3),
                      const SizedBox(width: AppSpacing.md),
                      _MonthBadge(monthName: n.monthName, year: n.year),
                      const Spacer(),

                      // Employee count badge
                      if (employees.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.indigo600.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.indigo600.withOpacity(0.3)),
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

                      // Statutory flags
                      if (n.isMsw) ...[
                        _FlagBadge(
                          label: 'MSW month  ₹6 active',
                          bg: AppColors.amber100,
                          fg: AppColors.amber700,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (n.isFeb) ...[
                        _FlagBadge(
                          label: 'Feb — PT ₹300',
                          bg: AppColors.indigo50,
                          fg: AppColors.indigo600,
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Export button
                      if (_exporting)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined,
                              size: 16),
                          label: const Text('Download PDF'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade400),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Company-code filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _codeChip(
                          'All',
                          code == 'All',
                          () => _stateCtrl.setCompanyCode('All'),
                        ),
                        ..._allCodes.map((c) => _codeChip(
                              c,
                              code == c,
                              () => _stateCtrl.setCompanyCode(c),
                            )),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Preview area ───────────────────────────────────────────────
              Expanded(
                child: _buildBody(n, employees),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(SalaryDataNotifier n, List<EmployeeModel> employees) {
    if (_stateCtrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_rows_outlined,
                size: 56, color: AppColors.slate300),
            const SizedBox(height: 16),
            Text(
              _stateCtrl.employees.isEmpty
                  ? 'No employees in master data yet.'
                  : 'No employees match the selected filter.',
              style: AppTextStyles.h4.copyWith(color: AppColors.slate400),
            ),
            const SizedBox(height: 6),
            Text(
              _stateCtrl.employees.isEmpty
                  ? 'Add employees in Employee Master Data first.'
                  : 'Try selecting "All" or a different code.',
              style: AppTextStyles.small,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // ─── Fixed: explicit ScrollControllers for both axes ───────────────────
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1424),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.slate700, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Scrollbar(
          controller: _verticalScrollController, // <-- explicit
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalScrollController, // <-- same controller
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Scrollbar(
                controller: _horizontalScrollController, // <-- explicit
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController, // <-- same controller
                  scrollDirection: Axis.horizontal,
                  child: SalaryStatementPreview(
                    config: _config,
                    employees: employees,
                    monthName: n.monthName,
                    year: n.year,
                    isMsw: n.isMsw,
                    isFeb: n.isFeb,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Chip builder ───────────────────────────────────────────────────────────

  static Widget _codeChip(
    String label,
    bool active,
    VoidCallback onTap,
  ) =>
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
                  color:
                      active ? AppColors.indigo600 : AppColors.slate600),
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

// ── Month badge ────────────────────────────────────────────────────────────────

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

// ── Flag badge (MSW / Feb indicator) ──────────────────────────────────────────

class _FlagBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _FlagBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: fg),
        ),
      );
}