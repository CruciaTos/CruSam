// lib/data/db/salary_analytics_repository.dart
//
// Read-only reporting repository for Salary Analytics.
// Reads exclusively from the Saved Salary fact table (`salary_month_employees`,
// owned by SalarySnapshotRepository). Never touches SalaryDataNotifier,
// SalaryStateController, or any live editable salary state.
//
// No write APIs on purpose — analytics is a reporting layer only.

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'salary_snapshot_repository.dart';
import '../../features/salary/models/salary_analytics_models.dart';
import '../../shared/utils/financial_year_utils.dart';

class SalaryAnalyticsRepository {
  SalaryAnalyticsRepository._();
  static final SalaryAnalyticsRepository instance = SalaryAnalyticsRepository._();

  static const String _table = SalarySnapshotRepository.tableEmployees;

  Future<Database> _db() async => DatabaseHelper.instance.database;

  Future<void> _ready() => SalarySnapshotRepository.instance.ensureTablesReady();

  /// Every distinct (month, year) with at least one Saved Salary employee
  /// record, newest first.
  Future<List<MonthYear>> getAvailableMonths() async {
    await _ready();
    final db = await _db();
    final rows = await db.query(
      _table,
      columns: ['month', 'year'],
      distinct: true,
      orderBy: 'year DESC, month DESC',
    );
    return rows
        .map((r) => MonthYear(
              (r['month'] as int?) ?? 1,
              (r['year'] as int?) ?? DateTime.now().year,
            ))
        .toList();
  }

  /// All employee-month records for the given [months]. Saved Salaries
  /// only — no live salary state is ever consulted.
  Future<List<EmployeeAnalyticsRecord>> getRecordsForMonths(
    List<MonthYear> months,
  ) async {
    if (months.isEmpty) return const [];
    await _ready();
    final db = await _db();

    final keys = months.map((m) => m.sortKey).toSet().toList();
    final placeholders = List.filled(keys.length, '?').join(',');

    final rows = await db.query(
      _table,
      where: '(year * 100 + month) IN ($placeholders)',
      whereArgs: keys,
      orderBy: 'employee_name ASC, year ASC, month ASC',
    );

    return rows.map(EmployeeAnalyticsRecord.fromDbMap).toList();
  }
}