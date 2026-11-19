import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/repositories/ledger_repository.dart';
import 'package:crusam/features/society/data/repositories/society_repository.dart';

class LedgerService {
  final Database db;
  late final LedgerRepository _repo;
  late final SocietyRepository _socRepo;

  LedgerService(this.db) {
    _repo = LedgerRepository(db);
    _socRepo = SocietyRepository(db);
  }

  Future<FinancialYear> requireOpenYear(DatabaseExecutor executor, int societyId, String date) async {
    final rows = await executor.query(
      'financial_years',
      where: 'society_id = ? AND start_date <= ? AND end_date >= ?',
      whereArgs: [societyId, date, date],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw SocietyException('closed_year', 'No financial year configured for date $date');
    }
    final fy = FinancialYear.fromMap(rows.first);
    if (!fy.isOpen) {
      throw SocietyException('closed_year', 'Financial year ${fy.code} for date $date is closed');
    }
    return fy;
  }

  Future<int> accountIdForKey(DatabaseExecutor executor, int societyId, String systemKey) async {
    final acc = await _repo.getAccountBySystemKey(executor, societyId, systemKey);
    if (acc == null) {
      throw SocietyException('not_found', 'Required system account "$systemKey" not found');
    }
    return acc.id;
  }

  Future<Account?> getAccount(int accountId, {DatabaseExecutor? executor}) {
    return _repo.getAccount(executor ?? db, accountId);
  }

  Future<Account?> getAccountByCode(int societyId, String code) {
    return _repo.getAccountByCode(db, societyId, code);
  }

  Future<List<AccountGroup>> listGroups(int societyId) {
    return _repo.listGroups(societyId);
  }

  Future<String> nextNumber(Transaction txn, int societyId, int fyId, String docType) async {
    final series = await _repo.getNumberSeries(txn, societyId, fyId, docType);
    if (series == null) {
      throw SocietyException('not_found', 'No number series found for doc_type: $docType');
    }
    final formatted = '${series.prefix}${series.nextNo.toString().padLeft(series.pad, '0')}';
    await _repo.incrementNumberSeries(txn, series.id);
    return formatted;
  }

  Future<PostedJournal> post(Transaction txn, JournalDraft draft) async {
    // 1. At least two lines
    if (draft.lines.length < 2) {
      throw const SocietyException('validation', 'Journal entry must have at least two lines');
    }

    var totalDebit = 0;
    var totalCredit = 0;

    // 2. Every line has exactly one positive side
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final isDebit = line.debitPaise > 0 && line.creditPaise == 0;
      final isCredit = line.creditPaise > 0 && line.debitPaise == 0;
      if (!isDebit && !isCredit) {
        throw SocietyException(
          'validation',
          'Line ${i + 1} must have either positive debit or positive credit (not both or zero)',
        );
      }
      totalDebit += line.debitPaise;
      totalCredit += line.creditPaise;
    }

    // 3. Total debit equals total credit
    if (totalDebit != totalCredit) {
      throw SocietyException(
        'unbalanced_entry',
        'Unbalanced journal entry: Total Debit $totalDebit does not equal Total Credit $totalCredit',
      );
    }

    // 4. Entry date on or after books_start_date
    final society = await _socRepo.getSociety(draft.societyId, txn);
    if (society == null) {
      throw SocietyException('wrong_society', 'Society not found: ${draft.societyId}');
    }
    if (draft.entryDate.compareTo(society.booksStartDate) < 0) {
      throw SocietyException(
        'before_books_start',
        'Entry date ${draft.entryDate} is before books start date ${society.booksStartDate}',
      );
    }

    // 5. Financial year open
    final fy = await requireOpenYear(txn, draft.societyId, draft.entryDate);

    // 6 - 11. Validate accounts and specific requirements
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final acc = await _repo.getAccount(txn, line.accountId);
      if (acc == null || acc.societyId != draft.societyId) {
        throw SocietyException('wrong_society', 'Account ${line.accountId} does not belong to this society');
      }
      if (!acc.isActive) {
        throw SocietyException('inactive_account', 'Account "${acc.name}" (${acc.code}) is inactive');
      }

