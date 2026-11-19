import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/expense_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/other_income_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/bank/bank_service.dart';
import 'package:crusam/features/society/domain/expenses/expense_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/other_income/other_income_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late BankService bank;
  late ExpenseService expenses;
  late OtherIncomeService otherIncome;
  late Society society;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    bank = BankService(db, ledgerService: ledger);
    expenses = ExpenseService(db, ledgerService: ledger);
    otherIncome = OtherIncomeService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Tax Register Test CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
      gstin: '27AABCT9999F1Z0',
      gstRegistered: true,
    ));
    society = await admin.getSociety(socId);

    // 1. Post Other Invoice (Outward GST):
    // Billboard rent ₹50,000 + 18% same-state GST = ₹9,000 (CGST ₹4,500, SGST ₹4,500)
    final partyId = await otherIncome.saveParty(
      society.id,
      const PartyDraft(name: 'Ad Agency', stateCode: 'MH'),
    );
    final billboardAcc = (await ledger.getAccountByCode(society.id, '3301'))!;
    await otherIncome.postInvoice(
      society.id,
      OtherInvoiceDraft(
        partyId: partyId,
        invoiceDate: '2026-04-10',
        dueDate: '2026-04-25',
        lines: [
          OtherInvoiceLineDraft(
            accountId: billboardAcc.id,
            description: 'Terrace hoarding April',
            amountPaise: 5000000, // ₹50,000.00
            gstRateBp: 1800,      // 18%
          ),
        ],
      ),
    );

    // 2. Post Expense Bill (Inward GST & TDS Deducted):
    // Security services ₹40,000 + 18% same-state GST (₹3,600 CGST, ₹3,600 SGST) - 2% TDS (₹800)
    final vendorId = await expenses.saveVendor(
      society.id,
      const VendorDraft(name: 'Apex Security', stateCode: 'MH', pan: 'APEXS1234F'),
    );
    final secAcc = (await ledger.getAccountByCode(society.id, '4102'))!;
    await expenses.postExpenseBill(
      society.id,
      ExpenseBillDraft(
        vendorId: vendorId,
        vendorBillNo: 'SEC-APR-001',
        billDate: '2026-04-15',
        postDate: '2026-04-15',
        tdsRateBp: 200, // 2% TDS = ₹800.00
        lines: [
          ExpenseLineDraft(
            accountId: secAcc.id,
            description: 'Security guards April',
            amountPaise: 4000000, // ₹40,000.00
            gstRateBp: 1800,      // 18%
          ),
        ],
      ),
    );
  });

  tearDownAll(() async {
    await db.close();
  });

  test('GST and TDS registers tie directly to ledger account balances', () async {
    final from = '2026-04-01';
    final to = '2026-04-30';

    // 1. Check GST Register
    final gst = await bank.gstRegister(society.id, from, to);
    expect(gst.gstOutwardLines.length, equals(1));
    expect(gst.gstInwardLines.length, equals(1));

    // Outward totals: CGST ₹4,500, SGST ₹4,500 (450,000 paise each)
    final outLine = gst.gstOutwardLines.first;
    expect(outLine.cgstPaise, equals(450000));
    expect(outLine.sgstPaise, equals(450000));

    // Inward totals: CGST ₹3,600, SGST ₹3,600 (360,000 paise each)
    final inLine = gst.gstInwardLines.first;
    expect(inLine.cgstPaise, equals(360000));
    expect(inLine.sgstPaise, equals(360000));

    // Verify trial balance accounts tie exactly
    final tb = await ledger.trialBalance(society.id, from, to);
    expect(tb.isBalanced, isTrue);

    // Output CGST (2601) credit = 450,000
    final outCgstAcc = tb.rows.firstWhere((r) => r.accountCode == '2601');
    expect(outCgstAcc.closingCreditPaise, equals(outLine.cgstPaise));

    // Output SGST (2602) credit = 450,000
    final outSgstAcc = tb.rows.firstWhere((r) => r.accountCode == '2602');
    expect(outSgstAcc.closingCreditPaise, equals(outLine.sgstPaise));

    // Input CGST (1601) debit = 360,000
    final inCgstAcc = tb.rows.firstWhere((r) => r.accountCode == '1601');
    expect(inCgstAcc.closingDebitPaise, equals(inLine.cgstPaise));

    // Input SGST (1602) debit = 360,000
    final inSgstAcc = tb.rows.firstWhere((r) => r.accountCode == '1602');
    expect(inSgstAcc.closingDebitPaise, equals(inLine.sgstPaise));

    // 2. Check TDS Register
    final tds = await bank.tdsRegister(society.id, from, to);
    expect(tds.tdsLines.length, equals(1));

    final tdsLine = tds.tdsLines.first;
    expect(tdsLine.tdsPaise, equals(80000)); // ₹800.00 (80,000 paise)
    expect(tdsLine.isPayable, isTrue);

    // TDS Payable (2604) credit = 80,000
    final tdsPayableAcc = tb.rows.firstWhere((r) => r.accountCode == '2604');
    expect(tdsPayableAcc.closingCreditPaise, equals(tdsLine.tdsPaise));
  });
}
