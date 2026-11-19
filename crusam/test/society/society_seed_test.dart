import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/data/society_database.dart';
import 'package:crusam/features/society/data/seed/society_seed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  setUp(() async {
    db = await SocietyDatabase.openForTest();
  });

  tearDown(() async {
    await db.close();
  });

  test('society seed creates all groups, accounts, heads and series exactly once', () async {
    final societyId = await db.insert('societies', {
      'name': 'Green Acres CHS',
      'books_start_date': '2026-04-01',
    });

    await seedNewSociety(db, societyId: societyId, booksStartDate: '2026-04-01');

    final groups = await db.query('account_groups', where: 'society_id = ?', whereArgs: [societyId]);
    expect(groups.length, 25);

    final accounts = await db.query('accounts', where: 'society_id = ?', whereArgs: [societyId]);
    expect(accounts.length, 54);

    final cashBanks = await db.query('bank_accounts', where: 'society_id = ?', whereArgs: [societyId]);
    expect(cashBanks.length, 1);
    expect(cashBanks.first['account_type'], 'cash');

    final heads = await db.query('charge_heads', where: 'society_id = ?', whereArgs: [societyId]);
    expect(heads.length, 10);

    final series = await db.query('number_series', where: 'society_id = ?', whereArgs: [societyId]);
    expect(series.length, 11);

    final settings = await db.query('society_settings', where: 'society_id = ?', whereArgs: [societyId]);
    expect(settings.length, 14);

    final fy = await db.query('financial_years', where: 'society_id = ?', whereArgs: [societyId]);
    expect(fy.length, 1);
    expect(fy.first['code'], '2026-27');
  });

  test('failed society creation leaves no partial rows in transaction', () async {
    try {
      await db.transaction((txn) async {
        final socId = await txn.insert('societies', {
          'name': 'Failing Society',
          'books_start_date': '2026-04-01',
        });
        await seedNewSociety(txn, societyId: socId, booksStartDate: '2026-04-01');
        // Force an error
        throw Exception('Simulated crash during creation');
      });
    } catch (_) {}

    final societies = await db.query('societies');
    expect(societies, isEmpty);

    final groups = await db.query('account_groups');
    expect(groups, isEmpty);

    final accounts = await db.query('accounts');
    expect(accounts, isEmpty);
  });

  test('two societies keep separate settings and accounts', () async {
    final soc1 = await db.insert('societies', {
      'name': 'Society One',
      'books_start_date': '2026-04-01',
    });
    await seedNewSociety(db, societyId: soc1, booksStartDate: '2026-04-01');

    final soc2 = await db.insert('societies', {
      'name': 'Society Two',
      'books_start_date': '2026-04-01',
    });
    await seedNewSociety(db, societyId: soc2, booksStartDate: '2026-04-01');

    // Update setting in soc1
    await db.insert(
      'society_settings',
      {'society_id': soc1, 'key': 'billing.round_mode', 'value': 'rupee'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final s1Row = await db.query('society_settings', where: 'society_id = ? AND key = ?', whereArgs: [soc1, 'billing.round_mode']);
    final s2Row = await db.query('society_settings', where: 'society_id = ? AND key = ?', whereArgs: [soc2, 'billing.round_mode']);

    expect(s1Row.first['value'], 'rupee');
    expect(s2Row.first['value'], 'none');
  });
}
