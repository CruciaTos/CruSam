import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/data/models/expense_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/bank_models.dart';
import 'package:crusam/features/society/domain/bank/bank_service.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/expenses/expense_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/reports/financial_statement_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'package:crusam/features/society/domain/year_end/year_end_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late MemberService member;
  late LedgerService ledger;
  late BillingService billing;
  late CollectionService collection;
  late ExpenseService expense;
  late BankService bank;
  late FinancialStatementService statements;
  late YearEndService yearEnd;

  setUp(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);
    collection = CollectionService(db, ledgerService: ledger);
    expense = ExpenseService(db, ledgerService: ledger);
    bank = BankService(db, ledgerService: ledger);
    statements = FinancialStatementService(db, ledger);
    yearEnd = YearEndService(db, ledger);
  });

  tearDown(() async {
    await db.close();
  });

  test('Full 12-month sample financial year lifecycle from setup to year-end close', () async {
    // 1. Setup Society
    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Palm Meadows Cooperative Housing Society',
      city: 'Navi Mumbai',
      state: 'Maharashtra',
      pincode: '400706',
      booksStartDate: '2026-04-01',
    ));
    final society = await admin.getSociety(socId);
    final fyList = await admin.listFinancialYears(society.id);
    final fy26 = fyList.first;

    // 2. Setup Unit Types, Units and Members
    final type2Bhk = await member.createUnitType(society.id, const UnitTypeDraft(name: '2BHK'));
    final type3Bhk = await member.createUnitType(society.id, const UnitTypeDraft(name: '3BHK'));
    final blockA = await member.createBlock(society.id, const BlockDraft(name: 'Wing A'));

    final u101 = await member.createUnit(society.id, UnitDraft(
      blockId: blockA,
      unitNo: '101',
      unitTypeId: type2Bhk,
      area1Centi: 75000,
    ));
    final u102 = await member.createUnit(society.id, UnitDraft(
      blockId: blockA,
      unitNo: '102',
      unitTypeId: type3Bhk,
      area1Centi: 110000,
    ));

    final p1 = await member.createPerson(society.id, const PersonDraft(fullName: 'Aakash Sharma', email: 'aakash@example.com'));
    final p2 = await member.createPerson(society.id, const PersonDraft(fullName: 'Bina Patel', email: 'bina@example.com'));

    await member.assignPerson(society.id, UnitPersonDraft(
      unitId: u101,
      personId: p1,
      role: 'owner',
      isBillTo: true,
      fromDate: '2026-04-01',
    ));
    await member.assignPerson(society.id, UnitPersonDraft(
      unitId: u102,
      personId: p2,
      role: 'owner',
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    // 3. Opening Balances: Bank ₹5,00,000, General Fund ₹5,00,000
    final bankRowId = await bank.createBankAccount(society.id, const BankAccountDraft(
      bankName: 'State Bank of India',
      accountNumber: 'SBI987654321',
      accountType: 'savings',
    ));
    final bankAcc = (await bank.listBankAccounts(society.id)).firstWhere((b) => b.bankAccount.id == bankRowId);
    final bankAccId = bankAcc.account.id;

    final genFundAcc = (await ledger.getAccountByCode(society.id, '2301'))!;
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(accountId: bankAccId, debitPaise: 50000000, creditPaise: 0, asOfDate: '2026-04-01'),
      OpeningBalanceDraft(accountId: genFundAcc.id, debitPaise: 0, creditPaise: 50000000, asOfDate: '2026-04-01'),
    ]);

    // 4. Setup Billing Rules:
    // Fixed maintenance: ₹3,000 for 2BHK, ₹4,500 for 3BHK
    final headMaint = (await billing.listChargeHeads(society.id)).firstWhere((h) => h.name == 'Maintenance Charges');
    await billing.createRule(society.id, BillingRuleDraft(
      chargeHeadId: headMaint.id,
      unitTypeId: type2Bhk,
      ruleType: 'area_and_fixed',
      fixedPaise: 300000,
      effectiveFrom: '2026-04-01',
    ));
    await billing.createRule(society.id, BillingRuleDraft(
      chargeHeadId: headMaint.id,
      unitTypeId: type3Bhk,
      ruleType: 'area_and_fixed',
      fixedPaise: 450000,
      effectiveFrom: '2026-04-01',
    ));

    // Setup Vendor
    final liftVendorAcc = (await ledger.getAccountByCode(society.id, '4101'))!;
    final vendorId = await expense.saveVendor(society.id, const VendorDraft(
      name: 'Otis Elevators Ltd',
      stateCode: '27',
    ));

    // Setup Fixed Deposit on 2026-04-01: ₹2,00,000 @ 7% p.a.
    final fdId = await bank.openFixedDeposit(society.id, FixedDepositDraft(
      fdNo: 'FD-2026-001',
      bankName: 'State Bank of India',
      startDate: '2026-04-01',
      maturityDate: '2027-03-31',
      principalPaise: 20000000,
      rateBp: 700,
      bankCashAccountId: bankAccId,
    ));
    expect(fdId, isPositive);

    // 5. Run 12 Monthly Billing Cycles (April 2026 through March 2027)
    final months = [
      ('2026-04-01', '2026-04-30', '2026-04-20'),
      ('2026-05-01', '2026-05-31', '2026-05-20'),
      ('2026-06-01', '2026-06-30', '2026-06-20'),
      ('2026-07-01', '2026-07-31', '2026-07-20'),
      ('2026-08-01', '2026-08-31', '2026-08-20'),
      ('2026-09-01', '2026-09-30', '2026-09-20'),
      ('2026-10-01', '2026-10-31', '2026-10-20'),
      ('2026-11-01', '2026-11-30', '2026-11-20'),
      ('2026-12-01', '2026-12-31', '2026-12-20'),
      ('2027-01-01', '2027-01-31', '2027-01-20'),
      ('2027-02-01', '2027-02-28', '2027-02-20'),
      ('2027-03-01', '2027-03-31', '2027-03-20'),
    ];

    for (int i = 0; i < months.length; i++) {
      final (from, to, due) = months[i];

      // A. Post Bill Run
      final runId = await billing.createDraftRun(society.id, BillRunDraft(
        frequency: 'monthly',
        periodFrom: from,
        periodTo: to,
        billDate: from,
        dueDate: due,
      ));
      await billing.postDraftRun(society.id, runId);

      // B. Collect receipts: u101 pays ₹3,000, u102 pays ₹4,500
      final rcptDate = from.replaceRange(8, 10, '10');
      await collection.createReceipt(society.id, ReceiptDraft(
        receiptDate: rcptDate,
        unitId: u101,
        amountPaise: 300000,
        mode: 'neft',
        bankCashAccountId: bankAccId,
        payerName: 'Aakash Sharma',
      ));
      await collection.createReceipt(society.id, ReceiptDraft(
        receiptDate: rcptDate,
        unitId: u102,
        amountPaise: 450000,
        mode: 'neft',
        bankCashAccountId: bankAccId,
        payerName: 'Bina Patel',
      ));

      // C. Monthly Lift Vendor Bill & Payment: ₹2,00,00/month
      await expense.postExpenseBill(society.id, ExpenseBillDraft(
        vendorId: vendorId,
        vendorBillNo: 'OTIS-M${i + 1}',
        billDate: from,
        postDate: from,
        dueDate: due,
        lines: [
          ExpenseLineDraft(
            accountId: liftVendorAcc.id,
            description: 'Monthly Lift Maintenance',
            amountPaise: 200000,
          ),
        ],
      ));

      await expense.postPayment(society.id, VendorPaymentDraft(
        paymentKind: 'against_bills',
        vendorId: vendorId,
        paymentDate: rcptDate,
        amountPaise: 200000,
        mode: 'neft',
        bankCashAccountId: bankAccId,
      ));
    }

    // 6. Quarterly FD Accruals (June 30, Sept 30, Dec 31, March 31): ₹3,500 each quarter
    await bank.postFdTransaction(society.id, FdTransactionDraft(
      fdId: fdId,
      txnType: 'interest_accrued',
      txnDate: '2026-06-30',
      amountPaise: 350000,
      tdsPaise: 0,
    ));
    await bank.postFdTransaction(society.id, FdTransactionDraft(
      fdId: fdId,
      txnType: 'interest_accrued',
      txnDate: '2026-09-30',
      amountPaise: 350000,
      tdsPaise: 0,
    ));
    await bank.postFdTransaction(society.id, FdTransactionDraft(
      fdId: fdId,
      txnType: 'interest_accrued',
      txnDate: '2026-12-31',
      amountPaise: 350000,
      tdsPaise: 0,
    ));
    await bank.postFdTransaction(society.id, FdTransactionDraft(
      fdId: fdId,
      txnType: 'interest_accrued',
      txnDate: '2027-03-31',
      amountPaise: 350000,
      tdsPaise: 0,
    ));

    // 7. Pre-Close Verification
    final tbPreClose = await ledger.trialBalance(society.id, '2026-04-01', '2027-03-31');
    expect(tbPreClose.isBalanced, isTrue);

    final iePreClose = await statements.incomeAndExpenditure(society.id, '2026-04-01', '2027-03-31');
    // Total Income: Maintenance (7,500 * 12 = 90,000) + FD Interest (3,500 * 4 = 14,000) = ₹1,04,000.00 (10,400,000 paise)
    expect(iePreClose.totalIncomePaise, equals(10400000));
    // Total Expenses: Lift Maintenance (2,000 * 12 = 24,000) = ₹24,000.00 (2,400,000 paise)
    expect(iePreClose.totalExpensePaise, equals(2400000));
    // Surplus: 1,04,000 - 24,000 = ₹80,000.00 (8,000,000 paise)
    expect(iePreClose.netSurplusDeficitPaise, equals(8000000));
    expect(iePreClose.isSurplus, isTrue);

    final bsPreClose = await statements.balanceSheet(society.id, '2027-03-31');
    expect(bsPreClose.isBalanced, isTrue);

    // 8. Execute Year-End Close
    final errors = await yearEnd.checkPreconditions(society.id, fy26.id);
    expect(errors, isEmpty);

    final closeEntryId = await yearEnd.closeYear(society.id, fy26.id);
    expect(closeEntryId, isPositive);

    // 9. Post-Close Verification
    final closeEntry = await ledger.entryDetail(society.id, closeEntryId);
    expect(closeEntry, isNotNull);
    final surplusLine = closeEntry.lines.firstWhere((l) => l.accountCode == '2801');
    expect(surplusLine.creditPaise, equals(8000000));

    // FY 2026-27 is closed
    final years = await admin.listFinancialYears(society.id);
    final fyClosed = years.firstWhere((y) => y.id == fy26.id);
    expect(fyClosed.isOpen, isFalse);

    // Next financial year 2027-28 is automatically created and open
    final fyNext = years.firstWhere((y) => y.code == '2027-28');
    expect(fyNext.isOpen, isTrue);

    // Post-close trial balance remains balanced
    final tbPostClose = await ledger.trialBalance(society.id, '2026-04-01', '2027-03-31');
    expect(tbPostClose.isBalanced, isTrue);

    // Post-close Balance Sheet remains balanced
    final bsPostClose = await statements.balanceSheet(society.id, '2027-03-31');
    expect(bsPostClose.isBalanced, isTrue);
    expect(bsPostClose.totalAssetsPaise, equals(bsPostClose.totalLiabilitiesPaise));
  });
}
