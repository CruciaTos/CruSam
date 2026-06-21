// lib/shared/utils/financial_year_utils.dart
//
// Pure date-bucketing helpers for Financial Year (April -> March) reporting.
// Reusable by future reporting modules (Income Tax, Form 16, PF Reports,
// ESIC Reports, Compliance Reports).

class MonthYear {
  final int month; // 1-12
  final int year;
  const MonthYear(this.month, this.year);

  @override
  bool operator ==(Object other) =>
      other is MonthYear && other.month == month && other.year == year;

  @override
  int get hashCode => month * 10000 + year;

  /// Sort/compare key: YYYYMM as int.
  int get sortKey => year * 100 + month;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get monthName => _monthNames[(month - 1).clamp(0, 11)];
  String get shortLabel => '${monthName.substring(0, 3)} $year';
  String get label => '$monthName $year';

  @override
  String toString() => label;
}

class FinancialYearUtils {
  FinancialYearUtils._();

  /// FY runs April -> March. Returns the FY start year for [date]
  /// (e.g. Feb 2026 -> FY 2025-26, startYear = 2025).
  static int fyStartYearFor(DateTime date) =>
      date.month >= 4 ? date.year : date.year - 1;

  static String fyLabel(int startYear) =>
      '$startYear-${(startYear + 1).toString().substring(2)}';

  /// All 12 (month, year) pairs for the FY starting in [startYear]
  /// (April [startYear] -> March [startYear + 1]).
  static List<MonthYear> monthsForFinancialYear(int startYear) {
    final months = <MonthYear>[];
    for (int m = 4; m <= 12; m++) {
      months.add(MonthYear(m, startYear));
    }
    for (int m = 1; m <= 3; m++) {
      months.add(MonthYear(m, startYear + 1));
    }
    return months;
  }

  static List<MonthYear> thisFinancialYear([DateTime? now]) {
    final n = now ?? DateTime.now();
    return monthsForFinancialYear(fyStartYearFor(n));
  }

  static List<MonthYear> lastFinancialYear([DateTime? now]) {
    final n = now ?? DateTime.now();
    return monthsForFinancialYear(fyStartYearFor(n) - 1);
  }

  static List<MonthYear> thisCalendarYear([DateTime? now]) {
    final n = now ?? DateTime.now();
    return List.generate(12, (i) => MonthYear(i + 1, n.year));
  }

  static String thisFinancialYearLabel([DateTime? now]) =>
      fyLabel(fyStartYearFor(now ?? DateTime.now()));

  static String lastFinancialYearLabel([DateTime? now]) =>
      fyLabel(fyStartYearFor(now ?? DateTime.now()) - 1);
}