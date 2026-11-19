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
  late int bankAccId;

  setUpAll(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    bank = BankService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'FD Test CHS',
      city: 'Mumbai',
      state: 'Maharashtra',
      stateCode: 'MH',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);

    // Create Bank Account with ₹5,00,000.00 opening balance
    final bId = await bank.createBankAccount(
      society.id,
      const BankAccountDraft(
        bankName: 'Canara Bank',
        accountNumber: 'CAN123456',
        accountType: 'savings',
      ),
    );
    final row = (await bank.listBankAccounts(society.id)).firstWhere((a) => a.bankAccount.id == bId);
    bankAccId = row.account.id;

    final genFund = (await ledger.getAccountByCode(society.id, '2301'))!;
    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(
        accountId: bankAccId,
        debitPaise: 50000000, // ₹5,00,000.00
        creditPaise: 0,
        asOfDate: '2026-04-01',
      ),
      OpeningBalanceDraft(
        accountId: genFund.id,
        debitPaise: 0,
        creditPaise: 50000000,
        asOfDate: '2026-04-01',
      ),
    ]);
  });

  tearDownAll(() async {
    await db.close();
  });

  test('FD open, accrual, receipt and close all balance with double entry parity', () async {
    // 1. Open Fixed Deposit: ₹2,00,000.00 for 1 year at 7.00%
    final fdId = await bank.openFixedDeposit(
      society.id,
      FixedDepositDraft(
        fdNo: 'CAN/FD/2026/001',
        bankName: 'Canara Bank',
        startDate: '2026-04-05',
        maturityDate: '2027-03-31',
        principalPaise: 20000000, // ₹2,00,000.00
        rateBp: 700,
        bankCashAccountId: bankAccId,
      ),
    );
    expect(fdId, isPositive);

    final fd = await bank.getFixedDeposit(society.id, fdId);
    expect(fd, isNotNull);
    expect(fd!.principalPaise, equals(20000000));
    expect(fd.status, equals('active'));

    // Verify trial balance after FD open
    var tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tb.isBalanced, isTrue);

    // Bank should be 5,00,000 - 2,00,000 = 3,00,000.00 (30,000,000 paise)
    final bankRow = tb.rows.firstWhere((r) => r.accountId == bankAccId);
    expect(bankRow.closingDebitPaise, equals(30000000));

    // FD account under 1400 should have ₹2,00,000.00
    final fdAccRow = tb.rows.firstWhere((r) => r.accountId == fd.accountId);
    expect(fdAccRow.closingDebitPaise, equals(20000000));

    // 2. Accrue quarterly interest on 2026-06-30:
    // Interest: ₹3,500.00, TDS 10% = ₹350.00, Net Accrued = ₹3,150.00
    await bank.postFdTransaction(
      society.id,
      FdTransactionDraft(
        fdId: fdId,
        txnType: 'interest_accrued',
        txnDate: '2026-06-30',
        amountPaise: 350000, // ₹3,500.00
        tdsPaise: 35000,     // ₹350.00
      ),
    );

    tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-06-30');
    expect(tb.isBalanced, isTrue);

    // Accrued Interest (1401): 3,150.00 debit
    final accIntRow = tb.rows.firstWhere((r) => r.accountCode == '1401');
    expect(accIntRow.closingDebitPaise, equals(315000));

    // TDS Receivable (1604): 350.00 debit
    final tdsRecRow = tb.rows.firstWhere((r) => r.accountCode == '1604');
    expect(tdsRecRow.closingDebitPaise, equals(35000));

    // FD Interest Income (3203): 3,500.00 credit
    final fdIncRow = tb.rows.firstWhere((r) => r.accountCode == '3203');
    expect(fdIncRow.closingCreditPaise, equals(350000));

    // 3. Receive quarterly interest into Bank on 2026-09-30:
    // Interest: ₹3,500.00, TDS 10% = ₹350.00, Net Deposited = ₹3,150.00
    await bank.postFdTransaction(
      society.id,
      FdTransactionDraft(
        fdId: fdId,
        txnType: 'interest_received',
        txnDate: '2026-09-30',
        amountPaise: 350000, // ₹3,500.00
        tdsPaise: 35000,     // ₹350.00
        bankCashAccountId: bankAccId,
      ),
    );

    tb = await ledger.trialBalance(society.id, '2026-04-01', '2026-09-30');
    expect(tb.isBalanced, isTrue);

    // Bank increased by 3,150.00 -> 30,000,000 + 315,000 = 30,315,000
    final bankRowQ2 = tb.rows.firstWhere((r) => r.accountId == bankAccId);
    expect(bankRowQ2.closingDebitPaise, equals(30315000));

    // TDS Receivable increased by 350 -> 700.00
    final tdsRecRowQ2 = tb.rows.firstWhere((r) => r.accountCode == '1604');
    expect(tdsRecRowQ2.closingDebitPaise, equals(70000));

    // FD Interest Income increased by 3,500 -> 7,000.00
    final fdIncRowQ2 = tb.rows.firstWhere((r) => r.accountCode == '3203');
    expect(fdIncRowQ2.closingCreditPaise, equals(700000));

    // 4. Close FD on maturity 2027-03-31:
    // Payout received: Principal ₹2,00,000 + Remaining Interest ₹7,000 = ₹2,07,000.00
    // TDS deducted: ₹700.00. Net received in bank = ₹2,06,300.00
    await bank.postFdTransaction(
      society.id,
      FdTransactionDraft(
        fdId: fdId,
        txnType: 'close',
        txnDate: '2027-03-31',
        amountPaise: 20700000, // ₹2,07,000.00
        tdsPaise: 70000,       // ₹700.00
        bankCashAccountId: bankAccId,
      ),
    );

    // FD status is now closed
    final closedFd = await bank.getFixedDeposit(society.id, fdId);
    expect(closedFd!.status, equals('closed'));

    // FD Principal account nets to zero
    tb = await ledger.trialBalance(society.id, '2026-04-01', '2027-04-30');
    expect(tb.isBalanced, isTrue);
    final fdAccRowAfter = tb.rows.firstWhere((r) => r.accountId == fd.accountId);
    expect(fdAccRowAfter.closingDebitPaise, equals(0));
    expect(fdAccRowAfter.closingCreditPaise, equals(0));
  });
}
