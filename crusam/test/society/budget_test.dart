import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/expense_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/expenses/expense_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late ExpenseService expenses;
  late Society society;
  late int fy1Id;
  late int fy2Id;
  late int liftMaintAccId;
  late int securityAccId;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    expenses = ExpenseService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Budget Test CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);

    final fys = await admin.listFinancialYears(society.id);
    fy1Id = fys.first.id;

    // Create next FY 2027-28
    fy2Id = await admin.createNextFinancialYear(society.id);

    final liftAcc = await ledger.getAccountByCode(society.id, '4101');
    liftMaintAccId = liftAcc!.id;

    final secAcc = await ledger.getAccountByCode(society.id, '4102');
    securityAccId = secAcc!.id;
  });

  tearDownAll(() async {
    await db.close();
  });

  test('Save budget rows and copy budget across financial years', () async {
    // 1. Save budget for FY1
    await expenses.saveBudget(society.id, fy1Id, [
      BudgetDraft(accountId: liftMaintAccId, amountPaise: 12000000), // ₹1,20,000.00 / year (₹10,000/mo)
      BudgetDraft(accountId: securityAccId, amountPaise: 24000000),  // ₹2,40,000.00 / year (₹20,000/mo)
    ]);

    final rep1 = await expenses.budgetReport(society.id, fy1Id, '2026-04-30');
    expect(rep1.totalBudgetPaise, equals(36000000));
    final liftRow = rep1.rows.firstWhere((r) => r.accountId == liftMaintAccId);
    expect(liftRow.budgetPaise, equals(12000000));

    // 2. Copy budget from FY1 to FY2
    await expenses.copyBudget(society.id, fy1Id, fy2Id);

    final rep2 = await expenses.budgetReport(society.id, fy2Id, '2027-04-30');
    expect(rep2.totalBudgetPaise, equals(36000000));
    final liftRow2 = rep2.rows.firstWhere((r) => r.accountId == liftMaintAccId);
    expect(liftRow2.budgetPaise, equals(12000000));
  });

  test('Budget variance report calculates actual vs budget variance accurately', () async {
    // Post an actual expense for Lift Maintenance in April: ₹10,000.00
    final vendorId = await expenses.saveVendor(
      society.id,
      const VendorDraft(
        name: 'Alpha Lift Services',
        stateCode: 'MH',
      ),
    );

    await expenses.postExpenseBill(
      society.id,
      ExpenseBillDraft(
        vendorId: vendorId,
        vendorBillNo: 'ALS-001',
        billDate: '2026-04-15',
        postDate: '2026-04-15',
        lines: [
          ExpenseLineDraft(
            accountId: liftMaintAccId,
            description: 'Lift Maintenance April',
            amountPaise: 1000000, // ₹10,000.00
          ),
        ],
      ),
    );

    final rep = await expenses.budgetReport(society.id, fy1Id, '2026-04-30');
    final liftRow = rep.rows.firstWhere((r) => r.accountId == liftMaintAccId);
    expect(liftRow.actualPaise, equals(1000000)); // ₹10,000.00 actual
    expect(liftRow.budgetPaise, equals(12000000));
    expect(liftRow.variancePaise, equals(11000000)); // ₹1,10,000 unspent / favorable

    final secRow = rep.rows.firstWhere((r) => r.accountId == securityAccId);
    expect(secRow.actualPaise, equals(0));
    expect(secRow.budgetPaise, equals(24000000));
  });

  test('Expense comparison across monthly and quarterly periods', () async {
    // Compare monthly
    final monthlyComp = await expenses.expenseComparison(
      society.id,
      ComparisonRequest(fyId: fy1Id, mode: 'monthly'),
    );
    expect(monthlyComp.columns.length, equals(12));
    final aprCol = monthlyComp.columns.first;
    expect(aprCol.accountAmountPaise[liftMaintAccId], equals(1000000));

    // Compare quarterly
    final quarterlyComp = await expenses.expenseComparison(
      society.id,
      ComparisonRequest(fyId: fy1Id, mode: 'quarterly'),
    );
    expect(quarterlyComp.columns.length, equals(4));
    final q1Col = quarterlyComp.columns.first;
    expect(q1Col.accountAmountPaise[liftMaintAccId], equals(1000000));
  });
}
