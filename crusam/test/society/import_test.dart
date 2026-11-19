import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/imports/import_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Society society;
  late LedgerService ledger;
  late MemberService member;
  late ImportService importService;

  setUp(() async {
    db = await createTestDb();
    society = await createTestSociety(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    final billing = BillingService(db, ledgerService: ledger);
    importService = ImportService(db, memberService: member, ledgerService: ledger, billingService: billing);
  });

  tearDown(() async {
    await db.close();
  });

  group('Import Service', () {
    test('500-unit import works in one transaction', () async {
      final rows = <Map<String, String>>[];
      for (var i = 1; i <= 500; i++) {
        final blockNum = ((i - 1) ~/ 100) + 1;
        final unitInBlock = ((i - 1) % 100) + 1;
        rows.add({
          'block': 'Tower $blockNum',
          'unit_no': '${blockNum}0$unitInBlock',
          'unit_type': '2BHK',
          'area_1': '1050.50',
          'occupancy': 'owner_occupied',
          'active': 'yes',
        });
      }

      final res = await importService.importUnits(society.id, rows);
      expect(res.count, 500);

      final countRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM units WHERE society_id = ?',
        [society.id],
      );
      expect(countRows.first['cnt'], 500);
    });

    test('one bad row leaves no imported rows (atomic rollback)', () async {
      final rows = <Map<String, String>>[
        {'block': 'Wing A', 'unit_no': '101', 'unit_type': '1BHK', 'occupancy': 'owner_occupied'},
        {'block': 'Wing A', 'unit_no': '102', 'unit_type': '1BHK', 'occupancy': 'owner_occupied'},
        {'block': 'Wing A', 'unit_no': '', 'unit_type': '1BHK', 'occupancy': 'owner_occupied'}, // Bad row: empty unit_no
        {'block': 'Wing A', 'unit_no': '104', 'unit_type': '1BHK', 'occupancy': 'owner_occupied'},
      ];

      expect(
        () => importService.importUnits(society.id, rows),
        throwsA(isA<SocietyException>()),
      );

      // Verify ZERO units were created
      final countRows = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM units WHERE society_id = ?',
        [society.id],
      );
      expect(countRows.first['cnt'], 0);
    });

    test('imports people with primary contact and bill-to', () async {
      // First import unit
      await importService.importUnits(society.id, [
        {'block': 'Wing B', 'unit_no': '201', 'unit_type': '2BHK', 'occupancy': 'owner_occupied'},
      ]);

      final peopleRows = [
        {
          'block': 'Wing B',
          'unit_no': '201',
          'full_name': 'Ramesh Tendulkar',
          'role': 'owner',
          'primary_contact': 'yes',
          'bill_to': 'yes',
          'phone': '9988776655',
          'email': 'ramesh@example.com',
          'from_date': '2026-04-01',
        },
      ];

      final res = await importService.importPeople(society.id, peopleRows);
      expect(res.count, 1);

      final units = await member.listUnits(society.id);
      expect(units.rows.first.primaryContactName, 'Ramesh Tendulkar');
      expect(units.rows.first.billToName, 'Ramesh Tendulkar');
    });

    test('unit opening balances reconcile to Members Receivable in Ledger', () async {
      // 1. Import units
      await importService.importUnits(society.id, [
        {'block': 'Block A', 'unit_no': '101', 'unit_type': '2BHK', 'occupancy': 'owner_occupied'},
        {'block': 'Block A', 'unit_no': '102', 'unit_type': '2BHK', 'occupancy': 'owner_occupied'},
      ]);

      // 2. Import unit opening balances
      // A-101 owes ₹10,000.00 Dr
      // A-102 owes ₹5,000.00 Dr
      final openingRows = [
        {'block': 'Block A', 'unit_no': '101', 'debit': '10000.00', 'credit': '0', 'as_of': '2026-04-01'},
        {'block': 'Block A', 'unit_no': '102', 'debit': '5000.00', 'credit': '0', 'as_of': '2026-04-01'},
      ];

      final res = await importService.importOpeningUnits(society.id, openingRows);
      expect(res.count, 2);

      // 3. Check trial balance for Members Receivable (1201)
      final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);

      final memRecAccId = await getAccountIdBySystemKey(db, society.id, 'members_receivable');
      final memRow = tb.rows.firstWhere((r) => r.accountId == memRecAccId);

      // Total ₹15,000.00 = 1500000 paise
      expect(memRow.closingDebitPaise, 1500000);
    });
  });
}
