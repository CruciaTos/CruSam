import 'package:sqflite/sqflite.dart';
import '../../core/society_exception.dart';
import '../../data/models/bank_models.dart';
import '../../data/models/ledger_models.dart';
import '../../data/repositories/bank_repository.dart';
import '../ledger/ledger_service.dart';

class BankService {
  final Database db;
  final BankRepository _repo;
  final LedgerService _ledger;

  BankService(
    this.db, {
    required LedgerService ledgerService,
    BankRepository? bankRepo,
  })  : _ledger = ledgerService,
        _repo = bankRepo ?? BankRepository(db);

  // Bank Accounts
  Future<List<BankAccountRow>> listBankAccounts(int societyId) async {
    return await _repo.listBankAccounts(societyId);
  }

  Future<int> createBankAccount(int societyId, BankAccountDraft draft) async {
    if (draft.bankName.trim().isEmpty) {
      throw const SocietyException('validation', 'Bank name is required');
    }

    int accId;
    if (draft.accountId != null) {
      accId = draft.accountId!;
    } else {
      // Create account in group 1100 (Bank and Cash accounts)
      final groups = await _ledger.listGroups(societyId);
      final bankGroup = groups.firstWhere(
        (g) => g.code == '1100',
        orElse: () => throw const SocietyException('not_found', 'Bank & Cash group 1100 not found'),
      );

      final code = draft.accountCode ?? await _generateNextAccountCode(db, societyId, '11');
      accId = await _ledger.createAccount(
        societyId,
        AccountDraft(
          groupId: bankGroup.id,
          code: code,
          name: '${draft.bankName}${draft.accountNumber != null ? " - ${draft.accountNumber}" : ""}',
          accountKind: draft.accountType == 'cash' ? 'cash' : 'bank',
        ),
      );
    }

    return await _repo.insertBankAccount(
      societyId: societyId,
      accountId: accId,
      bankName: draft.bankName,
      branch: draft.branch,
      accountNumber: draft.accountNumber,
      ifsc: draft.ifsc,
      accountType: draft.accountType,
      isActive: draft.isActive,
    );
  }

  Future<void> updateBankAccount(int societyId, int bankAccountId, BankAccountDraft draft) async {
    await _repo.updateBankAccount(
      societyId: societyId,
      bankAccountId: bankAccountId,
      bankName: draft.bankName,
      branch: draft.branch,
      accountNumber: draft.accountNumber,
      ifsc: draft.ifsc,
      accountType: draft.accountType,
      isActive: draft.isActive,
    );
  }

  // Bank Transfers
  Future<int> postTransfer(int societyId, BankTransferDraft draft) async {
    if (draft.amountPaise <= 0) {
      throw const SocietyException('validation', 'Transfer amount must be positive');
    }
    if (draft.fromAccountId == draft.toAccountId) {
      throw const SocietyException('same_account', 'Source and destination accounts cannot be the same');
    }

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.transferDate);
      final transferNo = await _ledger.nextNumber(txn, societyId, fy.id, 'bank_transfer');

      final fromAcc = await _ledger.getAccount(draft.fromAccountId, executor: txn);
      final toAcc = await _ledger.getAccount(draft.toAccountId, executor: txn);
      if (fromAcc == null || toAcc == null) {
        throw const SocietyException('not_found', 'Invalid from or to account');
      }

