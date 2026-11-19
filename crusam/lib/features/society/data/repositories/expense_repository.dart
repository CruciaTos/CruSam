import 'package:sqflite/sqflite.dart';
import '../models/expense_models.dart';

class ExpenseRepository {
  final Database db;

  const ExpenseRepository(this.db);

  DatabaseExecutor _getExecutor(DatabaseExecutor? txn) => txn ?? db;

  // Vendors
  Future<int> saveVendor(int societyId, VendorDraft draft, {int? vendorId, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final values = <String, dynamic>{
      'vendor_code': draft.vendorCode,
      'name': draft.name,
      'contact_name': draft.contactName,
      'phone': draft.phone,
      'email': draft.email,
      'alternate_emails': draft.alternateEmails,
      'notes': draft.notes,
      'address': draft.address,
      'state_code': draft.stateCode,
      'pan': draft.pan,
      'gstin': draft.gstin,
      'default_gst_rate_bp': draft.defaultGstRateBp,
      'legal_type': draft.legalType,
      'payee_name': draft.payeeName,
      'bank_account_no': draft.bankAccountNo,
      'bank_branch': draft.bankBranch,
      'ifsc': draft.ifsc,
      'default_expense_account_id': draft.defaultExpenseAccountId,
      'tds_section_id': draft.tdsSectionId,
      'tds_rate_bp': draft.tdsRateBp,
      'is_active': draft.isActive ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (vendorId != null) {
      await exec.update('vendors', values, where: 'id = ? AND society_id = ?', whereArgs: [vendorId, societyId]);
      return vendorId;
    } else {
      values['society_id'] = societyId;
      values['created_at'] = DateTime.now().toIso8601String();
      return await exec.insert('vendors', values);
    }
  }

  Future<Vendor?> getVendor(int societyId, int vendorId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT v.*, a.name as default_expense_account_name, ts.code as tds_section_code
      FROM vendors v
      LEFT JOIN accounts a ON a.id = v.default_expense_account_id
      LEFT JOIN tds_sections ts ON ts.id = v.tds_section_id
      WHERE v.id = ? AND v.society_id = ?
    ''', [vendorId, societyId]);
    if (rows.isEmpty) return null;
    return Vendor.fromMap(rows.first);
  }

  Future<List<VendorRow>> listVendors(int societyId, {VendorFilter? filter, DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final where = <String>['v.society_id = ?'];
    final args = <dynamic>[societyId];

    if (filter?.isActive != null) {
      where.add('v.is_active = ?');
      args.add(filter!.isActive! ? 1 : 0);
    }
    if (filter?.search != null && filter!.search!.trim().isNotEmpty) {
      where.add('(v.name LIKE ? OR v.vendor_code LIKE ? OR v.phone LIKE ? OR v.email LIKE ? OR v.pan LIKE ?)');
      final term = '%${filter.search!.trim()}%';
      args.addAll([term, term, term, term, term]);
    }

    final sql = '''
      SELECT v.*, a.name as default_expense_account_name, ts.code as tds_section_code,
        COALESCE((
          SELECT SUM(jl.credit_paise - jl.debit_paise)
          FROM journal_lines jl
          JOIN accounts acc ON acc.id = jl.account_id
          WHERE acc.system_key = 'vendors_payable' AND jl.vendor_id = v.id AND jl.society_id = v.society_id
        ), 0) as balance,
        COALESCE((
          SELECT SUM(jl.debit_paise - jl.credit_paise)
          FROM journal_lines jl
          JOIN accounts acc ON acc.id = jl.account_id
          WHERE acc.system_key = 'vendor_advances' AND jl.vendor_id = v.id AND jl.society_id = v.society_id
        ), 0) as total_advance,
        COALESCE((
          SELECT SUM(eb.payable_paise) FROM expense_bills eb
          WHERE eb.vendor_id = v.id AND eb.status = 'posted' AND eb.bill_kind = 'bill'
        ), 0) -
        COALESCE((
          SELECT SUM(eb.payable_paise) FROM expense_bills eb
          WHERE eb.vendor_id = v.id AND eb.status = 'posted' AND eb.bill_kind = 'debit_note'
        ), 0) as total_billed,
        COALESCE((
          SELECT SUM(vp.amount_paise) FROM vendor_payments vp
          WHERE vp.vendor_id = v.id AND vp.status = 'posted' AND vp.payment_kind = 'against_bills'
        ), 0) as total_paid
      FROM vendors v
      LEFT JOIN accounts a ON a.id = v.default_expense_account_id
      LEFT JOIN tds_sections ts ON ts.id = v.tds_section_id
      WHERE ${where.join(' AND ')}
      ORDER BY v.name ASC
    ''';

    final rows = await exec.rawQuery(sql, args);
    return rows.map((r) {
      final vendor = Vendor.fromMap(r);
      final billed = r['total_billed'] as int? ?? 0;
      final paid = r['total_paid'] as int? ?? 0;
      final adv = r['total_advance'] as int? ?? 0;
      final bal = r['balance'] as int? ?? 0;
      return VendorRow(
        vendor: vendor,
        billedPaise: billed,
        paidPaise: paid,
        advancePaise: adv,
        balancePaise: bal,
      );
    }).toList();
  }

  Future<VendorDetail?> getVendorDetail(int societyId, int vendorId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final vendor = await getVendor(societyId, vendorId, executor: exec);
    if (vendor == null) return null;

    final billedRows = await exec.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN bill_kind = 'bill' THEN payable_paise ELSE -payable_paise END), 0) as billed
      FROM expense_bills
      WHERE vendor_id = ? AND society_id = ? AND status = 'posted'
    ''', [vendorId, societyId]);

    final paidRows = await exec.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN payment_kind = 'against_bills' THEN amount_paise ELSE 0 END), 0) as paid
      FROM vendor_payments
      WHERE vendor_id = ? AND society_id = ? AND status = 'posted'
    ''', [vendorId, societyId]);

    final vpBalRow = await exec.rawQuery('''
      SELECT
        COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as balance
      FROM journal_lines jl
      JOIN accounts acc ON acc.id = jl.account_id
      WHERE acc.system_key = 'vendors_payable' AND jl.vendor_id = ? AND jl.society_id = ?
    ''', [vendorId, societyId]);

    final advRow = await exec.rawQuery('''
      SELECT
        COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as advance
      FROM journal_lines jl
      JOIN accounts acc ON acc.id = jl.account_id
      WHERE acc.system_key = 'vendor_advances' AND jl.vendor_id = ? AND jl.society_id = ?
    ''', [vendorId, societyId]);

    final openRows = await exec.rawQuery('''
      SELECT COUNT(*) as open_count
      FROM expense_bills eb
      WHERE eb.vendor_id = ? AND eb.society_id = ? AND eb.status = 'posted' AND eb.bill_kind = 'bill'
        AND eb.payable_paise > (
          SELECT COALESCE(SUM(vpa.allocated_paise), 0)
          FROM vendor_payment_allocations vpa
          WHERE vpa.expense_bill_id = eb.id AND vpa.is_active = 1
        )
    ''', [vendorId, societyId]);

    final billed = billedRows.first['billed'] as int? ?? 0;
    final paid = paidRows.first['paid'] as int? ?? 0;
    final bal = vpBalRow.first['balance'] as int? ?? 0;
    final adv = advRow.first['advance'] as int? ?? 0;
    final openCount = openRows.first['open_count'] as int? ?? 0;

    return VendorDetail(
      vendor: vendor,
      totalBilledPaise: billed,
      totalPaidPaise: paid,
      advancePaise: adv,
      balancePaise: bal,
      openBillsCount: openCount,
    );
  }

  // TDS Sections
  Future<List<TdsSection>> listTdsSections(int societyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'tds_sections',
      where: 'society_id = ? AND is_active = 1',
      whereArgs: [societyId],
      orderBy: 'code ASC',
    );
    return rows.map((r) => TdsSection.fromMap(r)).toList();
  }

  // Expense Bills
  Future<int> insertExpenseBill({
    required int societyId,
    required int fyId,
    required String voucherNo,
    required String billKind,
    required int vendorId,
    required String vendorBillNo,
    required String billDate,
    required String postDate,
    String? dueDate,
    required int subtotalPaise,
    required int cgstPaise,
    required int sgstPaise,
    required int igstPaise,
    int? tdsSectionId,
    int? tdsRateBp,
    required int tdsPaise,
    required int totalPaise,
    required int payablePaise,
    String? payeeName,
    String? narration,
    required int journalEntryId,
    required List<ExpenseLine> lines,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final billId = await exec.insert('expense_bills', {
      'society_id': societyId,
      'fy_id': fyId,
      'voucher_no': voucherNo,
      'bill_kind': billKind,
      'vendor_id': vendorId,
      'vendor_bill_no': vendorBillNo,
      'bill_date': billDate,
      'post_date': postDate,
      'due_date': dueDate,
      'subtotal_paise': subtotalPaise,
      'cgst_paise': cgstPaise,
      'sgst_paise': sgstPaise,
      'igst_paise': igstPaise,
      'tds_section_id': tdsSectionId,
      'tds_rate_bp': tdsRateBp,
      'tds_paise': tdsPaise,
      'total_paise': totalPaise,
      'payable_paise': payablePaise,
      'payee_name': payeeName,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });

    for (final line in lines) {
      await exec.insert('expense_lines', {
        'society_id': societyId,
        'expense_bill_id': billId,
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

    return billId;
  }

  Future<ExpenseBill?> getExpenseBill(int societyId, int billId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT eb.*, v.name as vendor_name,
        COALESCE((
          SELECT SUM(vpa.allocated_paise)
          FROM vendor_payment_allocations vpa
          WHERE vpa.expense_bill_id = eb.id AND vpa.is_active = 1
        ), 0) as paid_paise
      FROM expense_bills eb
      JOIN vendors v ON v.id = eb.vendor_id
      WHERE eb.id = ? AND eb.society_id = ?
    ''', [billId, societyId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ExpenseBill.fromMap(r, paidPaise: r['paid_paise'] as int? ?? 0);
  }

