import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/bank_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/bank/bank_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late BankService bank;
  late Society society;
  late int bankAccRecordId;
  late int bankAccId;
  late int cashAccId;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    bank = BankService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Reconciliation Test CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);

    // Create Bank Account
    bankAccRecordId = await bank.createBankAccount(
      society.id,
      const BankAccountDraft(
        bankName: 'Axis Bank Current A/c',
        accountNumber: '999888777',
        accountType: 'current',
      ),
    );
    final accounts = await bank.listBankAccounts(society.id);
    final row = accounts.firstWhere((a) => a.bankAccount.id == bankAccRecordId);
    bankAccId = row.account.id;

    // Create Cash Account
    final cashRecordId = await bank.createBankAccount(
      society.id,
      const BankAccountDraft(
        bankName: 'Petty Cash',
        accountType: 'cash',
      ),
    );
    final cashRow = (await bank.listBankAccounts(society.id)).firstWhere((a) => a.bankAccount.id == cashRecordId);
    cashAccId = cashRow.account.id;

    // 1. Opening Balance: Bank ₹50,000.00
    final genFund = (await ledger.getAccountByCode(society.id, '2301'))!;
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(
        accountId: bankAccId,
        debitPaise: 5000000, // ₹50,000.00
        creditPaise: 0,
        asOfDate: '2026-04-01',
      ),
      OpeningBalanceDraft(
        accountId: genFund.id,
        debitPaise: 0,
        creditPaise: 5000000,
        asOfDate: '2026-04-01',
      ),
    ]);
  });

  tearDownAll(() async {
    await db.close();
  });

  test('Bank Reconciliation formula with uncleared receipts and payments', () async {
    // 2. Receipt into bank: ₹10,000.00 on 2026-04-10 (Debit Bank ₹10,000, Credit Misc Income)
    final miscInc = (await ledger.getAccountByCode(society.id, '3303'))!;
    await db.transaction((txn) => ledger.post(
      txn,
      JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-10',
        sourceType: 'manual',
        narration: 'Hall booking receipt',
        lines: [
          JournalLineDraft(accountId: bankAccId, debitPaise: 1000000, creditPaise: 0),
          JournalLineDraft(accountId: miscInc.id, debitPaise: 0, creditPaise: 1000000),
        ],
      ),
    ));

    // 3. Payment from bank: Transfer to Cash ₹6,000.00 on 2026-04-12 (Credit Bank ₹6,000, Debit Cash)
    await bank.postTransfer(
      society.id,
      BankTransferDraft(
        transferDate: '2026-04-12',
        fromAccountId: bankAccId,
        toAccountId: cashAccId,
        amountPaise: 600000,
      ),
    );

    // Initial reconciliation view before any clearances:
    // Book balance: 50,000 + 10,000 - 6,000 = ₹54,000.00 (5,400,000 paise)
    // Uncleared receipts: Opening 50,000 + 10,000 = 60,000.00 (6,000,000 paise)
    // Uncleared payments: 6,000.00 (600,000 paise)
    // Expected statement balance: 54,000 - 60,000 + 6,000 = 0.00
    var recon = await bank.reconciliation(society.id, bankAccRecordId, '2026-04-30');
    expect(recon.summary.bookBalancePaise, equals(5400000));
    expect(recon.summary.unclearedReceiptsPaise, equals(6000000));
    expect(recon.summary.unclearedPaymentsPaise, equals(600000));
    expect(recon.summary.expectedStatementBalancePaise, equals(0));

    // 4. Clear the opening balance line (₹50,000.00)
    final openingItem = recon.bookItems.firstWhere((b) => b.debitPaise == 5000000);
    await bank.clearLine(society.id, openingItem.journalLineId, '2026-04-01');

    // After clearing opening balance:
    // Uncleared receipts drops to 10,000.00
    // Expected statement balance: 54,000 - 10,000 + 6,000 = 50,000.00
    recon = await bank.reconciliation(society.id, bankAccRecordId, '2026-04-30');
    expect(recon.summary.unclearedReceiptsPaise, equals(1000000));
    expect(recon.summary.expectedStatementBalancePaise, equals(5000000));

    // 5. Clear the receipt line (₹10,000.00)
    final rcptItem = recon.bookItems.firstWhere((b) => b.debitPaise == 1000000);
    await bank.clearLine(society.id, rcptItem.journalLineId, '2026-04-11');

    // After clearing receipt:
    // Uncleared receipts = 0
    // Expected statement balance: 54,000 - 0 + 6,000 = 60,000.00
    recon = await bank.reconciliation(society.id, bankAccRecordId, '2026-04-30');
    expect(recon.summary.unclearedReceiptsPaise, equals(0));
    expect(recon.summary.unclearedPaymentsPaise, equals(600000));
    expect(recon.summary.expectedStatementBalancePaise, equals(6000000));

    // 6. Unclear the receipt line -> Uncleared receipts goes back to 10,000.00
    await bank.unclearLine(society.id, rcptItem.journalLineId);
    recon = await bank.reconciliation(society.id, bankAccRecordId, '2026-04-30');
    expect(recon.summary.unclearedReceiptsPaise, equals(1000000));
    expect(recon.summary.expectedStatementBalancePaise, equals(5000000));
  });

  test('Bank Statement Import and difference calculation', () async {
    // Import bank statement showing actual closing balance of ₹50,000.00 on 2026-04-30
    await bank.importStatement(
      society.id,
      bankAccRecordId,
      'axis_apr_2026.csv',
      [
        const StatementLineDraft(
          date: '2026-04-01',
          description: 'Opening Balance',
          depositPaise: 5000000,
          balancePaise: 5000000,
        ),
      ],
    );

    final recon = await bank.reconciliation(society.id, bankAccRecordId, '2026-04-30');
    expect(recon.summary.statementBalancePaise, equals(5000000));
    expect(recon.summary.expectedStatementBalancePaise, equals(5000000));
    expect(recon.summary.differencePaise, equals(0)); // Perfect match!
    expect(recon.statementLines.length, equals(1));
  });
}
