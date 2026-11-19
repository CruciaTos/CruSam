import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/other_income_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/other_income/other_income_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late OtherIncomeService otherIncome;
  late Society society;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    otherIncome = OtherIncomeService(db, ledgerService: ledger);

    // Create society with GST registration enabled
    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Lotus Towers CHS',
      city: 'Pune',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
      gstin: '27AAAAA0000A1Z5',
      gstRegistered: true,
    ));
    society = await admin.getSociety(socId);
  });

  tearDownAll(() async {
    await db.close();
  });

  test('OtherIncomeService party creation and list', () async {
    final partyId = await otherIncome.saveParty(
      society.id,
      const PartyDraft(
        name: 'Airtel Tower Services Ltd',
        contactName: 'Ramesh Patel',
        phone: '9876543210',
        email: 'ramesh@airtel.com',
        pan: 'AAACA1234A',
        gstin: '27AAACA1234A1Z5',
        stateCode: 'MH',
      ),
    );
    expect(partyId, isPositive);

    final parties = await otherIncome.listParties(society.id);
    expect(parties.length, greaterThanOrEqualTo(1));
    expect(parties.any((p) => p.party.name == 'Airtel Tower Services Ltd'), isTrue);
  });

  test('OtherIncomeService intra-state invoice splits GST 50/50 and posts balanced journal', () async {
    final parties = await otherIncome.listParties(society.id);
    final party = parties.first.party;

    // Line with ₹10,000 rent + 18% GST (CGST ₹900, SGST ₹900)
    final otherIncomeAccId = await getAccountIdBySystemKey(db, society.id, 'misc_income');

    final invoiceId = await otherIncome.postInvoice(
      society.id,
      OtherInvoiceDraft(
        partyId: party.id,
        invoiceDate: '2026-04-10',
        dueDate: '2026-04-25',
        lines: [
          OtherInvoiceLineDraft(
            accountId: otherIncomeAccId,
            description: 'Terrace Mobile Tower Rent April 2026',
            amountPaise: 1000000, // ₹10,000.00
            gstRateBp: 1800, // 18%
          ),
        ],
        narration: 'Tower rent for April',
      ),
    );

    final invoice = await otherIncome.getInvoice(society.id, invoiceId);
    expect(invoice, isNotNull);
    expect(invoice!.subtotalPaise, equals(1000000));
    expect(invoice.cgstPaise, equals(90000));
    expect(invoice.sgstPaise, equals(90000));
    expect(invoice.igstPaise, equals(0));
    expect(invoice.totalPaise, equals(1180000)); // ₹11,800.00

    // Verify journal entry lines
    final entry = await ledger.entryDetail(society.id, invoice.journalEntryId!);
    expect(entry, isNotNull);
    expect(entry.status, equals('posted'));

    // Check trial balance balances
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);
  });

  test('OtherIncomeService inter-state invoice applies IGST', () async {
    // Inter-state party in Gujarat (GJ)
    final partyId = await otherIncome.saveParty(
      society.id,
      const PartyDraft(
        name: 'Gujarat Billboard Agency',
        stateCode: 'GJ',
      ),
    );

    final otherIncomeAccId = await getAccountIdBySystemKey(db, society.id, 'misc_income');

    final invoiceId = await otherIncome.postInvoice(
      society.id,
      OtherInvoiceDraft(
        partyId: partyId,
        invoiceDate: '2026-04-12',
        dueDate: '2026-04-27',
        lines: [
          OtherInvoiceLineDraft(
            accountId: otherIncomeAccId,
            description: 'Compound wall hoarding rent',
            amountPaise: 500000, // ₹5,000.00
            gstRateBp: 1800, // 18%
          ),
        ],
      ),
    );

    final invoice = await otherIncome.getInvoice(society.id, invoiceId);
    expect(invoice, isNotNull);
    expect(invoice!.subtotalPaise, equals(500000));
    expect(invoice.cgstPaise, equals(0));
    expect(invoice.sgstPaise, equals(0));
    expect(invoice.igstPaise, equals(90000)); // ₹900.00 IGST
    expect(invoice.totalPaise, equals(590000));
  });

  test('OtherIncomeService post receipt, party statement, and reversal', () async {
    final parties = await otherIncome.listParties(society.id);
    final party = parties.firstWhere((p) => p.party.name == 'Airtel Tower Services Ltd').party;

    final cashAccId = await getAccountIdByCode(db, society.id, '1101'); // Cash in Hand

    // Post receipt of ₹11,800
    final receiptId = await otherIncome.postReceipt(
      society.id,
      OtherReceiptDraft(
        partyId: party.id,
        receiptDate: '2026-04-20',
        amountPaise: 1180000,
        mode: 'neft',
        bankCashAccountId: cashAccId,
        instrumentNo: 'NEFT12345678',
        narration: 'April rent received',
      ),
    );

    final receipt = await otherIncome.getReceipt(society.id, receiptId);
    expect(receipt, isNotNull);
    expect(receipt!.amountPaise, equals(1180000));

    // Verify statement: opening 0, invoice 11,800 debit, receipt 11,800 credit, closing 0
    final stmt = await otherIncome.partyStatement(society.id, party.id, '2026-04-01', '2026-04-30');
    expect(stmt.rows.length, equals(2));
    expect(stmt.closingBalancePaise, equals(0));

    // Reverse receipt
    await otherIncome.reverseReceipt(society.id, receiptId, '2026-04-21', 'Cheque return / bounce');
    final revReceipt = await otherIncome.getReceipt(society.id, receiptId);
    expect(revReceipt!.status, equals('reversed'));

    // Statement balance should restore to 11,800 debit
    final stmtAfter = await otherIncome.partyStatement(society.id, party.id, '2026-04-01', '2026-04-30');
    expect(stmtAfter.closingBalancePaise, equals(1180000));
  });
}
