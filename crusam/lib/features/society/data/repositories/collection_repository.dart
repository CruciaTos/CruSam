import 'package:sqflite/sqflite.dart';
import '../models/collection_models.dart';
import '../models/society_models.dart';

class CollectionRepository {
  final Database db;
  CollectionRepository(this.db);

  // -------------------------------------------------------------
  // Receipts
  // -------------------------------------------------------------

  Future<PageResult<Receipt>> listReceipts(
    int societyId, {
    int? unitId,
    String? status,
    String? fromDate,
    String? toDate,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('r.society_id = ?');
    final args = <Object?>[societyId];

    if (unitId != null) {
      where.write(' AND r.unit_id = ?');
      args.add(unitId);
    }
    if (status != null && status.isNotEmpty) {
      where.write(' AND r.status = ?');
      args.add(status);
    }
    if (fromDate != null && fromDate.isNotEmpty) {
      where.write(' AND r.receipt_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      where.write(' AND r.receipt_date <= ?');
      args.add(toDate);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM receipts r WHERE $where';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        r.*,
        u.unit_no,
        b.name as block_name,
        acc.name as bank_account_name,
        COALESCE((
          SELECT SUM(ba.allocated_paise) 
          FROM bill_allocations ba 
          WHERE ba.source_type = 'receipt' AND ba.source_id = r.id AND ba.is_active = 1
        ), 0) as allocated_paise
      FROM receipts r
      JOIN units u ON r.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      LEFT JOIN accounts acc ON r.bank_cash_account_id = acc.id
      WHERE $where
      ORDER BY r.receipt_date DESC, r.id DESC
      LIMIT ? OFFSET ?
    ''';

    final rows = await exec.rawQuery(selectSql, [...args, page.limit, page.offset]);
    final list = rows.map((row) {
      final alloc = (row['allocated_paise'] as int?) ?? 0;
      return Receipt.fromMap(row, alloc);
    }).toList();

    return PageResult(list, total);
  }

  Future<Receipt?> getReceipt(DatabaseExecutor executor, int receiptId) async {
    final sql = '''
      SELECT 
        r.*,
        u.unit_no,
        b.name as block_name,
        acc.name as bank_account_name,
        COALESCE((
          SELECT SUM(ba.allocated_paise) 
          FROM bill_allocations ba 
          WHERE ba.source_type = 'receipt' AND ba.source_id = r.id AND ba.is_active = 1
        ), 0) as allocated_paise
      FROM receipts r
      JOIN units u ON r.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      LEFT JOIN accounts acc ON r.bank_cash_account_id = acc.id
      WHERE r.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [receiptId]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final alloc = (row['allocated_paise'] as int?) ?? 0;
    return Receipt.fromMap(row, alloc);
  }

  Future<int> insertReceipt(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('receipts', values);
  }

  Future<void> updateReceiptStatus(
    DatabaseExecutor executor,
    int receiptId,
    String status, {
    String? reversalKind,
    String? reversalReason,
    int? reversalEntryId,
  }) {
    final map = <String, Object?>{'status': status};
    if (reversalKind != null) map['reversal_kind'] = reversalKind;
    if (reversalReason != null) map['reversal_reason'] = reversalReason;
    if (reversalEntryId != null) map['reversal_entry_id'] = reversalEntryId;
    return executor.update('receipts', map, where: 'id = ?', whereArgs: [receiptId]);
  }

  // -------------------------------------------------------------
  // Allocations
  // -------------------------------------------------------------

  Future<List<BillAllocation>> listAllocations(
    int societyId, {
    String? sourceType,
    int? sourceId,
    int? billLineId,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('ba.society_id = ? AND ba.is_active = 1');
    final args = <Object?>[societyId];

    if (sourceType != null) {
      where.write(' AND ba.source_type = ?');
      args.add(sourceType);
    }
    if (sourceId != null) {
      where.write(' AND ba.source_id = ?');
      args.add(sourceId);
    }
    if (billLineId != null) {
      where.write(' AND ba.bill_line_id = ?');
      args.add(billLineId);
    }

    final sql = '''
      SELECT 
        ba.*,
        bl.bill_id,
        b.bill_no,
        ch.name as charge_head_name
      FROM bill_allocations ba
      JOIN bill_lines bl ON ba.bill_line_id = bl.id
      JOIN bills b ON bl.bill_id = b.id
      JOIN charge_heads ch ON bl.charge_head_id = ch.id
      WHERE $where
      ORDER BY ba.allocation_date ASC, ba.id ASC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map(BillAllocation.fromMap).toList();
  }

  Future<int> insertAllocation(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('bill_allocations', values);
  }

  Future<void> deactivateAllocationsForSource(
    DatabaseExecutor executor,
    String sourceType,
    int sourceId,
  ) {
    return executor.update(
      'bill_allocations',
      {'is_active': 0},
      where: 'source_type = ? AND source_id = ? AND is_active = 1',
      whereArgs: [sourceType, sourceId],
    );
  }

  // -------------------------------------------------------------
  // Open Bill Lines for Unit
  // -------------------------------------------------------------

  Future<List<OpenBillLine>> getOpenBillLines(
    DatabaseExecutor executor,
    int societyId,
    int unitId, {
    String? asOfDate,
  }) async {
    // 1. Posted bills for this unit (status = 'posted')
    // 2. Order by:
    //    - bill due_date ASC, bill_date ASC, bill id ASC
    //    - interest lines first (ch.head_kind = 'interest' DESC), then line_no ASC
    final dateFilter = asOfDate != null ? 'AND b.bill_date <= ?' : '';
    final args = <Object?>[societyId, unitId];
    if (asOfDate != null) args.add(asOfDate);

    final sql = '''
      SELECT 
        b.id as bill_id,
        b.bill_no,
        b.bill_date,
        b.due_date,
        bl.id as bill_line_id,
        bl.line_no,
        bl.charge_head_id,
        ch.name as charge_head_name,
        ch.head_kind,
        ch.is_interest_bearing,
        bl.payable_paise,
        COALESCE((
          SELECT SUM(ba.allocated_paise)
          FROM bill_allocations ba
          WHERE ba.bill_line_id = bl.id AND ba.is_active = 1
        ), 0) as allocated_paise
      FROM bill_lines bl
      JOIN bills b ON bl.bill_id = b.id
      JOIN charge_heads ch ON bl.charge_head_id = ch.id
      WHERE b.society_id = ? AND b.unit_id = ? AND b.status = 'posted' $dateFilter
      ORDER BY 
        b.due_date ASC, 
        b.bill_date ASC, 
        b.id ASC, 
        CASE WHEN ch.head_kind = 'interest' THEN 0 ELSE 1 END ASC, 
        bl.line_no ASC
    ''';

    final rows = await executor.rawQuery(sql, args);
    final results = <OpenBillLine>[];
    for (final r in rows) {
      final payable = (r['payable_paise'] as int?) ?? 0;
      final allocated = (r['allocated_paise'] as int?) ?? 0;
      if (payable > allocated) {
        results.add(OpenBillLine(
          billId: r['bill_id'] as int,
          billNo: (r['bill_no'] as String?) ?? '',
          billDate: r['bill_date'] as String,
          dueDate: r['due_date'] as String,
          billLineId: r['bill_line_id'] as int,
          lineNo: r['line_no'] as int,
          chargeHeadId: r['charge_head_id'] as int,
          chargeHeadName: (r['charge_head_name'] as String?) ?? '',
          headKind: (r['head_kind'] as String?) ?? 'charge',
          isInterestBearing: (r['is_interest_bearing'] as int?) == 1,
          payablePaise: payable,
          allocatedPaise: allocated,
        ));
      }
    }
    return results;
  }

  // -------------------------------------------------------------
  // Credit Notes
  // -------------------------------------------------------------

  Future<PageResult<CreditNote>> listCreditNotes(
    int societyId, {
    int? unitId,
    String? status,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('cn.society_id = ?');
    final args = <Object?>[societyId];

    if (unitId != null) {
      where.write(' AND cn.unit_id = ?');
      args.add(unitId);
    }
    if (status != null && status.isNotEmpty) {
      where.write(' AND cn.status = ?');
      args.add(status);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM credit_notes cn WHERE $where';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        cn.*,
        u.unit_no,
        b.name as block_name,
        ch.name as charge_head_name
      FROM credit_notes cn
      JOIN units u ON cn.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      LEFT JOIN charge_heads ch ON cn.charge_head_id = ch.id
      WHERE $where
      ORDER BY cn.note_date DESC, cn.id DESC
      LIMIT ? OFFSET ?
    ''';
    final rows = await exec.rawQuery(selectSql, [...args, page.limit, page.offset]);
    return PageResult(rows.map(CreditNote.fromMap).toList(), total);
  }

  Future<CreditNote?> getCreditNote(DatabaseExecutor executor, int id) async {
    final sql = '''
      SELECT 
        cn.*,
        u.unit_no,
        b.name as block_name,
        ch.name as charge_head_name
      FROM credit_notes cn
      JOIN units u ON cn.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      LEFT JOIN charge_heads ch ON cn.charge_head_id = ch.id
      WHERE cn.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;
    return CreditNote.fromMap(rows.first);
  }

  Future<int> insertCreditNote(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('credit_notes', values);
  }

  Future<void> updateCreditNoteStatus(
    DatabaseExecutor executor,
    int id,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
  }) {
    final map = <String, Object?>{'status': status};
    if (reversalReason != null) map['reversal_reason'] = reversalReason;
    if (reversalEntryId != null) map['reversal_entry_id'] = reversalEntryId;
    return executor.update('credit_notes', map, where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------
  // Unidentified Receipts
  // -------------------------------------------------------------

  Future<PageResult<UnidentifiedReceipt>> listUnidentified(
    int societyId, {
    String? status,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('ur.society_id = ?');
    final args = <Object?>[societyId];

    if (status != null && status.isNotEmpty) {
      where.write(' AND ur.status = ?');
      args.add(status);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM unidentified_receipts ur WHERE $where';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        ur.*,
        acc.name as bank_account_name
      FROM unidentified_receipts ur
      JOIN accounts acc ON ur.bank_cash_account_id = acc.id
      WHERE $where
      ORDER BY ur.receipt_date DESC, ur.id DESC
      LIMIT ? OFFSET ?
    ''';
    final rows = await exec.rawQuery(selectSql, [...args, page.limit, page.offset]);
    return PageResult(rows.map(UnidentifiedReceipt.fromMap).toList(), total);
  }

  Future<UnidentifiedReceipt?> getUnidentified(DatabaseExecutor executor, int id) async {
    final sql = '''
      SELECT 
        ur.*,
        acc.name as bank_account_name
      FROM unidentified_receipts ur
      JOIN accounts acc ON ur.bank_cash_account_id = acc.id
      WHERE ur.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;
    return UnidentifiedReceipt.fromMap(rows.first);
  }

  Future<int> insertUnidentified(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('unidentified_receipts', values);
  }

  Future<void> updateUnidentifiedStatus(
    DatabaseExecutor executor,
    int id,
    String status, {
    int? resolvedReceiptId,
    bool clearResolvedReceipt = false,
    int? reversalEntryId,
    String? reversalReason,
  }) {
    final map = <String, Object?>{'status': status};
    if (clearResolvedReceipt) {
      map['resolved_receipt_id'] = null;
    } else if (resolvedReceiptId != null) {
      map['resolved_receipt_id'] = resolvedReceiptId;
    }
    if (reversalEntryId != null) map['reversal_entry_id'] = reversalEntryId;
    if (reversalReason != null) map['reversal_reason'] = reversalReason;
    return executor.update('unidentified_receipts', map, where: 'id = ?', whereArgs: [id]);
  }
}
