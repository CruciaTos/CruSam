import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  setUpAll(initTestSupport);

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late MemberService member;
  late BillingService billing;
  late int societyId;

  setUp(() async {
    db = await createTestDatabase();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);

    societyId = await admin.createSociety(const SocietyDraft(
      name: 'Billing Test Society',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411001',
      booksStartDate: '2026-04-01',
      gstRegistered: false,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  test('Unit-type specific rule beats general rule', () async {
    // Create unit types: Resi and Comm
    final resiId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final commId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Commercial', sortOrder: 2));

    // Create block and units
    final blockId = await member.createBlock(societyId, const BlockDraft(name: 'A'));
    final u1 = await member.createUnit(societyId, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: resiId,
      area1Centi: 100000, // 1000 sq ft
      occupancy: 'owner_occupied',
    ));
    final u2 = await member.createUnit(societyId, UnitDraft(
      blockId: blockId,
      unitNo: '102',
      unitTypeId: commId,
      area1Centi: 100000, // 1000 sq ft
      occupancy: 'owner_occupied',
    ));

    // Assign members as bill-to
    final p1 = await member.createPerson(societyId, const PersonDraft(fullName: 'Person 1', email: 'p1@test.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: u1,
      personId: p1,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    final p2 = await member.createPerson(societyId, const PersonDraft(fullName: 'Person 2', email: 'p2@test.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: u2,
      personId: p2,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    // Get Maintenance charge head (seeded)
    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

    // Rule 1: General rule: ₹3.00/sq ft (300 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      ruleType: 'area_and_fixed',
      rate1Paise: 300,
      effectiveFrom: '2026-04-01',
    ));

    // Rule 2: Commercial specific rule: ₹5.00/sq ft (500 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      unitTypeId: commId,
      ruleType: 'area_and_fixed',
      rate1Paise: 500,
      effectiveFrom: '2026-04-01',
    ));

    // Run preview for April
    final preview = await billing.previewBillRun(societyId, const BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    ));

    expect(preview.blockers, isEmpty);
    expect(preview.calculatedBills.length, equals(2));

    final b1 = preview.calculatedBills.firstWhere((b) => b.unitId == u1);
    final b2 = preview.calculatedBills.firstWhere((b) => b.unitId == u2);

    // Resi uses general rule: 1000 sq ft * 3.00 = ₹3,000.00 (300000 paise)
    expect(b1.totalPaise, equals(300000));

    // Comm uses specific rule: 1000 sq ft * 5.00 = ₹5,000.00 (500000 paise)
    expect(b2.totalPaise, equals(500000));
  });

  test('Quarterly bill multiplies monthly rate by 3', () async {
    final typeId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final blockId = await member.createBlock(societyId, const BlockDraft(name: 'A'));
    final uId = await member.createUnit(societyId, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: typeId,
      area1Centi: 100000,
      occupancy: 'owner_occupied',
    ));

    final pId = await member.createPerson(societyId, const PersonDraft(fullName: 'Person 1', email: 'p1@test.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: uId,
      personId: pId,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 100000, // ₹1,000/month fixed
      effectiveFrom: '2026-04-01',
    ));

    // Quarterly run (3 months)
    final preview = await billing.previewBillRun(societyId, const BillRunDraft(
      frequency: 'quarterly',
      periodFrom: '2026-04-01',
      periodTo: '2026-06-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    ));

    expect(preview.calculatedBills.first.totalPaise, equals(300000)); // 3 * ₹1,000 = ₹3,000.00
  });

  test('Missing bill-to person blocks run and duplicate run is blocked', () async {
    final typeId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final blockId = await member.createBlock(societyId, const BlockDraft(name: 'A'));
    await member.createUnit(societyId, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: typeId,
      area1Centi: 50000,
      occupancy: 'owner_occupied',
    ));
    // Notice: NO person assigned as bill-to!

    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 50000,
      effectiveFrom: '2026-04-01',
    ));

    const draft = BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    );

    // Preview reports blocker
    final preview = await billing.previewBillRun(societyId, draft);
    expect(preview.blockers.isNotEmpty, isTrue);

    // Creating draft run directly throws
    expect(() => billing.createDraftRun(societyId, draft), throwsA(isA<SocietyException>()));
  });

  test('Bill posting matches double entry journal totals and reverses cleanly', () async {
    final typeId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final blockId = await member.createBlock(societyId, const BlockDraft(name: 'A'));
    final uId = await member.createUnit(societyId, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: typeId,
      area1Centi: 100000,
      occupancy: 'owner_occupied',
    ));

    final pId = await member.createPerson(societyId, const PersonDraft(fullName: 'Person 1', email: 'p1@test.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: uId,
      personId: pId,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 250000, // ₹2,500.00
      effectiveFrom: '2026-04-01',
    ));

    const draft = BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    );

    final runId = await billing.createDraftRun(societyId, draft);
    await billing.postDraftRun(societyId, runId);

    // Verify bill
    final bills = await billing.listBills(societyId, runId: runId);
    expect(bills.rows.length, equals(1));
    final postedBill = bills.rows.first;
    expect(postedBill.status, equals('posted'));
    expect(postedBill.totalPaise, equals(250000));
    expect(postedBill.billNo, isNotNull);
    expect(postedBill.billNo!.startsWith('BILL/2026-27/'), isTrue);

    // Verify trial balance: Members Receivable Debit = 2,500.00, Maintenance Credit = 2,500.00
    final tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);
    expect(tb.totalDebitPaise, equals(250000));
    expect(tb.totalCreditPaise, equals(250000));

    // Duplicate run blocked
    expect(() => billing.createDraftRun(societyId, draft), throwsA(isA<SocietyException>()));

    // Reverse bill
    await billing.reverseBill(societyId, postedBill.id, '2026-04-10', 'Correction');
    final revBill = await billing.getBill(postedBill.id);
    expect(revBill!.status, equals('reversed'));
    expect(revBill.reversalReason, equals('Correction'));

    // Trial balance nets to zero after reversal
    final tbAfter = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tbAfter.isBalanced, isTrue);
    expect(tbAfter.totalDebitPaise, equals(500000));
    expect(tbAfter.totalCreditPaise, equals(500000));
  });
}
