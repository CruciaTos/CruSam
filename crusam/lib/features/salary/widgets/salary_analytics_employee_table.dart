// lib/features/salary/widgets/salary_analytics_employee_table.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/salary_analytics_models.dart';
import '../notifier/salary_analytics_notifier.dart';

class SalaryAnalyticsEmployeeTable extends StatefulWidget {
  final PayrollAnalyticsSnapshot snapshot;
  final SalaryAnalyticsNotifier notifier;

  const SalaryAnalyticsEmployeeTable({
    super.key,
    required this.snapshot,
    required this.notifier,
  });

  // Column flex weights — keep header + rows in sync. Referenced by
  // _EmployeeRowGroup below via SalaryAnalyticsEmployeeTable._flexName etc.
  static const _flexName = 3;
  static const _flexNum = 2;

  @override
  State<SalaryAnalyticsEmployeeTable> createState() =>
      _SalaryAnalyticsEmployeeTableState();
}

class _SalaryAnalyticsEmployeeTableState
    extends State<SalaryAnalyticsEmployeeTable> {
  late final ScrollController _hScroll;

  @override
  void initState() {
    super.initState();
    _hScroll = ScrollController();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employees = widget.snapshot.employeeSummaries;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1380, // wide enough for all 12 numeric columns + name
              child: Column(
                children: [
                  _headerRow(),
                  // Expanded (not a fixed height) so this fills whatever
                  // vertical space the parent screen's Expanded provides —
                  // matches the original widget's sizing behavior.
                  Expanded(
                    child: ListView.separated(
                      itemCount: employees.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.slate100),
                      itemBuilder: (ctx, i) => _EmployeeRowGroup(
                        summary: employees[i],
                        expanded: widget.notifier.isExpanded(employees[i].employeeId),
                        onToggle: () =>
                            widget.notifier.toggleExpanded(employees[i].employeeId),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.slate50,
          border: Border(bottom: BorderSide(color: AppColors.slate200)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 24),
            Expanded(
                flex: SalaryAnalyticsEmployeeTable._flexName,
                child: Text('Employee', style: AppTextStyles.label)),
            _hdr('Master\nBasic'),
            _hdr('Master\nOther'),
            _hdr('Master\nGross'),
            _hdr('Earned\nBasic'),
            _hdr('Earned\nOther'),
            _hdr('Earned\nGross'),
            _hdr('PF'),
            _hdr('ESIC'),
            _hdr('MSW'),
            _hdr('Prof.\nTax'),
            _hdr('Total\nDeductions'),
            _hdr('Net\nSalary'),
          ],
        ),
      );

  static Widget _hdr(String label) => Expanded(
        flex: SalaryAnalyticsEmployeeTable._flexNum,
        child: Text(label, textAlign: TextAlign.right, style: AppTextStyles.label),
      );
}

class _EmployeeRowGroup extends StatelessWidget {
  final EmployeeAnalyticsSummary summary;
  final bool expanded;
  final VoidCallback onToggle;

  const _EmployeeRowGroup({
    required this.summary,
    required this.expanded,
    required this.onToggle,
  });

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static String _monthName(int m) => _months[(m - 1).clamp(0, 11)];

  static const _flexName = SalaryAnalyticsEmployeeTable._flexName;
  static const _flexNum = SalaryAnalyticsEmployeeTable._flexNum;

  static String _money(double v) => '₹${v.toStringAsFixed(0)}';
  static String _moneyInt(int v) => '₹$v';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18, color: AppColors.slate500),
                Expanded(
                  flex: _flexName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(summary.employeeName, style: AppTextStyles.bodySemi),
                      Text(summary.code.isEmpty ? '—' : summary.code,
                          style: AppTextStyles.small.copyWith(color: AppColors.slate500)),
                    ],
                  ),
                ),
                _cell(_money(summary.totalMasterBasic)),
                _cell(_money(summary.totalMasterOther)),
                _cell(_money(summary.totalMasterGross)),
                _cell(_money(summary.totalEarnedBasic)),
                _cell(_money(summary.totalEarnedOther)),
                _cell(_money(summary.totalGross), bold: true, color: AppColors.indigo600),
                _cell(_moneyInt(summary.totalPf), color: Colors.red.shade600),
                _cell(_moneyInt(summary.totalEsic), color: Colors.red.shade600),
                _cell(_moneyInt(summary.totalMsw), color: Colors.red.shade600),
                _cell(_moneyInt(summary.totalPt), color: Colors.red.shade600),
                _cell(_money(summary.totalDeductions),
                    bold: true, color: Colors.red.shade700),
                _cell(_money(summary.totalNet),
                    bold: true, color: AppColors.emerald700),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.only(left: 44, right: 12, bottom: 8),
            child: Column(
              children: summary.monthlyRecords.map((r) {
                final noData = r.attendance == 0;
                String dash(String v) => noData ? '—' : v;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: _flexName,
                        child: Text('${_monthName(r.month)} ${r.year}',
                            style: AppTextStyles.small.copyWith(color: AppColors.slate600)),
                      ),
                      _smallCell(dash(_money(r.masterBasic))),
                      _smallCell(dash(_money(r.masterOther))),
                      _smallCell(dash(_money(r.masterGross))),
                      _smallCell(dash(_money(r.earnedBasic))),
                      _smallCell(dash(_money(r.earnedOther))),
                      _smallCell(dash(_money(r.grossSalary)), color: AppColors.indigo600),
                      _smallCell(dash(_moneyInt(r.pf)), color: Colors.red.shade400),
                      _smallCell(dash(_moneyInt(r.esic)), color: Colors.red.shade400),
                      _smallCell(dash(_moneyInt(r.msw)), color: Colors.red.shade400),
                      _smallCell(dash(_moneyInt(r.pt)), color: Colors.red.shade400),
                      _smallCell(dash(_money(r.totalDeduction)), color: Colors.red.shade400),
                      _smallCell(dash(_money(r.netSalary)), color: AppColors.emerald700),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  static Widget _cell(String text, {bool bold = false, Color? color}) => Expanded(
        flex: _flexNum,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: (bold ? AppTextStyles.bodySemi : AppTextStyles.body)
              .copyWith(color: color),
        ),
      );

  static Widget _smallCell(String text, {Color? color}) => Expanded(
        flex: _flexNum,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: AppTextStyles.small.copyWith(color: color),
        ),
      );
}