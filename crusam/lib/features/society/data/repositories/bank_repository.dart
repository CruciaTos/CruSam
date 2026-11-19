import 'package:sqflite/sqflite.dart';
import '../models/bank_models.dart';
import '../models/ledger_models.dart';

class BankRepository {
  final Database db;

  BankRepository(this.db);

  DatabaseExecutor _getExecutor(DatabaseExecutor? executor) => executor ?? db;

  // Bank Accounts
  Future<List<BankAccountRow>> listBankAccounts(int societyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final sql = '''
      SELECT ba.*, a.code as account_code, a.name as account_name,
        a.group_id as account_group_id, a.account_kind, a.system_key, a.is_active as account_is_active,
        a.created_at as account_created_at, a.updated_at as account_updated_at,
        COALESCE((
          SELECT SUM(jl.debit_paise - jl.credit_paise)
          FROM journal_lines jl
          WHERE jl.account_id = ba.account_id AND jl.society_id = ba.society_id
        ), 0) as balance_paise
      FROM bank_accounts ba
      JOIN accounts a ON a.id = ba.account_id
      WHERE ba.society_id = ?
      ORDER BY ba.is_active DESC, a.code ASC
    ''';
    final rows = await exec.rawQuery(sql, [societyId]);
    return rows.map((r) {
      final ba = BankAccount.fromMap(r);
      final acc = Account(
        id: r['account_id'] as int,
        societyId: r['society_id'] as int,
        groupId: r['account_group_id'] as int,
        code: r['account_code'] as String,
        name: r['account_name'] as String,
        accountKind: r['account_kind'] as String,
        systemKey: r['system_key'] as String?,
        isActive: (r['account_is_active'] as int? ?? 1) == 1,
        createdAt: (r['account_created_at'] as String?) ?? '',
        updatedAt: (r['account_updated_at'] as String?) ?? '',
      );
      final bal = r['balance_paise'] as int? ?? 0;
      return BankAccountRow(bankAccount: ba, account: acc, balancePaise: bal);
    }).toList();
  }

