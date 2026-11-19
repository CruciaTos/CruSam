import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/domain/backup/backup_service.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late MemberService member;
  late LedgerService ledger;
  late BillingService billing;
  late CollectionService collection;
  late BackupService backup;
  late Society originalSociety;

  setUp(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);
    collection = CollectionService(db, ledgerService: ledger);
    backup = BackupService(db);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Gulmohar Heights CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      pincode: '400053',
      booksStartDate: '2026-04-01',
    ));
    originalSociety = await admin.getSociety(socId);

    // Setup unit type, block, unit, member
    final typeId = await member.createUnitType(originalSociety.id, const UnitTypeDraft(name: '2BHK'));
    final blockId = await member.createBlock(originalSociety.id, const BlockDraft(name: 'A'));
    final unitId = await member.createUnit(originalSociety.id, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: typeId,
      area1Centi: 75000,
    ));

    final personId = await member.createPerson(originalSociety.id, const PersonDraft(
      fullName: 'Aditi Deshmukh',
      email: 'aditi@example.com',
      phone: '9820011223',
    ));

    await member.assignPerson(originalSociety.id, UnitPersonDraft(
      unitId: unitId,
      personId: personId,
      role: 'owner',
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    // Setup charge rule and post a bill run
    final headMaint = (await billing.listChargeHeads(originalSociety.id)).firstWhere((h) => h.name == 'Maintenance Charges');
    await billing.createRule(originalSociety.id, BillingRuleDraft(
      chargeHeadId: headMaint.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 350000, // ₹3,500.00
      effectiveFrom: '2026-04-01',
    ));

    final runId = await billing.createDraftRun(originalSociety.id, const BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    ));
    await billing.postDraftRun(originalSociety.id, runId);

    // Post cash receipt of ₹3,500
    final cashAcc = (await ledger.getAccountByCode(originalSociety.id, '1101'))!;
    await collection.createReceipt(originalSociety.id, ReceiptDraft(
      receiptDate: '2026-04-10',
      unitId: unitId,
      amountPaise: 350000,
      mode: 'cash',
      bankCashAccountId: cashAcc.id,
      payerName: 'Aditi Deshmukh',
    ));
  });

  tearDown(() async {
    await db.close();
  });

  test('Backup exports, inspects preview, and restores as a completely independent society', () async {
    // 1. Export backup bytes
    final backupBytes = await backup.exportSociety(originalSociety.id);
    expect(backupBytes, isNotEmpty);

    // 2. Inspect backup
    final preview = await backup.inspect(backupBytes);
    expect(preview.originalSocietyName, equals('Gulmohar Heights CHS'));
    expect(preview.unitCount, equals(1));
    expect(preview.memberCount, equals(1));
    expect(preview.billCount, equals(1));
    expect(preview.receiptCount, equals(1));
    expect(preview.journalEntryCount, greaterThanOrEqualTo(2));

    // 3. Restore As New Society
    const restoredName = 'Gulmohar Heights CHS (Restored Copy)';
    final newSocId = await backup.restoreAsNewSociety(preview, restoredName);
    expect(newSocId, isNot(equals(originalSociety.id)));

    // 4. Verify new society details
    final restoredSoc = await admin.getSociety(newSocId);
    expect(restoredSoc.name, equals(restoredName));
    expect(restoredSoc.city, equals('Mumbai'));

    // Verify units in restored society
    final restoredUnits = await member.listUnits(newSocId);
    expect(restoredUnits.rows.length, equals(1));
    expect(restoredUnits.rows.first.unitNo, equals('101'));

    // Verify trial balances in original and restored societies match to the exact paise
    final origTb = await ledger.trialBalance(originalSociety.id, '2026-04-01', '2026-04-30');
    final restoredTb = await ledger.trialBalance(newSocId, '2026-04-01', '2026-04-30');

    expect(origTb.isBalanced, isTrue);
    expect(restoredTb.isBalanced, isTrue);
    expect(restoredTb.totalDebitPaise, equals(origTb.totalDebitPaise));
    expect(restoredTb.totalCreditPaise, equals(origTb.totalCreditPaise));

    // 5. Verify source society is completely unmodified
    final originalUnitsAfter = await member.listUnits(originalSociety.id);
    expect(originalUnitsAfter.rows.length, equals(1));
    final origSocAfter = await admin.getSociety(originalSociety.id);
    expect(origSocAfter.name, equals('Gulmohar Heights CHS'));
  });
}