  Future<List<ExpenseLine>> getExpenseBillLines(int societyId, int billId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT el.*, a.name as account_name, a.code as account_code
      FROM expense_lines el
      JOIN accounts a ON a.id = el.account_id
      WHERE el.expense_bill_id = ? AND el.society_id = ?
      ORDER BY el.line_no ASC
    ''', [billId, societyId]);
    return rows.map((r) => ExpenseLine.fromMap(r)).toList();
  }

  Future<List<ExpenseBill>> listExpenseBills(
    int societyId, {
    int? vendorId,
    String? billKind,
    String? status,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final where = <String>['eb.society_id = ?'];
    final args = <dynamic>[societyId];

    if (vendorId != null) {
      where.add('eb.vendor_id = ?');
      args.add(vendorId);
    }
    if (billKind != null) {
      where.add('eb.bill_kind = ?');
      args.add(billKind);
    }
    if (status != null) {
      where.add('eb.status = ?');
      args.add(status);
    }

    final rows = await exec.rawQuery('''
      SELECT eb.*, v.name as vendor_name,
        COALESCE((
          SELECT SUM(vpa.allocated_paise)
          FROM vendor_payment_allocations vpa
          WHERE vpa.expense_bill_id = eb.id AND vpa.is_active = 1
        ), 0) as paid_paise
      FROM expense_bills eb
      JOIN vendors v ON v.id = eb.vendor_id
      WHERE ${where.join(' AND ')}
      ORDER BY eb.post_date DESC, eb.id DESC
    ''', args);

    return rows.map((r) => ExpenseBill.fromMap(r, paidPaise: r['paid_paise'] as int? ?? 0)).toList();
  }

  Future<void> updateExpenseBillStatus(
    int societyId,
    int billId,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'expense_bills',
      {
        'status': status,
        if (reversalReason != null) 'reversal_reason': reversalReason,
        if (reversalEntryId != null) 'reversal_entry_id': reversalEntryId,
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [billId, societyId],
    );
  }

  Future<List<OpenExpenseBill>> getOpenExpenseBills(int societyId, int vendorId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT eb.*, v.name as vendor_name,
        COALESCE((
          SELECT SUM(vpa.allocated_paise)
          FROM vendor_payment_allocations vpa
          WHERE vpa.expense_bill_id = eb.id AND vpa.is_active = 1
        ), 0) as allocated_paise
      FROM expense_bills eb
      JOIN vendors v ON v.id = eb.vendor_id
      WHERE eb.society_id = ? AND eb.vendor_id = ? AND eb.status = 'posted' AND eb.bill_kind = 'bill'
      ORDER BY eb.post_date ASC, eb.id ASC
    ''', [societyId, vendorId]);

