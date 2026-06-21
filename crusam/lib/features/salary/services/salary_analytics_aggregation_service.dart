// lib/features/salary/services/salary_analytics_aggregation_service.dart
//
// Stateless, pure aggregation. Knows nothing about SQLite, widgets, or
// navigation — only EmployeeAnalyticsRecord in, PayrollAnalyticsSnapshot
// out. Reusable by future reporting modules.

import '../models/salary_analytics_models.dart';
import '../../../shared/utils/financial_year_utils.dart';

class SalaryAnalyticsAggregationService {
  const SalaryAnalyticsAggregationService();

  /// Missing-month handling: if an employee has a record in at least one
  /// of [selectedMonths] but not all of them, the gaps are filled with
  /// zero-value records so totals/averages stay correct and the UI can
  /// show "—" for that month instead of skipping it.
  PayrollAnalyticsSnapshot aggregate({
    required List<EmployeeAnalyticsRecord> records,
    required List<MonthYear> selectedMonths,
  }) {
    if (selectedMonths.isEmpty) return PayrollAnalyticsSnapshot.empty;

    final byEmployee = <int, List<EmployeeAnalyticsRecord>>{};
    final identity = <int, (String name, String code, String pfNo)>{};

    for (final r in records) {
      byEmployee.putIfAbsent(r.employeeId, () => []).add(r);
      identity[r.employeeId] = (r.employeeName, r.code, r.pfNo);
    }

    final sortedMonths = [...selectedMonths]
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

    final summaries = <EmployeeAnalyticsSummary>[];
    for (final entry in byEmployee.entries) {
      final employeeId = entry.key;
      final recordsByMonth = {for (final r in entry.value) r.monthYear: r};
      final (name, code, pfNo) = identity[employeeId]!;

      final monthly = sortedMonths.map((m) {
        return recordsByMonth[m] ??
            EmployeeAnalyticsRecord.zero(
              employeeId: employeeId,
              employeeName: name,
              code: code,
              pfNo: pfNo,
              month: m.month,
              year: m.year,
            );
      }).toList();

      summaries.add(EmployeeAnalyticsSummary(
        employeeId: employeeId,
        employeeName: name,
        code: code,
        pfNo: pfNo,
        monthlyRecords: monthly,
      ));
    }

    summaries.sort((a, b) =>
        a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase()));

    return PayrollAnalyticsSnapshot(
      selectedMonths: sortedMonths,
      employeeSummaries: summaries,
    );
  }
}