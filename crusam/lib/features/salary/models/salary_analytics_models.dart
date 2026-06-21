// lib/features/salary/models/salary_analytics_models.dart
//
// Read-only reporting models for Salary Analytics. Derived purely from
// Saved Salary (snapshot) data — never from live SalaryDataNotifier /
// SalaryStateController state.

import '../../../shared/utils/financial_year_utils.dart';

/// One Employee + One Month — the atomic reporting unit.
class EmployeeAnalyticsRecord {
  final int employeeId;
  final String employeeName;
  final String code;
  final String pfNo;
  final int month;
  final int year;
  final int attendance;
  final double grossSalary; // earned gross for that month
  final int pf;
  final int esic;
  final int msw;
  final int pt;
  final double totalDeduction;
  final double bonus;
  final double netSalary;

  const EmployeeAnalyticsRecord({
    required this.employeeId,
    required this.employeeName,
    this.code = '',
    this.pfNo = '',
    required this.month,
    required this.year,
    required this.attendance,
    required this.grossSalary,
    required this.pf,
    required this.esic,
    required this.msw,
    required this.pt,
    required this.totalDeduction,
    this.bonus = 0,
    required this.netSalary,
  });

  MonthYear get monthYear => MonthYear(month, year);

  /// Zero-filled placeholder for a month with no Saved Salary record —
  /// lets the aggregation service treat "missing month" as zero rather
  /// than dropping it from totals/averages.
  factory EmployeeAnalyticsRecord.zero({
    required int employeeId,
    required String employeeName,
    required String code,
    required String pfNo,
    required int month,
    required int year,
  }) => EmployeeAnalyticsRecord(
        employeeId: employeeId,
        employeeName: employeeName,
        code: code,
        pfNo: pfNo,
        month: month,
        year: year,
        attendance: 0,
        grossSalary: 0,
        pf: 0,
        esic: 0,
        msw: 0,
        pt: 0,
        totalDeduction: 0,
        bonus: 0,
        netSalary: 0,
      );

  factory EmployeeAnalyticsRecord.fromDbMap(Map<String, dynamic> m) =>
      EmployeeAnalyticsRecord(
        employeeId: (m['employee_id'] as int?) ?? 0,
        employeeName: (m['employee_name'] as String?) ?? '',
        code: (m['code'] as String?) ?? '',
        pfNo: (m['pf_no'] as String?) ?? '',
        month: (m['month'] as int?) ?? 1,
        year: (m['year'] as int?) ?? DateTime.now().year,
        attendance: (m['attendance'] as int?) ?? 0,
        grossSalary: (m['gross_salary'] as num?)?.toDouble() ?? 0.0,
        pf: (m['pf'] as int?) ?? 0,
        esic: (m['esic'] as int?) ?? 0,
        msw: (m['msw'] as int?) ?? 0,
        pt: (m['pt'] as int?) ?? 0,
        totalDeduction: (m['deductions'] as num?)?.toDouble() ?? 0.0,
        bonus: (m['bonus'] as num?)?.toDouble() ?? 0.0,
        netSalary: (m['net_salary'] as num?)?.toDouble() ?? 0.0,
      );
}

/// One Employee + Multiple Selected Months — backs the expandable
/// employee rows.
class EmployeeAnalyticsSummary {
  final int employeeId;
  final String employeeName;
  final String code;
  final String pfNo;
  final List<EmployeeAnalyticsRecord> monthlyRecords; // one per selected month

  const EmployeeAnalyticsSummary({
    required this.employeeId,
    required this.employeeName,
    required this.code,
    required this.pfNo,
    required this.monthlyRecords,
  });

  double get totalGross => monthlyRecords.fold(0.0, (s, r) => s + r.grossSalary);
  double get totalDeductions => monthlyRecords.fold(0.0, (s, r) => s + r.totalDeduction);
  double get totalNet => monthlyRecords.fold(0.0, (s, r) => s + r.netSalary);
  int get totalPf => monthlyRecords.fold(0, (s, r) => s + r.pf);
  int get totalEsic => monthlyRecords.fold(0, (s, r) => s + r.esic);
  int get totalMsw => monthlyRecords.fold(0, (s, r) => s + r.msw);
  int get totalPt => monthlyRecords.fold(0, (s, r) => s + r.pt);
  double get totalBonus => monthlyRecords.fold(0.0, (s, r) => s + r.bonus);

  bool get hasActivity => monthlyRecords.any((r) => r.attendance > 0);
}

/// Entire Filtered Report — backs the whole Salary Analytics screen.
class PayrollAnalyticsSnapshot {
  final List<MonthYear> selectedMonths;
  final List<EmployeeAnalyticsSummary> employeeSummaries;

  const PayrollAnalyticsSnapshot({
    required this.selectedMonths,
    required this.employeeSummaries,
  });

  static const empty = PayrollAnalyticsSnapshot(
    selectedMonths: [],
    employeeSummaries: [],
  );

  bool get isEmpty => employeeSummaries.isEmpty;

  int get employeeCount => employeeSummaries.where((e) => e.hasActivity).length;

  double get totalPayroll => employeeSummaries.fold(0.0, (s, e) => s + e.totalGross);
  double get totalNetSalaryPaid => employeeSummaries.fold(0.0, (s, e) => s + e.totalNet);
  int get totalPf => employeeSummaries.fold(0, (s, e) => s + e.totalPf);
  int get totalEsic => employeeSummaries.fold(0, (s, e) => s + e.totalEsic);
  int get totalMsw => employeeSummaries.fold(0, (s, e) => s + e.totalMsw);
  int get totalPt => employeeSummaries.fold(0, (s, e) => s + e.totalPt);

  double get averageMonthlyPayroll =>
      selectedMonths.isEmpty ? 0 : totalPayroll / selectedMonths.length;
}