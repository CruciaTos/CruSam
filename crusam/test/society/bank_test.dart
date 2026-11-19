import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_exception.dart';
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
  late int bank1AccId;
  late int bank2AccId;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    bank = BankService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Bank Test CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);

    // Create 2 Bank Accounts
    final b1Id = await bank.createBankAccount(
      society.id,
      const BankAccountDraft(
        bankName: 'HDFC Current A/c',
        branch: 'Bandra',
        accountNumber: '111122223333',
        ifsc: 'HDFC0001234',
        accountType: 'current',
      ),
    );
    final b1 = (await bank.listBankAccounts(society.id)).firstWhere((a) => a.bankAccount.id == b1Id);
    bank1AccId = b1.account.id;

    final b2Id = await bank.createBankAccount(
      society.id,
      const BankAccountDraft(
        bankName: 'SBI Savings A/c',
        branch: 'Fort',
        accountNumber: '444455556666',
        ifsc: 'SBIN0000001',
        accountType: 'savings',
      ),
    );
    final b2 = (await bank.listBankAccounts(society.id)).firstWhere((a) => a.bankAccount.id == b2Id);
    bank2AccId = b2.account.id;

    // Seed Opening balance in HDFC: ₹1,00,000.00
    final genFund = (await ledger.getAccountByCode(society.id, '2301'))!;
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(
        accountId: bank1AccId,
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
  });

  tearDownAll(() async {
    await db.close();
  });

  test('Transfer cannot use the same account', () async {
    await expectLater(
      bank.postTransfer(
        society.id,
        BankTransferDraft(
          transferDate: '2026-04-10',
          fromAccountId: bank1AccId,
          toAccountId: bank1AccId, // Same account!
          amountPaise: 500000,
        ),
      ),
      throwsA(isA<SocietyException>()),
    );
  });

  test('Bank transfer creates balanced contra journal and updates account balances', () async {
    // Transfer ₹25,000.00 from HDFC to SBI
    final trfId = await bank.postTransfer(
      society.id,
      BankTransferDraft(
        transferDate: '2026-04-10',
        fromAccountId: bank1AccId,
        toAccountId: bank2AccId,
        amountPaise: 2500000,
        instrumentNo: 'CHQ-1001',
        narration: 'Transfer to SBI for operational expenses',
      ),
    );
    expect(trfId, isPositive);

    // Verify trial balance
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);

    // HDFC (Bank 1) should be 1,00,000 - 25,000 = 75,000.00
    final hdfcRow = tb.rows.firstWhere((r) => r.accountId == bank1AccId);
    expect(hdfcRow.closingDebitPaise, equals(7500000));

    // SBI (Bank 2) should be 25,000.00
    final sbiRow = tb.rows.firstWhere((r) => r.accountId == bank2AccId);
    expect(sbiRow.closingDebitPaise, equals(2500000));
  });

  test('Cleared transfer cannot be reversed, but uncleaned transfer reverses cleanly', () async {
    // Transfer ₹5,000.00 from HDFC to SBI
    final trfId = await bank.postTransfer(
      society.id,
      BankTransferDraft(
        transferDate: '2026-04-15',
        fromAccountId: bank1AccId,
        toAccountId: bank2AccId,
        amountPaise: 500000,
        instrumentNo: 'CHQ-1002',
      ),
    );

    final trf = await bank.listTransfers(society.id);
    final thisTrf = trf.firstWhere((t) => t.id == trfId);

    // Clear one of the transfer lines
    final entry = await ledger.entryDetail(society.id, thisTrf.journalEntryId!);
    final firstLineId = entry.lines.first.id;
    await bank.clearLine(society.id, firstLineId, '2026-04-16');

    // Attempting to reverse cleared transfer throws SocietyException
    await expectLater(
      bank.reverseTransfer(society.id, trfId, '2026-04-17', 'Attempt reversal of cleared transfer'),
      throwsA(isA<SocietyException>()),
    );

    // Unclear the line
    await bank.unclearLine(society.id, firstLineId);

    // Now reversal succeeds
    await bank.reverseTransfer(society.id, trfId, '2026-04-17', 'Uncleared reversal succeeds');

    final afterTrf = (await bank.listTransfers(society.id)).firstWhere((t) => t.id == trfId);
    expect(afterTrf.status, equals('reversed'));

    // Balances net back to before this transfer
    final tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);
    final hdfcRow = tb.rows.firstWhere((r) => r.accountId == bank1AccId);
    expect(hdfcRow.closingDebitPaise, equals(7500000));
  });
}