  Future<BankAccount?> getBankAccount(int societyId, int id, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'bank_accounts',
      where: 'society_id = ? AND id = ?',
      whereArgs: [societyId, id],
    );
    if (rows.isEmpty) return null;
    return BankAccount.fromMap(rows.first);
  }

  Future<BankAccount?> getBankAccountByAccountId(int societyId, int accountId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'bank_accounts',
      where: 'society_id = ? AND account_id = ?',
      whereArgs: [societyId, accountId],
    );
    if (rows.isEmpty) return null;
    return BankAccount.fromMap(rows.first);
  }

  Future<int> insertBankAccount({
    required int societyId,
    required int accountId,
    required String bankName,
    String? branch,
    String? accountNumber,
    String? ifsc,
    required String accountType,
    bool isActive = true,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    return await exec.insert('bank_accounts', {
      'society_id': societyId,
      'account_id': accountId,
      'bank_name': bankName.trim(),
      'branch': branch?.trim(),
      'account_number': accountNumber?.trim(),
      'ifsc': ifsc?.trim().toUpperCase(),
      'account_type': accountType,
      'is_active': isActive ? 1 : 0,
    });
  }

  Future<void> updateBankAccount({
    required int societyId,
    required int bankAccountId,
    required String bankName,
    String? branch,
    String? accountNumber,
    String? ifsc,
    required String accountType,
    required bool isActive,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'bank_accounts',
      {
        'bank_name': bankName.trim(),
        'branch': branch?.trim(),
        'account_number': accountNumber?.trim(),
        'ifsc': ifsc?.trim().toUpperCase(),
        'account_type': accountType,
        'is_active': isActive ? 1 : 0,
      },
      where: 'society_id = ? AND id = ?',
      whereArgs: [societyId, bankAccountId],
    );
  }

  // Bank Transfers
  Future<int> insertBankTransfer({
    required int societyId,
    required int fyId,
    required String transferNo,
    required String transferDate,
    required int fromAccountId,
    required int toAccountId,
    required int amountPaise,
    String? instrumentNo,
    String? narration,
    required int journalEntryId,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    return await exec.insert('bank_transfers', {
      'society_id': societyId,
      'fy_id': fyId,
      'transfer_no': transferNo,
      'transfer_date': transferDate,
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'amount_paise': amountPaise,
      'instrument_no': instrumentNo,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });
  }

  Future<BankTransfer?> getBankTransfer(int societyId, int id, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final sql = '''
      SELECT bt.*, fa.name as from_account_name, ta.name as to_account_name
      FROM bank_transfers bt
      JOIN accounts fa ON fa.id = bt.from_account_id
      JOIN accounts ta ON ta.id = bt.to_account_id
      WHERE bt.society_id = ? AND bt.id = ?
    ''';
    final rows = await exec.rawQuery(sql, [societyId, id]);
    if (rows.isEmpty) return null;
    return BankTransfer.fromMap(rows.first);
  }

  Future<List<BankTransfer>> listBankTransfers(int societyId, {String? status, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final where = ['bt.society_id = ?'];
    final args = <Object?>[societyId];
    if (status != null) {
      where.add('bt.status = ?');
      args.add(status);
    }
    final sql = '''
      SELECT bt.*, fa.name as from_account_name, ta.name as to_account_name
      FROM bank_transfers bt
      JOIN accounts fa ON fa.id = bt.from_account_id
      JOIN accounts ta ON ta.id = bt.to_account_id
      WHERE ${where.join(' AND ')}
      ORDER BY bt.transfer_date DESC, bt.id DESC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map((r) => BankTransfer.fromMap(r)).toList();
  }

  Future<void> updateBankTransferStatus(
    int societyId,
    int transferId,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'bank_transfers',
      {
        'status': status,
        'reversal_reason': reversalReason,
        'reversal_entry_id': reversalEntryId,
      },
      where: 'society_id = ? AND id = ?',
      whereArgs: [societyId, transferId],
    );
  }

  // Statements & Clearances
  Future<int> insertStatementImport(int societyId, int bankAccountId, String fileName, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    return await exec.insert('bank_statement_imports', {
      'society_id': societyId,
      'bank_account_id': bankAccountId,
      'file_name': fileName,
    });
  }

  Future<void> insertStatementLines(int societyId, int importId, int bankAccountId, List<StatementLineDraft> lines, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    for (final l in lines) {
      await exec.insert('bank_statement_lines', {
        'society_id': societyId,
        'import_id': importId,
        'bank_account_id': bankAccountId,
        'line_date': l.date,
        'description': l.description,
        'reference': l.reference,
        'withdrawal_paise': l.withdrawalPaise,
        'deposit_paise': l.depositPaise,
        'statement_balance_paise': l.balancePaise,
      });
    }
  }

  Future<List<BankStatementLine>> listStatementLines(
    int societyId,
    int bankAccountId, {
    String? fromDate,
    String? toDate,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final where = ['bsl.society_id = ?', 'bsl.bank_account_id = ?'];
    final args = <Object?>[societyId, bankAccountId];
    if (fromDate != null) {
      where.add('bsl.line_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('bsl.line_date <= ?');
      args.add(toDate);
    }
    final sql = '''
      SELECT bsl.*,
        CASE WHEN bc.journal_line_id IS NOT NULL THEN 1 ELSE 0 END as is_matched
      FROM bank_statement_lines bsl
      LEFT JOIN bank_clearances bc ON bc.statement_line_id = bsl.id
      WHERE ${where.join(' AND ')}
      ORDER BY bsl.line_date ASC, bsl.id ASC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map((r) => BankStatementLine.fromMap(r)).toList();
  }

  Future<void> insertBankClearance(int journalLineId, int societyId, String clearedDate, {int? statementLineId, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    await exec.insert(
      'bank_clearances',
      {
        'journal_line_id': journalLineId,
        'society_id': societyId,
        'cleared_date': clearedDate,
        'statement_line_id': statementLineId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBankClearance(int societyId, int journalLineId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    await exec.delete(
      'bank_clearances',
      where: 'society_id = ? AND journal_line_id = ?',
      whereArgs: [societyId, journalLineId],
    );
  }

  Future<bool> isJournalLineCleared(int societyId, int journalLineId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final count = Sqflite.firstIntValue(await exec.rawQuery(
      'SELECT COUNT(*) FROM bank_clearances WHERE society_id = ? AND journal_line_id = ?',
      [societyId, journalLineId],
    ));
    return (count ?? 0) > 0;
  }

  Future<bool> isJournalEntryCleared(int societyId, int journalEntryId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final count = Sqflite.firstIntValue(await exec.rawQuery('''
      SELECT COUNT(*)
      FROM bank_clearances bc
      JOIN journal_lines jl ON jl.id = bc.journal_line_id
      WHERE bc.society_id = ? AND jl.entry_id = ?
    ''', [societyId, journalEntryId]));
    return (count ?? 0) > 0;
  }

  Future<List<BankBookRow>> getBankBookRows(
    int societyId,
    int bankAccountId, {
    required String fromDate,
    required String toDate,
    bool? clearedOnly,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final ba = await getBankAccount(societyId, bankAccountId, executor: exec);
    if (ba == null) return [];

    final where = [
      'jl.society_id = ?',
      'jl.account_id = ?',
      'je.entry_date <= ?',
    ];
    final args = <Object?>[societyId, ba.accountId, toDate];

    final sql = '''
      SELECT jl.id as journal_line_id, je.id as journal_entry_id, je.entry_date, je.entry_no,
        je.source_type, je.narration, jl.debit_paise, jl.credit_paise,
        bc.cleared_date, bc.statement_line_id,
        CASE WHEN bc.journal_line_id IS NOT NULL THEN 1 ELSE 0 END as is_cleared,
        (
          SELECT c_acc.name FROM journal_lines c_jl
          JOIN accounts c_acc ON c_acc.id = c_jl.account_id
          WHERE c_jl.entry_id = je.id AND c_jl.account_id != jl.account_id
          LIMIT 1
        ) as contra_account_name
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      LEFT JOIN bank_clearances bc ON bc.journal_line_id = jl.id
      WHERE ${where.join(' AND ')}
      ORDER BY je.entry_date ASC, je.id ASC, jl.line_no ASC
    ''';

    final rows = await exec.rawQuery(sql, args);
    var running = 0;
    final result = <BankBookRow>[];

    for (final r in rows) {
      final deb = r['debit_paise'] as int? ?? 0;
      final cred = r['credit_paise'] as int? ?? 0;
      running += (deb - cred);

      final entryDate = r['entry_date'] as String;
      final isCleared = (r['is_cleared'] as int? ?? 0) == 1;

      // Filter by fromDate for inclusion in view
      if (entryDate.compareTo(fromDate) >= 0) {
        if (clearedOnly != null && isCleared != clearedOnly) {
          continue;
        }
        result.add(BankBookRow(
          journalLineId: r['journal_line_id'] as int,
          journalEntryId: r['journal_entry_id'] as int,
          entryDate: entryDate,
          entryNo: r['entry_no'] as String,
          sourceType: r['source_type'] as String,
          narration: (r['narration'] as String?) ?? '',
          contraAccountName: r['contra_account_name'] as String?,
          debitPaise: deb,
          creditPaise: cred,
          runningBalancePaise: running,
          isCleared: isCleared,
          clearedDate: r['cleared_date'] as String?,
          statementLineId: r['statement_line_id'] as int?,
        ));
      }
    }

    return result;
  }

  // Fixed Deposits
  Future<int> insertFixedDeposit({
    required int societyId,
    required int accountId,
    required String fdNo,
    required String bankName,
    required String startDate,
    required String maturityDate,
    required int principalPaise,
    required int rateBp,
    required String compounding,
    required String interestFrequency,
    required int tdsRateBp,
    int? expectedMaturityPaise,
    String? instructions,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    return await exec.insert('fixed_deposits', {
      'society_id': societyId,
      'account_id': accountId,
      'fd_no': fdNo.trim(),
      'bank_name': bankName.trim(),
      'start_date': startDate,
      'maturity_date': maturityDate,
      'principal_paise': principalPaise,
      'rate_bp': rateBp,
      'compounding': compounding,
      'interest_frequency': interestFrequency,
      'tds_rate_bp': tdsRateBp,
      'expected_maturity_paise': expectedMaturityPaise,
      'instructions': instructions?.trim(),
      'status': 'active',
    });
  }

  Future<FixedDeposit?> getFixedDeposit(int societyId, int id, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final sql = '''
      SELECT fd.*, a.code as account_code, a.name as account_name, a.group_id as account_group_id,
        a.account_kind, a.system_key, a.is_active as account_is_active,
        a.created_at as account_created_at, a.updated_at as account_updated_at
      FROM fixed_deposits fd
      JOIN accounts a ON a.id = fd.account_id
      WHERE fd.society_id = ? AND fd.id = ?
    ''';
    final rows = await exec.rawQuery(sql, [societyId, id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final acc = Account(
      id: r['account_id'] as int,
      societyId: r['society_id'] as int,
      groupId: r['account_group_id'] as int,
      code: r['account_code'] as String,
      name: r['account_name'] as String,
      accountKind: r['account_kind'] as String,
      systemKey: r['system_key'] as String?,
      isActive: (r['account_is_active'] as int? ?? 1) == 1,
      createdAt: (r['account_created_at'] as String?) ?? '',
      updatedAt: (r['account_updated_at'] as String?) ?? '',
    );
    return FixedDeposit.fromMap(r, account: acc);
  }

  Future<List<FixedDeposit>> listFixedDeposits(int societyId, {String? status, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final where = ['fd.society_id = ?'];
    final args = <Object?>[societyId];
    if (status != null) {
      where.add('fd.status = ?');
      args.add(status);
    }
    final sql = '''
      SELECT fd.*, a.code as account_code, a.name as account_name, a.group_id as account_group_id,
        a.account_kind, a.system_key, a.is_active as account_is_active,
        a.created_at as account_created_at, a.updated_at as account_updated_at
      FROM fixed_deposits fd
      JOIN accounts a ON a.id = fd.account_id
      WHERE ${where.join(' AND ')}
      ORDER BY fd.status ASC, fd.maturity_date ASC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map((r) {
      final acc = Account(
        id: r['account_id'] as int,
        societyId: r['society_id'] as int,
        groupId: r['account_group_id'] as int,
        code: r['account_code'] as String,
        name: r['account_name'] as String,
        accountKind: r['account_kind'] as String,
        systemKey: r['system_key'] as String?,
        isActive: (r['account_is_active'] as int? ?? 1) == 1,
        createdAt: (r['account_created_at'] as String?) ?? '',
        updatedAt: (r['account_updated_at'] as String?) ?? '',
      );
      return FixedDeposit.fromMap(r, account: acc);
    }).toList();
  }

  Future<void> updateFixedDepositStatus(int societyId, int fdId, String status, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'fixed_deposits',
      {'status': status},
      where: 'society_id = ? AND id = ?',
      whereArgs: [societyId, fdId],
    );
  }

  Future<int> insertFdTransaction({
    required int societyId,
    required int fdId,
    required int fyId,
    required String txnType,
    required String txnDate,
    required int amountPaise,
    int tdsPaise = 0,
    int? bankCashAccountId,
    String? narration,
    required int journalEntryId,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    return await exec.insert('fd_transactions', {
      'society_id': societyId,
      'fd_id': fdId,
      'fy_id': fyId,
      'txn_type': txnType,
      'txn_date': txnDate,
      'amount_paise': amountPaise,
      'tds_paise': tdsPaise,
      'bank_cash_account_id': bankCashAccountId,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });
  }

  Future<List<FdTransaction>> listFdTransactions(int societyId, int fdId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'fd_transactions',
      where: 'society_id = ? AND fd_id = ?',
      whereArgs: [societyId, fdId],
      orderBy: 'txn_date ASC, id ASC',
    );
    return rows.map((r) => FdTransaction.fromMap(r)).toList();
  }

  // Tax Registers: Outward GST (Member bills + Other invoices)
  Future<List<TaxRegisterLine>> getGstOutwardLines(int societyId, String from, String to, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final lines = <TaxRegisterLine>[];

    // Member Bills
    final mbRows = await exec.rawQuery('''
      SELECT mb.bill_date as date, mb.bill_no as doc_no, mb.bill_to_name as party_name,
        mb.subtotal_paise as taxable, mb.cgst_paise, mb.sgst_paise, mb.igst_paise, mb.total_paise
      FROM bills mb
      WHERE mb.society_id = ? AND mb.status = 'posted' AND mb.bill_date BETWEEN ? AND ?
        AND (mb.cgst_paise > 0 OR mb.sgst_paise > 0 OR mb.igst_paise > 0)
      ORDER BY mb.bill_date ASC, mb.id ASC
    ''', [societyId, from, to]);

    for (final r in mbRows) {
      final cgst = r['cgst_paise'] as int? ?? 0;
      final sgst = r['sgst_paise'] as int? ?? 0;
      final igst = r['igst_paise'] as int? ?? 0;
      lines.add(TaxRegisterLine(
        date: r['date'] as String,
        docType: 'Member Bill',
        docNo: r['doc_no'] as String,
        partyOrMemberName: (r['party_name'] as String?) ?? 'Member',
        taxablePaise: r['taxable'] as int? ?? 0,
        cgstPaise: cgst,
        sgstPaise: sgst,
        igstPaise: igst,
        totalTaxPaise: cgst + sgst + igst,
        totalPaise: r['total_paise'] as int? ?? 0,
      ));
    }

    // Other Invoices
    final oiRows = await exec.rawQuery('''
      SELECT oi.invoice_date as date, oi.invoice_no as doc_no, p.name as party_name,
        p.gstin, p.state_code, oi.subtotal_paise as taxable, oi.cgst_paise, oi.sgst_paise, oi.igst_paise, oi.total_paise
      FROM other_invoices oi
      JOIN parties p ON p.id = oi.party_id
      WHERE oi.society_id = ? AND oi.status = 'posted' AND oi.invoice_date BETWEEN ? AND ?
        AND (oi.cgst_paise > 0 OR oi.sgst_paise > 0 OR oi.igst_paise > 0)
      ORDER BY oi.invoice_date ASC, oi.id ASC
    ''', [societyId, from, to]);

    for (final r in oiRows) {
      final cgst = r['cgst_paise'] as int? ?? 0;
      final sgst = r['sgst_paise'] as int? ?? 0;
      final igst = r['igst_paise'] as int? ?? 0;
      lines.add(TaxRegisterLine(
        date: r['date'] as String,
        docType: 'Other Invoice',
        docNo: r['doc_no'] as String,
        partyOrMemberName: r['party_name'] as String,
        gstin: r['gstin'] as String?,
        stateCode: r['state_code'] as String?,
        taxablePaise: r['taxable'] as int? ?? 0,
        cgstPaise: cgst,
        sgstPaise: sgst,
        igstPaise: igst,
        totalTaxPaise: cgst + sgst + igst,
        totalPaise: r['total_paise'] as int? ?? 0,
      ));
    }

    return lines;
  }

  // Tax Registers: Inward GST (Expense bills)
  Future<List<TaxRegisterLine>> getGstInwardLines(int societyId, String from, String to, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final ebRows = await exec.rawQuery('''
      SELECT eb.bill_date as date, eb.voucher_no as doc_no, v.name as party_name,
        v.gstin, v.state_code, eb.subtotal_paise as taxable, eb.cgst_paise, eb.sgst_paise, eb.igst_paise, eb.total_paise
      FROM expense_bills eb
      JOIN vendors v ON v.id = eb.vendor_id
      WHERE eb.society_id = ? AND eb.status = 'posted' AND eb.bill_date BETWEEN ? AND ?
        AND (eb.cgst_paise > 0 OR eb.sgst_paise > 0 OR eb.igst_paise > 0)
      ORDER BY eb.bill_date ASC, eb.id ASC
    ''', [societyId, from, to]);

    return ebRows.map((r) {
      final cgst = r['cgst_paise'] as int? ?? 0;
      final sgst = r['sgst_paise'] as int? ?? 0;
      final igst = r['igst_paise'] as int? ?? 0;
      return TaxRegisterLine(
        date: r['date'] as String,
        docType: 'Expense Bill',
        docNo: r['doc_no'] as String,
        partyOrMemberName: r['party_name'] as String,
        gstin: r['gstin'] as String?,
        stateCode: r['state_code'] as String?,
        taxablePaise: r['taxable'] as int? ?? 0,
        cgstPaise: cgst,
        sgstPaise: sgst,
        igstPaise: igst,
        totalTaxPaise: cgst + sgst + igst,
        totalPaise: r['total_paise'] as int? ?? 0,
      );
    }).toList();
  }

  // TDS Lines: Deducted on vendor bills + Receivable from FD
  Future<List<TdsRegisterLine>> getTdsLines(int societyId, String from, String to, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final lines = <TdsRegisterLine>[];

    // Vendor Bills (TDS Deducted / Payable)
    final vRows = await exec.rawQuery('''
      SELECT eb.bill_date as date, eb.voucher_no as doc_no, v.name as deductee_name,
        v.pan, ts.code as section_code, eb.subtotal_paise as gross, eb.tds_rate_bp, eb.tds_paise
      FROM expense_bills eb
      JOIN vendors v ON v.id = eb.vendor_id
      LEFT JOIN tds_sections ts ON ts.id = eb.tds_section_id
      WHERE eb.society_id = ? AND eb.status = 'posted' AND eb.bill_date BETWEEN ? AND ?
        AND eb.tds_paise > 0
      ORDER BY eb.bill_date ASC, eb.id ASC
    ''', [societyId, from, to]);

    for (final r in vRows) {
      lines.add(TdsRegisterLine(
        date: r['date'] as String,
        docType: 'Expense Bill',
        docNo: r['doc_no'] as String,
        deducteeName: r['deductee_name'] as String,
        pan: r['pan'] as String?,
        sectionCode: (r['section_code'] as String?) ?? '194C',
        grossAmountPaise: r['gross'] as int? ?? 0,
        tdsRateBp: r['tds_rate_bp'] as int? ?? 0,
        tdsPaise: r['tds_paise'] as int? ?? 0,
        isPayable: true,
      ));
    }

    // Fixed Deposit Transactions (TDS Deducted by Bank / Receivable)
    final fdRows = await exec.rawQuery('''
      SELECT fdt.txn_date as date, fd.fd_no as doc_no, fd.bank_name as deductee_name,
        fdt.amount_paise as gross, fd.tds_rate_bp, fdt.tds_paise
      FROM fd_transactions fdt
      JOIN fixed_deposits fd ON fd.id = fdt.fd_id
      WHERE fdt.society_id = ? AND fdt.status = 'posted' AND fdt.txn_date BETWEEN ? AND ?
        AND fdt.tds_paise > 0
      ORDER BY fdt.txn_date ASC, fdt.id ASC
    ''', [societyId, from, to]);

    for (final r in fdRows) {
      lines.add(TdsRegisterLine(
        date: r['date'] as String,
        docType: 'Fixed Deposit',
        docNo: r['doc_no'] as String,
        deducteeName: r['deductee_name'] as String,
        sectionCode: '194A',
        grossAmountPaise: r['gross'] as int? ?? 0,
        tdsRateBp: r['tds_rate_bp'] as int? ?? 0,
        tdsPaise: r['tds_paise'] as int? ?? 0,
        isPayable: false,
      ));
    }

    return lines;
  }
}
