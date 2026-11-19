import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Society society;
  late LedgerService ledger;

  late int cashAccId;
  late int bankAccId;
  late int memberRecAccId;
  late int maintIncomeAccId;
  late int otherRecAccId;
  late int vendorPayableAccId;

  late int testUnitId;
  late int testVendorId;
  late int testPartyId;

  setUp(() async {
    db = await createTestDb();
    society = await createTestSociety(db, booksStartDate: '2026-04-01');
    ledger = LedgerService(db);

    cashAccId = await getAccountIdBySystemKey(db, society.id, 'cash');
    memberRecAccId = await getAccountIdBySystemKey(db, society.id, 'members_receivable');
    maintIncomeAccId = await getAccountIdBySystemKey(db, society.id, 'maintenance_income');
    otherRecAccId = await getAccountIdBySystemKey(db, society.id, 'other_receivable');
    vendorPayableAccId = await getAccountIdBySystemKey(db, society.id, 'vendors_payable');

    final cashBankGroupId = (await db.query(
      'account_groups',
      columns: ['id'],
      where: 'society_id = ? AND code = ?',
      whereArgs: [society.id, '1100'],
    )).first['id'] as int;

    bankAccId = await db.insert('accounts', {
      'society_id': society.id,
      'group_id': cashBankGroupId,
      'code': '1102',
      'name': 'HDFC Bank - Society Current A/c',
      'account_kind': 'bank',
      'is_active': 1,
    });

    // Create block, unit type, and unit for testing subledger
    final blockId = await db.insert('blocks', {
      'society_id': society.id,
      'name': 'A Block',
      'is_active': 1,
    });
    final unitTypeId = await db.insert('unit_types', {
      'society_id': society.id,
      'name': '2BHK',
      'sort_order': 0,
      'is_active': 1,
    });
    testUnitId = await db.insert('units', {
      'society_id': society.id,
      'block_id': blockId,
      'unit_no': 'A-101',
      'unit_type_id': unitTypeId,
      'area1_centi': 100000,
      'area2_centi': 0,
      'occupancy': 'owner_occupied',
      'is_active': 1,
    });

    testVendorId = await db.insert('vendors', {
      'society_id': society.id,
      'vendor_code': 'V001',
      'name': 'Reliable Security Services',
      'is_active': 1,
    });

    testPartyId = await db.insert('parties', {
      'society_id': society.id,
      'name': 'Telecom Tower Corp',
      'is_active': 1,
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Ledger posting gates & numbering', () {
    test('posts valid manual journal and increments number series', () async {
      final draft1 = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-10',
        sourceType: 'manual',
        narration: 'Cash deposit to bank',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 500000), // ₹5,000
          JournalLineDraft(accountId: cashAccId, creditPaise: 500000),
        ],
      );

      final posted1 = await ledger.postManual(draft1);
      expect(posted1.entryNo, 'JE/2026-27/000001');
      expect(posted1.id, isPositive);

      final draft2 = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-12',
        sourceType: 'manual',
        narration: 'Second cash deposit to bank',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 200000), // ₹2,000
          JournalLineDraft(accountId: cashAccId, creditPaise: 200000),
        ],
      );

      final posted2 = await ledger.postManual(draft2);
      expect(posted2.entryNo, 'JE/2026-27/000002');
    });

    test('Gate 1: rejects entry date earlier than books_start_date', () async {
      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-03-31', // booksStartDate is 2026-04-01
        sourceType: 'manual',
        narration: 'Prior period entry',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('before books start date'))),
      );
    });

    test('Gate 2: rejects posting if financial year is closed', () async {
      await db.update(
        'financial_years',
        {'status': 'closed'},
        where: 'society_id = ? AND code = ?',
        whereArgs: [society.id, '2026-27'],
      );

      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-05-01',
        sourceType: 'manual',
        narration: 'Entry in closed year',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('closed'))),
      );
    });

    test('Gate 4: rejects journal with fewer than 2 lines', () async {
      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'One line only',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('at least two lines'))),
      );
    });

    test('Gate 5: rejects unbalanced debits and credits', () async {
      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Unbalanced journal',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 90000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('Unbalanced journal'))),
      );
    });

    test('Gate 6: rejects lines with both debit and credit or non-positive', () async {
      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Both debit and credit',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000, creditPaise: 50000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 50000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('either positive debit or positive credit'))),
      );
    });

    test('Gate 7: rejects account from another society', () async {
      final soc2 = await createTestSociety(db, name: 'Second Society CHS');
      final soc2CashId = await getAccountIdBySystemKey(db, soc2.id, 'cash');

      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Cross society account',
        lines: [
          JournalLineDraft(accountId: soc2CashId, debitPaise: 100000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('does not belong'))),
      );
    });

    test('Gate 7: rejects inactive account', () async {
      await db.update('accounts', {'is_active': 0}, where: 'id = ?', whereArgs: [cashAccId]);

      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Inactive account test',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 100000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draft),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('inactive'))),
      );
    });

    test('Gate 8: requires unit_id for member receivable', () async {
      final draftWithoutUnit = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Member receivable without unit',
        lines: [
          JournalLineDraft(accountId: memberRecAccId, debitPaise: 150000),
          JournalLineDraft(accountId: maintIncomeAccId, creditPaise: 150000),
        ],
      );

      expect(
        () => ledger.postManual(draftWithoutUnit),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('requires a unit'))),
      );

      final draftWithUnit = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Member receivable with unit',
        lines: [
          JournalLineDraft(accountId: memberRecAccId, debitPaise: 150000, unitId: testUnitId),
          JournalLineDraft(accountId: maintIncomeAccId, creditPaise: 150000),
        ],
      );

      final posted = await ledger.postManual(draftWithUnit);
      expect(posted.id, isPositive);
    });

    test('Gate 9: requires party_id for other receivables', () async {
      final draftWithoutParty = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Other receivable without party',
        lines: [
          JournalLineDraft(accountId: otherRecAccId, debitPaise: 100000),
          JournalLineDraft(accountId: bankAccId, creditPaise: 100000),
        ],
      );

      expect(
        () => ledger.postManual(draftWithoutParty),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('requires a party'))),
      );

      final draftWithParty = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Other receivable with party',
        lines: [
          JournalLineDraft(accountId: otherRecAccId, debitPaise: 100000, partyId: testPartyId),
          JournalLineDraft(accountId: bankAccId, creditPaise: 100000),
        ],
      );

      final posted = await ledger.postManual(draftWithParty);
      expect(posted.id, isPositive);
    });

    test('Gate 10: requires vendor_id for accounts payable', () async {
      final draftWithoutVendor = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Accounts payable without vendor',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 200000),
          JournalLineDraft(accountId: vendorPayableAccId, creditPaise: 200000),
        ],
      );

      expect(
        () => ledger.postManual(draftWithoutVendor),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('requires a vendor'))),
      );

      final draftWithVendor = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Accounts payable with vendor',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 200000),
          JournalLineDraft(accountId: vendorPayableAccId, creditPaise: 200000, vendorId: testVendorId),
        ],
      );

      final posted = await ledger.postManual(draftWithVendor);
      expect(posted.id, isPositive);
    });
  });

  group('Reversals', () {
    test('reversal mirrors lines, nets balance to zero, and cannot be reversed twice', () async {
      final draft = JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Initial deposit',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 500000),
          JournalLineDraft(accountId: cashAccId, creditPaise: 500000),
        ],
      );

      final original = await ledger.postManual(draft);
      expect(original.id, isPositive);

      // Reversal
      await ledger.reverseManual(society.id, original.id, '2026-04-16', 'Deposited to wrong account');

      final updatedOrig = await ledger.entryDetail(society.id, original.id);
      expect(updatedOrig.status, 'reversed');
      expect(updatedOrig.reversedById, isNotNull);

      final reversalEntry = await ledger.entryDetail(society.id, updatedOrig.reversedById!);
      expect(reversalEntry.sourceType, 'reversal');
      expect(reversalEntry.reversalOfId, original.id);

      // Verify mirrored lines (Bank is credit 500000, Cash is debit 500000)
      final bankLine = reversalEntry.lines.firstWhere((l) => l.accountId == bankAccId);
      final cashLine = reversalEntry.lines.firstWhere((l) => l.accountId == cashAccId);
      expect(bankLine.creditPaise, 500000);
      expect(bankLine.debitPaise, 0);
      expect(cashLine.debitPaise, 500000);
      expect(cashLine.creditPaise, 0);

      // Trial balance nets to zero
      final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);
      expect(tb.totalClosingDebitPaise, 0);
      expect(tb.totalClosingCreditPaise, 0);

      // Reversing an already reversed entry must fail
      expect(
        () => ledger.reverseManual(society.id, original.id, '2026-04-17', 'Try reverse again'),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('already been reversed'))),
      );

      // Reversing a reversal entry must also fail
      expect(
        () => ledger.reverseManual(society.id, reversalEntry.id, '2026-04-17', 'Try reverse reversal'),
        throwsA(isA<SocietyException>().having((e) => e.message, 'message', contains('Cannot reverse a reversal entry'))),
      );
    });
  });

  group('Trial balance & Opening balances', () {
    test('saveOpeningBalances posts journal and updates trial balance', () async {
      await ledger.saveOpeningBalances(society.id, [
        OpeningBalanceDraft(
          accountId: bankAccId,
          debitPaise: 10000000, // ₹1,00,000 Dr
          asOfDate: '2026-04-01',
        ),
        OpeningBalanceDraft(
          accountId: cashAccId,
          debitPaise: 2000000, // ₹20,000 Dr
          asOfDate: '2026-04-01',
        ),
      ]);

      // Both debited, so difference was credited to opening_adjustment (system account 2899)
      final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);
      expect(tb.totalClosingDebitPaise, 12000000);
      expect(tb.totalClosingCreditPaise, 12000000);

      final openAdjAccId = await getAccountIdBySystemKey(db, society.id, 'opening_adjustment');
      final adjRow = tb.rows.firstWhere((r) => r.accountId == openAdjAccId);
      expect(adjRow.closingCreditPaise, 12000000);
    });
  });
}
