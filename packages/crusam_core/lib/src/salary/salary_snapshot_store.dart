// Saved salary months ("snapshots"): salary_month_snapshots holds the JSON
// payload, salary_month_employees holds one flattened row per employee for
// analytics. Moved out of SalarySnapshotRepository so the MCP server writes
// exactly what the app writes.

import 'package:sqflite_common/sqlite_api.dart';

import '../models/salary_snapshot_model.dart';

class SalarySnapshotStore {
  SalarySnapshotStore._();

  static const tableSnapshots = 'salary_month_snapshots';
  static const tableEmployees = 'salary_month_employees';

  /// One snapshot per calendar month.
  static String keyFor(int month, int year) =>
      'salary_$year-${month.toString().padLeft(2, '0')}';

  /// Saves (or replaces) the snapshot for payload.month/year. Returns its id.
  /// [nowIso] uses the app's convention: local time, DateTime.toIso8601String().
  static Future<int> save(
    DatabaseExecutor db, {
    required String snapshotName,
    required SalarySnapshotPayload payload,
    required String nowIso,
  }) async {
    final key = keyFor(payload.month, payload.year);
    final json = payload.encode();

    final existing = await db.query(tableSnapshots,
        where: 'snapshot_key = ?', whereArgs: [key], limit: 1);

    int snapshotId;
    if (existing.isNotEmpty) {
      snapshotId = existing.first['id'] as int;
      await db.update(
        tableSnapshots,
        {
          'snapshot_name': snapshotName,
          'month': payload.month,
          'year': payload.year,
          'payload': json,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [snapshotId],
      );
      await db.delete(tableEmployees,
          where: 'snapshot_id = ?', whereArgs: [snapshotId]);
    } else {
      snapshotId = await db.insert(tableSnapshots, {
        'snapshot_key': key,
        'snapshot_name': snapshotName,
        'month': payload.month,
        'year': payload.year,
        'payload': json,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
    }

    for (final emp in payload.employees) {
      await db.insert(tableEmployees, {
        'snapshot_id': snapshotId,
        'employee_id': emp.employeeId,
        'employee_name': emp.employeeName,
        'code': emp.code,
        'pf_no': emp.pfNo,
        'month': payload.month,
        'year': payload.year,
        'attendance': emp.days,
        'gross_salary': emp.earnedGross,
        'deductions': emp.totalDeduction.toDouble(),
        'bonus': emp.bonus,
        'net_salary': emp.netSalary,
        'pf': emp.pf,
        'esic': emp.esic,
        'msw': emp.msw,
        'pt': emp.pt,
        'basic_charges': emp.basicCharges,
        'other_charges': emp.otherCharges,
        'master_gross': emp.grossSalary,
        'earned_basic': emp.earnedBasic,
        'earned_other': emp.earnedOther,
        'created_at': nowIso,
      });
    }
    return snapshotId;
  }

  static Future<List<SalaryMonthSnapshotModel>> list(DatabaseExecutor db) async {
    final rows = await db.query(tableSnapshots,
        orderBy: 'year DESC, month DESC, updated_at DESC');
    return rows.map(SalaryMonthSnapshotModel.fromDbMap).toList();
  }

  static Future<SalaryMonthSnapshotModel?> get(DatabaseExecutor db, int id) async {
    final rows =
        await db.query(tableSnapshots, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : SalaryMonthSnapshotModel.fromDbMap(rows.first);
  }

  static Future<SalaryMonthSnapshotModel?> getByPeriod(
      DatabaseExecutor db, int month, int year) async {
    final rows = await db.query(tableSnapshots,
        where: 'snapshot_key = ?', whereArgs: [keyFor(month, year)], limit: 1);
    return rows.isEmpty ? null : SalaryMonthSnapshotModel.fromDbMap(rows.first);
  }

  static Future<void> rename(
      DatabaseExecutor db, int id, String newName, String nowIso) async {
    await db.update(tableSnapshots, {'snapshot_name': newName, 'updated_at': nowIso},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> delete(DatabaseExecutor db, int id) async {
    await db.delete(tableEmployees, where: 'snapshot_id = ?', whereArgs: [id]);
    await db.delete(tableSnapshots, where: 'id = ?', whereArgs: [id]);
  }
}
