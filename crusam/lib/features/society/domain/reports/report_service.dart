import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/money.dart';
import '../../core/society_exception.dart';
import '../ledger/ledger_service.dart';
import 'financial_statement_service.dart';
import 'report_definitions.dart';

class ReportService {
  final Database db;
  final LedgerService ledgerService;
  final FinancialStatementService statementService;

  ReportService(this.db, this.ledgerService, this.statementService);

  Future<ReportResult> runReport(
    int societyId,
    String reportKey,
    Map<String, dynamic> params,
  ) async {
    final def = ReportCatalog.find(reportKey);
    if (def == null) {
      throw SocietyException('not_found', 'Report definition not found: $reportKey');
    }

    final fromDate = params['fromDate'] as String? ?? '1900-01-01';
    final toDate = params['toDate'] as String? ?? '2099-12-31';
    final asOfDate = params['asOfDate'] as String? ?? toDate;

    List<Map<String, dynamic>> rows = [];
    Map<String, dynamic>? summaryRow;

    switch (reportKey) {
      // Billing
      case 'billing_register':
        final dbRows = await db.rawQuery('''
          SELECT b.bill_no, b.bill_date, b.due_date,
                 u.block || '-' || u.unit_no as unit_name,
                 b.subtotal_paise, (b.cgst_paise + b.sgst_paise + b.igst_paise) as tax_paise,
                 b.total_paise, b.status
          FROM bills b
          JOIN units u ON u.id = b.unit_id
          WHERE b.society_id = ? AND b.bill_date >= ? AND b.bill_date <= ?
          ORDER BY b.bill_date DESC, b.id DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'bill_no': r['bill_no'] ?? '(Draft)',
          'bill_date': r['bill_date'],
          'due_date': r['due_date'],
          'unit_name': r['unit_name'],
          'subtotal': formatPaise(r['subtotal_paise'] as int),
          'tax': formatPaise(r['tax_paise'] as int),
          'total': formatPaise(r['total_paise'] as int),
          'status': (r['status'] as String).toUpperCase(),
        }).toList();
        break;

      case 'bill_detail':
        final dbRows = await db.rawQuery('''
          SELECT b.bill_no, b.bill_date, u.block || '-' || u.unit_no as unit_name,
                 h.name as head_name, bl.amount_paise, (bl.cgst_paise + bl.sgst_paise) as tax_paise,
                 (bl.amount_paise + bl.cgst_paise + bl.sgst_paise) as payable_paise
          FROM bill_lines bl
          JOIN bills b ON b.id = bl.bill_id
          JOIN units u ON u.id = b.unit_id
          JOIN charge_heads h ON h.id = bl.charge_head_id
          WHERE b.society_id = ? AND b.bill_date >= ? AND b.bill_date <= ?
          ORDER BY b.bill_date DESC, bl.id ASC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'bill_no': r['bill_no'] ?? '(Draft)',
          'bill_date': r['bill_date'],
          'unit_name': r['unit_name'],
          'head_name': r['head_name'],
          'amount': formatPaise(r['amount_paise'] as int),
          'tax': formatPaise(r['tax_paise'] as int),
          'payable': formatPaise(r['payable_paise'] as int),
        }).toList();
        break;

      case 'head_billing':
        final dbRows = await db.rawQuery('''
          SELECT h.name as head_name, a.code as account_code,
                 COUNT(bl.id) as count,
                 SUM(bl.amount_paise) as subtotal_paise,
                 SUM(bl.cgst_paise + bl.sgst_paise) as tax_paise,
                 SUM(bl.amount_paise + bl.cgst_paise + bl.sgst_paise) as total_paise
          FROM bill_lines bl
          JOIN bills b ON b.id = bl.bill_id
          JOIN charge_heads h ON h.id = bl.charge_head_id
          JOIN accounts a ON a.id = h.account_id
          WHERE b.society_id = ? AND b.bill_date >= ? AND b.bill_date <= ?
          GROUP BY h.id
          ORDER BY total_paise DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'head_name': r['head_name'],
          'account_code': r['account_code'],
          'count': r['count'].toString(),
          'subtotal': formatPaise(r['subtotal_paise'] as int? ?? 0),
          'tax': formatPaise(r['tax_paise'] as int? ?? 0),
          'total': formatPaise(r['total_paise'] as int? ?? 0),
        }).toList();
        break;

      case 'reversed_bills':
        final dbRows = await db.rawQuery('''
          SELECT b.bill_no, b.bill_date, u.block || '-' || u.unit_no as unit_name,
                 b.total_paise, b.reversal_date, b.reversal_reason
          FROM bills b
          JOIN units u ON u.id = b.unit_id
          WHERE b.society_id = ? AND b.status = 'reversed'
            AND b.bill_date >= ? AND b.bill_date <= ?
          ORDER BY b.reversal_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'bill_no': r['bill_no'],
          'bill_date': r['bill_date'],
          'unit_name': r['unit_name'],
          'total': formatPaise(r['total_paise'] as int),
          'reversal_date': r['reversal_date'] ?? '-',
          'reversal_reason': r['reversal_reason'] ?? '-',
        }).toList();
        break;

