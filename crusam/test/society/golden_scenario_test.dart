import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/data/models/expense_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/expenses/expense_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'package:crusam/features/society/domain/reports/financial_statement_service.dart';
import 'package:crusam/features/society/domain/year_end/year_end_service.dart';
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

    // 1. Create Society: Sample Heights CHS
    societyId = await admin.createSociety(const SocietyDraft(
      name: 'Sample Heights CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      pincode: '400001',
      booksStartDate: '2026-04-01',
      gstRegistered: false,
    ));

    // Set billing round mode to none
    await admin.setSettings(societyId, {'billing.round_mode': 'none'});
  });

  tearDown(() async {
    await db.close();
  });

  test('Golden Scenario: April Bill Run matches exact accounting specification', () async {
    // 2. Bank Opening balance: Sample Bank ₹50,000.00 debit, General Fund ₹50,000.00 credit
    final groups = await ledger.listGroups(societyId);
    final bankGroup = groups.firstWhere((g) => g.code == '1100');
    final bankAccId = await ledger.createAccount(
      societyId,
      AccountDraft(
        groupId: bankGroup.id,
        code: '1102',
        name: 'Sample Bank',
        accountKind: 'bank',
      ),
    );

    final genFundAcc = (await ledger.getAccountByCode(societyId, '2301'))!;

    await ledger.saveOpeningBalances(societyId, [
      OpeningBalanceDraft(
        accountId: bankAccId,
        debitPaise: 5000000, // ₹50,000.00
        creditPaise: 0,
        asOfDate: '2026-04-01',
        narration: 'Opening bank balance',
      ),
      OpeningBalanceDraft(
        accountId: genFundAcc.id,
        debitPaise: 0,
        creditPaise: 5000000, // ₹50,000.00
        asOfDate: '2026-04-01',
        narration: 'Balancing credit to General Fund',
      ),
    ]);

    // 3. Setup Units
    final resiTypeId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final blockAId = await member.createBlock(societyId, const BlockDraft(name: 'A'));

    // Unit A-101: 650.00 sq ft (65000 centi), owner_occupied
    final u101 = await member.createUnit(societyId, UnitDraft(
      blockId: blockAId,
      unitNo: '101',
      unitTypeId: resiTypeId,
      area1Centi: 65000,
      occupancy: 'owner_occupied',
    ));

    // Unit A-102: 800.00 sq ft (80000 centi), tenanted
    final u102 = await member.createUnit(societyId, UnitDraft(
      blockId: blockAId,
      unitNo: '102',
      unitTypeId: resiTypeId,
      area1Centi: 80000,
      occupancy: 'tenanted',
    ));

    // Members
    final p101 = await member.createPerson(societyId, const PersonDraft(fullName: 'Owner A-101', email: 'a101@example.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: u101,
      personId: p101,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    final p102 = await member.createPerson(societyId, const PersonDraft(fullName: 'Owner A-102', email: 'a102@example.com'));
    await member.assignPerson(societyId, UnitPersonDraft(
      unitId: u102,
      personId: p102,
      role: 'owner',
      isPrimaryContact: true,
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    // 4. Charge Heads and Rules
    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');
    final waterHead = heads.firstWhere((h) => h.name == 'Water Charges');
    final nonOccHead = heads.firstWhere((h) => h.name == 'Non-Occupancy Charges');
    final sinkingHead = heads.firstWhere((h) => h.name == 'Sinking Fund');
    final repairHead = heads.firstWhere((h) => h.name == 'Repair Fund');

    final sinkingHeadId = sinkingHead.id;
    final repairHeadId = repairHead.id;

    // Rules from 2026-04-01:
    // Maintenance: ₹3.00/sq ft (300 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: maintHead.id,
      ruleType: 'area_and_fixed',
      rate1Paise: 300,
      effectiveFrom: '2026-04-01',
    ));

    // Sinking Fund: ₹0.50/sq ft (50 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: sinkingHeadId,
      ruleType: 'area_and_fixed',
      rate1Paise: 50,
      effectiveFrom: '2026-04-01',
    ));

    // Repair Fund: ₹200 fixed (20000 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: repairHeadId,
      ruleType: 'area_and_fixed',
      fixedPaise: 20000,
      effectiveFrom: '2026-04-01',
    ));

    // Water: ₹150 fixed (15000 paise)
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: waterHead.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 15000,
      effectiveFrom: '2026-04-01',
    ));

    // Non-Occupancy: 10.00% (1000 bp) of Maintenance, tenanted only
    await billing.createRule(societyId, BillingRuleDraft(
      chargeHeadId: nonOccHead.id,
      ruleType: 'percent_of_heads',
      percentBp: 1000,
      baseHeadIds: [maintHead.id],
      occupancyFilter: 'tenanted',
      effectiveFrom: '2026-04-01',
    ));

    // 5. Post April Bill Run
    const runDraft = BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    );

    final runId = await billing.createDraftRun(societyId, runDraft);
    await billing.postDraftRun(societyId, runId);

    // Verify Bills
    final bills = await billing.listBills(societyId, runId: runId);
    expect(bills.rows.length, equals(2));

    final billA101 = bills.rows.firstWhere((b) => b.unitId == u101);
    final billA102 = bills.rows.firstWhere((b) => b.unitId == u102);

    // A-101 Total: ₹2,625.00 (262500 paise)
    expect(billA101.totalPaise, equals(262500));
    final full101 = await billing.getBill(billA101.id);
    expect(full101!.lines.length, equals(4));
    expect(full101.lines.firstWhere((l) => l.chargeHeadId == maintHead.id).payablePaise, equals(195000));
    expect(full101.lines.firstWhere((l) => l.chargeHeadId == sinkingHeadId).payablePaise, equals(32500));
    expect(full101.lines.firstWhere((l) => l.chargeHeadId == repairHeadId).payablePaise, equals(20000));
    expect(full101.lines.firstWhere((l) => l.chargeHeadId == waterHead.id).payablePaise, equals(15000));

    // A-102 Total: ₹3,390.00 (339000 paise)
    expect(billA102.totalPaise, equals(339000));
    final full102 = await billing.getBill(billA102.id);
    expect(full102!.lines.length, equals(5));
    expect(full102.lines.firstWhere((l) => l.chargeHeadId == maintHead.id).payablePaise, equals(240000));
    expect(full102.lines.firstWhere((l) => l.chargeHeadId == sinkingHeadId).payablePaise, equals(40000));
    expect(full102.lines.firstWhere((l) => l.chargeHeadId == repairHeadId).payablePaise, equals(20000));
    expect(full102.lines.firstWhere((l) => l.chargeHeadId == waterHead.id).payablePaise, equals(15000));
    expect(full102.lines.firstWhere((l) => l.chargeHeadId == nonOccHead.id).payablePaise, equals(24000));

    // Bill run total = ₹6,015.00 (601500 paise)
    final run = await billing.getBillRun(runId);
    expect(run!.totalPaise, equals(601500));

    // Verify Ledger Trial Balance
    final tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);

    // Check account balances:
    // Members Receivable debit = 601500 paise (₹6,015.00)
    final memRec = tb.rows.firstWhere((r) => r.accountCode == '1201');
    expect(memRec.closingDebitPaise, equals(601500));

    // Maintenance Charges credit = 435000 paise (₹4,350.00)
    final maintAcc = tb.rows.firstWhere((r) => r.accountCode == '3101');
    expect(maintAcc.closingCreditPaise, equals(435000));

    // Sinking Fund credit = 72500 paise (₹725.00)
    final sinkingRow = tb.rows.firstWhere((r) => r.accountCode == '2201');
    expect(sinkingRow.closingCreditPaise, equals(72500));

    // Repair Fund credit = 40000 paise (₹400.00)
    final repairRow = tb.rows.firstWhere((r) => r.accountCode == '2202');
    expect(repairRow.closingCreditPaise, equals(40000));

    // Water Charges credit = 30000 paise (₹300.00)
    final waterAcc = tb.rows.firstWhere((r) => r.accountCode == '3102');
    expect(waterAcc.closingCreditPaise, equals(30000));

    // Non-Occupancy Charges credit = 24000 paise (₹240.00)
    final nonOccAcc = tb.rows.firstWhere((r) => r.accountCode == '3105');
    expect(nonOccAcc.closingCreditPaise, equals(24000));

    // =========================================================
    // PHASE 5: Collections, Interest, and May Bill Run
    // =========================================================
    final collections = CollectionService(db, ledgerService: ledger);

    // 1. Receipt: A-101 pays ₹1,000.00 on 2026-04-15
    final rcpt101 = await collections.createReceipt(
      societyId,
      ReceiptDraft(
        unitId: u101,
        payerName: 'Owner A-101',
        receiptDate: '2026-04-15',
        mode: 'neft',
        bankCashAccountId: bankAccId,
        amountPaise: 100000, // ₹1,000.00
        narration: 'Part payment of April maintenance',
      ),
    );
    expect(rcpt101.status, equals('posted'));
    expect(rcpt101.amountPaise, equals(100000));

    // Trial balance after receipt
    final tbAfterRcpt = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tbAfterRcpt.isBalanced, isTrue);

    // =========================================================
    // PHASE 6: Golden Vendor Bill and Payment (April)
    // Lift Maintenance ₹10,000.00, 18% same-state GST, TDS 2% of subtotal.
    // =========================================================
    final expenses = ExpenseService(db, ledgerService: ledger);
    final vendorId = await expenses.saveVendor(
      societyId,
      const VendorDraft(
        name: 'Apex Elevator Services',
        stateCode: 'MH',
        tdsRateBp: 200,
      ),
    );

    final liftAcc = (await ledger.getAccountByCode(societyId, '4101'))!;

    // Post bill: 10,000 + 18% GST (900 CGST + 900 SGST) - 2% TDS (200) = 11,600 payable
    final billId = await expenses.postExpenseBill(
      societyId,
      ExpenseBillDraft(
        vendorId: vendorId,
        vendorBillNo: 'AES/APR/001',
        billDate: '2026-04-20',
        postDate: '2026-04-20',
        dueDate: '2026-04-30',
        tdsRateBp: 200,
        lines: [
          ExpenseLineDraft(
            accountId: liftAcc.id,
            description: 'Lift Maintenance April',
            amountPaise: 1000000, // ₹10,000.00
            gstRateBp: 1800, // 18%
          ),
        ],
      ),
    );

    final bill = await expenses.getExpenseBill(societyId, billId);
    expect(bill!.payablePaise, equals(1160000));
    expect(bill.tdsPaise, equals(20000));

    // Pay full ₹11,600.00
    await expenses.postPayment(
      societyId,
      VendorPaymentDraft(
        paymentKind: 'against_bills',
        vendorId: vendorId,
        paymentDate: '2026-04-22',
        mode: 'neft',
        bankCashAccountId: bankAccId,
        amountPaise: 1160000,
        instrumentNo: 'NEFT-AES-APR',
      ),
    );

    // Verify Golden April Trial Balance Total: exactly ₹56,215.00 (5,621,500 paise)
    final tbAprilGolden = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tbAprilGolden.isBalanced, isTrue);
    expect(tbAprilGolden.totalClosingDebitPaise, equals(5621500));
    expect(tbAprilGolden.totalClosingCreditPaise, equals(5621500));

    // Verify individual account balances in April Golden Trial Balance:
    // Assets:
    // Bank 39,400.00; Members Receivable 5,015.00; Input CGST 900.00; Input SGST 900.00; Lift Maintenance 10,000.00
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '1102').closingDebitPaise, equals(3940000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '1201').closingDebitPaise, equals(501500));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '1601').closingDebitPaise, equals(90000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '1602').closingDebitPaise, equals(90000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '4101').closingDebitPaise, equals(1000000));

    // Liabilities and Funds:
    // General Fund 50,000.00; Sinking Fund 725.00; Repair Fund 400.00; TDS Payable 200.00
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '2301').closingCreditPaise, equals(5000000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '2201').closingCreditPaise, equals(72500));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '2202').closingCreditPaise, equals(40000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '2604').closingCreditPaise, equals(20000));

    // Income:
    // Maintenance Charges 4,350.00; Water Charges 300.00; Non-Occupancy Charges 240.00
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '3101').closingCreditPaise, equals(435000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '3102').closingCreditPaise, equals(30000));
    expect(tbAprilGolden.rows.firstWhere((r) => r.accountCode == '3105').closingCreditPaise, equals(24000));

    // 2. Configure Late Payment Interest & Rupee Rounding
    await admin.setSettings(societyId, {
      'interest.enabled': '1',
      'interest.start_date': '2026-04-01',
      'interest.grace_days': '0',
      'interest.rate_bp': '1200', // 12.00% p.a.
      'billing.round_mode': 'rupee',
    });

    // 3. Post May Bill Run
    const mayRunDraft = BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-05-01',
      periodTo: '2026-05-31',
      billDate: '2026-05-01',
      dueDate: '2026-05-20',
    );

    final mayRunId = await billing.createDraftRun(societyId, mayRunDraft);
    await billing.postDraftRun(societyId, mayRunId);

    final mayBills = await billing.listBills(societyId, runId: mayRunId);
    expect(mayBills.rows.length, equals(2));

    final mayBillA101 = mayBills.rows.firstWhere((b) => b.unitId == u101);
    final mayBillA102 = mayBills.rows.firstWhere((b) => b.unitId == u102);

    final fullMay101 = await billing.getBill(mayBillA101.id);
    final fullMay102 = await billing.getBill(mayBillA102.id);

    // Check Late Payment Interest
    // A-101: ₹4.85 (485 paise)
    final a101InterestLine = fullMay101!.lines.firstWhere((l) => l.lineKind == 'interest');
    expect(a101InterestLine.amountPaise, equals(485));

    // A-102: ₹10.65 (1065 paise)
    final a102InterestLine = fullMay102!.lines.firstWhere((l) => l.lineKind == 'interest');
    expect(a102InterestLine.amountPaise, equals(1065));

    // Check Rupee Rounding on A-101:
    // Raw total: 1950.00 + 325.00 + 200.00 + 150.00 + 4.85 = 2629.85 (262985 paise)
    // Bill total rounded to ₹2,630.00 (263000 paise)
    // Round-off credit = 15 paise (₹0.15 credit)
    expect(mayBillA101.totalPaise, equals(263000));
    expect(mayBillA101.roundOffPaise, equals(15));

    // Final Trial Balance verified
    final tbMay = await ledger.trialBalance(societyId, '2026-04-01', '2026-05-31');
    expect(tbMay.isBalanced, isTrue);
  });

  test('Golden Scenario: Year-End Close deficit ₹5,110.00 and Balance Sheet total ₹46,215.00', () async {
    final statements = FinancialStatementService(db, ledger);
    final yearEnd = YearEndService(db, ledger);
    final collections = CollectionService(db, ledgerService: ledger);
    final expenses = ExpenseService(db, ledgerService: ledger);

    // Bank Opening balance: Sample Bank ₹50,000.00 debit, General Fund ₹50,000.00 credit
    final groups = await ledger.listGroups(societyId);
    final bankGroup = groups.firstWhere((g) => g.code == '1100');
    final bankAccId = await ledger.createAccount(
      societyId,
      AccountDraft(
        groupId: bankGroup.id,
        code: '1102',
        name: 'Sample Bank',
        accountKind: 'bank',
      ),
    );
    final genFundAcc = (await ledger.getAccountByCode(societyId, '2301'))!;
    await ledger.saveOpeningBalances(societyId, [
      OpeningBalanceDraft(
        accountId: bankAccId,
        debitPaise: 5000000,
        creditPaise: 0,
        asOfDate: '2026-04-01',
      ),
      OpeningBalanceDraft(
        accountId: genFundAcc.id,
        debitPaise: 0,
        creditPaise: 5000000,
        asOfDate: '2026-04-01',
      ),
    ]);

    // Units
    final resiTypeId = await member.createUnitType(societyId, const UnitTypeDraft(name: 'Residential', sortOrder: 1));
    final blockAId = await member.createBlock(societyId, const BlockDraft(name: 'A'));
    final u101 = await member.createUnit(societyId, UnitDraft(
      blockId: blockAId,
      unitNo: '101',
      unitTypeId: resiTypeId,
      area1Centi: 65000,
      occupancy: 'owner_occupied',
    ));
    final u102 = await member.createUnit(societyId, UnitDraft(
      blockId: blockAId,
      unitNo: '102',
      unitTypeId: resiTypeId,
      area1Centi: 80000,
      occupancy: 'tenanted',
    ));
    final p101 = await member.createPerson(societyId, const PersonDraft(fullName: 'Owner A-101', email: 'a101@example.com'));
    await member.assignPerson(societyId, UnitPersonDraft(unitId: u101, personId: p101, role: 'owner', isPrimaryContact: true, isBillTo: true, fromDate: '2026-04-01'));
    final p102 = await member.createPerson(societyId, const PersonDraft(fullName: 'Owner A-102', email: 'a102@example.com'));
    await member.assignPerson(societyId, UnitPersonDraft(unitId: u102, personId: p102, role: 'owner', isPrimaryContact: true, isBillTo: true, fromDate: '2026-04-01'));

    // Rules
    final heads = await billing.listChargeHeads(societyId);
    final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');
    final waterHead = heads.firstWhere((h) => h.name == 'Water Charges');
    final nonOccHead = heads.firstWhere((h) => h.name == 'Non-Occupancy Charges');
    final sinkingHead = heads.firstWhere((h) => h.name == 'Sinking Fund');
    final repairHead = heads.firstWhere((h) => h.name == 'Repair Fund');

    await billing.createRule(societyId, BillingRuleDraft(chargeHeadId: maintHead.id, ruleType: 'area_and_fixed', rate1Paise: 300, effectiveFrom: '2026-04-01'));
    await billing.createRule(societyId, BillingRuleDraft(chargeHeadId: sinkingHead.id, ruleType: 'area_and_fixed', rate1Paise: 50, effectiveFrom: '2026-04-01'));
    await billing.createRule(societyId, BillingRuleDraft(chargeHeadId: repairHead.id, ruleType: 'area_and_fixed', fixedPaise: 20000, effectiveFrom: '2026-04-01'));
    await billing.createRule(societyId, BillingRuleDraft(chargeHeadId: waterHead.id, ruleType: 'area_and_fixed', fixedPaise: 15000, effectiveFrom: '2026-04-01'));
    await billing.createRule(societyId, BillingRuleDraft(chargeHeadId: nonOccHead.id, ruleType: 'percent_of_heads', percentBp: 1000, baseHeadIds: [maintHead.id], occupancyFilter: 'tenanted', effectiveFrom: '2026-04-01'));

    // April Bill Run
    final runId = await billing.createDraftRun(societyId, const BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    ));
    await billing.postDraftRun(societyId, runId);

    // A-101 Receipt ₹1,000.00
    await collections.createReceipt(societyId, ReceiptDraft(
      unitId: u101,
      payerName: 'Owner A-101',
      receiptDate: '2026-04-15',
      mode: 'neft',
      bankCashAccountId: bankAccId,
      amountPaise: 100000,
    ));

    // Vendor Bill: Lift Maintenance ₹10,000 + 18% GST ₹1,800 - TDS ₹200 = ₹11,600
    final vendorId = await expenses.saveVendor(societyId, const VendorDraft(
      name: 'Apex Elevator Services',
      stateCode: 'MH',
      tdsRateBp: 200,
    ));
    final liftExpAcc = (await ledger.getAccountByCode(societyId, '4101'))!;
    await expenses.postExpenseBill(societyId, ExpenseBillDraft(
      vendorId: vendorId,
      vendorBillNo: 'AES/APR/001',
      billDate: '2026-04-20',
      postDate: '2026-04-20',
      dueDate: '2026-04-30',
      tdsRateBp: 200,
      lines: [ExpenseLineDraft(accountId: liftExpAcc.id, description: 'Lift Maintenance April', amountPaise: 1000000, gstRateBp: 1800)],
    ));
    await expenses.postPayment(societyId, VendorPaymentDraft(
      paymentKind: 'against_bills',
      vendorId: vendorId,
      paymentDate: '2026-04-22',
      mode: 'neft',
      bankCashAccountId: bankAccId,
      amountPaise: 1160000,
    ));

    // Verify trial balance is ₹56,215.00 before close
    var tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
    expect(tb.totalClosingDebitPaise, equals(5621500));

    // Verify Income & Expenditure: Net Deficit = ₹5,110.00
    final ie = await statements.incomeAndExpenditure(societyId, '2026-04-01', '2027-03-31');
    expect(ie.totalIncomePaise, equals(489000)); // 4350 + 300 + 240 = ₹4,890.00
    expect(ie.totalExpensePaise, equals(1000000)); // ₹10,000.00
    expect(ie.netSurplusDeficitPaise, equals(-511000)); // Deficit ₹5,110.00

    // Year-End Close for FY 2026-27
    final years = await admin.listFinancialYears(societyId);
    final fy26 = years.first;
    final closeEntryId = await yearEnd.closeYear(societyId, fy26.id);
    expect(closeEntryId, isPositive);

    // Verify close entry lines:
    final closeEntry = await ledger.entryDetail(societyId, closeEntryId);
    expect(closeEntry, isNotNull);
    // Maintenance Charges debit 4,350.00
    expect(closeEntry.lines.firstWhere((l) => l.accountCode == '3101').debitPaise, equals(435000));
    // Water Charges debit 300.00
    expect(closeEntry.lines.firstWhere((l) => l.accountCode == '3102').debitPaise, equals(30000));
    // Non-Occupancy Charges debit 240.00
    expect(closeEntry.lines.firstWhere((l) => l.accountCode == '3105').debitPaise, equals(24000));
    // Lift Maintenance credit 10,000.00
    expect(closeEntry.lines.firstWhere((l) => l.accountCode == '4101').creditPaise, equals(1000000));
    // Income and Expenditure Account (2801) debit 5,110.00 (Deficit)
    expect(closeEntry.lines.firstWhere((l) => l.accountCode == '2801').debitPaise, equals(511000));

    // Verify Balance Sheet after close totals exactly ₹46,215.00 (4,621,500 paise):
    final bs = await statements.balanceSheet(societyId, '2027-03-31');
    expect(bs.isBalanced, isTrue);
    expect(bs.totalAssetsPaise, equals(4621500));
    expect(bs.totalLiabilitiesPaise, equals(4621500));

    // Verify Asset items:
    // Bank 39,400.00; Members Receivable 5,015.00; Input GST 1,800.00
    final assetLines = bs.assetGroups.expand((g) => g.lines).toList();
    expect(assetLines.firstWhere((l) => l.code == '1102').amountPaise, equals(3940000));
    expect(assetLines.firstWhere((l) => l.code == '1201').amountPaise, equals(501500));
    expect(assetLines.firstWhere((l) => l.code == '1601').amountPaise, equals(90000)); // Input CGST
    expect(assetLines.firstWhere((l) => l.code == '1602').amountPaise, equals(90000)); // Input SGST

    // Verify Liabilities & Funds items:
    // General Fund 50,000.00; Sinking Fund 725.00; Repair Fund 400.00; TDS Payable 200.00; I&E deficit (5,110.00)
    final liabLines = bs.liabilityGroups.expand((g) => g.lines).toList();
    expect(liabLines.firstWhere((l) => l.code == '2301').amountPaise, equals(5000000));
    expect(liabLines.firstWhere((l) => l.code == '2201').amountPaise, equals(72500));
    expect(liabLines.firstWhere((l) => l.code == '2202').amountPaise, equals(40000));
    expect(liabLines.firstWhere((l) => l.code == '2604').amountPaise, equals(20000));
    expect(liabLines.firstWhere((l) => l.code == '2801').amountPaise, equals(-511000)); // Deficit
  });
}
