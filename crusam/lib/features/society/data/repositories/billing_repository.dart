import 'package:sqflite/sqflite.dart';
import '../models/billing_models.dart';
import '../models/society_models.dart';

class BillingRepository {
  final Database db;
  BillingRepository(this.db);

  // -------------------------------------------------------------
  // Charge Heads
  // -------------------------------------------------------------

  Future<List<ChargeHead>> listChargeHeads(int societyId, {bool includeInactive = false, DatabaseExecutor? executor}) async {
    final exec = executor ?? db;
    final where = includeInactive
        ? 'ch.society_id = ?'
        : 'ch.society_id = ? AND ch.is_active = 1';

    final sql = '''
      SELECT 
        ch.*,
        a.code as account_code,
        a.name as account_name
      FROM charge_heads ch
      JOIN accounts a ON ch.account_id = a.id
      WHERE $where
      ORDER BY ch.sort_order ASC, ch.name ASC
    ''';
    final rows = await exec.rawQuery(sql, [societyId]);
    return rows.map(ChargeHead.fromMap).toList();
  }

  Future<ChargeHead?> getChargeHead(DatabaseExecutor executor, int id) async {
    final sql = '''
      SELECT 
        ch.*,
        a.code as account_code,
        a.name as account_name
      FROM charge_heads ch
      JOIN accounts a ON ch.account_id = a.id
      WHERE ch.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;
    return ChargeHead.fromMap(rows.first);
  }

  Future<int> insertChargeHead(DatabaseExecutor executor, int societyId, ChargeHeadDraft draft) {
    return executor.insert('charge_heads', draft.toMap(societyId));
  }

  Future<void> updateChargeHead(DatabaseExecutor executor, int societyId, int id, ChargeHeadDraft draft) {
    return executor.update(
      'charge_heads',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [id, societyId],
    );
  }

  Future<void> setChargeHeadActive(DatabaseExecutor executor, int societyId, int id, bool active) {
    return executor.update(
      'charge_heads',
      {'is_active': active ? 1 : 0},
      where: 'id = ? AND society_id = ?',
      whereArgs: [id, societyId],
    );
  }

  // -------------------------------------------------------------
  // Meter Types & Slabs
  // -------------------------------------------------------------

  Future<List<MeterType>> listMeterTypes(int societyId, {bool includeInactive = false, DatabaseExecutor? executor}) async {
    final exec = executor ?? db;
    final where = includeInactive
        ? 'mt.society_id = ?'
        : 'mt.society_id = ? AND mt.is_active = 1';

    final sql = '''
      SELECT 
        mt.*,
        ch.name as charge_head_name
      FROM meter_types mt
      JOIN charge_heads ch ON mt.charge_head_id = ch.id
      WHERE $where
      ORDER BY mt.name ASC
    ''';
    final rows = await exec.rawQuery(sql, [societyId]);

    final result = <MeterType>[];
    for (final r in rows) {
      final mtId = r['id'] as int;
      final slabRows = await exec.query(
        'meter_slabs',
        where: 'meter_type_id = ?',
        whereArgs: [mtId],
        orderBy: 'seq ASC',
      );
      final slabs = slabRows.map(MeterSlab.fromMap).toList();
      result.add(MeterType.fromMap(r, slabs));
    }
    return result;
  }

  Future<MeterType?> getMeterType(DatabaseExecutor executor, int id) async {
    final sql = '''
      SELECT 
        mt.*,
        ch.name as charge_head_name
      FROM meter_types mt
      JOIN charge_heads ch ON mt.charge_head_id = ch.id
      WHERE mt.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;

    final slabRows = await executor.query(
      'meter_slabs',
      where: 'meter_type_id = ?',
      whereArgs: [id],
      orderBy: 'seq ASC',
    );
    final slabs = slabRows.map(MeterSlab.fromMap).toList();
    return MeterType.fromMap(rows.first, slabs);
  }

  Future<int> insertMeterType(DatabaseExecutor executor, int societyId, MeterTypeDraft draft) async {
    final id = await executor.insert('meter_types', draft.toMap(societyId));
    for (final s in draft.slabs) {
      await executor.insert('meter_slabs', s.toMap(societyId, id));
    }
    return id;
  }

