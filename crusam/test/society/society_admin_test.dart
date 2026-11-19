import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/society_database.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SocietyAdminService service;

  setUp(() async {
    db = await SocietyDatabase.openForTest();
    service = SocietyAdminService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates a society and creates audit entry', () async {
    final id = await service.createSociety(const SocietyDraft(
      name: 'Sunflower CHS',
      city: 'Pune',
      booksStartDate: '2026-04-01',
    ));

    expect(id, isPositive);
    final soc = await service.getSociety(id);
    expect(soc.name, 'Sunflower CHS');
    expect(soc.city, 'Pune');
    expect(soc.booksStartDate, '2026-04-01');

    final audits = await db.query('audit_log', where: 'society_id = ?', whereArgs: [id]);
    expect(audits, isNotEmpty);
    expect(audits.first['action'], 'create');
  });

  test('rejects duplicate society name', () async {
    await service.createSociety(const SocietyDraft(
      name: 'Rosewood CHS',
      booksStartDate: '2026-04-01',
    ));

    expect(
      () => service.createSociety(const SocietyDraft(
        name: 'Rosewood CHS',
        booksStartDate: '2026-04-01',
      )),
      throwsA(isA<SocietyException>().having((e) => e.code, 'code', 'duplicate')),
    );
  });

  test('creates next financial year and seeds its number series', () async {
    final id = await service.createSociety(const SocietyDraft(
      name: 'Palm Meadows',
      booksStartDate: '2026-04-01',
    ));

    final nextFyId = await service.createNextFinancialYear(id);
    expect(nextFyId, isPositive);

    final years = await service.listFinancialYears(id);
    expect(years.length, 2);
    expect(years[0].code, '2026-27');
    expect(years[1].code, '2027-28');

    final series27 = await db.query(
      'number_series',
      where: 'society_id = ? AND fy_id = ?',
      whereArgs: [id, nextFyId],
    );
    expect(series27.length, 11);
    expect(series27.first['prefix'], contains('2027-28'));
  });

  test('manages dated settings correctly', () async {
    final id = await service.createSociety(const SocietyDraft(
      name: 'Skyline Towers',
      booksStartDate: '2026-04-01',
    ));

    await service.addDatedSetting(id, 'interest.rate_bp', '1800', '2026-04-01');
    await service.addDatedSetting(id, 'interest.rate_bp', '2100', '2026-10-01');

    final rateBefore = await service.getDatedSetting(id, 'interest.rate_bp', '2026-06-15');
    expect(rateBefore, '1800');

    final rateAfter = await service.getDatedSetting(id, 'interest.rate_bp', '2026-10-15');
    expect(rateAfter, '2100');
  });
}
