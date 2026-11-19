import 'package:sqflite/sqflite.dart';
import '../models/member_models.dart';
import '../models/society_models.dart';

class MemberRepository {
  final Database db;
  MemberRepository(this.db);

  // -------------------------------------------------------------
  // Blocks
  // -------------------------------------------------------------

  Future<List<Block>> listBlocks(int societyId, {bool includeInactive = false}) async {
    final where = includeInactive
        ? 'society_id = ?'
        : 'society_id = ? AND is_active = 1';
    final rows = await db.query(
      'blocks',
      where: where,
      whereArgs: [societyId],
      orderBy: 'name ASC',
    );
    return rows.map(Block.fromMap).toList();
  }

  Future<Block?> getBlock(DatabaseExecutor executor, int blockId) async {
    final rows = await executor.query(
      'blocks',
      where: 'id = ?',
      whereArgs: [blockId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Block.fromMap(rows.first);
  }

  Future<int> insertBlock(DatabaseExecutor executor, int societyId, BlockDraft draft) {
    return executor.insert('blocks', draft.toMap(societyId));
  }

  Future<void> updateBlock(DatabaseExecutor executor, int societyId, int blockId, BlockDraft draft) {
    return executor.update(
      'blocks',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [blockId, societyId],
    );
  }

  // -------------------------------------------------------------
  // Unit Types
  // -------------------------------------------------------------

  Future<List<UnitType>> listUnitTypes(int societyId, {bool includeInactive = false}) async {
    final where = includeInactive
        ? 'society_id = ?'
        : 'society_id = ? AND is_active = 1';
    final rows = await db.query(
      'unit_types',
      where: where,
      whereArgs: [societyId],
      orderBy: 'sort_order ASC, name ASC',
    );
    return rows.map(UnitType.fromMap).toList();
  }

  Future<UnitType?> getUnitType(DatabaseExecutor executor, int typeId) async {
    final rows = await executor.query(
      'unit_types',
      where: 'id = ?',
      whereArgs: [typeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UnitType.fromMap(rows.first);
  }

  Future<int> insertUnitType(DatabaseExecutor executor, int societyId, UnitTypeDraft draft) {
    return executor.insert('unit_types', draft.toMap(societyId));
  }

  Future<void> updateUnitType(DatabaseExecutor executor, int societyId, int typeId, UnitTypeDraft draft) {
    return executor.update(
      'unit_types',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [typeId, societyId],
    );
  }

  // -------------------------------------------------------------
  // Units
  // -------------------------------------------------------------

  Future<PageResult<UnitRow>> listUnits(
    int societyId, {
    int? blockId,
    int? unitTypeId,
    String? occupancy,
    String? search,
    bool includeInactive = false,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('u.society_id = ?');
    final args = <Object?>[societyId];

    if (!includeInactive) {
      where.write(' AND u.is_active = 1');
    }
    if (blockId != null) {
      where.write(' AND u.block_id = ?');
      args.add(blockId);
    }
    if (unitTypeId != null) {
      where.write(' AND u.unit_type_id = ?');
      args.add(unitTypeId);
    }
    if (occupancy != null && occupancy.isNotEmpty) {
      where.write(' AND u.occupancy = ?');
      args.add(occupancy);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND (u.unit_no LIKE ? OR b.name LIKE ?)');
      final term = '%${search.trim()}%';
      args.add(term);
      args.add(term);
    }

    final countSql = '''
      SELECT COUNT(*) as cnt
      FROM units u
      JOIN blocks b ON u.block_id = b.id
      WHERE $where
    ''';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        u.*,
        b.name as block_name,
        ut.name as unit_type_name,
        (SELECT p.full_name FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_primary_contact = 1 AND up.to_date IS NULL LIMIT 1) as primary_contact_name,
        (SELECT p.phone FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_primary_contact = 1 AND up.to_date IS NULL LIMIT 1) as primary_contact_phone,
        (SELECT p.full_name FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_bill_to = 1 AND up.to_date IS NULL LIMIT 1) as bill_to_name
      FROM units u
      JOIN blocks b ON u.block_id = b.id
      JOIN unit_types ut ON u.unit_type_id = ut.id
      WHERE $where
      ORDER BY b.name ASC, u.unit_no ASC
      LIMIT ? OFFSET ?
    ''';

    final queryArgs = [...args, page.limit, page.offset];
    final rows = await exec.rawQuery(selectSql, queryArgs);
    final items = rows.map(UnitRow.fromMap).toList();

    return PageResult(items, total);
  }

  Future<UnitRow?> getUnit(DatabaseExecutor executor, int unitId) async {
    final selectSql = '''
      SELECT 
        u.*,
        b.name as block_name,
        ut.name as unit_type_name,
        (SELECT p.full_name FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_primary_contact = 1 AND up.to_date IS NULL LIMIT 1) as primary_contact_name,
        (SELECT p.phone FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_primary_contact = 1 AND up.to_date IS NULL LIMIT 1) as primary_contact_phone,
        (SELECT p.full_name FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_bill_to = 1 AND up.to_date IS NULL LIMIT 1) as bill_to_name
      FROM units u
      JOIN blocks b ON u.block_id = b.id
      JOIN unit_types ut ON u.unit_type_id = ut.id
      WHERE u.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(selectSql, [unitId]);
    if (rows.isEmpty) return null;
    return UnitRow.fromMap(rows.first);
  }

  Future<int> insertUnit(DatabaseExecutor executor, int societyId, UnitDraft draft) {
    return executor.insert('units', draft.toMap(societyId));
  }

  Future<void> updateUnit(DatabaseExecutor executor, int societyId, int unitId, UnitDraft draft) {
    return executor.update(
      'units',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [unitId, societyId],
    );
  }

  Future<void> setUnitActive(DatabaseExecutor executor, int societyId, int unitId, bool active) {
    return executor.update(
      'units',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [unitId, societyId],
    );
  }

  Future<bool> hasLedgerHistory(DatabaseExecutor executor, int unitId) async {
    final jl = await executor.rawQuery(
      'SELECT 1 FROM journal_lines WHERE unit_id = ? LIMIT 1',
      [unitId],
    );
    if (jl.isNotEmpty) return true;

    final bl = await executor.rawQuery(
      'SELECT 1 FROM bills WHERE unit_id = ? LIMIT 1',
      [unitId],
    );
    if (bl.isNotEmpty) return true;

    final rc = await executor.rawQuery(
      'SELECT 1 FROM receipts WHERE unit_id = ? LIMIT 1',
      [unitId],
    );
    if (rc.isNotEmpty) return true;

    return false;
  }

  // -------------------------------------------------------------
  // People
  // -------------------------------------------------------------

  Future<PageResult<Person>> listPeople(
    int societyId, {
    String? search,
    bool includeInactive = false,
    PageRequest page = const PageRequest(),
  }) async {
    final where = StringBuffer('society_id = ?');
    final args = <Object?>[societyId];

    if (!includeInactive) {
      where.write(' AND is_active = 1');
    }
    if (search != null && search.trim().isNotEmpty) {
      where.write(' AND (full_name LIKE ? OR phone LIKE ? OR email LIKE ?)');
      final term = '%${search.trim()}%';
      args.add(term);
      args.add(term);
      args.add(term);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM people WHERE $where';
    final countRows = await db.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT * FROM people
      WHERE $where
      ORDER BY full_name ASC
      LIMIT ? OFFSET ?
    ''';
    final rows = await db.rawQuery(selectSql, [...args, page.limit, page.offset]);

    final people = <Person>[];
    for (final r in rows) {
      final pId = r['id'] as int;
      final unitsRows = await db.rawQuery('''
        SELECT b.name || '-' || u.unit_no as unit_name
        FROM unit_people up
        JOIN units u ON up.unit_id = u.id
        JOIN blocks b ON u.block_id = b.id
        WHERE up.person_id = ? AND up.to_date IS NULL
        ORDER BY b.name, u.unit_no
      ''', [pId]);
      final unitNames = unitsRows.map((ur) => ur['unit_name'] as String).toList();
      people.add(Person.fromMap(r, unitNames));
    }

    return PageResult(people, total);
  }

  Future<Person?> getPerson(DatabaseExecutor executor, int personId) async {
    final rows = await executor.query(
      'people',
      where: 'id = ?',
      whereArgs: [personId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final unitsRows = await executor.rawQuery('''
      SELECT b.name || '-' || u.unit_no as unit_name
      FROM unit_people up
      JOIN units u ON up.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      WHERE up.person_id = ? AND up.to_date IS NULL
      ORDER BY b.name, u.unit_no
    ''', [personId]);
    final unitNames = unitsRows.map((ur) => ur['unit_name'] as String).toList();

    return Person.fromMap(rows.first, unitNames);
  }

  Future<int> insertPerson(DatabaseExecutor executor, int societyId, PersonDraft draft) {
    return executor.insert('people', draft.toMap(societyId));
  }

  Future<void> updatePerson(DatabaseExecutor executor, int societyId, int personId, PersonDraft draft) {
    return executor.update(
      'people',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [personId, societyId],
    );
  }

  Future<void> setPersonActive(DatabaseExecutor executor, int societyId, int personId, bool active) {
    return executor.update(
      'people',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [personId, societyId],
    );
  }

  // -------------------------------------------------------------
  // Unit People (Assignments)
  // -------------------------------------------------------------

  Future<List<UnitPerson>> listUnitPeople(
    DatabaseExecutor executor,
    int societyId,
    int unitId, {
    bool currentOnly = false,
  }) async {
    final where = StringBuffer('up.unit_id = ? AND up.society_id = ?');
    final args = <Object?>[unitId, societyId];

    if (currentOnly) {
      where.write(' AND up.to_date IS NULL');
    }

    final sql = '''
      SELECT 
        up.*,
        p.full_name,
        p.phone,
        p.email
      FROM unit_people up
      JOIN people p ON up.person_id = p.id
      WHERE $where
      ORDER BY (CASE WHEN up.to_date IS NULL THEN 0 ELSE 1 END), up.from_date DESC
    ''';
    final rows = await executor.rawQuery(sql, args);
    return rows.map(UnitPerson.fromMap).toList();
  }

  Future<int> insertUnitPerson(DatabaseExecutor executor, int societyId, UnitPersonDraft draft) {
    return executor.insert('unit_people', draft.toMap(societyId));
  }

  Future<void> endUnitPerson(DatabaseExecutor executor, int assignmentId, String toDate) {
    return executor.update(
      'unit_people',
      {'to_date': toDate},
      where: 'id = ?',
      whereArgs: [assignmentId],
    );
  }

  Future<void> endActiveRolesForUnit(
    DatabaseExecutor executor,
    int unitId,
    String toDate, {
    String? role,
  }) async {
    final where = StringBuffer('unit_id = ? AND to_date IS NULL');
    final args = <Object?>[toDate, unitId];

    if (role != null) {
      where.write(' AND role = ?');
      args.add(role);
    }

    await executor.rawUpdate(
      'UPDATE unit_people SET to_date = ? WHERE $where',
      args,
    );
  }

  Future<void> clearPrimaryContact(DatabaseExecutor executor, int unitId) async {
    await executor.update(
      'unit_people',
      {'is_primary_contact': 0},
      where: 'unit_id = ? AND is_primary_contact = 1 AND to_date IS NULL',
      whereArgs: [unitId],
    );
  }

  Future<void> clearBillTo(DatabaseExecutor executor, int unitId) async {
    await executor.update(
      'unit_people',
      {'is_bill_to': 0},
      where: 'unit_id = ? AND is_bill_to = 1 AND to_date IS NULL',
      whereArgs: [unitId],
    );
  }
}