    return rows
        .where((r) {
          final payable = r['payable_paise'] as int;
          final allocated = r['allocated_paise'] as int;
          return payable > allocated;
        })
        .map((r) => OpenExpenseBill(
              bill: ExpenseBill.fromMap(r),
              allocatedPaise: r['allocated_paise'] as int,
            ))
        .toList();
  }

  // Payments
  Future<int> insertVendorPayment({
    required int societyId,
    required int fyId,
    required String paymentNo,
    required String paymentKind,
    int? vendorId,
    int? expenseAccountId,
    required String paymentDate,
    required int amountPaise,
    required String mode,
    String? instrumentNo,
    String? instrumentDate,
    String? payeeName,
    required int bankCashAccountId,
    String? narration,
    required int journalEntryId,
    List<VendorPaymentAllocationDraft>? allocations,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final paymentId = await exec.insert('vendor_payments', {
      'society_id': societyId,
      'fy_id': fyId,
      'payment_no': paymentNo,
      'payment_kind': paymentKind,
      'vendor_id': vendorId,
      'expense_account_id': expenseAccountId,
      'payment_date': paymentDate,
      'amount_paise': amountPaise,
      'mode': mode,
      'instrument_no': instrumentNo,
      'instrument_date': instrumentDate,
      'payee_name': payeeName,
      'bank_cash_account_id': bankCashAccountId,
      'narration': narration,
      'status': 'posted',
      'journal_entry_id': journalEntryId,
    });

    if (allocations != null) {
      for (final alloc in allocations) {
        await exec.insert('vendor_payment_allocations', {
          'society_id': societyId,
          'payment_id': paymentId,
          'expense_bill_id': alloc.expenseBillId,
          'allocated_paise': alloc.allocatedPaise,
          'allocation_date': paymentDate,
          'is_active': 1,
        });
      }
    }

    return paymentId;
  }

  Future<VendorPayment?> getVendorPayment(int societyId, int paymentId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT vp.*, v.name as vendor_name, ea.name as expense_account_name, ba.name as bank_account_name
      FROM vendor_payments vp
      LEFT JOIN vendors v ON v.id = vp.vendor_id
      LEFT JOIN accounts ea ON ea.id = vp.expense_account_id
      JOIN accounts ba ON ba.id = vp.bank_cash_account_id
      WHERE vp.id = ? AND vp.society_id = ?
    ''', [paymentId, societyId]);
    if (rows.isEmpty) return null;
    return VendorPayment.fromMap(rows.first);
  }

  Future<List<VendorPayment>> listVendorPayments(
    int societyId, {
    int? vendorId,
    String? status,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final where = <String>['vp.society_id = ?'];
    final args = <dynamic>[societyId];

    if (vendorId != null) {
      where.add('vp.vendor_id = ?');
      args.add(vendorId);
    }
    if (status != null) {
      where.add('vp.status = ?');
      args.add(status);
    }

    final rows = await exec.rawQuery('''
      SELECT vp.*, v.name as vendor_name, ea.name as expense_account_name, ba.name as bank_account_name
      FROM vendor_payments vp
      LEFT JOIN vendors v ON v.id = vp.vendor_id
      LEFT JOIN accounts ea ON ea.id = vp.expense_account_id
      JOIN accounts ba ON ba.id = vp.bank_cash_account_id
      WHERE ${where.join(' AND ')}
      ORDER BY vp.payment_date DESC, vp.id DESC
    ''', args);

    return rows.map((r) => VendorPayment.fromMap(r)).toList();
  }

  Future<void> updatePaymentStatus(
    int societyId,
    int paymentId,
    String status, {
    String? reversalReason,
    int? reversalEntryId,
    bool clearAllocations = false,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.update(
      'vendor_payments',
      {
        'status': status,
        if (reversalReason != null) 'reversal_reason': reversalReason,
        if (reversalEntryId != null) 'reversal_entry_id': reversalEntryId,
      },
      where: 'id = ? AND society_id = ?',
      whereArgs: [paymentId, societyId],
    );

    if (clearAllocations) {
      await exec.update(
        'vendor_payment_allocations',
        {'is_active': 0},
        where: 'payment_id = ? AND society_id = ?',
        whereArgs: [paymentId, societyId],
      );
    }
  }

  Future<void> insertPaymentAllocation({
    required int societyId,
    required int paymentId,
    required int expenseBillId,
    required int allocatedPaise,
    required String allocationDate,
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    await exec.insert('vendor_payment_allocations', {
      'society_id': societyId,
      'payment_id': paymentId,
      'expense_bill_id': expenseBillId,
      'allocated_paise': allocatedPaise,
      'allocation_date': allocationDate,
      'is_active': 1,
    });
  }

  // Statements
  Future<List<VendorStatementRow>> getVendorStatementRows(
    int societyId,
    int vendorId,
    String fromDate,
    String toDate, {
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);

    final rows = await exec.rawQuery('''
      SELECT je.entry_date, je.source_type, je.entry_no, je.narration, jl.debit_paise, jl.credit_paise, a.system_key
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.society_id = ? AND jl.vendor_id = ? AND a.system_key IN ('vendors_payable', 'vendor_advances')
        AND je.entry_date >= ? AND je.entry_date <= ?
      ORDER BY je.entry_date ASC, je.id ASC
    ''', [societyId, vendorId, fromDate, toDate]);

    final openRows = await exec.rawQuery('''
      SELECT COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as opening
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.society_id = ? AND jl.vendor_id = ? AND a.system_key IN ('vendors_payable', 'vendor_advances')
        AND je.entry_date < ?
    ''', [societyId, vendorId, fromDate]);

    final opening = openRows.first['opening'] as int? ?? 0;
    var running = opening;

    final result = <VendorStatementRow>[];
    for (final r in rows) {
      final debit = r['debit_paise'] as int;
      final credit = r['credit_paise'] as int;
      running += (credit - debit);

      String type = 'Journal';
      final src = r['source_type'] as String;
      if (src == 'expense_bill') type = 'Bill';
      if (src == 'expense_debit_note') type = 'Debit Note';
      if (src == 'vendor_payment') type = 'Payment';
      if (src == 'advance_adjustment') type = 'Adjustment';
      if (src == 'reversal') type = 'Reversal';

      result.add(VendorStatementRow(
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

  // Budgets
  Future<List<Map<String, dynamic>>> getBudgets(int societyId, int fyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    return await exec.rawQuery('''
      SELECT b.account_id, b.amount_paise, a.code as account_code, a.name as account_name, ag.name as group_name
      FROM budgets b
      JOIN accounts a ON a.id = b.account_id
      JOIN account_groups ag ON ag.id = a.group_id
      WHERE b.society_id = ? AND b.fy_id = ?
      ORDER BY a.code ASC
    ''', [societyId, fyId]);
  }

  Future<void> saveBudget(int societyId, int fyId, int accountId, int amountPaise, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    await exec.rawInsert('''
      INSERT INTO budgets (society_id, fy_id, account_id, amount_paise)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(society_id, fy_id, account_id) DO UPDATE SET amount_paise = excluded.amount_paise
    ''', [societyId, fyId, accountId, amountPaise]);
  }

  Future<void> copyBudget(int societyId, int fromFyId, int toFyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    final rows = await exec.query(
      'budgets',
      where: 'society_id = ? AND fy_id = ?',
      whereArgs: [societyId, fromFyId],
    );
    for (final r in rows) {
      await exec.rawInsert('''
        INSERT INTO budgets (society_id, fy_id, account_id, amount_paise)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(society_id, fy_id, account_id) DO UPDATE SET amount_paise = excluded.amount_paise
      ''', [societyId, toFyId, r['account_id'], r['amount_paise']]);
    }
  }

  Future<List<Map<String, dynamic>>> getExpenseAccounts(int societyId, {DatabaseExecutor? executor}) async {
    final exec = _getExecutor(executor);
    return await exec.rawQuery('''
      SELECT a.id, a.code, a.name, ag.name as group_name
      FROM accounts a
      JOIN account_groups ag ON ag.id = a.group_id
      WHERE a.society_id = ? AND ag.account_type = 'expense' AND a.is_active = 1
      ORDER BY a.code ASC
    ''', [societyId]);
  }

  Future<int> getAccountActualExpense(
    int societyId,
    int accountId,
    String fromDate,
    String toDate, {
    DatabaseExecutor? executor,
  }) async {
    final exec = _getExecutor(executor);
    final rows = await exec.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as actual
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND jl.account_id = ?
        AND je.entry_date >= ? AND je.entry_date <= ?
    ''', [societyId, accountId, fromDate, toDate]);
    return rows.first['actual'] as int? ?? 0;
  }
}
