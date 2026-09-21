// Database access for invoices (the `vouchers` + `voucher_rows` tables).
// Every function takes a DatabaseExecutor so it works both on a Database
// and inside a Transaction.

import 'package:sqflite_common/sqlite_api.dart';

import '../models/voucher_model.dart';
import '../models/voucher_row_model.dart';

class InvoiceFilter {
  final String? client;
  final String? dateFrom; // yyyy-mm-dd, inclusive
  final String? dateTo; // yyyy-mm-dd, inclusive
  final String? status; // 'saved' | 'draft'
  final String? billNo;
  final String? poNo;
  final String? employee; // matches any row's employee name
  final bool includeDeleted;
  final int limit;
  final int offset;

  const InvoiceFilter({
    this.client,
    this.dateFrom,
    this.dateTo,
    this.status,
    this.billNo,
    this.poNo,
    this.employee,
    this.includeDeleted = false,
    this.limit = 50,
    this.offset = 0,
  });
}

class DuplicateMatch {
  final int id;
  final String reason;
  final String billNo;
  final String clientName;
  final String date;
  final double finalTotal;
  const DuplicateMatch(
      this.id, this.reason, this.billNo, this.clientName, this.date, this.finalTotal);

  Map<String, Object?> toJson() => {
        'id': id,
        'reason': reason,
        'bill_no': billNo,
        'client_name': clientName,
        'date': date,
        'final_total': finalTotal,
      };
}

class VoucherStore {
  VoucherStore._();

  static const _notDeleted = '(is_deleted = 0 OR is_deleted IS NULL)';

  /// Inserts the header and all rows. Call inside a transaction so a failure
  /// part-way never leaves a header without rows.
  static Future<int> insertWithRows(DatabaseExecutor db, VoucherModel v) async {
    final header = v.toDbMap()..remove('id');
    final id = await db.insert('vouchers', header);
    for (final row in v.rows) {
      await db.insert('voucher_rows', row.toDbMap(id));
    }
    return id;
  }

  /// Replaces the header and all rows of an existing invoice.
  static Future<void> updateWithRows(
      DatabaseExecutor db, int id, VoucherModel v) async {
    final header = v.toDbMap()..remove('id');
    final n = await db.update('vouchers', header, where: 'id=?', whereArgs: [id]);
    if (n == 0) throw StateError('Invoice $id not found');
    await db.delete('voucher_rows', where: 'voucher_id=?', whereArgs: [id]);
    for (final row in v.rows) {
      await db.insert('voucher_rows', row.toDbMap(id));
    }
  }

  /// Soft delete, identical to DatabaseHelper.deleteVoucher.
  static Future<bool> softDelete(
      DatabaseExecutor db, int id, String nowUtcIso, String userEmail) async {
    final n = await db.update(
      'vouchers',
      {
        'is_deleted': 1,
        'deleted_at': nowUtcIso,
        'updated_at': nowUtcIso,
        'updated_by': userEmail,
      },
      where: 'id=? AND $_notDeleted',
      whereArgs: [id],
    );
    return n > 0;
  }

  static Future<VoucherModel?> getById(DatabaseExecutor db, int id,
      {bool includeDeleted = false}) async {
    final rows = await db.query(
      'vouchers',
      where: includeDeleted ? 'id=?' : 'id=? AND $_notDeleted',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return VoucherModel.fromDbMap(rows.first, await rowsFor(db, id));
  }

  static Future<List<VoucherRowModel>> rowsFor(DatabaseExecutor db, int id) async {
    final maps = await db.query('voucher_rows',
        where: 'voucher_id=?', whereArgs: [id], orderBy: 'id ASC');
    return maps.map(VoucherRowModel.fromDbMap).toList();
  }

  /// Returns matching headers (newest first) plus the total match count.
  static Future<(List<VoucherModel>, int)> search(
      DatabaseExecutor db, InvoiceFilter f) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!f.includeDeleted) where.add(_notDeleted);
    if (f.client != null && f.client!.trim().isNotEmpty) {
      where.add('(LOWER(client_name) LIKE ? OR LOWER(client_gstin) LIKE ?)');
      final q = '%${f.client!.trim().toLowerCase()}%';
      args.addAll([q, q]);
    }
    if (f.dateFrom != null) {
      where.add('substr(created_at,1,10) >= ?');
      args.add(f.dateFrom);
    }
    if (f.dateTo != null) {
      where.add('substr(created_at,1,10) <= ?');
      args.add(f.dateTo);
    }
    if (f.status != null) {
      where.add('status = ?');
      args.add(f.status);
    }
    if (f.billNo != null && f.billNo!.trim().isNotEmpty) {
      where.add('LOWER(TRIM(bill_no)) = ?');
      args.add(f.billNo!.trim().toLowerCase());
    }
    if (f.poNo != null && f.poNo!.trim().isNotEmpty) {
      where.add('LOWER(TRIM(po_no)) = ?');
      args.add(f.poNo!.trim().toLowerCase());
    }
    if (f.employee != null && f.employee!.trim().isNotEmpty) {
      where.add('id IN (SELECT voucher_id FROM voucher_rows '
          'WHERE LOWER(employee_name) LIKE ?)');
      args.add('%${f.employee!.trim().toLowerCase()}%');
    }
    final whereSql = where.isEmpty ? null : where.join(' AND ');
    final count = (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM vouchers${whereSql == null ? '' : ' WHERE $whereSql'}',
      args,
    ))
        .first['n'] as int;
    final maps = await db.query('vouchers',
        where: whereSql,
        whereArgs: args,
        orderBy: 'created_at DESC, id DESC',
        limit: f.limit,
        offset: f.offset);
    final out = <VoucherModel>[];
    for (final m in maps) {
      out.add(VoucherModel.fromDbMap(m, await rowsFor(db, m['id'] as int)));
    }
    return (out, count);
  }

  /// Existing (not deleted) invoices that look like the same invoice:
  /// same bill number, or same client + date + final total.
  static Future<List<DuplicateMatch>> findDuplicates(
    DatabaseExecutor db, {
    required String billNo,
    required String clientName,
    required String date,
    required double finalTotal,
    int? excludeId,
  }) async {
    final out = <DuplicateMatch>[];
    final seen = <int>{};
    DuplicateMatch toMatch(Map<String, Object?> m, String reason) => DuplicateMatch(
          m['id'] as int,
          reason,
          (m['bill_no'] as String?) ?? '',
          (m['client_name'] as String?) ?? '',
          ((m['created_at'] as String?) ?? '').split('T').first,
          (m['final_total'] as num?)?.toDouble() ?? 0,
        );
    final exclude = excludeId == null ? '' : ' AND id != $excludeId';

    if (billNo.trim().isNotEmpty) {
      final rows = await db.query('vouchers',
          where: '$_notDeleted AND LOWER(TRIM(bill_no)) = ?$exclude',
          whereArgs: [billNo.trim().toLowerCase()]);
      for (final r in rows) {
        if (seen.add(r['id'] as int)) out.add(toMatch(r, 'same bill_no'));
      }
    }
    final rows = await db.query('vouchers',
        where: '$_notDeleted AND LOWER(TRIM(client_name)) = ? '
            'AND substr(created_at,1,10) = ? AND ABS(final_total - ?) < 0.005$exclude',
        whereArgs: [clientName.trim().toLowerCase(), date, finalTotal]);
    for (final r in rows) {
      if (seen.add(r['id'] as int)) {
        out.add(toMatch(r, 'same client, date and final_total'));
      }
    }
    return out;
  }
}
