import 'package:sqflite/sqflite.dart';
import '../models/other_income_models.dart';

class OtherIncomeRepository {
  final Database db;

  const OtherIncomeRepository(this.db);

  DatabaseExecutor _getExecutor(DatabaseExecutor? txn) => txn ?? db;

  // Parties
  Future<int> saveParty(int societyId, PartyDraft draft, {int? partyId, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    if (partyId != null) {
      await exec.update(
        'parties',
        {
          'name': draft.name,
          'contact_name': draft.contactName,
          'phone': draft.phone,
          'email': draft.email,
          'address': draft.address,
          'pan': draft.pan,
          'gstin': draft.gstin,
          'state_code': draft.stateCode,
          'is_active': draft.isActive ? 1 : 0,
        },
        where: 'id = ? AND society_id = ?',
        whereArgs: [partyId, societyId],
      );
      return partyId;
    } else {
      return await exec.insert('parties', {
        'society_id': societyId,
        'name': draft.name,
        'contact_name': draft.contactName,
        'phone': draft.phone,
        'email': draft.email,
        'address': draft.address,
        'pan': draft.pan,
        'gstin': draft.gstin,
        'state_code': draft.stateCode,
        'is_active': draft.isActive ? 1 : 0,
      });
    }
  }

  Future<Party?> getParty(int societyId, int partyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'parties',
      where: 'id = ? AND society_id = ?',
      whereArgs: [partyId, societyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Party.fromMap(rows.first);
  }

  Future<List<PartyRow>> listParties(int societyId, {PartyFilter? filter, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final whereClauses = <String>['p.society_id = ?'];
    final whereArgs = <dynamic>[societyId];

    if (filter?.isActive != null) {
      whereClauses.add('p.is_active = ?');
      whereArgs.add(filter!.isActive! ? 1 : 0);
    }
    if (filter?.search != null && filter!.search!.trim().isNotEmpty) {
      whereClauses.add('(p.name LIKE ? OR p.phone LIKE ? OR p.email LIKE ?)');
      final term = '%${filter.search!.trim()}%';
      whereArgs.addAll([term, term, term]);
    }

    final sql = '''
      SELECT p.*,
        COALESCE((SELECT SUM(oi.total_paise) FROM other_invoices oi WHERE oi.party_id = p.id AND oi.status = 'posted'), 0) as total_invoiced,
        COALESCE((SELECT SUM(orct.amount_paise) FROM other_receipts orct WHERE orct.party_id = p.id AND orct.status = 'posted'), 0) as total_paid
      FROM parties p
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY p.name ASC
    ''';

    final rows = await exec.rawQuery(sql, whereArgs);
    return rows.map((r) {
      final party = Party.fromMap(r);
      final invoiced = r['total_invoiced'] as int? ?? 0;
      final paid = r['total_paid'] as int? ?? 0;
      return PartyRow(
        party: party,
        totalInvoicedPaise: invoiced,
        totalPaidPaise: paid,
        balancePaise: invoiced - paid,
      );
    }).toList();
  }

  // Invoices
  Future<int> insertInvoice({
    required int societyId,
    required int fyId,
    required String invoiceNo,
    required int partyId,
    required String invoiceDate,
    required String dueDate,
    required int subtotalPaise,
    required int cgstPaise,
    required int sgstPaise,
    required int igstPaise,
    required int totalPaise,
    String? narration,
    required int journalEntryId,
    required List<OtherInvoiceLine> lines,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final invoiceId = await exec.insert('other_invoices', {
      'society_id': societyId,
      'fy_id': fyId,
      'invoice_no': invoiceNo,
      'party_id': partyId,
      'invoice_date': invoiceDate,
      'due_date': dueDate,
      'subtotal_paise': subtotalPaise,
      'cgst_paise': cgstPaise,
      'sgst_paise': sgstPaise,
      'igst_paise': igstPaise,
      'total_paise': totalPaise,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });

    for (final line in lines) {
      await exec.insert('other_invoice_lines', {
        'society_id': societyId,
        'invoice_id': invoiceId,
        'line_no': line.lineNo,
        'account_id': line.accountId,
        'description': line.description,
        'hsn_sac': line.hsnSac,
        'amount_paise': line.amountPaise,
        'gst_rate_bp': line.gstRateBp,
        'cgst_paise': line.cgstPaise,
        'sgst_paise': line.sgstPaise,
        'igst_paise': line.igstPaise,
      });
    }

    return invoiceId;
  }

  Future<OtherInvoice?> getInvoice(int societyId, int invoiceId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT oi.*, p.name as party_name
      FROM other_invoices oi
      JOIN parties p ON p.id = oi.party_id
      WHERE oi.id = ? AND oi.society_id = ?
    ''', [invoiceId, societyId]);
    if (rows.isEmpty) return null;
    return OtherInvoice.fromMap(rows.first);
  }

  Future<List<OtherInvoiceLine>> getInvoiceLines(int societyId, int invoiceId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT oil.*, a.name as account_name, a.code as account_code
      FROM other_invoice_lines oil
      JOIN accounts a ON a.id = oil.account_id
      WHERE oil.invoice_id = ? AND oil.society_id = ?
      ORDER BY oil.line_no ASC
    ''', [invoiceId, societyId]);
    return rows.map((r) => OtherInvoiceLine.fromMap(r)).toList();
  }

  Future<List<OtherInvoice>> listInvoices(int societyId, {int? partyId, String? status, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final where = <String>['oi.society_id = ?'];
    final args = <dynamic>[societyId];

    if (partyId != null) {
      where.add('oi.party_id = ?');
      args.add(partyId);
    }
    if (status != null) {
      where.add('oi.status = ?');
      args.add(status);
    }

    final rows = await exec.rawQuery('''
      SELECT oi.*, p.name as party_name
      FROM other_invoices oi
      JOIN parties p ON p.id = oi.party_id
      WHERE ${where.join(' AND ')}
      ORDER BY oi.invoice_date DESC, oi.id DESC
    ''', args);
    return rows.map((r) => OtherInvoice.fromMap(r)).toList();
  }

  Future<void> updateInvoiceStatus(
    int societyId,
    int invoiceId,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'other_invoices',
      {
        'status': status,
        if (reversalReason != null) 'reversal_reason': reversalReason,
        if (reversalEntryId != null) 'reversal_entry_id': reversalEntryId,
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [invoiceId, societyId],
    );
  }

  // Receipts
  Future<int> insertReceipt({
    required int societyId,
    required int fyId,
    required String receiptNo,
    required int partyId,
    required String receiptDate,
    required int amountPaise,
    required String mode,
    String? instrumentNo,
    String? instrumentBank,
    required int bankCashAccountId,
    String? narration,
    required int journalEntryId,
    List<OtherReceiptAllocationDraft>? allocations,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final receiptId = await exec.insert('other_receipts', {
      'society_id': societyId,
      'fy_id': fyId,
      'receipt_no': receiptNo,
      'party_id': partyId,
      'receipt_date': receiptDate,
      'amount_paise': amountPaise,
      'mode': mode,
      'instrument_no': instrumentNo,
      'instrument_bank': instrumentBank,
      'bank_cash_account_id': bankCashAccountId,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });

    if (allocations != null) {
      for (final alloc in allocations) {
        await exec.insert('other_receipt_allocations', {
          'society_id': societyId,
          'receipt_id': receiptId,
          'invoice_id': alloc.invoiceId,
          'allocated_paise': alloc.allocatedPaise,
          'is_active': 1,
        });
      }
    }

    return receiptId;
  }

  Future<OtherReceipt?> getReceipt(int societyId, int receiptId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT r.*, p.name as party_name, a.name as bank_account_name
      FROM other_receipts r
      JOIN parties p ON p.id = r.party_id
      JOIN accounts a ON a.id = r.bank_cash_account_id
      WHERE r.id = ? AND r.society_id = ?
    ''', [receiptId, societyId]);
    if (rows.isEmpty) return null;
    return OtherReceipt.fromMap(rows.first);
  }

  Future<List<OtherReceipt>> listReceipts(int societyId, {int? partyId, String? status, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final where = <String>['r.society_id = ?'];
    final args = <dynamic>[societyId];

    if (partyId != null) {
      where.add('r.party_id = ?');
      args.add(partyId);
    }
    if (status != null) {
      where.add('r.status = ?');
      args.add(status);
    }

    final rows = await exec.rawQuery('''
      SELECT r.*, p.name as party_name, a.name as bank_account_name
      FROM other_receipts r
      JOIN parties p ON p.id = r.party_id
      JOIN accounts a ON a.id = r.bank_cash_account_id
      WHERE ${where.join(' AND ')}
      ORDER BY r.receipt_date DESC, r.id DESC
    ''', args);
    return rows.map((r) => OtherReceipt.fromMap(r)).toList();
  }

  Future<void> updateReceiptStatus(
    int societyId,
    int receiptId,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
    bool clearAllocations = false,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'other_receipts',
      {
        'status': status,
        if (reversalReason != null) 'reversal_reason': reversalReason,
        if (reversalEntryId != null) 'reversal_entry_id': reversalEntryId,
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [receiptId, societyId],
    );

    if (clearAllocations) {
      await exec.update(
        'other_receipt_allocations',
        {'is_active': 0},
        where: 'receipt_id = ? AND society_id = ?',
        whereArgs: [receiptId, societyId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getOpenInvoices(int societyId, int partyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT oi.*,
        COALESCE((
          SELECT SUM(ora.allocated_paise)
          FROM other_receipt_allocations ora
          WHERE ora.invoice_id = oi.id AND ora.is_active = 1
        ), 0) as allocated_paise
      FROM other_invoices oi
      WHERE oi.society_id = ? AND oi.party_id = ? AND oi.status = 'posted'
      ORDER BY oi.due_date ASC, oi.id ASC
    ''', [societyId, partyId]);

    return rows.where((r) {
      final total = r['total_paise'] as int;
      final allocated = r['allocated_paise'] as int;
      return total > allocated;
    }).map((r) {
      final total = r['total_paise'] as int;
      final allocated = r['allocated_paise'] as int;
      return {
        'invoice': OtherInvoice.fromMap(r),
        'total_paise': total,
        'allocated_paise': allocated,
        'due_paise': total - allocated,
      };
    }).toList();
  }

  Future<List<PartyStatementRow>> getPartyStatementRows(
    int societyId,
    int partyId,
    String fromDate,
    String toDate, {
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);

    final rows = await exec.rawQuery('''
      SELECT je.entry_date, je.source_type, je.entry_no, je.narration, jl.debit_paise, jl.credit_paise
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.society_id = ? AND jl.party_id = ? AND a.system_key = 'other_receivable'
        AND je.entry_date >= ? AND je.entry_date <= ?
      ORDER BY je.entry_date ASC, je.id ASC
    ''', [societyId, partyId, fromDate, toDate]);

    final openRows = await exec.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as opening
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.society_id = ? AND jl.party_id = ? AND a.system_key = 'other_receivable'
        AND je.entry_date < ?
    ''', [societyId, partyId, fromDate]);

    final opening = openRows.first['opening'] as int? ?? 0;
    var running = opening;

    final result = <PartyStatementRow>[];
    for (final r in rows) {
      final debit = r['debit_paise'] as int;
      final credit = r['credit_paise'] as int;
      running += (debit - credit);

      String type = 'Journal';
      final src = r['source_type'] as String;
      if (src == 'other_invoice') type = 'Invoice';
      if (src == 'other_receipt') type = 'Receipt';
      if (src == 'reversal') type = 'Reversal';

      result.add(PartyStatementRow(
        date: r['entry_date'] as String,
        type: type,
        refNo: r['entry_no'] as String,
        description: r['narration'] as String,
        debitPaise: debit,
        creditPaise: credit,
        balancePaise: running,
      ));
    }

    return result;
  }
}
