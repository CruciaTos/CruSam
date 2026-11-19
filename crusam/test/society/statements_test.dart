import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/reports/financial_statement_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  setUpAll(initTestSupport);

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late MemberService member;
  late FinancialStatementService statements;
  late Society society;

  setUp(() async {
    db = await createTestDatabase();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    statements = FinancialStatementService(db, ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Statements Test Society',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411038',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);
  });

  tearDown(() async {
    await db.close();
  });

  test('Financial Statements calculate Income & Expenditure, Receipts & Payments and Balance Sheet', () async {
    final bankAcc = (await ledger.getAccountByCode(society.id, '1101'))!; // Cash in Hand
    final memberRecAcc = (await ledger.getAccountByCode(society.id, '1201'))!;
    final maintAcc = (await ledger.getAccountByCode(society.id, '3101'))!;
    final repairsAcc = (await ledger.getAccountByCode(society.id, '4102'))!;
    final genFundAcc = (await ledger.getAccountByCode(society.id, '2301'))!;

    // Opening Balance: Bank/Cash ₹10,000, General Fund ₹10,000
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(
        accountId: bankAcc.id,
        debitPaise: 1000000,
        creditPaise: 0,
        asOfDate: '2026-04-01',
      ),
      OpeningBalanceDraft(
        accountId: genFundAcc.id,
        debitPaise: 0,
        creditPaise: 1000000,
        asOfDate: '2026-04-01',
      ),
    ]);

    // Setup unit
    final tId = await member.createUnitType(society.id, const UnitTypeDraft(name: 'Flat'));
    final bId = await member.createBlock(society.id, const BlockDraft(name: 'A'));
    final unitId = await member.createUnit(society.id, UnitDraft(blockId: bId, unitNo: '101', unitTypeId: tId));

    // Transaction 1: Bill Maintenance ₹5,000 to Member Receivable
    await db.transaction((txn) => ledger.post(txn, JournalDraft(
      societyId: society.id,
      entryDate: '2026-04-05',
      sourceType: 'bill',
      narration: 'Maintenance Bill',
      lines: [
        JournalLineDraft(accountId: memberRecAcc.id, debitPaise: 500000, creditPaise: 0, unitId: unitId),
        JournalLineDraft(accountId: maintAcc.id, debitPaise: 0, creditPaise: 500000),
      ],
    )));

    // Transaction 2: Cash Receipt ₹3,000 from Member
    await db.transaction((txn) => ledger.post(txn, JournalDraft(
      societyId: society.id,
      entryDate: '2026-04-10',
      sourceType: 'receipt',
      narration: 'Cash Collection',
      lines: [
        JournalLineDraft(accountId: bankAcc.id, debitPaise: 300000, creditPaise: 0),
        JournalLineDraft(accountId: memberRecAcc.id, debitPaise: 0, creditPaise: 300000, unitId: unitId),
      ],
    )));

    // Transaction 3: Repairs expense ₹2,000 paid by Cash
    await db.transaction((txn) => ledger.post(txn, JournalDraft(
      societyId: society.id,
      entryDate: '2026-04-15',
      sourceType: 'payment',
      narration: 'Building Repair Payment',
      lines: [
        JournalLineDraft(accountId: repairsAcc.id, debitPaise: 200000, creditPaise: 0),
        JournalLineDraft(accountId: bankAcc.id, debitPaise: 0, creditPaise: 200000),
      ],
    )));

    // 1. Income and Expenditure Statement
    final ie = await statements.incomeAndExpenditure(society.id, '2026-04-01', '2026-04-30');
    expect(ie.totalIncomePaise, equals(500000)); // ₹5,000.00
    expect(ie.totalExpensePaise, equals(200000)); // ₹2,000.00
    expect(ie.netSurplusDeficitPaise, equals(300000)); // Surplus ₹3,000.00
    expect(ie.isSurplus, isTrue);

    // 2. Receipts and Payments Statement
    final rp = await statements.receiptsAndPayments(society.id, '2026-04-01', '2026-04-30');
    expect(rp.openingBalancePaise, equals(1000000)); // ₹10,000.00
    expect(rp.totalReceiptsPaise, equals(300000)); // ₹3,000.00
    expect(rp.totalPaymentsPaise, equals(200000)); // ₹2,000.00
    expect(rp.closingBalancePaise, equals(1100000)); // ₹11,000.00 (10,000 + 3,000 - 2,000)

    // 3. Balance Sheet Statement (Pre-close includes current period surplus)
    final bs = await statements.balanceSheet(society.id, '2026-04-30');
    expect(bs.isBalanced, isTrue);
    // Assets: Cash 11,000 + Members Receivable 2,000 = ₹13,000.00
    expect(bs.totalAssetsPaise, equals(1300000));
    // Liabilities: General Fund 10,000 + Current Surplus 3,000 = ₹13,000.00
    expect(bs.totalLiabilitiesPaise, equals(1300000));
  });

  test('Balance Sheet separates Member Advances and Vendor Advances without netting', () async {
    final typeId = await member.createUnitType(society.id, const UnitTypeDraft(name: 'Flat'));
    final blkId = await member.createBlock(society.id, const BlockDraft(name: 'A'));
    final u1 = await member.createUnit(society.id, UnitDraft(blockId: blkId, unitNo: '101', unitTypeId: typeId));
    final u2 = await member.createUnit(society.id, UnitDraft(blockId: blkId, unitNo: '102', unitTypeId: typeId));

    final memberRecAcc = (await ledger.getAccountByCode(society.id, '1201'))!;
    final cashAcc = (await ledger.getAccountByCode(society.id, '1101'))!;

    // u1 owes ₹5,000 (Debit on 1201 with unitId u1)
    // u2 has an advance of ₹2,000 (Credit on 1201 with unitId u2)
    await db.transaction((txn) async {
      await ledger.post(txn, JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-05',
        sourceType: 'bill',
        narration: 'Bill for u1',
        lines: [
          JournalLineDraft(accountId: memberRecAcc.id, debitPaise: 500000, creditPaise: 0, unitId: u1),
          JournalLineDraft(accountId: cashAcc.id, debitPaise: 0, creditPaise: 500000),
        ],
      ));
      await ledger.post(txn, JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-06',
        sourceType: 'receipt',
        narration: 'Advance from u2',
        lines: [
          JournalLineDraft(accountId: cashAcc.id, debitPaise: 200000, creditPaise: 0),
          JournalLineDraft(accountId: memberRecAcc.id, debitPaise: 0, creditPaise: 200000, unitId: u2),
        ],
      ));
    });

    final bs = await statements.balanceSheet(society.id, '2026-04-30');

    // Rule: u1 debit ₹5,000 shows under Assets (Members Receivable)
    final assetsGroup = bs.assetGroups.expand((g) => g.lines);
    final recLine = assetsGroup.firstWhere((l) => l.code == '1201');
    expect(recLine.amountPaise, equals(500000));

    // Rule: u2 credit ₹2,000 shows under Liabilities (Advances from Members)
    final liabGroup = bs.liabilityGroups.expand((g) => g.lines);
    final advLine = liabGroup.firstWhere((l) => l.code == '2403');
    expect(advLine.amountPaise, equals(200000));
  });
}
