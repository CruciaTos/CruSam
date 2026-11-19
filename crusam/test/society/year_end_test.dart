import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'package:crusam/features/society/domain/year_end/year_end_service.dart';
import 'test_support.dart';

void main() {
  setUpAll(initTestSupport);

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late YearEndService yearEnd;
  late Society society;
  late int fyId;

  setUp(() async {
    db = await createTestDatabase();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    yearEnd = YearEndService(db, ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Year End Test Society',
      city: 'Mumbai',
      state: 'Maharashtra',
      pincode: '400001',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);
    final years = await admin.listFinancialYears(society.id);
    fyId = years.first.id;
  });

  tearDown(() async {
    await db.close();
  });

  test('YearEndService preconditions, close, and reopen operations', () async {
    final maintAcc = (await ledger.getAccountByCode(society.id, '3101'))!;
    final electricityAcc = (await ledger.getAccountByCode(society.id, '4201'))!;
    final bankAcc = (await ledger.getAccountByCode(society.id, '1101'))!;

    // Post sample income: ₹20,000.00
    await db.transaction((txn) => ledger.post(txn, JournalDraft(
      societyId: society.id,
      entryDate: '2026-05-10',
      sourceType: 'bill',
      narration: 'Maintenance Income',
      lines: [
        JournalLineDraft(accountId: bankAcc.id, debitPaise: 2000000, creditPaise: 0),
        JournalLineDraft(accountId: maintAcc.id, debitPaise: 0, creditPaise: 2000000),
      ],
    )));

    // Post sample expense: ₹8,000.00
    await db.transaction((txn) => ledger.post(txn, JournalDraft(
      societyId: society.id,
      entryDate: '2026-06-15',
      sourceType: 'expense',
      narration: 'Electricity Expense',
      lines: [
        JournalLineDraft(accountId: electricityAcc.id, debitPaise: 800000, creditPaise: 0),
        JournalLineDraft(accountId: bankAcc.id, debitPaise: 0, creditPaise: 800000),
      ],
    )));

    // Check preconditions - should be ready to close
    final issues = await yearEnd.checkPreconditions(society.id, fyId);
    expect(issues.where((i) => !i.startsWith('WARNING:')).isEmpty, isTrue);

    // 1. Close the financial year
    final closingEntryId = await yearEnd.closeYear(society.id, fyId);
    expect(closingEntryId, isPositive);

    // Verify FY status is closed
    final yearsAfter = await admin.listFinancialYears(society.id);
    final closedYear = yearsAfter.firstWhere((y) => y.id == fyId);
    expect(closedYear.isOpen, isFalse);
    expect(closedYear.status, equals('closed'));

    // Verify closing entry lines:
    // Income (3101) debited by 20,000.00
    // Expense (4201) credited by 8,000.00
    // I&E (2801) credited by surplus 12,000.00
    final entry = await ledger.entryDetail(society.id, closingEntryId);
    expect(entry, isNotNull);
    expect(entry.sourceType, equals('year_close'));

    final maintLine = entry.lines.firstWhere((l) => l.accountId == maintAcc.id);
    expect(maintLine.debitPaise, equals(2000000));
    expect(maintLine.creditPaise, equals(0));

    final electLine = entry.lines.firstWhere((l) => l.accountId == electricityAcc.id);
    expect(electLine.debitPaise, equals(0));
    expect(electLine.creditPaise, equals(800000));

    final incExpLine = entry.lines.firstWhere((l) => l.accountCode == '2801');
    expect(incExpLine.debitPaise, equals(0));
    expect(incExpLine.creditPaise, equals(1200000)); // ₹12,000.00 surplus

    // Trial balance after close remains balanced
    final tbAfterClose = await ledger.trialBalance(society.id, '2026-04-01', '2027-03-31');
    expect(tbAfterClose.isBalanced, isTrue);

    // After close, attempting to post dated within closed year is blocked
    await expectLater(
      db.transaction((txn) => ledger.post(txn, JournalDraft(
        societyId: society.id,
        entryDate: '2026-07-01',
        sourceType: 'manual',
        narration: 'Blocked posting into closed year',
        lines: [
          JournalLineDraft(accountId: bankAcc.id, debitPaise: 100, creditPaise: 0),
          JournalLineDraft(accountId: maintAcc.id, debitPaise: 0, creditPaise: 100),
        ],
      ))),
      throwsA(isA<SocietyException>()),
    );

    // 2. Reopen year requires exact confirmation "REOPEN"
    await expectLater(
      yearEnd.reopenYear(society.id, fyId, 'NO'),
      throwsA(isA<SocietyException>()),
    );

    // Reopen with valid confirmation succeeds
    await yearEnd.reopenYear(society.id, fyId, 'REOPEN');

    final yearsReopened = await admin.listFinancialYears(society.id);
    final reopenedYear = yearsReopened.firstWhere((y) => y.id == fyId);
    expect(reopenedYear.isOpen, isTrue);
    expect(reopenedYear.status, equals('open'));

    // Closing entry is now reversed
    final originalClosing = await ledger.entryDetail(society.id, closingEntryId);
    expect(originalClosing, isNotNull);
    expect(originalClosing.status, equals('reversed'));
  });
}
