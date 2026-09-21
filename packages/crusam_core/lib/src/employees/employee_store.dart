// Employee persistence rules shared by the Employee form (app) and the MCP
// server.

import 'package:sqflite_common/sqlite_api.dart';

import '../models/employee_model.dart';

class EmployeeStore {
  EmployeeStore._();

  /// Codes offered by the Employee form's code dropdown.
  static const codes = ['F&B', 'I&L', 'P&S', 'A&P'];

  static const _notDeleted = '(is_deleted = 0 OR is_deleted IS NULL)';

  /// The row the Employee form writes: model fields + audit/sync columns.
  static Map<String, dynamic> formRow(
    EmployeeModel emp, {
    required String cloudId,
    required String createdAt,
    required String nowUtcIso,
  }) =>
      {
        ...emp.toMap()..remove('id'),
        'cloud_id': cloudId,
        'created_at': createdAt,
        'updated_at': nowUtcIso,
        'is_deleted': 0,
        'deleted_at': null,
      };

  static Future<List<EmployeeModel>> listActive(DatabaseExecutor db) async {
    final maps = await db.query('employees',
        where: _notDeleted, orderBy: 'sr_no ASC');
    return maps.map(EmployeeModel.fromMap).toList();
  }

  static Future<Map<String, Object?>?> getRow(DatabaseExecutor db, int id,
      {bool includeDeleted = false}) async {
    final rows = await db.query('employees',
        where: includeDeleted ? 'id=?' : 'id=? AND $_notDeleted',
        whereArgs: [id],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> insert(DatabaseExecutor db, Map<String, dynamic> row) =>
      db.insert('employees', row);

  static Future<int> update(
          DatabaseExecutor db, int id, Map<String, dynamic> row) =>
      db.update('employees', row, where: 'id=?', whereArgs: [id]);

  /// Soft delete, identical to DatabaseHelper.deleteEmployee.
  static Future<bool> softDelete(
      DatabaseExecutor db, int id, String nowUtcIso) async {
    final n = await db.update(
      'employees',
      {'is_deleted': 1, 'deleted_at': nowUtcIso, 'updated_at': nowUtcIso},
      where: 'id=? AND $_notDeleted',
      whereArgs: [id],
    );
    return n > 0;
  }

  /// Converts yyyy-mm-dd to the dd/MM/yyyy format the form stores.
  static String joiningDateForDb(String iso) {
    final p = iso.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }
}
