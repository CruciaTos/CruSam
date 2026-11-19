import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/expense_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
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
  late int bankAccId;
  late int liftMaintAccId;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    expenses = ExpenseService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Shree Ganesh CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
      gstin: '27AABCS1234F1Z5',
      gstRegistered: true,
    ));
    society = await admin.getSociety(socId);

    // Get or create Bank Account
    final groups = await ledger.listGroups(society.id);
    final bankGroup = groups.firstWhere((g) => g.code == '1100');
    bankAccId = await ledger.createAccount(
      society.id,
      AccountDraft(
        groupId: bankGroup.id,
        code: '1102',
        name: 'Society Current Bank',
        accountKind: 'bank',
      ),
    );

    // Initial Bank Balance ₹1,00,000.00
    final genFund = (await ledger.getAccountByCode(society.id, '2301'))!;
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(
        accountId: bankAccId,
        debitPaise: 10000000,
        creditPaise: 0,
        asOfDate: '2026-04-01',
      ),
      OpeningBalanceDraft(
        accountId: genFund.id,
        debitPaise: 0,
        creditPaise: 10000000,
        asOfDate: '2026-04-01',
      ),
    ]);

    // Lift Maintenance expense account
    final liftAcc = await ledger.getAccountByCode(society.id, '4101');
    liftMaintAccId = liftAcc!.id;
  });

  tearDownAll(() async {
    await db.close();
  });

  test('Vendor creation and list', () async {
    final vId = await expenses.saveVendor(
      society.id,
      const VendorDraft(
        name: 'Otis Elevator Services',
        contactName: 'Sanjay Deshmukh',
        phone: '9820011223',
        email: 'otis@example.com',
        pan: 'AABCO1234E',
        gstin: '27AABCO1234E1Z1',
        stateCode: 'MH',
        tdsRateBp: 200,
      ),
    );
    expect(vId, isPositive);

    final vendors = await expenses.listVendors(society.id);
    expect(vendors.any((v) => v.vendor.name == 'Otis Elevator Services'), isTrue);
  });

  test('Same-state Expense Bill calculates GST and TDS, balances journal', () async {
    final vendors = await expenses.listVendors(society.id);
    final vendor = vendors.firstWhere((v) => v.vendor.name == 'Otis Elevator Services').vendor;

    // Bill: ₹10,000 + 18% same-state GST (9% CGST, 9% SGST) - 2% TDS (₹200) = ₹11,600 payable
    final billId = await expenses.postExpenseBill(
      society.id,
      ExpenseBillDraft(
        vendorId: vendor.id,
        vendorBillNo: 'OTIS/2026/001',
        billDate: '2026-04-10',
        postDate: '2026-04-10',
        dueDate: '2026-04-30',
        tdsRateBp: 200, // 2%
        lines: [
          ExpenseLineDraft(
            accountId: liftMaintAccId,
            description: 'Lift AMC April 2026',
            amountPaise: 1000000, // ₹10,000.00
            gstRateBp: 1800, // 18%
          ),
        ],
      ),
    );

    final bill = await expenses.getExpenseBill(society.id, billId);
    expect(bill, isNotNull);
    expect(bill!.subtotalPaise, equals(1000000));
    expect(bill.cgstPaise, equals(90000));
    expect(bill.sgstPaise, equals(90000));
    expect(bill.igstPaise, equals(0));
    expect(bill.taxTotalPaise, equals(180000));
    expect(bill.tdsPaise, equals(20000));
    expect(bill.totalPaise, equals(1180000));
    expect(bill.payablePaise, equals(1160000));
    expect(bill.paidPaise, equals(0));

    // Verify Trial Balance
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);

    // Lift Maintenance: 10,000 debit
    final liftRow = tb.rows.firstWhere((r) => r.accountCode == '4101');
    expect(liftRow.closingDebitPaise, equals(1000000));

    // Input CGST: 900 debit
    final cgstRow = tb.rows.firstWhere((r) => r.accountCode == '1601');
    expect(cgstRow.closingDebitPaise, equals(90000));

    // Input SGST: 900 debit
    final sgstRow = tb.rows.firstWhere((r) => r.accountCode == '1602');
    expect(sgstRow.closingDebitPaise, equals(90000));

    // Vendors Payable: 11,600 credit
    final vpRow = tb.rows.firstWhere((r) => r.accountCode == '2501');
    expect(vpRow.closingCreditPaise, equals(1160000));

    // TDS Payable: 200 credit
    final tdsRow = tb.rows.firstWhere((r) => r.accountCode == '2604');
    expect(tdsRow.closingCreditPaise, equals(20000));
  });

  test('Duplicate vendor bill number is rejected', () async {
    final vendors = await expenses.listVendors(society.id);
    final vendor = vendors.firstWhere((v) => v.vendor.name == 'Otis Elevator Services').vendor;

    expect(
      () => expenses.postExpenseBill(
        society.id,
        ExpenseBillDraft(
          vendorId: vendor.id,
          vendorBillNo: 'OTIS/2026/001', // Duplicate!
          billDate: '2026-04-15',
          postDate: '2026-04-15',
          lines: [
            ExpenseLineDraft(
              accountId: liftMaintAccId,
              description: 'Duplicate bill attempt',
              amountPaise: 500000,
            ),
          ],
        ),
      ),
      throwsA(isA<SocietyException>()),
    );
  });

  test('Inter-state Expense Bill applies IGST', () async {
    final vId = await expenses.saveVendor(
      society.id,
      const VendorDraft(
        name: 'Delhi Security Systems',
        pan: 'DELHS1234D',
        gstin: '07DELHS1234D1Z2',
        stateCode: 'DL', // Different state from MH
      ),
    );

    final securityAcc = (await ledger.getAccountByCode(society.id, '4102'))!;

    final billId = await expenses.postExpenseBill(
      society.id,
      ExpenseBillDraft(
        vendorId: vId,
        vendorBillNo: 'DSS/2026/101',
        billDate: '2026-04-12',
        postDate: '2026-04-12',
        lines: [
          ExpenseLineDraft(
            accountId: securityAcc.id,
            description: 'CCTV Hardware',
            amountPaise: 2000000, // ₹20,000.00
            gstRateBp: 1800, // 18% IGST = ₹3,600.00
          ),
        ],
      ),
    );

    final bill = await expenses.getExpenseBill(society.id, billId);
    expect(bill!.cgstPaise, equals(0));
    expect(bill.sgstPaise, equals(0));
    expect(bill.igstPaise, equals(360000));
    expect(bill.payablePaise, equals(2360000));

    // Verify Input IGST account
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);
    final igstRow = tb.rows.firstWhere((r) => r.accountCode == '1603');
    expect(igstRow.closingDebitPaise, equals(360000));
  });

  test('Vendor Payment clears payable and ties vendor balances to ledger', () async {
    final vendors = await expenses.listVendors(society.id);
    final otis = vendors.firstWhere((v) => v.vendor.name == 'Otis Elevator Services').vendor;

    // Check open bills
    final openBills = await expenses.getOpenExpenseBills(society.id, otis.id);
    expect(openBills.length, equals(1));
    expect(openBills.first.duePaise, equals(1160000));

    // Pay full ₹11,600.00
    final pmtId = await expenses.postPayment(
      society.id,
      VendorPaymentDraft(
        paymentKind: 'against_bills',
        vendorId: otis.id,
        paymentDate: '2026-04-20',
        mode: 'neft',
        bankCashAccountId: bankAccId,
        amountPaise: 1160000,
        instrumentNo: 'NEFT-OTIS-0420',
        narration: 'Payment for April Lift AMC',
      ),
    );
    expect(pmtId, isPositive);

    // Bill should now be paid
    final billAfter = await expenses.getExpenseBill(society.id, openBills.first.bill.id);
    expect(billAfter!.paidPaise, equals(1160000));
    expect(billAfter.balancePaise, equals(0));
    expect(billAfter.status, equals('posted'));

    // Vendor statement check
    final stmt = await expenses.vendorStatement(society.id, otis.id, '2026-04-01', '2026-04-30');
    expect(stmt.closingBalancePaise, equals(0));

    // Over-payment: posts excess to advance
    final advPmtId = await expenses.postPayment(
      society.id,
      VendorPaymentDraft(
        paymentKind: 'against_bills',
        vendorId: otis.id,
        paymentDate: '2026-04-21',
        mode: 'neft',
        bankCashAccountId: bankAccId,
        amountPaise: 500000, // ₹5,000.00 advance
        narration: 'Advance payment',
      ),
    );
    expect(advPmtId, isPositive);

    // Verify Vendor Advances account 1701
    final tbAdv = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tbAdv.isBalanced, isTrue);
    final advRow = tbAdv.rows.firstWhere((r) => r.accountCode == '1701');
    expect(advRow.closingDebitPaise, equals(500000));

    // Bill with allocations cannot be reversed
    expect(
      () => expenses.reverseExpenseBill(society.id, billAfter.id, '2026-04-22', 'Test cannot reverse paid bill'),
      throwsA(isA<SocietyException>()),
    );

    // Reversing payment restores bill balance
    await expenses.reversePayment(society.id, pmtId, '2026-04-22', 'Payment cheque bounced');
    final restoredBill = await expenses.getExpenseBill(society.id, billAfter.id);
    expect(restoredBill!.paidPaise, equals(0));
    expect(restoredBill.status, equals('posted'));
  });

  test('Vendor Advance Adjustment balances against new bill', () async {
    final vendors = await expenses.listVendors(society.id);
    final otis = vendors.firstWhere((v) => v.vendor.name == 'Otis Elevator Services').vendor;

    // Create a new bill for May: ₹4,000.00
    final mayBillId = await expenses.postExpenseBill(
      society.id,
      ExpenseBillDraft(
        vendorId: otis.id,
        vendorBillNo: 'OTIS/2026/002',
        billDate: '2026-05-05',
        postDate: '2026-05-05',
        lines: [
          ExpenseLineDraft(
            accountId: liftMaintAccId,
            description: 'May Maintenance',
            amountPaise: 400000, // ₹4,000.00
          ),
        ],
      ),
    );

    // Adjust ₹3,000.00 of existing advance against this bill
    await expenses.adjustVendorAdvance(
      society.id,
      VendorAdvanceAdjustmentDraft(
        vendorId: otis.id,
        expenseBillId: mayBillId,
        amountPaise: 300000,
        date: '2026-05-06',
        narration: 'Advance adjusted against May bill',
      ),
    );

    final mayBill = await expenses.getExpenseBill(society.id, mayBillId);
    expect(mayBill!.paidPaise, equals(300000));
    expect(mayBill.balancePaise, equals(100000));
    expect(mayBill.status, equals('posted'));

    // Verify trial balance balances
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-05-31');
    expect(tb.isBalanced, isTrue);

    // Advance account decreased from 5,000 to 2,000
    final advRow = tb.rows.firstWhere((r) => r.accountCode == '1701');
    expect(advRow.closingDebitPaise, equals(200000));
  });
}
