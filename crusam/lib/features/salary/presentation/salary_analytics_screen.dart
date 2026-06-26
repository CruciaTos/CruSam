// lib/features/salary/presentation/salary_analytics_screen.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../notifier/salary_analytics_notifier.dart';
import '../widgets/salary_analytics_month_filter.dart';
import '../widgets/salary_analytics_summary_cards.dart';
import '../widgets/salary_analytics_employee_table.dart';

class SalaryAnalyticsScreen extends StatefulWidget {
  const SalaryAnalyticsScreen({super.key});

  @override
  State<SalaryAnalyticsScreen> createState() => _SalaryAnalyticsScreenState();
}

class _SalaryAnalyticsScreenState extends State<SalaryAnalyticsScreen> {
  final _notifier = SalaryAnalyticsNotifier.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifier.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Salary Analytics',
                    style: AppTextStyles.h3.copyWith(color: Colors.white), // heading now white
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: AppColors.slate400),
                    tooltip: 'Refresh',
                    onPressed: _notifier.isLoading ? null : () => _notifier.refresh(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SalaryAnalyticsMonthFilter(notifier: _notifier),
              const SizedBox(height: AppSpacing.lg),

              if (_notifier.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_notifier.error!, style: TextStyle(color: Colors.red.shade800)),
                ),

              if (_notifier.isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_notifier.availableMonths.isEmpty)
                const Expanded(child: _EmptyState())
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SalaryAnalyticsSummaryCards(snapshot: _notifier.snapshot),
                      const SizedBox(height: AppSpacing.lg),
                      Expanded(
                        child: _notifier.snapshot.isEmpty
                            ? const _EmptyState(message: 'No Saved Salaries in the selected period.')
                            : SalaryAnalyticsEmployeeTable(
                                snapshot: _notifier.snapshot,
                                notifier: _notifier,
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

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({this.message = 'No Saved Salaries Available'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 48, color: AppColors.slate300),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.body.copyWith(color: AppColors.slate500)),
          const SizedBox(height: 6),
          Text(
            'Save a salary period from Employee Salary → Saved Salary\nbefore analytics can show data.',
            style: AppTextStyles.small.copyWith(color: AppColors.slate400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}