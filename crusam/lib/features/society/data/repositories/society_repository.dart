import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/society_models.dart';

class SocietyRepository {
  final Database db;
  SocietyRepository(this.db);

  Future<List<SocietySummary>> listSocieties({bool includeInactive = false}) async {
    final where = includeInactive ? '' : 'WHERE s.is_active = 1';
    final rows = await db.rawQuery('''
      SELECT 
        s.id, 
        s.name, 
        s.city, 
        s.is_active,
        (SELECT id FROM financial_years fy WHERE fy.society_id = s.id AND fy.status = 'open' ORDER BY fy.start_date DESC LIMIT 1) as active_fy_id,
        (SELECT code FROM financial_years fy WHERE fy.society_id = s.id AND fy.status = 'open' ORDER BY fy.start_date DESC LIMIT 1) as active_fy_code
      FROM societies s
      $where
      ORDER BY s.name ASC
    ''');
    return rows.map(SocietySummary.fromMap).toList();
  }

  Future<Society?> getSociety(int societyId, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final rows = await exec.query(
      'societies',
      where: 'id = ?',
      whereArgs: [societyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Society.fromMap(rows.first);
  }

  Future<int> insertSociety(DatabaseExecutor executor, SocietyDraft draft) async {
    return executor.insert('societies', draft.toInsertMap());
  }

  Future<void> updateSociety(DatabaseExecutor executor, int societyId, SocietyDraft draft) async {
    final map = draft.toInsertMap();
    map['updated_at'] = DateTime.now().toUtc().toIso8601String();
    await executor.update(
      'societies',
      map,
      where: 'id = ?',
      whereArgs: [societyId],
    );
  }

  Future<void> setSocietyActive(DatabaseExecutor executor, int societyId, bool active) async {
    await executor.update(
      'societies',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [societyId],
    );
  }

  Future<List<FinancialYear>> listFinancialYears(int societyId) async {
    final rows = await db.query(
      'financial_years',
      where: 'society_id = ?',
      whereArgs: [societyId],
      orderBy: 'start_date ASC',
    );
    return rows.map(FinancialYear.fromMap).toList();
  }

  Future<FinancialYear?> getFinancialYear(int fyId) async {
    final rows = await db.query(
      'financial_years',
      where: 'id = ?',
      whereArgs: [fyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FinancialYear.fromMap(rows.first);
  }

  Future<FinancialYear?> getFinancialYearByCode(int societyId, String code) async {
    final rows = await db.query(
      'financial_years',
      where: 'society_id = ? AND code = ?',
      whereArgs: [societyId, code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FinancialYear.fromMap(rows.first);
  }

  Future<FinancialYear?> getFinancialYearForDate(int societyId, String date) async {
    final rows = await db.query(
      'financial_years',
      where: 'society_id = ? AND start_date <= ? AND end_date >= ?',
      whereArgs: [societyId, date, date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FinancialYear.fromMap(rows.first);
  }

  Future<int> insertFinancialYear(
    DatabaseExecutor executor,
    int societyId,
    String code,
    String start,
    String end, {
    String status = 'open',
  }) async {
    return executor.insert('financial_years', {
      'society_id': societyId,
      'code': code,
      'start_date': start,
      'end_date': end,
      'status': status,
    });
  }

  Future<void> insertNumberSeries(
    DatabaseExecutor executor,
    int societyId,
    int fyId,
    String docType,
    String prefix, {
    int nextNo = 1,
    int pad = 6,
  }) async {
    await executor.insert('number_series', {
      'society_id': societyId,
      'fy_id': fyId,
      'doc_type': docType,
      'prefix': prefix,
      'next_no': nextNo,
      'pad': pad,
    });
  }

  Future<String?> getSetting(int societyId, String key, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final rows = await exec.query(
      'society_settings',
      columns: ['value'],
      where: 'society_id = ? AND key = ?',
      whereArgs: [societyId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<Map<String, String>> getAllSettings(int societyId, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final rows = await exec.query(
      'society_settings',
      where: 'society_id = ?',
      whereArgs: [societyId],
    );
    final map = <String, String>{};
    for (final r in rows) {
      final k = r['key'] as String;
      final v = r['value'] as String?;
      if (v != null) map[k] = v;
    }
    return map;
  }

  Future<void> setSetting(DatabaseExecutor executor, int societyId, String key, String? value) async {
    if (value == null) {
      await executor.delete(
        'society_settings',
        where: 'society_id = ? AND key = ?',
        whereArgs: [societyId, key],
      );
    } else {
      await executor.insert(
        'society_settings',
        {
          'society_id': societyId,
          'key': key,
          'value': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<String?> getDatedSetting(int societyId, String key, String onDate) async {
    final rows = await db.query(
      'dated_settings',
      columns: ['value'],
      where: 'society_id = ? AND key = ? AND effective_from <= ?',
      whereArgs: [societyId, key, onDate],
      orderBy: 'effective_from DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> addDatedSetting(
    DatabaseExecutor executor,
    int societyId,
    String key,
    String value,
    String effectiveFrom, {
    String? note,
  }) async {
    await executor.insert(
      'dated_settings',
      {
        'society_id': societyId,
        'key': key,
        'value': value,
        'effective_from': effectiveFrom,
        'note': note,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertAudit(
    DatabaseExecutor executor,
    int? societyId,
    String action,
    String entityType,
    int? entityId,
    String summary,
  ) async {
    await executor.insert('audit_log', {
      'society_id': societyId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'summary': summary,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
