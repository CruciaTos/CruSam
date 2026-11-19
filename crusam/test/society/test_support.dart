import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/society_database.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';

void initTestSupport() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<Database> createTestDatabase() => createTestDb();

Future<Database> createTestDb() async {
  return await SocietyDatabase.openForTest();
}

Future<Society> createTestSociety(
  Database db, {
  String name = 'Test Palm Meadows CHS',
  String booksStartDate = '2026-04-01',
  String city = 'Mumbai',
}) async {
  final admin = SocietyAdminService(db);
  final id = await admin.createSociety(SocietyDraft(
    name: name,
    city: city,
    booksStartDate: booksStartDate,
  ));
  return await admin.getSociety(id);
}

Future<int> getAccountIdBySystemKey(Database db, int societyId, String systemKey) async {
  final rows = await db.query(
    'accounts',
    columns: ['id'],
    where: 'society_id = ? AND system_key = ?',
    whereArgs: [societyId, systemKey],
  );
  if (rows.isEmpty) {
    throw StateError('Account with system_key $systemKey not found in society $societyId');
  }
  return rows.first['id'] as int;
}

Future<int> getAccountIdByCode(Database db, int societyId, String code) async {
  final rows = await db.query(
    'accounts',
    columns: ['id'],
    where: 'society_id = ? AND code = ?',
    whereArgs: [societyId, code],
  );
  if (rows.isEmpty) {
    throw StateError('Account with code $code not found in society $societyId');
  }
  return rows.first['id'] as int;
}