      // 7. Member receivables requires unit_id
      if (acc.systemKey == 'members_receivable' && line.unitId == null) {
        throw SocietyException('validation', 'Line ${i + 1} (${acc.name}) requires a unit selection');
      }

      // 8. Other receivables requires party_id
      if (acc.systemKey == 'other_receivable' && line.partyId == null) {
        throw SocietyException('validation', 'Line ${i + 1} (${acc.name}) requires a party selection');
      }

      // 9. Payable requires vendor_id
      if (acc.systemKey == 'vendors_payable' && line.vendorId == null) {
        throw SocietyException('validation', 'Line ${i + 1} (${acc.name}) requires a vendor selection');
      }

      // 10. Refundable deposits requires unit_id
      if (acc.systemKey == 'refundable_deposits' && line.unitId == null) {
        throw SocietyException('validation', 'Line ${i + 1} (${acc.name}) requires a unit selection');
      }

      // 11. Vendor advances requires vendor_id
      if (acc.systemKey == 'vendor_advances' && line.vendorId == null) {
        throw SocietyException('validation', 'Line ${i + 1} (${acc.name}) requires a vendor selection');
      }
    }

    final entryNo = await nextNumber(txn, draft.societyId, fy.id, 'journal');

    final entryId = await _repo.insertJournalEntry(
      txn,
      societyId: draft.societyId,
      fyId: fy.id,
      entryNo: entryNo,
      entryDate: draft.entryDate,
      sourceType: draft.sourceType,
      sourceId: draft.sourceId,
      narration: draft.narration,
    );

    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      await _repo.insertJournalLine(
        txn,
        societyId: draft.societyId,
        entryId: entryId,
        lineNo: i + 1,
        accountId: line.accountId,
        debitPaise: line.debitPaise,
        creditPaise: line.creditPaise,
        unitId: line.unitId,
        vendorId: line.vendorId,
        partyId: line.partyId,
        note: line.note,
      );
    }

    await _socRepo.insertAudit(
      txn,
      draft.societyId,
      'post',
      'journal_entry',
      entryId,
      'Posted journal $entryNo for $totalDebit paise',
    );

    return PostedJournal(id: entryId, fyId: fy.id, entryNo: entryNo);
  }

  Future<PostedJournal> postManual(JournalDraft draft) {
    return db.transaction((txn) => post(txn, draft));
  }

  Future<PostedJournal> reverse(
    Transaction txn,
    int societyId,
    int entryId,
    String reversalDate,
    String reason,
  ) async {
    final original = await _repo.entryDetail(societyId, entryId, txn);
    if (original == null) {
      throw SocietyException('not_found', 'Journal entry not found: $entryId');
    }
    if (original.status == 'reversed') {
      throw const SocietyException('already_reversed', 'This journal entry has already been reversed');
    }
    if (original.reversalOfId != null) {
      throw const SocietyException('already_reversed', 'Cannot reverse a reversal entry');
    }
    if (reason.trim().isEmpty) {
      throw const SocietyException('validation', 'Reversal reason is required');
    }

    // Mirror every line (swap debits and credits)
    final mirrorLines = original.lines.map((l) {
      return JournalLineDraft(
        accountId: l.accountId,
        debitPaise: l.creditPaise, // swapped
        creditPaise: l.debitPaise, // swapped
        unitId: l.unitId,
        vendorId: l.vendorId,
        partyId: l.partyId,
        note: 'Reversal of ${original.entryNo}: ${l.note ?? ""}'.trim(),
      );
    }).toList();

    final reversalDraft = JournalDraft(
      societyId: societyId,
      entryDate: reversalDate,
      sourceType: 'reversal',
      sourceId: entryId,
      narration: 'Reversal of ${original.entryNo}: $reason',
      lines: mirrorLines,
    );

    final posted = await post(txn, reversalDraft);

    await _repo.markJournalReversed(
      txn,
      originalEntryId: entryId,
      reversalEntryId: posted.id,
    );

    await txn.update(
      'journal_entries',
      {'reversal_of_id': entryId},
      where: 'id = ?',
      whereArgs: [posted.id],
    );

    await _socRepo.insertAudit(
      txn,
      societyId,
      'reverse',
      'journal_entry',
      entryId,
      'Reversed journal ${original.entryNo} with ${posted.entryNo} ($reason)',
    );

    return posted;
  }

  Future<void> reverseManual(
    int societyId,
    int entryId,
    String reversalDate,
    String reason,
  ) {
    return db.transaction((txn) => reverse(txn, societyId, entryId, reversalDate, reason));
  }

  Future<List<AccountTreeGroup>> chartOfAccounts(int societyId, {bool includeInactive = false}) async {
    final groups = await _repo.listGroups(societyId, includeInactive: includeInactive);
    final accounts = await _repo.listAccounts(societyId, includeInactive: includeInactive);

    final accountsByGroup = <int, List<Account>>{};
    for (final a in accounts) {
      accountsByGroup.putIfAbsent(a.groupId, () => []).add(a);
    }

    final result = <AccountTreeGroup>[];
    for (final g in groups) {
      result.add(AccountTreeGroup(
        group: g,
        accounts: accountsByGroup[g.id] ?? [],
      ));
    }
    return result;
  }

  Future<List<Account>> listAccounts(int societyId, {bool includeInactive = false}) {
    return _repo.listAccounts(societyId, includeInactive: includeInactive);
  }

  Future<int> createGroup(int societyId, AccountGroupDraft draft) {
    return db.transaction((txn) => _repo.insertGroup(txn, societyId, draft));
  }

  Future<int> createAccount(int societyId, AccountDraft draft) {
    return db.transaction((txn) => _repo.insertAccount(txn, societyId, draft));
  }

  Future<void> updateAccount(int societyId, int accountId, AccountDraft draft) {
    return db.transaction((txn) => _repo.updateAccount(txn, societyId, accountId, draft));
  }

  Future<void> setAccountActive(int societyId, int accountId, bool active) {
    return db.transaction((txn) => _repo.setAccountActive(txn, societyId, accountId, active));
  }

  Future<void> saveOpeningBalances(int societyId, List<OpeningBalanceDraft> rows) async {
    if (rows.isEmpty) return;

    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    final asOfDate = rows.first.asOfDate;
    var totalDebit = 0;
    var totalCredit = 0;

    final lines = <JournalLineDraft>[];
    for (final r in rows) {
      if (r.debitPaise > 0 || r.creditPaise > 0) {
        lines.add(JournalLineDraft(
          accountId: r.accountId,
          debitPaise: r.debitPaise,
          creditPaise: r.creditPaise,
          note: r.narration ?? 'Opening balance',
        ));
        totalDebit += r.debitPaise;
        totalCredit += r.creditPaise;
      }
    }

    if (lines.isEmpty) return;

    // Balancing opening_adjustment if needed
    if (totalDebit != totalCredit) {
      final adjAccountId = await accountIdForKey(db, societyId, 'opening_adjustment');
      if (totalDebit > totalCredit) {
        lines.add(JournalLineDraft(
          accountId: adjAccountId,
          creditPaise: totalDebit - totalCredit,
          note: 'Opening balance difference adjustment',
        ));
      } else {
        lines.add(JournalLineDraft(
          accountId: adjAccountId,
          debitPaise: totalCredit - totalDebit,
          note: 'Opening balance difference adjustment',
        ));
      }
    }

    final draft = JournalDraft(
      societyId: societyId,
      entryDate: asOfDate,
      sourceType: 'opening',
      narration: 'Account Opening Balances as of $asOfDate',
      lines: lines,
    );

    await postManual(draft);
  }

  Future<PageResult<JournalEntryRow>> listEntries(
    int societyId,
    JournalFilter filter,
    PageRequest page,
  ) {
    return _repo.listEntries(societyId, filter, page);
  }

  Future<JournalEntryDetail> entryDetail(int societyId, int entryId) async {
    final detail = await _repo.entryDetail(societyId, entryId);
    if (detail == null) {
      throw SocietyException('not_found', 'Journal entry not found: $entryId');
    }
    return detail;
  }

  Future<LedgerResult> ledgerEnquiry(
    int societyId,
    LedgerFilter filter,
    PageRequest page,
  ) async {
    final whereBefore = StringBuffer("jl.society_id = ? AND je.status IN ('posted', 'reversed') AND je.entry_date < ?");
    final argsBefore = <Object?>[societyId, filter.fromDate];

    if (filter.accountId != null) {
      whereBefore.write(' AND jl.account_id = ?');
      argsBefore.add(filter.accountId);
    }
    if (filter.groupId != null) {
      whereBefore.write(' AND a.group_id = ?');
      argsBefore.add(filter.groupId);
    }
    if (filter.unitId != null) {
      whereBefore.write(' AND jl.unit_id = ?');
      argsBefore.add(filter.unitId);
    }
    if (filter.vendorId != null) {
      whereBefore.write(' AND jl.vendor_id = ?');
      argsBefore.add(filter.vendorId);
    }
    if (filter.partyId != null) {
      whereBefore.write(' AND jl.party_id = ?');
      argsBefore.add(filter.partyId);
    }

    final openSql = '''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as bal
      FROM journal_lines jl
      JOIN journal_entries je ON jl.entry_id = je.id
      JOIN accounts a ON jl.account_id = a.id
      WHERE $whereBefore
    ''';
    final openRows = await db.rawQuery(openSql, argsBefore);
    final openingBalance = (openRows.first['bal'] as int?) ?? 0;

    final wherePeriod = StringBuffer("jl.society_id = ? AND je.status IN ('posted', 'reversed') AND je.entry_date >= ? AND je.entry_date <= ?");
    final argsPeriod = <Object?>[societyId, filter.fromDate, filter.toDate];

    if (filter.accountId != null) {
      wherePeriod.write(' AND jl.account_id = ?');
      argsPeriod.add(filter.accountId);
    }
    if (filter.groupId != null) {
      wherePeriod.write(' AND a.group_id = ?');
      argsPeriod.add(filter.groupId);
    }
    if (filter.unitId != null) {
      wherePeriod.write(' AND jl.unit_id = ?');
      argsPeriod.add(filter.unitId);
    }
    if (filter.vendorId != null) {
      wherePeriod.write(' AND jl.vendor_id = ?');
      argsPeriod.add(filter.vendorId);
    }
    if (filter.partyId != null) {
      wherePeriod.write(' AND jl.party_id = ?');
      argsPeriod.add(filter.partyId);
    }

    final totalsSql = '''
      SELECT 
        COALESCE(SUM(jl.debit_paise), 0) as total_debit,
        COALESCE(SUM(jl.credit_paise), 0) as total_credit,
        COUNT(*) as total_rows
      FROM journal_lines jl
      JOIN journal_entries je ON jl.entry_id = je.id
      JOIN accounts a ON jl.account_id = a.id
      WHERE $wherePeriod
    ''';
    final totalsRows = await db.rawQuery(totalsSql, argsPeriod);
    final totalDebit = (totalsRows.first['total_debit'] as int?) ?? 0;
    final totalCredit = (totalsRows.first['total_credit'] as int?) ?? 0;
    final totalRows = (totalsRows.first['total_rows'] as int?) ?? 0;

    final linesSql = '''
      SELECT 
        je.id as journal_id,
        je.entry_no,
        je.entry_date,
        je.narration,
        je.source_type,
        je.source_id,
        a.code as account_code,
        a.name as account_name,
        jl.debit_paise,
        jl.credit_paise
      FROM journal_lines jl
      JOIN journal_entries je ON jl.entry_id = je.id
      JOIN accounts a ON jl.account_id = a.id
      WHERE $wherePeriod
      ORDER BY je.entry_date ASC, je.id ASC, jl.line_no ASC
      LIMIT ? OFFSET ?
    ''';
    final linesArgs = List<Object?>.from(argsPeriod)..addAll([page.limit, page.offset]);
    final lineRows = await db.rawQuery(linesSql, linesArgs);

    var running = openingBalance;
    final lines = <LedgerLine>[];
    for (final r in lineRows) {
      final deb = r['debit_paise'] as int;
      final cred = r['credit_paise'] as int;
      running += (deb - cred);
      lines.add(LedgerLine(
        journalId: r['journal_id'] as int,
        entryNo: r['entry_no'] as String,
        date: r['entry_date'] as String,
        narration: r['narration'] as String,
        accountCode: r['account_code'] as String,
        accountName: r['account_name'] as String,
        debitPaise: deb,
        creditPaise: cred,
        runningBalancePaise: running,
        sourceType: r['source_type'] as String,
        sourceId: r['source_id'] as int?,
      ));
    }

    final closingBalance = openingBalance + totalDebit - totalCredit;

    return LedgerResult(
      openingBalancePaise: openingBalance,
      totalDebitPaise: totalDebit,
      totalCreditPaise: totalCredit,
      closingBalancePaise: closingBalance,
      lines: PageResult(lines, totalRows),
    );
  }

  Future<TrialBalance> trialBalance(int societyId, String from, String to) async {
    final sql = '''
      SELECT 
        a.id as account_id,
        a.code as account_code,
        a.name as account_name,
        g.account_type,
        g.name as group_name,
        COALESCE((
          SELECT SUM(jl.debit_paise)
          FROM journal_lines jl
          JOIN journal_entries je ON jl.entry_id = je.id
          WHERE jl.account_id = a.id AND je.status IN ('posted', 'reversed') AND je.entry_date < ?
        ), 0) as open_debit,
        COALESCE((
          SELECT SUM(jl.credit_paise)
          FROM journal_lines jl
          JOIN journal_entries je ON jl.entry_id = je.id
          WHERE jl.account_id = a.id AND je.status IN ('posted', 'reversed') AND je.entry_date < ?
        ), 0) as open_credit,
        COALESCE((
          SELECT SUM(jl.debit_paise)
          FROM journal_lines jl
          JOIN journal_entries je ON jl.entry_id = je.id
          WHERE jl.account_id = a.id AND je.status IN ('posted', 'reversed') AND je.entry_date >= ? AND je.entry_date <= ?
        ), 0) as period_debit,
        COALESCE((
          SELECT SUM(jl.credit_paise)
          FROM journal_lines jl
          JOIN journal_entries je ON jl.entry_id = je.id
          WHERE jl.account_id = a.id AND je.status IN ('posted', 'reversed') AND je.entry_date >= ? AND je.entry_date <= ?
        ), 0) as period_credit
      FROM accounts a
      JOIN account_groups g ON a.group_id = g.id
      WHERE a.society_id = ? AND a.is_active = 1
      ORDER BY a.code ASC
    ''';

    final rows = await db.rawQuery(sql, [from, from, from, to, from, to, societyId]);

    var totOpenDeb = 0;
    var totOpenCred = 0;
    var totPeriodDeb = 0;
    var totPeriodCred = 0;
    var totCloseDeb = 0;
    var totCloseCred = 0;

    final tbRows = <TrialBalanceRow>[];
    for (final r in rows) {
      final od = r['open_debit'] as int;
      final oc = r['open_credit'] as int;
      final pd = r['period_debit'] as int;
      final pc = r['period_credit'] as int;

      final netOpening = od - oc;
      final netClosing = netOpening + pd - pc;

      final closingDeb = netClosing > 0 ? netClosing : 0;
      final closingCred = netClosing < 0 ? -netClosing : 0;

      final openingDeb = netOpening > 0 ? netOpening : 0;
      final openingCred = netOpening < 0 ? -netOpening : 0;

      totOpenDeb += openingDeb;
      totOpenCred += openingCred;
      totPeriodDeb += pd;
      totPeriodCred += pc;
      totCloseDeb += closingDeb;
      totCloseCred += closingCred;

      if (openingDeb > 0 || openingCred > 0 || pd > 0 || pc > 0 || closingDeb > 0 || closingCred > 0) {
        tbRows.add(TrialBalanceRow(
          accountId: r['account_id'] as int,
          accountCode: r['account_code'] as String,
          accountName: r['account_name'] as String,
          accountType: r['account_type'] as String,
          groupName: r['group_name'] as String,
          openingDebitPaise: openingDeb,
          openingCreditPaise: openingCred,
          debitPaise: pd,
          creditPaise: pc,
          closingDebitPaise: closingDeb,
          closingCreditPaise: closingCred,
        ));
      }
    }

    return TrialBalance(
      fromDate: from,
      toDate: to,
      rows: tbRows,
      totalDebitPaise: totPeriodDeb,
      totalCreditPaise: totPeriodCred,
      totalOpeningDebitPaise: totOpenDeb,
      totalOpeningCreditPaise: totOpenCred,
      totalClosingDebitPaise: totCloseDeb,
      totalClosingCreditPaise: totCloseCred,
    );
  }
}