  Future<void> updateMeterType(DatabaseExecutor executor, int societyId, int id, MeterTypeDraft draft) async {
    await executor.update(
      'meter_types',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [id, societyId],
    );
    await executor.delete('meter_slabs', where: 'meter_type_id = ?', whereArgs: [id]);
    for (final s in draft.slabs) {
      await executor.insert('meter_slabs', s.toMap(societyId, id));
    }
  }

  // -------------------------------------------------------------
  // Billing Rules
  // -------------------------------------------------------------

  Future<List<BillingRule>> listRules(
    int societyId, {
    int? chargeHeadId,
    bool includeInactive = false,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('br.society_id = ?');
    final args = <Object?>[societyId];

    if (!includeInactive) {
      where.write(' AND br.is_active = 1');
    }
    if (chargeHeadId != null) {
      where.write(' AND br.charge_head_id = ?');
      args.add(chargeHeadId);
    }

    final sql = '''
      SELECT 
        br.*,
        ch.name as charge_head_name,
        ut.name as unit_type_name,
        mt.name as meter_type_name
      FROM billing_rules br
      JOIN charge_heads ch ON br.charge_head_id = ch.id
      LEFT JOIN unit_types ut ON br.unit_type_id = ut.id
      LEFT JOIN meter_types mt ON br.meter_type_id = mt.id
      WHERE $where
      ORDER BY ch.sort_order ASC, br.effective_from DESC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map(BillingRule.fromMap).toList();
  }

  Future<BillingRule?> getRule(DatabaseExecutor executor, int id) async {
    final sql = '''
      SELECT 
        br.*,
        ch.name as charge_head_name,
        ut.name as unit_type_name,
        mt.name as meter_type_name
      FROM billing_rules br
      JOIN charge_heads ch ON br.charge_head_id = ch.id
      LEFT JOIN unit_types ut ON br.unit_type_id = ut.id
      LEFT JOIN meter_types mt ON br.meter_type_id = mt.id
      WHERE br.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;
    return BillingRule.fromMap(rows.first);
  }

  Future<int> insertRule(DatabaseExecutor executor, int societyId, BillingRuleDraft draft) {
    return executor.insert('billing_rules', draft.toMap(societyId));
  }

  Future<void> updateRule(DatabaseExecutor executor, int societyId, int id, BillingRuleDraft draft) {
    return executor.update(
      'billing_rules',
      draft.toMap(societyId),
      where: 'id = ? AND society_id = ?',
      whereArgs: [id, societyId],
    );
  }

  Future<void> setRuleActive(DatabaseExecutor executor, int societyId, int id, bool active) {
    return executor.update(
      'billing_rules',
      {'is_active': active ? 1 : 0},
      where: 'id = ? AND society_id = ?',
      whereArgs: [id, societyId],
    );
  }

  // -------------------------------------------------------------
  // Meters & Readings
  // -------------------------------------------------------------

  Future<List<Meter>> listMeters(
    int societyId, {
    int? unitId,
    int? meterTypeId,
    bool includeInactive = false,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('m.society_id = ?');
    final args = <Object?>[societyId];

    if (!includeInactive) {
      where.write(' AND m.is_active = 1');
    }
    if (unitId != null) {
      where.write(' AND m.unit_id = ?');
      args.add(unitId);
    }
    if (meterTypeId != null) {
      where.write(' AND m.meter_type_id = ?');
      args.add(meterTypeId);
    }

    final sql = '''
      SELECT 
        m.*,
        u.unit_no,
        b.name as block_name,
        mt.name as meter_type_name,
        (SELECT reading_milli FROM meter_readings mr WHERE mr.meter_id = m.id ORDER BY mr.period_to DESC LIMIT 1) as last_reading_milli,
        (SELECT reading_date FROM meter_readings mr WHERE mr.meter_id = m.id ORDER BY mr.period_to DESC LIMIT 1) as last_reading_date
      FROM meters m
      JOIN units u ON m.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      JOIN meter_types mt ON m.meter_type_id = mt.id
      WHERE $where
      ORDER BY b.name ASC, u.unit_no ASC
    ''';
    final rows = await exec.rawQuery(sql, args);
    return rows.map(Meter.fromMap).toList();
  }

  Future<int> insertMeter(DatabaseExecutor executor, int societyId, MeterDraft draft) {
    return executor.insert('meters', draft.toMap(societyId));
  }

  Future<MeterReading?> getLatestReading(DatabaseExecutor executor, int meterId, String beforeDate) async {
    final rows = await executor.query(
      'meter_readings',
      where: 'meter_id = ? AND period_to <= ?',
      whereArgs: [meterId, beforeDate],
      orderBy: 'period_to DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MeterReading.fromMap(rows.first);
  }

  Future<int> insertMeterReading(
    DatabaseExecutor executor,
    int societyId,
    int meterId,
    String periodFrom,
    String periodTo,
    String readingDate,
    int readingMilli,
  ) {
    return executor.insert('meter_readings', {
      'society_id': societyId,
      'meter_id': meterId,
      'period_from': periodFrom,
      'period_to': periodTo,
      'reading_date': readingDate,
      'reading_milli': readingMilli,
    });
  }

  Future<List<Map<String, dynamic>>> listMeterReadings(
    int societyId, {
    int? meterId,
    String? periodFrom,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('mr.society_id = ?');
    final args = <Object?>[societyId];
    if (meterId != null) {
      where.write(' AND mr.meter_id = ?');
      args.add(meterId);
    }
    if (periodFrom != null) {
      where.write(' AND mr.period_from = ?');
      args.add(periodFrom);
    }
    final sql = '''
      SELECT 
        mr.*,
        m.meter_no,
        m.opening_reading_milli,
        mt.name as meter_type_name,
        mt.unit_label,
        u.unit_no,
        b.name as block_name,
        COALESCE(
          (SELECT prev.reading_milli 
           FROM meter_readings prev 
           WHERE prev.meter_id = mr.meter_id AND prev.period_to <= mr.period_from 
           ORDER BY prev.period_to DESC LIMIT 1),
          m.opening_reading_milli
        ) as previous_reading_milli
      FROM meter_readings mr
      JOIN meters m ON mr.meter_id = m.id
      JOIN meter_types mt ON m.meter_type_id = mt.id
      JOIN units u ON m.unit_id = u.id
      JOIN blocks b ON u.block_id = b.id
      WHERE $where
      ORDER BY mr.reading_date DESC, mr.id DESC
    ''';
    return exec.rawQuery(sql, args);
  }

  // -------------------------------------------------------------
  // Bill Runs
  // -------------------------------------------------------------

  Future<PageResult<BillRun>> listBillRuns(
    int societyId, {
    String? status,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('br.society_id = ?');
    final args = <Object?>[societyId];

    if (status != null && status.isNotEmpty) {
      where.write(' AND br.status = ?');
      args.add(status);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM bill_runs br WHERE $where';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        br.*,
        (SELECT COUNT(*) FROM bills b WHERE b.run_id = br.id) as bill_count,
        (SELECT COALESCE(SUM(b.total_paise), 0) FROM bills b WHERE b.run_id = br.id) as total_paise
      FROM bill_runs br
      WHERE $where
      ORDER BY br.created_at DESC
      LIMIT ? OFFSET ?
    ''';
    final rows = await exec.rawQuery(selectSql, [...args, page.limit, page.offset]);
    return PageResult(rows.map(BillRun.fromMap).toList(), total);
  }

  Future<BillRun?> getBillRun(DatabaseExecutor executor, int runId) async {
    final sql = '''
      SELECT 
        br.*,
        (SELECT COUNT(*) FROM bills b WHERE b.run_id = br.id) as bill_count,
        (SELECT COALESCE(SUM(b.total_paise), 0) FROM bills b WHERE b.run_id = br.id) as total_paise
      FROM bill_runs br
      WHERE br.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(sql, [runId]);
    if (rows.isEmpty) return null;
    return BillRun.fromMap(rows.first);
  }

  Future<int> insertBillRun(DatabaseExecutor executor, int societyId, int fyId, BillRunDraft draft) {
    return executor.insert('bill_runs', {
      'society_id': societyId,
      'fy_id': fyId,
      'frequency': draft.frequency,
      'period_from': draft.periodFrom,
      'period_to': draft.periodTo,
      'bill_date': draft.billDate,
      'due_date': draft.dueDate,
      'interest_through': draft.interestThrough,
      'notes': draft.notes?.trim(),
      'status': 'draft',
    });
  }

  Future<void> updateBillRunStatus(DatabaseExecutor executor, int runId, String status, [String? postedAt]) {
    final map = <String, Object?>{'status': status};
    if (postedAt != null) map['posted_at'] = postedAt;
    return executor.update('bill_runs', map, where: 'id = ?', whereArgs: [runId]);
  }

  Future<void> deleteDraftRun(DatabaseExecutor executor, int runId) async {
    await executor.delete('bills', where: "run_id = ? AND status = 'draft'", whereArgs: [runId]);
    await executor.delete('bill_runs', where: "id = ? AND status = 'draft'", whereArgs: [runId]);
  }

  // -------------------------------------------------------------
  // Bills & Lines
  // -------------------------------------------------------------

  Future<PageResult<Bill>> listBills(
    int societyId, {
    int? runId,
    int? unitId,
    String? status,
    String? billKind,
    PageRequest page = const PageRequest(),
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final where = StringBuffer('b.society_id = ?');
    final args = <Object?>[societyId];

    if (runId != null) {
      where.write(' AND b.run_id = ?');
      args.add(runId);
    }
    if (unitId != null) {
      where.write(' AND b.unit_id = ?');
      args.add(unitId);
    }
    if (status != null && status.isNotEmpty) {
      where.write(' AND b.status = ?');
      args.add(status);
    }
    if (billKind != null && billKind.isNotEmpty) {
      where.write(' AND b.bill_kind = ?');
      args.add(billKind);
    }

    final countSql = 'SELECT COUNT(*) as cnt FROM bills b WHERE $where';
    final countRows = await exec.rawQuery(countSql, args);
    final total = (countRows.first['cnt'] as int?) ?? 0;

    final selectSql = '''
      SELECT 
        b.*,
        u.unit_no,
        blk.name as block_name
      FROM bills b
      JOIN units u ON b.unit_id = u.id
      JOIN blocks blk ON u.block_id = blk.id
      WHERE $where
      ORDER BY b.bill_date DESC, blk.name ASC, u.unit_no ASC
      LIMIT ? OFFSET ?
    ''';
    final rows = await exec.rawQuery(selectSql, [...args, page.limit, page.offset]);
    return PageResult(rows.map((r) => Bill.fromMap(r)).toList(), total);
  }

  Future<Bill?> getBill(DatabaseExecutor executor, int billId) async {
    final selectSql = '''
      SELECT 
        b.*,
        u.unit_no,
        blk.name as block_name
      FROM bills b
      JOIN units u ON b.unit_id = u.id
      JOIN blocks blk ON u.block_id = blk.id
      WHERE b.id = ?
      LIMIT 1
    ''';
    final rows = await executor.rawQuery(selectSql, [billId]);
    if (rows.isEmpty) return null;

    final lineSql = '''
      SELECT 
        bl.*,
        ch.name as charge_head_name
      FROM bill_lines bl
      JOIN charge_heads ch ON bl.charge_head_id = ch.id
      WHERE bl.bill_id = ?
      ORDER BY bl.line_no ASC
    ''';
    final lineRows = await executor.rawQuery(lineSql, [billId]);
    final lines = lineRows.map(BillLine.fromMap).toList();

    return Bill.fromMap(rows.first, lines);
  }

  Future<int> insertBill(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('bills', values);
  }

  Future<int> insertBillLine(DatabaseExecutor executor, Map<String, Object?> values) {
    return executor.insert('bill_lines', values);
  }

  Future<void> updateBillStatus(
    DatabaseExecutor executor,
    int billId,
    String status, {
    int? journalEntryId,
    String? billNo,
  }) {
    final map = <String, Object?>{'status': status};
    if (journalEntryId != null) map['journal_entry_id'] = journalEntryId;
    if (billNo != null) map['bill_no'] = billNo;
    return executor.update('bills', map, where: 'id = ?', whereArgs: [billId]);
  }
}
