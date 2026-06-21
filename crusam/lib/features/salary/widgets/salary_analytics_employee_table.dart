// lib/features/salary/widgets/salary_analytics_employee_table.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/salary_analytics_models.dart';
import '../notifier/salary_analytics_notifier.dart';

class SalaryAnalyticsEmployeeTable extends StatelessWidget {
  final PayrollAnalyticsSnapshot snapshot;
  final SalaryAnalyticsNotifier notifier;

  const SalaryAnalyticsEmployeeTable({
    super.key,
    required this.snapshot,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final employees = snapshot.employeeSummaries;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Column(
          children: [
            _headerRow(),
            Expanded(
              child: ListView.separated(
                itemCount: employees.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.slate100),
                itemBuilder: (ctx, i) => _EmployeeRowGroup(
                  summary: employees[i],
                  expanded: notifier.isExpanded(employees[i].employeeId),
                  onToggle: () => notifier.toggleExpanded(employees[i].employeeId),
                ),
              ),
            ),
          ],
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
            Expanded(flex: 3, child: Text('Employee', style: AppTextStyles.label)),
            Expanded(flex: 2, child: Text('Gross', textAlign: TextAlign.right, style: AppTextStyles.label)),
            Expanded(flex: 2, child: Text('Deductions', textAlign: TextAlign.right, style: AppTextStyles.label)),
            Expanded(flex: 2, child: Text('Net', textAlign: TextAlign.right, style: AppTextStyles.label)),
          ],
        ),
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
                Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.slate500),
                Expanded(
                  flex: 3,
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
                Expanded(
                  flex: 2,
                  child: Text('₹${summary.totalGross.toStringAsFixed(0)}',
                      textAlign: TextAlign.right, style: AppTextStyles.body),
                ),
                Expanded(
                  flex: 2,
                  child: Text('₹${summary.totalDeductions.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: AppTextStyles.body.copyWith(color: Colors.red.shade600)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('₹${summary.totalNet.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: AppTextStyles.bodySemi.copyWith(color: AppColors.emerald700)),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            color: const Color(0xFFF8FAFC),
            padding: const EdgeInsets.only(left: 44, right: 12, bottom: 8),
            child: Column(
              children: summary.monthlyRecords.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text('${_monthName(r.month)} ${r.year}',
                              style: AppTextStyles.small.copyWith(color: AppColors.slate600)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              r.attendance == 0 ? '—' : '₹${r.grossSalary.toStringAsFixed(0)}',
                              textAlign: TextAlign.right, style: AppTextStyles.small),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              r.attendance == 0 ? '—' : '₹${r.totalDeduction.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: AppTextStyles.small.copyWith(color: Colors.red.shade400)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              r.attendance == 0 ? '—' : '₹${r.netSalary.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: AppTextStyles.small.copyWith(color: AppColors.emerald700)),
                        ),
                      ],
                    ),
                  )).toList(),
            ),
          ),
      ],
    );
  }
}