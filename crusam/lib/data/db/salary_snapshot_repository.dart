// crusam/lib/data/db/salary_snapshot_repository.dart
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'package:crusam_core/crusam_core.dart';

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

    await _migrateAnalyticsColumns(db);   // ← added migration call

    _tablesReady = true;
  }

  /// Adds the pf/esic/msw/pt breakdown columns used by Salary Analytics,
  /// plus the full earnings breakdown (master basic/other/gross, earned
  /// basic/other) so every Salary Statement parameter is available for
  /// reporting — not just gross/deductions/net.
  /// Wrapped in a single transaction; verifies schema before committing,
  /// throws (→ rollback) on failure. No backfill — existing rows default
  /// to 0 (accepted v1 historical-data tradeoff).
  Future<void> _migrateAnalyticsColumns(Database db) async {
    final existing = await db.rawQuery('PRAGMA table_info($tableEmployees)');
    final existingNames = existing.map((c) => c['name'] as String).toSet();
    const intCols = ['pf', 'esic', 'msw', 'pt'];
    const realCols = [
      'basic_charges',   // master basic (full, non-prorated)
      'other_charges',   // master other (full, non-prorated)
      'master_gross',    // master gross (full, non-prorated)
      'earned_basic',    // prorated basic
      'earned_other',    // prorated other
    ];
    final missingInt = intCols.where((c) => !existingNames.contains(c)).toList();
    final missingReal = realCols.where((c) => !existingNames.contains(c)).toList();
    if (missingInt.isEmpty && missingReal.isEmpty) return;

    await db.transaction((txn) async {
      for (final col in missingInt) {
        await txn.execute('ALTER TABLE $tableEmployees ADD COLUMN $col INTEGER DEFAULT 0');
      }
      for (final col in missingReal) {
        await txn.execute('ALTER TABLE $tableEmployees ADD COLUMN $col REAL DEFAULT 0');
      }
      final verify = await txn.rawQuery('PRAGMA table_info($tableEmployees)');
      final verifyNames = verify.map((c) => c['name'] as String).toSet();
      final stillMissing = [...intCols, ...realCols]
          .where((c) => !verifyNames.contains(c))
          .toList();
      if (stillMissing.isNotEmpty) {
        throw StateError('Salary analytics migration failed — missing columns: $stillMissing');
      }
    });
  }

  /// Lets other repositories (SalaryAnalyticsRepository) ensure the fact
  /// table + analytics columns exist before querying.
  Future<void> ensureTablesReady() => _ensureTables();

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
    // Shared with the MCP server (crusam_core), in one transaction.
    final snapshotId = await db.transaction(
      (txn) => SalarySnapshotStore.save(
        txn,
        snapshotName: snapshotName,
        payload: payload,
        nowIso: _nowIso(),
      ),
    );

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