      // Collections
      case 'collection_register':
        final dbRows = await db.rawQuery('''
          SELECT r.receipt_no, r.receipt_date, u.block || '-' || u.unit_no as unit_name,
                 r.payment_mode, r.instrument_no, r.amount_paise, r.status
          FROM receipts r
          JOIN units u ON u.id = r.unit_id
          WHERE r.society_id = ? AND r.receipt_date >= ? AND r.receipt_date <= ?
          ORDER BY r.receipt_date DESC, r.id DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'receipt_no': r['receipt_no'],
          'receipt_date': r['receipt_date'],
          'unit_name': r['unit_name'],
          'mode': (r['payment_mode'] as String).toUpperCase(),
          'instrument_no': r['instrument_no'] ?? '-',
          'amount': formatPaise(r['amount_paise'] as int),
          'status': (r['status'] as String).toUpperCase(),
        }).toList();
        break;

      case 'mode_collection':
        final dbRows = await db.rawQuery('''
          SELECT payment_mode, COUNT(id) as count, SUM(amount_paise) as total_paise
          FROM receipts
          WHERE society_id = ? AND receipt_date >= ? AND receipt_date <= ? AND status = 'posted'
          GROUP BY payment_mode
          ORDER BY total_paise DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'mode': (r['payment_mode'] as String).toUpperCase(),
          'count': r['count'].toString(),
          'total_amount': formatPaise(r['total_paise'] as int? ?? 0),
        }).toList();
        break;

      case 'member_dues':
      case 'unit_balances':
        final memberRecAcc = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');
        final dbRows = await db.rawQuery('''
          SELECT u.block || '-' || u.unit_no as unit_name,
                 p.name as member_name,
                 COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as balance_paise
          FROM units u
          LEFT JOIN unit_members um ON um.unit_id = u.id AND um.member_type = 'primary'
          LEFT JOIN people p ON p.id = um.person_id
          LEFT JOIN journal_lines jl ON jl.unit_id = u.id AND jl.account_id = ?
          LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.entry_date <= ?
          WHERE u.society_id = ?
          GROUP BY u.id
          ORDER BY u.block, u.unit_no
        ''', [memberRecAcc, asOfDate, societyId]);
        rows = dbRows.map((r) {
          final bal = r['balance_paise'] as int? ?? 0;
          return {
            'unit_name': r['unit_name'],
            'member_name': r['member_name'] ?? '(Vacant)',
            'principal_dues': formatPaise(bal > 0 ? bal : 0),
            'interest_dues': formatPaise(0),
            'advance': formatPaise(bal < 0 ? -bal : 0),
            'net_due': formatPaise(bal > 0 ? bal : 0),
            'closing_balance': formatPaise(bal),
          };
        }).toList();
        break;

      case 'unit_ageing':
        final memberRecAcc = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');
        final dbRows = await db.rawQuery('''
          SELECT u.block || '-' || u.unit_no as unit_name,
                 p.name as member_name,
                 COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as balance_paise
          FROM units u
          LEFT JOIN unit_members um ON um.unit_id = u.id AND um.member_type = 'primary'
          LEFT JOIN people p ON p.id = um.person_id
          LEFT JOIN journal_lines jl ON jl.unit_id = u.id AND jl.account_id = ?
          LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.entry_date <= ?
          WHERE u.society_id = ?
          GROUP BY u.id
          HAVING balance_paise > 0
          ORDER BY balance_paise DESC
        ''', [memberRecAcc, asOfDate, societyId]);
        rows = dbRows.map((r) {
          final bal = r['balance_paise'] as int;
          return {
            'unit_name': r['unit_name'],
            'member_name': r['member_name'] ?? '(Vacant)',
            'current': formatPaise(bal),
            'd30_60': formatPaise(0),
            'd60_90': formatPaise(0),
            'd90_plus': formatPaise(0),
            'total_dues': formatPaise(bal),
          };
        }).toList();
        break;

      case 'member_advances':
        final memberRecAcc = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');
        final dbRows = await db.rawQuery('''
          SELECT u.block || '-' || u.unit_no as unit_name,
                 p.name as member_name,
                 COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as advance_paise
          FROM units u
          LEFT JOIN unit_members um ON um.unit_id = u.id AND um.member_type = 'primary'
          LEFT JOIN people p ON p.id = um.person_id
          LEFT JOIN journal_lines jl ON jl.unit_id = u.id AND jl.account_id = ?
          LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.entry_date <= ?
          WHERE u.society_id = ?
          GROUP BY u.id
          HAVING advance_paise > 0
          ORDER BY advance_paise DESC
        ''', [memberRecAcc, asOfDate, societyId]);
        rows = dbRows.map((r) => {
          'unit_name': r['unit_name'],
          'member_name': r['member_name'] ?? '(Vacant)',
          'advance_amount': formatPaise(r['advance_paise'] as int),
        }).toList();
        break;

      case 'pending_cheques':
        final dbRows = await db.rawQuery('''
          SELECT r.receipt_no, r.receipt_date, u.block || '-' || u.unit_no as unit_name,
                 r.instrument_no, r.drawee_bank as bank_name, r.amount_paise
          FROM receipts r
          JOIN units u ON u.id = r.unit_id
          LEFT JOIN journal_lines jl ON jl.entry_id = r.journal_entry_id AND jl.debit_paise > 0
          LEFT JOIN bank_clearances bc ON bc.journal_line_id = jl.id
          WHERE r.society_id = ? AND r.payment_mode = 'cheque' AND r.status = 'posted'
            AND bc.journal_line_id IS NULL
          ORDER BY r.receipt_date DESC
        ''', [societyId]);
        rows = dbRows.map((r) => {
          'receipt_no': r['receipt_no'],
          'receipt_date': r['receipt_date'],
          'unit_name': r['unit_name'],
          'instrument_no': r['instrument_no'] ?? '-',
          'bank_name': r['bank_name'] ?? '-',
          'amount': formatPaise(r['amount_paise'] as int),
        }).toList();
        break;

      case 'refundable_deposits':
        final depAcc = await ledgerService.accountIdForKey(db, societyId, 'refundable_deposits');
        final dbRows = await db.rawQuery('''
          SELECT u.block || '-' || u.unit_no as unit_name,
                 jl.narration as party_name, je.entry_date as deposit_date,
                 jl.credit_paise as received, jl.debit_paise as refunded,
                 (jl.credit_paise - jl.debit_paise) as balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.entry_id
          LEFT JOIN units u ON u.id = jl.unit_id
          WHERE jl.society_id = ? AND jl.account_id = ?
          ORDER BY je.entry_date DESC
        ''', [societyId, depAcc]);
        rows = dbRows.map((r) => {
          'unit_name': r['unit_name'] ?? '-',
          'party_name': r['party_name'] ?? 'Deposit',
          'deposit_date': r['deposit_date'],
          'received': formatPaise(r['received'] as int),
          'refunded': formatPaise(r['refunded'] as int),
          'balance': formatPaise(r['balance'] as int),
        }).toList();
        break;

      // Expenses
      case 'expense_register':
        final dbRows = await db.rawQuery('''
          SELECT eb.bill_no, eb.vendor_bill_no, eb.bill_date, v.name as vendor_name,
                 eb.subtotal_paise, (eb.cgst_paise + eb.sgst_paise + eb.igst_paise) as tax_paise,
                 eb.tds_paise, eb.payable_paise, eb.status
          FROM expense_bills eb
          JOIN vendors v ON v.id = eb.vendor_id
          WHERE eb.society_id = ? AND eb.bill_date >= ? AND eb.bill_date <= ?
          ORDER BY eb.bill_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'bill_no': r['bill_no'],
          'vendor_bill_no': r['vendor_bill_no'] ?? '-',
          'bill_date': r['bill_date'],
          'vendor_name': r['vendor_name'],
          'subtotal': formatPaise(r['subtotal_paise'] as int),
          'tax': formatPaise(r['tax_paise'] as int),
          'tds': formatPaise(r['tds_paise'] as int),
          'total': formatPaise(r['payable_paise'] as int),
          'status': (r['status'] as String).toUpperCase(),
        }).toList();
        break;

      case 'itemized_expenses':
        final dbRows = await db.rawQuery('''
          SELECT eb.bill_no, eb.bill_date, v.name as vendor_name,
                 a.name as account_name, ebl.description, ebl.amount_paise
          FROM expense_bill_lines ebl
          JOIN expense_bills eb ON eb.id = ebl.bill_id
          JOIN vendors v ON v.id = eb.vendor_id
          JOIN accounts a ON a.id = ebl.account_id
          WHERE eb.society_id = ? AND eb.bill_date >= ? AND eb.bill_date <= ?
          ORDER BY eb.bill_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'bill_no': r['bill_no'],
          'bill_date': r['bill_date'],
          'vendor_name': r['vendor_name'],
          'account_name': r['account_name'],
          'description': r['description'] ?? '-',
          'amount': formatPaise(r['amount_paise'] as int),
        }).toList();
        break;

      case 'vendor_statement':
      case 'payables_ageing':
        final vendorAcc = await ledgerService.accountIdForKey(db, societyId, 'vendors_payable');
        final dbRows = await db.rawQuery('''
          SELECT v.name as vendor_name,
                 COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as balance_paise
          FROM vendors v
          LEFT JOIN journal_lines jl ON jl.vendor_id = v.id AND jl.account_id = ?
          LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.entry_date <= ?
          WHERE v.society_id = ?
          GROUP BY v.id
          ORDER BY balance_paise DESC
        ''', [vendorAcc, asOfDate, societyId]);
        rows = dbRows.map((r) {
          final bal = r['balance_paise'] as int;
          return {
            'vendor_name': r['vendor_name'],
            'current': formatPaise(bal > 0 ? bal : 0),
            'd30_60': formatPaise(0),
            'd60_90': formatPaise(0),
            'd90_plus': formatPaise(0),
            'total_payable': formatPaise(bal > 0 ? bal : 0),
          };
        }).toList();
        break;

      // Bank & FD
      case 'fd_register':
      case 'fd_maturity':
        final dbRows = await db.rawQuery('''
          SELECT fd_no, bank_name, start_date, maturity_date, principal_paise, rate_bp, status
          FROM fixed_deposits
          WHERE society_id = ?
          ORDER BY maturity_date ASC
        ''', [societyId]);
        rows = dbRows.map((r) => {
          'fd_no': r['fd_no'],
          'bank_name': r['bank_name'],
          'start_date': r['start_date'],
          'maturity_date': r['maturity_date'],
          'principal': formatPaise(r['principal_paise'] as int),
          'rate': '${((r['rate_bp'] as int) / 100).toStringAsFixed(2)}%',
          'status': (r['status'] as String).toUpperCase(),
          'maturity_value': formatPaise(r['principal_paise'] as int),
        }).toList();
        break;

      // Tax
      case 'gst_output':
        final dbRows = await db.rawQuery('''
          SELECT b.bill_date as date, b.bill_no as doc_no, u.block || '-' || u.unit_no as party_name,
                 b.subtotal_paise as taxable, b.cgst_paise as cgst, b.sgst_paise as sgst,
                 b.igst_paise as igst, b.total_paise as total
          FROM bills b
          JOIN units u ON u.id = b.unit_id
          WHERE b.society_id = ? AND b.status = 'posted'
            AND (b.cgst_paise > 0 OR b.sgst_paise > 0 OR b.igst_paise > 0)
            AND b.bill_date >= ? AND b.bill_date <= ?
          ORDER BY b.bill_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'date': r['date'],
          'doc_no': r['doc_no'] ?? '-',
          'party_name': r['party_name'],
          'taxable': formatPaise(r['taxable'] as int),
          'cgst': formatPaise(r['cgst'] as int),
          'sgst': formatPaise(r['sgst'] as int),
          'igst': formatPaise(r['igst'] as int),
          'total': formatPaise(r['total'] as int),
        }).toList();
        break;

      case 'gst_input':
        final dbRows = await db.rawQuery('''
          SELECT eb.bill_date as date, eb.bill_no as doc_no, v.name as vendor_name,
                 v.gstin, eb.subtotal_paise as taxable, eb.cgst_paise as cgst,
                 eb.sgst_paise as sgst, eb.igst_paise as igst
          FROM expense_bills eb
          JOIN vendors v ON v.id = eb.vendor_id
          WHERE eb.society_id = ? AND eb.status = 'posted'
            AND (eb.cgst_paise > 0 OR eb.sgst_paise > 0 OR eb.igst_paise > 0)
            AND eb.bill_date >= ? AND eb.bill_date <= ?
          ORDER BY eb.bill_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'date': r['date'],
          'doc_no': r['doc_no'],
          'vendor_name': r['vendor_name'],
          'gstin': r['gstin'] ?? '-',
          'taxable': formatPaise(r['taxable'] as int),
          'cgst': formatPaise(r['cgst'] as int),
          'sgst': formatPaise(r['sgst'] as int),
          'igst': formatPaise(r['igst'] as int),
        }).toList();
        break;

      case 'tds_payable':
        final dbRows = await db.rawQuery('''
          SELECT eb.bill_date as date, '194C/J' as section, v.name as party_name,
                 v.pan, eb.subtotal_paise as gross_amount,
                 '2.00%' as rate, eb.tds_paise as tds_amount
          FROM expense_bills eb
          JOIN vendors v ON v.id = eb.vendor_id
          WHERE eb.society_id = ? AND eb.status = 'posted' AND eb.tds_paise > 0
            AND eb.bill_date >= ? AND eb.bill_date <= ?
          ORDER BY eb.bill_date DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'date': r['date'],
          'section': r['section'],
          'party_name': r['party_name'],
          'pan': r['pan'] ?? '-',
          'gross_amount': formatPaise(r['gross_amount'] as int),
          'rate': r['rate'],
          'tds_amount': formatPaise(r['tds_amount'] as int),
        }).toList();
        break;

      // Accounts
      case 'day_book':
        final dbRows = await db.rawQuery('''
          SELECT je.entry_date, je.entry_no, je.source_type, je.narration,
                 COALESCE(SUM(jl.debit_paise), 0) as total_debit_paise
          FROM journal_entries je
          LEFT JOIN journal_lines jl ON jl.entry_id = je.id
          WHERE je.society_id = ? AND je.entry_date >= ? AND je.entry_date <= ?
          GROUP BY je.id
          ORDER BY je.entry_date DESC, je.id DESC
        ''', [societyId, fromDate, toDate]);
        rows = dbRows.map((r) => {
          'date': r['entry_date'],
          'entry_no': r['entry_no'],
          'source_type': (r['source_type'] as String).toUpperCase(),
          'narration': r['narration'] ?? '-',
          'amount': formatPaise(r['total_debit_paise'] as int),
        }).toList();
        break;

      case 'trial_balance':
        final tb = await ledgerService.trialBalance(societyId, fromDate, toDate);
        rows = tb.rows.map((r) => {
          'code': r.accountCode,
          'name': r.accountName,
          'opening_debit': formatPaise(r.openingDebitPaise),
          'opening_credit': formatPaise(r.openingCreditPaise),
          'period_debit': formatPaise(r.debitPaise),
          'period_credit': formatPaise(r.creditPaise),
          'closing_debit': formatPaise(r.closingDebitPaise),
          'closing_credit': formatPaise(r.closingCreditPaise),
        }).toList();
        break;

      case 'income_expenditure':
        final ie = await statementService.incomeAndExpenditure(societyId, fromDate, toDate);
        for (final g in ie.incomeGroups) {
          for (final l in g.lines) {
            rows.add({
              'group_name': g.title,
              'account_name': l.name,
              'income': formatPaise(l.amountPaise),
              'expense': '-',
            });
          }
        }
        for (final g in ie.expenseGroups) {
          for (final l in g.lines) {
            rows.add({
              'group_name': g.title,
              'account_name': l.name,
              'income': '-',
              'expense': formatPaise(l.amountPaise),
            });
          }
        }
        break;

      case 'balance_sheet':
        final bs = await statementService.balanceSheet(societyId, asOfDate);
        for (final g in bs.assetGroups) {
          for (final l in g.lines) {
            rows.add({
              'side': 'ASSETS',
              'group_name': g.title,
              'account_name': l.name,
              'amount': formatPaise(l.amountPaise),
            });
          }
        }
        for (final g in bs.liabilityGroups) {
          for (final l in g.lines) {
            rows.add({
              'side': 'LIABILITIES & FUNDS',
              'group_name': g.title,
              'account_name': l.name,
              'amount': formatPaise(l.amountPaise),
            });
          }
        }
        break;

      case 'receipts_payments':
        final rp = await statementService.receiptsAndPayments(societyId, fromDate, toDate);
        for (final r in rp.receipts) {
          rows.add({
            'side': 'RECEIPT',
            'account_name': r.name,
            'amount': formatPaise(r.amountPaise),
          });
        }
        for (final p in rp.payments) {
          rows.add({
            'side': 'PAYMENT',
            'account_name': p.name,
            'amount': formatPaise(p.amountPaise),
          });
        }
        break;

      case 'fund_movement':
        final dbRows = await db.rawQuery('''
          SELECT a.name as account_name,
                 COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as closing_paise,
                 COALESCE(SUM(jl.credit_paise), 0) as additions_paise,
                 COALESCE(SUM(jl.debit_paise), 0) as utilization_paise
          FROM accounts a
          JOIN account_groups g ON g.id = a.group_id
          LEFT JOIN journal_lines jl ON jl.account_id = a.id
          LEFT JOIN journal_entries je ON je.id = jl.entry_id AND je.entry_date <= ?
          WHERE a.society_id = ? AND g.code IN ('2100', '2200', '2300')
          GROUP BY a.id
          ORDER BY a.code
        ''', [asOfDate, societyId]);
        rows = dbRows.map((r) => {
          'account_name': r['account_name'],
          'opening': formatPaise((r['closing_paise'] as int) - (r['additions_paise'] as int) + (r['utilization_paise'] as int)),
          'additions': formatPaise(r['additions_paise'] as int),
          'utilization': formatPaise(r['utilization_paise'] as int),
          'closing': formatPaise(r['closing_paise'] as int),
        }).toList();
        break;

      default:
        // Generic fallback
        rows = [];
        break;
    }

    return ReportResult(
      definition: def,
      parameters: params,
      columns: def.columns,
      rows: rows,
      summaryRow: summaryRow,
    );
  }
}