      // Contra Journal Entry: Debit To Account, Credit From Account
      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.transferDate,
          sourceType: 'bank_transfer',
          narration: draft.narration ?? 'Transfer $transferNo from ${fromAcc.name} to ${toAcc.name}',
          lines: [
            JournalLineDraft(
              accountId: draft.toAccountId,
              debitPaise: draft.amountPaise,
              creditPaise: 0,
              note: 'Transfer from ${fromAcc.name}',
            ),
            JournalLineDraft(
              accountId: draft.fromAccountId,
              debitPaise: 0,
              creditPaise: draft.amountPaise,
              note: 'Transfer to ${toAcc.name}',
            ),
          ],
        ),
      );

      final transferId = await _repo.insertBankTransfer(
        societyId: societyId,
        fyId: fy.id,
        transferNo: transferNo,
        transferDate: draft.transferDate,
        fromAccountId: draft.fromAccountId,
        toAccountId: draft.toAccountId,
        amountPaise: draft.amountPaise,
        instrumentNo: draft.instrumentNo,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        executor: txn,
      );

      return transferId;
    });
  }

  Future<void> reverseTransfer(int societyId, int transferId, String date, String reason) async {
    final transfer = await _repo.getBankTransfer(societyId, transferId);
    if (transfer == null) throw const SocietyException('not_found', 'Bank transfer not found');
    if (transfer.status == 'reversed') throw const SocietyException('already_reversed', 'Transfer is already reversed');

    // Rule: Cleared transfer cannot be reversed!
    if (transfer.journalEntryId != null) {
      final isCleared = await _repo.isJournalEntryCleared(societyId, transfer.journalEntryId!);
      if (isCleared) {
        throw const SocietyException('cleared_transfer', 'Cannot reverse a cleared bank transfer. Unclear it first.');
      }
    }

    await db.transaction((txn) async {
      final reversalJournal = await _ledger.reverse(
        txn,
        societyId,
        transfer.journalEntryId!,
        date,
        reason,
      );

      await _repo.updateBankTransferStatus(
        societyId,
        transferId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: reversalJournal.id,
        executor: txn,
      );
    });
  }

  Future<List<BankTransfer>> listTransfers(int societyId, {String? status}) async {
    return await _repo.listBankTransfers(societyId, status: status);
  }

  // Bank Book
  Future<List<BankBookRow>> bankBook(
    int societyId,
    BankBookFilter filter,
  ) async {
    return await _repo.getBankBookRows(
      societyId,
      filter.bankAccountId,
      fromDate: filter.fromDate,
      toDate: filter.toDate,
      clearedOnly: filter.clearedOnly,
    );
  }

  // Statement Import
  Future<int> importStatement(
    int societyId,
    int bankAccountId,
    String fileName,
    List<StatementLineDraft> rows,
  ) async {
    if (rows.isEmpty) throw const SocietyException('validation', 'No statement lines to import');

    return await db.transaction((txn) async {
      final importId = await _repo.insertStatementImport(
        societyId,
        bankAccountId,
        fileName,
        executor: txn,
      );

      await _repo.insertStatementLines(
        societyId,
        importId,
        bankAccountId,
        rows,
        executor: txn,
      );

      return importId;
    });
  }

  // Reconciliation
  Future<ReconciliationView> reconciliation(int societyId, int bankAccountId, String asOf) async {
    final ba = await _repo.getBankAccount(societyId, bankAccountId);
    if (ba == null) throw const SocietyException('not_found', 'Bank account not found');

    // 1. Book Balance through asOf
    final bookBalRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as book_bal
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND jl.account_id = ? AND je.entry_date <= ?
    ''', [societyId, ba.accountId, asOf]);
    final bookBal = bookBalRows.first['book_bal'] as int? ?? 0;

    // 2. Uncleared Receipts (Debits on this bank account through asOf without clearance on or before asOf)
    final uncRcptRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise), 0) as unc_rcpt
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      LEFT JOIN bank_clearances bc ON bc.journal_line_id = jl.id
      WHERE jl.society_id = ? AND jl.account_id = ? AND je.entry_date <= ?
        AND (bc.journal_line_id IS NULL OR bc.cleared_date > ?)
    ''', [societyId, ba.accountId, asOf, asOf]);
    final unclearedReceipts = uncRcptRows.first['unc_rcpt'] as int? ?? 0;

    // 3. Uncleared Payments (Credits on this bank account through asOf without clearance on or before asOf)
    final uncPmtRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.credit_paise), 0) as unc_pmt
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      LEFT JOIN bank_clearances bc ON bc.journal_line_id = jl.id
      WHERE jl.society_id = ? AND jl.account_id = ? AND je.entry_date <= ?
        AND (bc.journal_line_id IS NULL OR bc.cleared_date > ?)
    ''', [societyId, ba.accountId, asOf, asOf]);
    final unclearedPayments = uncPmtRows.first['unc_pmt'] as int? ?? 0;

    // Reconciliation formula:
    // expected_statement_balance = book_balance - uncleared_receipts + uncleared_payments
    final expectedStatement = bookBal - unclearedReceipts + unclearedPayments;

    // Statement Balance from imported lines
    final stmtRows = await db.rawQuery('''
      SELECT statement_balance_paise
      FROM bank_statement_lines
      WHERE society_id = ? AND bank_account_id = ? AND line_date <= ?
        AND statement_balance_paise IS NOT NULL
      ORDER BY line_date DESC, id DESC
      LIMIT 1
    ''', [societyId, ba.id, asOf]);
    final statementBal = stmtRows.isNotEmpty ? (stmtRows.first['statement_balance_paise'] as int? ?? 0) : expectedStatement;

    final diff = statementBal - expectedStatement;

    final summary = ReconciliationSummary(
      bookBalancePaise: bookBal,
      unclearedReceiptsPaise: unclearedReceipts,
      unclearedPaymentsPaise: unclearedPayments,
      expectedStatementBalancePaise: expectedStatement,
      statementBalancePaise: statementBal,
      differencePaise: diff,
    );

    // Book Items
    final bookItems = await _repo.getBankBookRows(
      societyId,
      ba.id,
      fromDate: '1900-01-01',
      toDate: asOf,
    );

    // Statement Lines
    final statementLines = await _repo.listStatementLines(
      societyId,
      ba.id,
      toDate: asOf,
    );

    return ReconciliationView(
      bankAccount: ba,
      asOfDate: asOf,
      summary: summary,
      bookItems: bookItems,
      statementLines: statementLines,
    );
  }

  Future<void> clearLine(int societyId, int journalLineId, String clearedDate, {int? statementLineId}) async {
    await _repo.insertBankClearance(journalLineId, societyId, clearedDate, statementLineId: statementLineId);
  }

  Future<void> unclearLine(int societyId, int journalLineId) async {
    await _repo.deleteBankClearance(societyId, journalLineId);
  }

  // Fixed Deposits
  Future<int> openFixedDeposit(int societyId, FixedDepositDraft draft) async {
    if (draft.principalPaise <= 0) {
      throw const SocietyException('validation', 'Principal amount must be positive');
    }
    if (draft.fdNo.trim().isEmpty) {
      throw const SocietyException('validation', 'FD number is required');
    }

    // Create FD Account under Group 1400 (Fixed Deposits)
    final groups = await _ledger.listGroups(societyId);
    final fdGroup = groups.firstWhere(
      (g) => g.code == '1400',
      orElse: () => throw const SocietyException('not_found', 'Fixed Deposits group 1400 not found'),
    );

    final code = await _generateNextAccountCode(db, societyId, '14');
    final accId = await _ledger.createAccount(
      societyId,
      AccountDraft(
        groupId: fdGroup.id,
        code: code,
        name: 'FD - ${draft.bankName} (${draft.fdNo})',
        accountKind: 'general',
      ),
    );

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.startDate);

      final fdId = await _repo.insertFixedDeposit(
        societyId: societyId,
        accountId: accId,
        fdNo: draft.fdNo,
        bankName: draft.bankName,
        startDate: draft.startDate,
        maturityDate: draft.maturityDate,
        principalPaise: draft.principalPaise,
        rateBp: draft.rateBp,
        compounding: draft.compounding,
        interestFrequency: draft.interestFrequency,
        tdsRateBp: draft.tdsRateBp,
        expectedMaturityPaise: draft.expectedMaturityPaise,
        instructions: draft.instructions,
        executor: txn,
      );

      // Journal: Debit FD Account, Credit Bank/Cash Account
      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.startDate,
          sourceType: 'fd_open',
          narration: 'FD Opened - ${draft.bankName} (${draft.fdNo})',
          lines: [
            JournalLineDraft(
              accountId: accId,
              debitPaise: draft.principalPaise,
              creditPaise: 0,
              note: 'FD Principal',
            ),
            JournalLineDraft(
              accountId: draft.bankCashAccountId,
              debitPaise: 0,
              creditPaise: draft.principalPaise,
              note: 'FD Opening Payout',
            ),
          ],
        ),
      );

      await _repo.insertFdTransaction(
        societyId: societyId,
        fdId: fdId,
        fyId: fy.id,
        txnType: 'open',
        txnDate: draft.startDate,
        amountPaise: draft.principalPaise,
        bankCashAccountId: draft.bankCashAccountId,
        narration: 'FD Opened',
        journalEntryId: postedJournal.id,
        executor: txn,
      );

      return fdId;
    });
  }

  Future<void> postFdTransaction(int societyId, FdTransactionDraft draft) async {
    if (draft.amountPaise <= 0) {
      throw const SocietyException('validation', 'Transaction amount must be positive');
    }

    final fd = await _repo.getFixedDeposit(societyId, draft.fdId);
    if (fd == null) throw const SocietyException('not_found', 'Fixed deposit not found');
    if (fd.status == 'closed') throw const SocietyException('validation', 'Fixed deposit is already closed');

    await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.txnDate);
      final accruedIntAccId = await _ledger.accountIdForKey(txn, societyId, 'accrued_interest');
      final interestIncomeAccId = await _ledger.accountIdForKey(txn, societyId, 'fd_interest_income');
      final tdsReceivableAccId = await _ledger.accountIdForKey(txn, societyId, 'tds_receivable');

      final journalLines = <JournalLineDraft>[];

      if (draft.txnType == 'interest_accrued') {
        // Debit accrued_interest (net) + Debit tds_receivable (if any), Credit fd_interest_income (gross)
        final netInterest = draft.amountPaise - draft.tdsPaise;
        journalLines.add(JournalLineDraft(
          accountId: accruedIntAccId,
          debitPaise: netInterest,
          creditPaise: 0,
          note: 'Interest Accrued on FD ${fd.fdNo}',
        ));
        if (draft.tdsPaise > 0) {
          journalLines.add(JournalLineDraft(
            accountId: tdsReceivableAccId,
            debitPaise: draft.tdsPaise,
            creditPaise: 0,
            note: 'TDS on FD ${fd.fdNo}',
          ));
        }
        journalLines.add(JournalLineDraft(
          accountId: interestIncomeAccId,
          debitPaise: 0,
          creditPaise: draft.amountPaise,
          note: 'FD Interest Income',
        ));
      } else if (draft.txnType == 'interest_received') {
        if (draft.bankCashAccountId == null) {
          throw const SocietyException('validation', 'Bank or cash account required for interest received');
        }
        final netReceived = draft.amountPaise - draft.tdsPaise;
        journalLines.add(JournalLineDraft(
          accountId: draft.bankCashAccountId!,
          debitPaise: netReceived,
          creditPaise: 0,
          note: 'FD Interest Received on ${fd.fdNo}',
        ));
        if (draft.tdsPaise > 0) {
          journalLines.add(JournalLineDraft(
            accountId: tdsReceivableAccId,
            debitPaise: draft.tdsPaise,
            creditPaise: 0,
            note: 'TDS on FD ${fd.fdNo}',
          ));
        }
        // If interest was accrued earlier, credit accrued_interest; otherwise credit fd_interest_income
        // We credit fd_interest_income as standard
        journalLines.add(JournalLineDraft(
          accountId: interestIncomeAccId,
          debitPaise: 0,
          creditPaise: draft.amountPaise,
          note: 'FD Interest Received',
        ));
      } else if (draft.txnType == 'close') {
        if (draft.bankCashAccountId == null) {
          throw const SocietyException('validation', 'Bank or cash account required for FD closure payout');
        }
        // Total payout = draft.amountPaise
        // Payout debits Bank/Cash. If TDS deducted, debit TDS Receivable.
        // Credits FD Principal Account (fd.principalPaise) and any interest to fd_interest_income.
        final netPayout = draft.amountPaise - draft.tdsPaise;
        journalLines.add(JournalLineDraft(
          accountId: draft.bankCashAccountId!,
          debitPaise: netPayout,
          creditPaise: 0,
          note: 'FD Closure Payout - ${fd.fdNo}',
        ));
        if (draft.tdsPaise > 0) {
          journalLines.add(JournalLineDraft(
            accountId: tdsReceivableAccId,
            debitPaise: draft.tdsPaise,
            creditPaise: 0,
            note: 'TDS on FD Closure - ${fd.fdNo}',
          ));
        }
        // Credit FD Principal
        journalLines.add(JournalLineDraft(
          accountId: fd.accountId,
          debitPaise: 0,
          creditPaise: fd.principalPaise,
          note: 'FD Principal Closed',
        ));
        // If payout > principal, credit remaining to interest income
        if (draft.amountPaise > fd.principalPaise) {
          final interestPaise = draft.amountPaise - fd.principalPaise;
          journalLines.add(JournalLineDraft(
            accountId: interestIncomeAccId,
            debitPaise: 0,
            creditPaise: interestPaise,
            note: 'FD Maturity Interest',
          ));
        }

        await _repo.updateFixedDepositStatus(societyId, fd.id, 'closed', executor: txn);
      } else {
        throw SocietyException('validation', 'Invalid transaction type ${draft.txnType}');
      }

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.txnDate,
          sourceType: 'fd_${draft.txnType}',
          narration: draft.narration ?? 'FD ${draft.txnType.replaceAll('_', ' ').toUpperCase()} - ${fd.fdNo}',
          lines: journalLines,
        ),
      );

      await _repo.insertFdTransaction(
        societyId: societyId,
        fdId: fd.id,
        fyId: fy.id,
        txnType: draft.txnType,
        txnDate: draft.txnDate,
        amountPaise: draft.amountPaise,
        tdsPaise: draft.tdsPaise,
        bankCashAccountId: draft.bankCashAccountId,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        executor: txn,
      );
    });
  }

  Future<List<FixedDeposit>> listFixedDeposits(int societyId, {String? status}) async {
    return await _repo.listFixedDeposits(societyId, status: status);
  }

  Future<FixedDeposit?> getFixedDeposit(int societyId, int id) async {
    return await _repo.getFixedDeposit(societyId, id);
  }

  Future<List<FdTransaction>> listFdTransactions(int societyId, int fdId) async {
    return await _repo.listFdTransactions(societyId, fdId);
  }

  // Tax Registers
  Future<TaxRegister> gstRegister(int societyId, String from, String to) async {
    final outward = await _repo.getGstOutwardLines(societyId, from, to);
    final inward = await _repo.getGstInwardLines(societyId, from, to);

    var totTaxable = 0;
    var totCgst = 0;
    var totSgst = 0;
    var totIgst = 0;

    for (final l in outward) {
      totTaxable += l.taxablePaise;
      totCgst += l.cgstPaise;
      totSgst += l.sgstPaise;
      totIgst += l.igstPaise;
    }
    for (final l in inward) {
      totTaxable += l.taxablePaise;
      totCgst += l.cgstPaise;
      totSgst += l.sgstPaise;
      totIgst += l.igstPaise;
    }

    return TaxRegister(
      fromDate: from,
      toDate: to,
      registerKind: 'gst',
      gstOutwardLines: outward,
      gstInwardLines: inward,
      totalTaxablePaise: totTaxable,
      totalCgstPaise: totCgst,
      totalSgstPaise: totSgst,
      totalIgstPaise: totIgst,
    );
  }

  Future<TaxRegister> tdsRegister(int societyId, String from, String to) async {
    final lines = await _repo.getTdsLines(societyId, from, to);

    var totPayable = 0;
    var totReceivable = 0;

    for (final l in lines) {
      if (l.isPayable) {
        totPayable += l.tdsPaise;
      } else {
        totReceivable += l.tdsPaise;
      }
    }

    return TaxRegister(
      fromDate: from,
      toDate: to,
      registerKind: 'tds',
      tdsLines: lines,
      totalTdsPayablePaise: totPayable,
      totalTdsReceivablePaise: totReceivable,
    );
  }

  // Helper
  Future<String> _generateNextAccountCode(DatabaseExecutor exec, int societyId, String prefix) async {
    final rows = await exec.rawQuery('''
      SELECT code FROM accounts
      WHERE society_id = ? AND code LIKE ?
      ORDER BY code DESC
      LIMIT 1
    ''', [societyId, '$prefix%']);
    if (rows.isEmpty) return '${prefix}01';
    final lastCode = rows.first['code'] as String;
    final numPart = int.tryParse(lastCode) ?? int.parse('${prefix}00');
    return (numPart + 1).toString();
  }
}
