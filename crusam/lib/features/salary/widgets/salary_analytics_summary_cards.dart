// lib/features/salary/widgets/salary_analytics_summary_cards.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/salary_analytics_models.dart';

class SalaryAnalyticsSummaryCards extends StatelessWidget {
  final PayrollAnalyticsSnapshot snapshot;

  const SalaryAnalyticsSummaryCards({super.key, required this.snapshot});

  static String _money(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_SummaryCardData>[
      _SummaryCardData(Icons.account_balance_wallet_outlined, 'Total Payroll',
          _money(snapshot.totalPayroll), AppColors.indigo400, const Color(0xFF1E1B4B)),
      _SummaryCardData(Icons.bar_chart_outlined, 'Master Gross',
          _money(snapshot.totalMasterGross), AppColors.indigo400, const Color(0xFF1E1B4B)),
      _SummaryCardData(Icons.account_balance_outlined, 'Earned Basic',
          _money(snapshot.totalEarnedBasic), AppColors.indigo400, const Color(0xFF1E1B4B)),
      _SummaryCardData(Icons.payments_outlined, 'Net Salary Paid',
          _money(snapshot.totalNetSalaryPaid), AppColors.emerald600, const Color(0xFF064E3B)),
      _SummaryCardData(Icons.savings_outlined, 'Total PF',
          '₹${snapshot.totalPf}', const Color(0xFFF59E0B), const Color(0xFF78350F)),
      _SummaryCardData(Icons.medical_services_outlined, 'Total ESIC',
          '₹${snapshot.totalEsic}', const Color(0xFFEC4899), const Color(0xFF500724)),
      _SummaryCardData(Icons.receipt_long_outlined, 'Total Prof. Tax',
          '₹${snapshot.totalPt}', const Color(0xFF3B82F6), const Color(0xFF1E3A5F)),
      _SummaryCardData(Icons.trending_up_outlined, 'Avg Monthly Payroll',
          _money(snapshot.averageMonthlyPayroll), AppColors.indigo400, const Color(0xFF1E1B4B)),
      _SummaryCardData(Icons.people_outline, 'Employees',
          '${snapshot.employeeCount}', AppColors.emerald600, const Color(0xFF064E3B)),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final width = ((constraints.maxWidth - 10 * (cards.length - 1)) / cards.length)
          .clamp(150.0, 240.0);
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: cards.map((c) => SizedBox(width: width, child: _SummaryCard(data: c))).toList(),
      );
    });
  }
}

class _SummaryCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final Color background;

  const _SummaryCardData(this.icon, this.label, this.value, this.accent, this.background);
}

class _SummaryCard extends StatelessWidget {
  final _SummaryCardData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.slate700, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: data.background, borderRadius: BorderRadius.circular(8)),
            child: Icon(data.icon, size: 16, color: data.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.3),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  data.label,
                  style: const TextStyle(fontSize: 10, color: AppColors.slate400),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}