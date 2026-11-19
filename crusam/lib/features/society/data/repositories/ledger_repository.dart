import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';

class LedgerRepository {
  final Database db;
  LedgerRepository(this.db);

  Future<List<AccountGroup>> listGroups(int societyId, {bool includeInactive = false}) async {
    final where = includeInactive ? 'society_id = ?' : 'society_id = ? AND is_active = 1';
    final rows = await db.query(
      'account_groups',
      where: where,
      whereArgs: [societyId],
      orderBy: 'sort_order ASC, code ASC',
    );
    return rows.map(AccountGroup.fromMap).toList();
  }

  Future<int> insertGroup(DatabaseExecutor executor, int societyId, AccountGroupDraft draft) {
    return executor.insert('account_groups', draft.toMap(societyId));
  }

  Future<List<Account>> listAccounts(int societyId, {bool includeInactive = false, int? groupId}) async {
    var where = 'society_id = ?';
    final args = <Object?>[societyId];

    if (!includeInactive) {
      where += ' AND is_active = 1';
    }
    if (groupId != null) {
      where += ' AND group_id = ?';
      args.add(groupId);
    }

    final rows = await db.query(
      'accounts',
      where: where,
      whereArgs: args,
      orderBy: 'code ASC',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> getAccount(DatabaseExecutor executor, int accountId) async {
    final rows = await executor.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<Account?> getAccountByCode(DatabaseExecutor executor, int societyId, String code) async {
    final rows = await executor.query(
      'accounts',
      where: 'society_id = ? AND code = ?',
      whereArgs: [societyId, code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<Account?> getAccountBySystemKey(DatabaseExecutor executor, int societyId, String key) async {
    final rows = await executor.query(
      'accounts',
      where: 'society_id = ? AND system_key = ?',
      whereArgs: [societyId, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<int> insertAccount(DatabaseExecutor executor, int societyId, AccountDraft draft) {
    return executor.insert('accounts', draft.toMap(societyId));
  }

  Future<void> updateAccount(DatabaseExecutor executor, int societyId, int accountId, AccountDraft draft) {
    return executor.update(
      'accounts',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [accountId, societyId],
    );
  }

  Future<void> setAccountActive(DatabaseExecutor executor, int societyId, int accountId, bool active) {
    return executor.update(
      'accounts',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [accountId, societyId],
    );
  }

  Future<NumberSeries?> getNumberSeries(DatabaseExecutor executor, int societyId, int fyId, String docType) async {
    final rows = await executor.query(
      'number_series',
      where: 'society_id = ? AND fy_id = ? AND doc_type = ?',
      whereArgs: [societyId, fyId, docType],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NumberSeries.fromMap(rows.first);
  }

  Future<void> incrementNumberSeries(DatabaseExecutor executor, int seriesId) {
    return executor.rawUpdate(
      'UPDATE number_series SET next_no = next_no + 1 WHERE id = ?',
      [seriesId],
    );
  }

  Future<int> insertJournalEntry(
    DatabaseExecutor executor, {
    required int societyId,
    required int fyId,
    required String entryNo,
    required String entryDate,
    required String sourceType,
    int? sourceId,
    required String narration,
    String status = 'posted',
    int? reversalOfId,
    int? reversedById,
  }) {
    return executor.insert('journal_entries', {
      'society_id': societyId,
      'fy_id': fyId,
      'entry_no': entryNo,
      'entry_date': entryDate,
      'source_type': sourceType,
      'source_id': sourceId,
      'narration': narration,
      'status': status,
      'reversal_of_id': reversalOfId,
      'reversed_by_id': reversedById,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> insertJournalLine(
    DatabaseExecutor executor, {
    required int societyId,
    required int entryId,
    required int lineNo,
    required int accountId,
    required int debitPaise,
    required int creditPaise,
    int? unitId,
    int? vendorId,
    int? partyId,
    String? note,
  }) {
    return executor.insert('journal_lines', {
      'society_id': societyId,
      'entry_id': entryId,
      'line_no': lineNo,
      'account_id': accountId,
      'debit_paise': debitPaise,
      'credit_paise': creditPaise,
      'unit_id': unitId,
      'vendor_id': vendorId,
      'party_id': partyId,
      'note': note,
    });
  }

  Future<void> markJournalReversed(
    DatabaseExecutor executor, {
    required int originalEntryId,
    required int reversalEntryId,
  }) {
    return executor.update(
      'journal_entries',
      {
        'status': 'reversed',
        'reversed_by_id': reversalEntryId,
      },
      where: 'id = ?',
      whereArgs: [originalEntryId],
    );
  }

  Future<PageResult<JournalEntryRow>> listEntries(
    int societyId,
    JournalFilter filter,
    PageRequest page,
  ) async {
    final where = StringBuffer('je.society_id = ?');
    final args = <Object?>[societyId];

    if (filter.fromDate != null && filter.fromDate!.isNotEmpty) {
      where.write(' AND je.entry_date >= ?');
      args.add(filter.fromDate);
    }
    if (filter.toDate != null && filter.toDate!.isNotEmpty) {
      where.write(' AND je.entry_date <= ?');
      args.add(filter.toDate);
    }
    if (filter.sourceType != null && filter.sourceType!.isNotEmpty) {
      where.write(' AND je.source_type = ?');
      args.add(filter.sourceType);
    }
    if (filter.status != null && filter.status!.isNotEmpty) {
      where.write(' AND je.status = ?');
      args.add(filter.status);
    }
    if (filter.accountId != null) {
      where.write(' AND EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.entry_id = je.id AND jl.account_id = ?)');
      args.add(filter.accountId);
    }
    if (filter.unitId != null) {
      where.write(' AND EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.entry_id = je.id AND jl.unit_id = ?)');
      args.add(filter.unitId);
    }
    if (page.search.isNotEmpty) {
      where.write(' AND (je.entry_no LIKE ? OR je.narration LIKE ?)');
      args.add('%${page.search}%');
      args.add('%${page.search}%');
    }

    final countSql = 'SELECT COUNT(*) as total FROM journal_entries je WHERE $where';
    final countRows = await db.rawQuery(countSql, args);
    final total = (countRows.first['total'] as int?) ?? 0;

    final querySql = '''
      SELECT 
        je.id,
        je.entry_no,
        je.entry_date,
        je.source_type,
        je.source_id,
        je.narration,
        je.status,
        COALESCE((SELECT SUM(jl.debit_paise) FROM journal_lines jl WHERE jl.entry_id = je.id), 0) as debit_total
      FROM journal_entries je
      WHERE $where
      ORDER BY je.entry_date DESC, je.id DESC
      LIMIT ? OFFSET ?
    ''';

    final queryArgs = List<Object?>.from(args)..addAll([page.limit, page.offset]);
    final rows = await db.rawQuery(querySql, queryArgs);

    final items = rows.map((r) => JournalEntryRow(
      id: r['id'] as int,
      entryNo: r['entry_no'] as String,
      entryDate: r['entry_date'] as String,
      sourceType: r['source_type'] as String,
      sourceId: r['source_id'] as int?,
      narration: r['narration'] as String,
      debitTotalPaise: (r['debit_total'] as int?) ?? 0,
      status: r['status'] as String,
    )).toList();

    return PageResult(items, total);
  }

  Future<JournalEntryDetail?> entryDetail(int societyId, int entryId, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final entryRows = await exec.query(
      'journal_entries',
      where: 'id = ? AND society_id = ?',
      whereArgs: [entryId, societyId],
      limit: 1,
    );
    if (entryRows.isEmpty) return null;
    final e = entryRows.first;

    final linesSql = '''
      SELECT 
        jl.id,
        jl.line_no,
        jl.account_id,
        a.code as account_code,
        a.name as account_name,
        jl.debit_paise,
        jl.credit_paise,
        jl.unit_id,
        u.unit_no,
        jl.vendor_id,
        v.name as vendor_name,
        jl.party_id,
        p.name as party_name,
        jl.note
      FROM journal_lines jl
      JOIN accounts a ON jl.account_id = a.id
      LEFT JOIN units u ON jl.unit_id = u.id
      LEFT JOIN vendors v ON jl.vendor_id = v.id
      LEFT JOIN parties p ON jl.party_id = p.id
      WHERE jl.entry_id = ?
      ORDER BY jl.line_no ASC
    ''';

    final lineRows = await exec.rawQuery(linesSql, [entryId]);
    final lines = lineRows.map((r) => JournalLineDetail(
      id: r['id'] as int,
      lineNo: r['line_no'] as int,
      accountId: r['account_id'] as int,
      accountCode: r['account_code'] as String,
      accountName: r['account_name'] as String,
      debitPaise: r['debit_paise'] as int,
      creditPaise: r['credit_paise'] as int,
      unitId: r['unit_id'] as int?,
      unitNo: r['unit_no'] as String?,
      vendorId: r['vendor_id'] as int?,
      vendorName: r['vendor_name'] as String?,
      partyId: r['party_id'] as int?,
      partyName: r['party_name'] as String?,
      note: r['note'] as String?,
    )).toList();

    return JournalEntryDetail(
      id: e['id'] as int,
      societyId: e['society_id'] as int,
      fyId: e['fy_id'] as int,
      entryNo: e['entry_no'] as String,
      entryDate: e['entry_date'] as String,
      sourceType: e['source_type'] as String,
      sourceId: e['source_id'] as int?,
      narration: e['narration'] as String,
      status: e['status'] as String,
      reversalOfId: e['reversal_of_id'] as int?,
      reversedById: e['reversed_by_id'] as int?,
      lines: lines,
    );
  }
}
