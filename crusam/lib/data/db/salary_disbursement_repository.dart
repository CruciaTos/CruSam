// lib/data/db/salary_disbursement_repository.dart
//
// Drop-in extension on DatabaseHelper. Wire these methods into
// DatabaseHelper directly (same class body) or call via a thin wrapper.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_helper.dart';
import '../../features/salary/models/salary_disbursement_model.dart';

extension SalaryDisbursementRepository on DatabaseHelper {
  // ── Disbursement batch CRUD ───────────────────────────────────────────────

  Future<List<SalaryDisbursementModel>> getAllSalaryDisbursements() async {
    final db   = await database;
    final rows = await db.query(
      'salary_disbursements',
      orderBy: 'created_at DESC',
    );
    return rows.map(SalaryDisbursementModel.fromDbMap).toList();
  }

  Future<SalaryDisbursementModel?> getSalaryDisbursementById(int id) async {
    final db   = await database;
    final rows = await db.query(
      'salary_disbursements',
      where:     'id = ?',
      whereArgs: [id],
      limit:     1,
    );
    return rows.isEmpty ? null : SalaryDisbursementModel.fromDbMap(rows.first);
  }

  Future<int> insertSalaryDisbursement(SalaryDisbursementModel m) async {
    final db  = await database;
    final map = m.toDbMap()
      ..['created_at'] = DateTime.now().toIso8601String()
      ..['updated_at'] = DateTime.now().toIso8601String();
    return db.insert('salary_disbursements', map);
  }

  Future<void> updateSalaryDisbursement(SalaryDisbursementModel m) async {
    final db  = await database;
    final map = m.toDbMap()
      ..['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      'salary_disbursements',
      map,
      where:     'id = ?',
      whereArgs: [m.id],
    );
  }

  Future<void> deleteSalaryDisbursement(int id) async {
    final db = await database;
    // CASCADE takes care of items
    await db.delete(
      'salary_disbursements',
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  // ── Disbursement items ────────────────────────────────────────────────────

  Future<List<SalaryDisbursementItemModel>> getDisbursementItems(
      int disbursementId) async {
    final db   = await database;
    final rows = await db.query(
      'salary_disbursement_items',
      where:     'disbursement_id = ?',
      whereArgs: [disbursementId],
      orderBy:   'employee_name ASC',
    );
    return rows.map(SalaryDisbursementItemModel.fromDbMap).toList();
  }

  Future<void> insertDisbursementItems(
      int disbursementId, List<SalaryDisbursementItemModel> items) async {
    final db    = await database;
    final batch = db.batch();
    for (final item in items) {
      final map = item
          .copyWith(disbursementId: disbursementId)
          .toDbMap()
        ..['created_at'] = DateTime.now().toIso8601String();
      batch.insert('salary_disbursement_items', map);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteDisbursementItems(int disbursementId) async {
    final db = await database;
    await db.delete(
      'salary_disbursement_items',
      where:     'disbursement_id = ?',
      whereArgs: [disbursementId],
    );
  }

  // ── Already-disbursed employee IDs for a given month/year ────────────────
  // Used to grey out / exclude employees who've already been disbursed.
  // Considers any batch in 'generated' or 'exported' state.

  Future<Set<int>> getDisbursedEmployeeIds({
    required int month,
    required int year,
  }) async {
    final db   = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT i.employee_id
      FROM salary_disbursement_items i
      JOIN salary_disbursements d ON d.id = i.disbursement_id
      WHERE d.month = ? AND d.year = ?
        AND (d.status = 'generated' OR d.status = 'exported')
    ''', [month, year]);
    return rows.map((r) => r['employee_id'] as int).toSet();
  }
}