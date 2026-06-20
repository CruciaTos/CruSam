// crusam/lib/data/db/salary_snapshot_repository.dart
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'package:crusam/features/salary/models/salary_snapshot_model.dart';

class SalarySnapshotRepository {
  SalarySnapshotRepository._();
  static final SalarySnapshotRepository instance = SalarySnapshotRepository._();

  static const String tableSnapshots = 'salary_month_snapshots';
  static const String tableEmployees = 'salary_month_employees';

  bool _tablesReady = false;

  Future<Database> _db() async => DatabaseHelper.instance.database;

  Future<void> _ensureTables() async {
    if (_tablesReady) return;
    final db = await _db();

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSnapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        snapshot_key TEXT UNIQUE,
        snapshot_name TEXT,
        month INTEGER,
        year INTEGER,
        payload TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableEmployees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        snapshot_id INTEGER,
        employee_id INTEGER,
        employee_name TEXT,
        code TEXT,
        pf_no TEXT,
        month INTEGER,
        year INTEGER,
        attendance INTEGER,
        gross_salary REAL,
        deductions REAL,
        bonus REAL,
        net_salary REAL,
        created_at TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_salary_month_employees_snapshot_id '
      'ON $tableEmployees (snapshot_id)',
    );

    _tablesReady = true;
  }

  static String _nowIso() => DateTime.now().toIso8601String();

  /// One snapshot per calendar month — saving the same month again replaces
  /// the previous snapshot (payload + flattened employee rows).
  static String keyFor(int month, int year) =>
      'salary_$year-${month.toString().padLeft(2, '0')}';

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<SalaryMonthSnapshotModel> saveSnapshot({
    required String snapshotName,
    required SalarySnapshotPayload payload,
  }) async {
    await _ensureTables();
    final db = await _db();
    final key = keyFor(payload.month, payload.year);
    final now = _nowIso();
    final json = payload.encode();

    final existing = await db.query(
      tableSnapshots,
      where: 'snapshot_key = ?',
      whereArgs: [key],
      limit: 1,
    );

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
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [snapshotId],
      );
      await db.delete(
        tableEmployees,
        where: 'snapshot_id = ?',
        whereArgs: [snapshotId],
      );
    } else {
      snapshotId = await db.insert(tableSnapshots, {
        'snapshot_key': key,
        'snapshot_name': snapshotName,
        'month': payload.month,
        'year': payload.year,
        'payload': json,
        'created_at': now,
        'updated_at': now,
      });
    }

    final batch = db.batch();
    for (final emp in payload.employees) {
      batch.insert(tableEmployees, {
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
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);

    final row = await db.query(
      tableSnapshots,
      where: 'id = ?',
      whereArgs: [snapshotId],
      limit: 1,
    );
    return SalaryMonthSnapshotModel.fromDbMap(row.first);
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  Future<SalarySnapshotPayload?> loadSnapshot(int snapshotId) async {
    await _ensureTables();
    final db = await _db();
    final rows = await db.query(
      tableSnapshots,
      where: 'id = ?',
      whereArgs: [snapshotId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final model = SalaryMonthSnapshotModel.fromDbMap(rows.first);
    return SalarySnapshotPayload.decode(model.payload);
  }

  Future<SalaryMonthSnapshotModel?> getSnapshot(int snapshotId) async {
    await _ensureTables();
    final db = await _db();
    final rows = await db.query(
      tableSnapshots,
      where: 'id = ?',
      whereArgs: [snapshotId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SalaryMonthSnapshotModel.fromDbMap(rows.first);
  }

  // ── Browse ─────────────────────────────────────────────────────────────────
  Future<List<SalaryMonthSnapshotModel>> getSnapshots() async {
    await _ensureTables();
    final db = await _db();
    final rows = await db.query(
      tableSnapshots,
      orderBy: 'year DESC, month DESC, updated_at DESC',
    );
    return rows.map(SalaryMonthSnapshotModel.fromDbMap).toList();
  }

  // ── Rename ─────────────────────────────────────────────────────────────────
  Future<void> renameSnapshot(int snapshotId, String newName) async {
    await _ensureTables();
    final db = await _db();
    await db.update(
      tableSnapshots,
      {'snapshot_name': newName, 'updated_at': _nowIso()},
      where: 'id = ?',
      whereArgs: [snapshotId],
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> deleteSnapshot(int snapshotId) async {
    await _ensureTables();
    final db = await _db();
    await db.delete(
      tableEmployees,
      where: 'snapshot_id = ?',
      whereArgs: [snapshotId],
    );
    await db.delete(tableSnapshots, where: 'id = ?', whereArgs: [snapshotId]);
  }

  // ── Reporting / analytics helper ────────────────────────────────────────────
  Future<List<SalarySnapshotEmployeeRecord>> getEmployeeRecords(
    int snapshotId,
  ) async {
    await _ensureTables();
    final db = await _db();
    final rows = await db.query(
      tableEmployees,
      where: 'snapshot_id = ?',
      whereArgs: [snapshotId],
      orderBy: 'employee_name ASC',
    );
    return rows.map(SalarySnapshotEmployeeRecord.fromDbMap).toList();
  }
}
