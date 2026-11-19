import 'package:flutter/foundation.dart';

@immutable
class ReportColumnDef {
  final String key;
  final String label;
  final bool isNumeric;
  final bool isDate;
  final double? width;

  const ReportColumnDef({
    required this.key,
    required this.label,
    this.isNumeric = false,
    this.isDate = false,
    this.width,
  });
}

enum ReportParamType { dateRange, asOfDate, financialYear, account, vendor, unit }

@immutable
class ReportParamDef {
  final String key;
  final String label;
  final ReportParamType type;
  final bool isRequired;
  final dynamic defaultValue;

  const ReportParamDef({
    required this.key,
    required this.label,
    required this.type,
    this.isRequired = true,
    this.defaultValue,
  });
}

@immutable
class ReportDefinition {
  final String key;
  final String title;
  final String category;
  final String description;
  final List<ReportColumnDef> columns;
  final List<ReportParamDef> parameters;

  const ReportDefinition({
    required this.key,
    required this.title,
    required this.category,
    required this.description,
    required this.columns,
    this.parameters = const [
      ReportParamDef(key: 'fromDate', label: 'From Date', type: ReportParamType.dateRange),
      ReportParamDef(key: 'toDate', label: 'To Date', type: ReportParamType.dateRange),
    ],
  });
}

@immutable
class ReportResult {
  final ReportDefinition definition;
  final Map<String, dynamic> parameters;
  final List<ReportColumnDef> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? summaryRow;

  const ReportResult({
    required this.definition,
    required this.parameters,
    required this.columns,
    required this.rows,
    this.summaryRow,
  });
}

class ReportCatalog {
  const ReportCatalog._();

  static const List<ReportDefinition> allReports = [
    // Billing
    ReportDefinition(
      key: 'billing_register',
      title: 'Billing Register',
      category: 'Billing',
      description: 'Summary of all bills issued to members in the selected period',
      columns: [
        ReportColumnDef(key: 'bill_no', label: 'Bill No'),
        ReportColumnDef(key: 'bill_date', label: 'Bill Date', isDate: true),
        ReportColumnDef(key: 'due_date', label: 'Due Date', isDate: true),
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'subtotal', label: 'Subtotal', isNumeric: true),
        ReportColumnDef(key: 'tax', label: 'Tax', isNumeric: true),
        ReportColumnDef(key: 'total', label: 'Total', isNumeric: true),
        ReportColumnDef(key: 'status', label: 'Status'),
      ],
    ),
    ReportDefinition(
      key: 'bill_detail',
      title: 'Bill Detail Register',
      category: 'Billing',
      description: 'Line-by-line itemized bill details per charge head',
      columns: [
        ReportColumnDef(key: 'bill_no', label: 'Bill No'),
        ReportColumnDef(key: 'bill_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'head_name', label: 'Charge Head'),
        ReportColumnDef(key: 'amount', label: 'Amount', isNumeric: true),
        ReportColumnDef(key: 'tax', label: 'Tax', isNumeric: true),
        ReportColumnDef(key: 'payable', label: 'Payable', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'head_billing',
      title: 'Head-wise Billing Summary',
      category: 'Billing',
      description: 'Aggregate billed amounts grouped by charge head',
      columns: [
        ReportColumnDef(key: 'head_name', label: 'Charge Head'),
        ReportColumnDef(key: 'account_code', label: 'Account Code'),
        ReportColumnDef(key: 'count', label: 'Bill Count', isNumeric: true),
        ReportColumnDef(key: 'subtotal', label: 'Subtotal', isNumeric: true),
        ReportColumnDef(key: 'tax', label: 'Tax', isNumeric: true),
        ReportColumnDef(key: 'total', label: 'Total Billed', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'reversed_bills',
      title: 'Reversed Bills Report',
      category: 'Billing',
      description: 'Listing of all cancelled or reversed member bills',
      columns: [
        ReportColumnDef(key: 'bill_no', label: 'Bill No'),
        ReportColumnDef(key: 'bill_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'total', label: 'Total', isNumeric: true),
        ReportColumnDef(key: 'reversal_date', label: 'Reversal Date', isDate: true),
        ReportColumnDef(key: 'reversal_reason', label: 'Reason'),
      ],
    ),

    // Collections
    ReportDefinition(
      key: 'collection_register',
      title: 'Collection Register',
      category: 'Collections',
      description: 'All receipts collected from members in the period',
      columns: [
        ReportColumnDef(key: 'receipt_no', label: 'Receipt No'),
        ReportColumnDef(key: 'receipt_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'mode', label: 'Mode'),
        ReportColumnDef(key: 'instrument_no', label: 'Cheque / Ref'),
        ReportColumnDef(key: 'amount', label: 'Amount Paid', isNumeric: true),
        ReportColumnDef(key: 'status', label: 'Status'),
      ],
    ),
    ReportDefinition(
      key: 'mode_collection',
      title: 'Mode-wise Collections',
      category: 'Collections',
      description: 'Total collections categorized by payment instrument (NEFT, UPI, Cheque, Cash)',
      columns: [
        ReportColumnDef(key: 'mode', label: 'Payment Mode'),
        ReportColumnDef(key: 'count', label: 'Receipts Count', isNumeric: true),
        ReportColumnDef(key: 'total_amount', label: 'Total Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'member_dues',
      title: 'Member Dues & Outstanding',
      category: 'Collections',
      description: 'Current outstanding balance per unit and member',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'member_name', label: 'Member Name'),
        ReportColumnDef(key: 'principal_dues', label: 'Principal Dues', isNumeric: true),
        ReportColumnDef(key: 'interest_dues', label: 'Interest Dues', isNumeric: true),
        ReportColumnDef(key: 'advance', label: 'Advance Balance', isNumeric: true),
        ReportColumnDef(key: 'net_due', label: 'Net Payable', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'unit_ageing',
      title: 'Dues Ageing Analysis',
      category: 'Collections',
      description: 'Outstanding dues grouped by aging brackets (0-30, 31-60, 61-90, 90+ days)',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'member_name', label: 'Member'),
        ReportColumnDef(key: 'current', label: '0-30 Days', isNumeric: true),
        ReportColumnDef(key: 'd30_60', label: '31-60 Days', isNumeric: true),
        ReportColumnDef(key: 'd60_90', label: '61-90 Days', isNumeric: true),
        ReportColumnDef(key: 'd90_plus', label: '90+ Days', isNumeric: true),
        ReportColumnDef(key: 'total_dues', label: 'Total Due', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'member_advances',
      title: 'Member Advances Register',
      category: 'Collections',
      description: 'Units holding credit advance balances',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'member_name', label: 'Member'),
        ReportColumnDef(key: 'advance_amount', label: 'Advance Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'pending_cheques',
      title: 'Pending / In-Transit Cheques',
      category: 'Collections',
      description: 'Cheques received but not yet cleared in bank reconciliation',
      columns: [
        ReportColumnDef(key: 'receipt_no', label: 'Receipt No'),
        ReportColumnDef(key: 'receipt_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'instrument_no', label: 'Cheque No'),
        ReportColumnDef(key: 'bank_name', label: 'Drawee Bank'),
        ReportColumnDef(key: 'amount', label: 'Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'unit_balances',
      title: 'Unit Balances Summary',
      category: 'Collections',
      description: 'Ledger balance for every unit in the society',
      columns: [
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'member_name', label: 'Primary Member'),
        ReportColumnDef(key: 'closing_balance', label: 'Closing Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'refundable_deposits',
      title: 'Refundable Deposits Register',
      category: 'Collections',
      description: 'Move-in, renovation and security deposits received and refunded',
      columns: [
        ReportColumnDef(key: 'unit_name', label: 'Unit'),
        ReportColumnDef(key: 'party_name', label: 'Depositor'),
        ReportColumnDef(key: 'deposit_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'received', label: 'Deposit Received', isNumeric: true),
        ReportColumnDef(key: 'refunded', label: 'Refunded', isNumeric: true),
        ReportColumnDef(key: 'balance', label: 'Balance Held', isNumeric: true),
      ],
    ),

    // Expenses
    ReportDefinition(
      key: 'expense_register',
      title: 'Expense Bills Register',
      category: 'Expenses',
      description: 'All vendor bills booked in the period',
      columns: [
        ReportColumnDef(key: 'bill_no', label: 'Internal Bill No'),
        ReportColumnDef(key: 'vendor_bill_no', label: 'Vendor Invoice'),
        ReportColumnDef(key: 'bill_date', label: 'Bill Date', isDate: true),
        ReportColumnDef(key: 'vendor_name', label: 'Vendor Name'),
        ReportColumnDef(key: 'subtotal', label: 'Subtotal', isNumeric: true),
        ReportColumnDef(key: 'tax', label: 'GST', isNumeric: true),
        ReportColumnDef(key: 'tds', label: 'TDS Deducted', isNumeric: true),
        ReportColumnDef(key: 'total', label: 'Payable Amount', isNumeric: true),
        ReportColumnDef(key: 'status', label: 'Status'),
      ],
    ),
    ReportDefinition(
      key: 'itemized_expenses',
      title: 'Itemized Expense Details',
      category: 'Expenses',
      description: 'Individual expense line items with ledger account classification',
      columns: [
        ReportColumnDef(key: 'bill_no', label: 'Bill No'),
        ReportColumnDef(key: 'bill_date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'vendor_name', label: 'Vendor'),
        ReportColumnDef(key: 'account_name', label: 'Expense Account'),
        ReportColumnDef(key: 'description', label: 'Description'),
        ReportColumnDef(key: 'amount', label: 'Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'vendor_statement',
      title: 'Vendor Statement',
      category: 'Expenses',
      description: 'Transaction history, bills, and payments for a selected vendor',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'type', label: 'Type'),
        ReportColumnDef(key: 'ref_no', label: 'Reference'),
        ReportColumnDef(key: 'debit', label: 'Paid (Debit)', isNumeric: true),
        ReportColumnDef(key: 'credit', label: 'Billed (Credit)', isNumeric: true),
        ReportColumnDef(key: 'balance', label: 'Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'payables_ageing',
      title: 'Vendor Payables Ageing',
      category: 'Expenses',
      description: 'Unpaid vendor invoices categorized by aging brackets',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'vendor_name', label: 'Vendor'),
        ReportColumnDef(key: 'current', label: '0-30 Days', isNumeric: true),
        ReportColumnDef(key: 'd30_60', label: '31-60 Days', isNumeric: true),
        ReportColumnDef(key: 'd60_90', label: '61-90 Days', isNumeric: true),
        ReportColumnDef(key: 'd90_plus', label: '90+ Days', isNumeric: true),
        ReportColumnDef(key: 'total_payable', label: 'Total Payable', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'budget_actual',
      title: 'Budget vs Actual Expenses',
      category: 'Expenses',
      description: 'Budget variances for the selected financial year',
      columns: [
        ReportColumnDef(key: 'account_code', label: 'Code'),
        ReportColumnDef(key: 'account_name', label: 'Expense Head'),
        ReportColumnDef(key: 'budget', label: 'Budget', isNumeric: true),
        ReportColumnDef(key: 'actual', label: 'Actual Spent', isNumeric: true),
        ReportColumnDef(key: 'variance', label: 'Variance', isNumeric: true),
        ReportColumnDef(key: 'percent', label: '% Utilized'),
      ],
    ),
    ReportDefinition(
      key: 'expense_comparison',
      title: 'Expense Comparison',
      category: 'Expenses',
      description: 'Period-over-period comparative expense summary',
      columns: [
        ReportColumnDef(key: 'account_code', label: 'Code'),
        ReportColumnDef(key: 'account_name', label: 'Expense Head'),
        ReportColumnDef(key: 'current_period', label: 'Current Period', isNumeric: true),
        ReportColumnDef(key: 'prior_period', label: 'Prior Period', isNumeric: true),
        ReportColumnDef(key: 'change', label: 'Change', isNumeric: true),
      ],
    ),

    // Bank
    ReportDefinition(
      key: 'cash_book',
      title: 'Cash Book',
      category: 'Bank',
      description: 'Petty cash receipts and payments ledger',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'voucher_no', label: 'Voucher'),
        ReportColumnDef(key: 'particulars', label: 'Particulars'),
        ReportColumnDef(key: 'debit', label: 'Cash In (Debit)', isNumeric: true),
        ReportColumnDef(key: 'credit', label: 'Cash Out (Credit)', isNumeric: true),
        ReportColumnDef(key: 'balance', label: 'Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'bank_book',
      title: 'Bank Book',
      category: 'Bank',
      description: 'Chronological transaction register for a bank account',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'voucher_no', label: 'Voucher'),
        ReportColumnDef(key: 'particulars', label: 'Particulars'),
        ReportColumnDef(key: 'debit', label: 'Deposits (Debit)', isNumeric: true),
        ReportColumnDef(key: 'credit', label: 'Withdrawals (Credit)', isNumeric: true),
        ReportColumnDef(key: 'balance', label: 'Running Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'cash_flow',
      title: 'Cash Flow Statement',
      category: 'Bank',
      description: 'Inflows and outflows across operational and financing activities',
      columns: [
        ReportColumnDef(key: 'activity', label: 'Activity'),
        ReportColumnDef(key: 'account_name', label: 'Account'),
        ReportColumnDef(key: 'inflow', label: 'Inflow', isNumeric: true),
        ReportColumnDef(key: 'outflow', label: 'Outflow', isNumeric: true),
        ReportColumnDef(key: 'net', label: 'Net Flow', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'deposit_slip',
      title: 'Bank Deposit Slips',
      category: 'Bank',
      description: 'Summary of collections deposited into bank accounts',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'bank_name', label: 'Bank'),
        ReportColumnDef(key: 'cheque_count', label: 'Cheques Count', isNumeric: true),
        ReportColumnDef(key: 'amount', label: 'Total Deposit', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'bank_reconciliation',
      title: 'Bank Reconciliation Summary',
      category: 'Bank',
      description: 'Book balance vs Statement balance and uncleared items',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'bank_name', label: 'Bank Account'),
        ReportColumnDef(key: 'book_balance', label: 'Book Balance', isNumeric: true),
        ReportColumnDef(key: 'uncleared_receipts', label: 'Uncleared Receipts', isNumeric: true),
        ReportColumnDef(key: 'uncleared_payments', label: 'Uncleared Payments', isNumeric: true),
        ReportColumnDef(key: 'expected_statement', label: 'Expected Statement', isNumeric: true),
        ReportColumnDef(key: 'difference', label: 'Difference', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'fd_register',
      title: 'Fixed Deposits Register',
      category: 'Bank',
      description: 'All active and matured term deposits held with banks',
      columns: [
        ReportColumnDef(key: 'fd_no', label: 'FD No'),
        ReportColumnDef(key: 'bank_name', label: 'Bank'),
        ReportColumnDef(key: 'start_date', label: 'Start Date', isDate: true),
        ReportColumnDef(key: 'maturity_date', label: 'Maturity Date', isDate: true),
        ReportColumnDef(key: 'principal', label: 'Principal', isNumeric: true),
        ReportColumnDef(key: 'rate', label: 'Interest Rate'),
        ReportColumnDef(key: 'status', label: 'Status'),
      ],
    ),
    ReportDefinition(
      key: 'fd_maturity',
      title: 'FD Maturity Schedule',
      category: 'Bank',
      description: 'Upcoming fixed deposit maturities with expected payout values',
      columns: [
        ReportColumnDef(key: 'maturity_date', label: 'Maturity Date', isDate: true),
        ReportColumnDef(key: 'fd_no', label: 'FD No'),
        ReportColumnDef(key: 'bank_name', label: 'Bank'),
        ReportColumnDef(key: 'principal', label: 'Principal', isNumeric: true),
        ReportColumnDef(key: 'maturity_value', label: 'Est. Maturity Value', isNumeric: true),
      ],
    ),

    // Tax
    ReportDefinition(
      key: 'gst_output',
      title: 'GSTR-1 Outward Supplies',
      category: 'Tax',
      description: 'Member bills and miscellaneous invoices with GST breakups',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'doc_no', label: 'Doc No'),
        ReportColumnDef(key: 'party_name', label: 'Party / Member'),
        ReportColumnDef(key: 'taxable', label: 'Taxable Value', isNumeric: true),
        ReportColumnDef(key: 'cgst', label: 'CGST', isNumeric: true),
        ReportColumnDef(key: 'sgst', label: 'SGST', isNumeric: true),
        ReportColumnDef(key: 'igst', label: 'IGST', isNumeric: true),
        ReportColumnDef(key: 'total', label: 'Total Value', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'gst_input',
      title: 'GSTR-2B Inward ITC Register',
      category: 'Tax',
      description: 'Vendor bills showing input tax credit claimable',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'doc_no', label: 'Bill No'),
        ReportColumnDef(key: 'vendor_name', label: 'Vendor Name'),
        ReportColumnDef(key: 'gstin', label: 'Vendor GSTIN'),
        ReportColumnDef(key: 'taxable', label: 'Taxable Value', isNumeric: true),
        ReportColumnDef(key: 'cgst', label: 'CGST (ITC)', isNumeric: true),
        ReportColumnDef(key: 'sgst', label: 'SGST (ITC)', isNumeric: true),
        ReportColumnDef(key: 'igst', label: 'IGST (ITC)', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'gst_payable',
      title: 'Net GST Summary (GSTR-3B)',
      category: 'Tax',
      description: 'Monthly summary comparing output tax against input tax credit',
      columns: [
        ReportColumnDef(key: 'period', label: 'Tax Period'),
        ReportColumnDef(key: 'output_tax', label: 'Output Tax', isNumeric: true),
        ReportColumnDef(key: 'input_itc', label: 'Input ITC', isNumeric: true),
        ReportColumnDef(key: 'net_payable', label: 'Net Payable / (ITC C/F)', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'tds_payable',
      title: 'TDS Deducted & Payable (26Q)',
      category: 'Tax',
      description: 'TDS deducted on contractor, professional and vendor payments',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'section', label: 'TDS Section'),
        ReportColumnDef(key: 'party_name', label: 'Deductee'),
        ReportColumnDef(key: 'pan', label: 'PAN'),
        ReportColumnDef(key: 'gross_amount', label: 'Gross Bill Amount', isNumeric: true),
        ReportColumnDef(key: 'rate', label: 'Rate'),
        ReportColumnDef(key: 'tds_amount', label: 'TDS Payable', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'tds_paid',
      title: 'TDS Withheld on Income (16A / 26AS)',
      category: 'Tax',
      description: 'TDS deducted by banks on society fixed deposit interest',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'doc_no', label: 'FD Reference'),
        ReportColumnDef(key: 'bank_name', label: 'Bank Deductor'),
        ReportColumnDef(key: 'gross_interest', label: 'Gross Interest', isNumeric: true),
        ReportColumnDef(key: 'tds_amount', label: 'TDS Withheld', isNumeric: true),
      ],
    ),

    // Accounts
    ReportDefinition(
      key: 'day_book',
      title: 'Day Book',
      category: 'Accounts',
      description: 'All journal transactions recorded in chronological order',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'entry_no', label: 'Voucher No'),
        ReportColumnDef(key: 'source_type', label: 'Type'),
        ReportColumnDef(key: 'narration', label: 'Narration'),
        ReportColumnDef(key: 'amount', label: 'Total Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'general_ledger',
      title: 'General Ledger Enquiry',
      category: 'Accounts',
      description: 'Full audit history of transactions on any ledger account',
      columns: [
        ReportColumnDef(key: 'date', label: 'Date', isDate: true),
        ReportColumnDef(key: 'entry_no', label: 'Voucher'),
        ReportColumnDef(key: 'contra', label: 'Contra Account'),
        ReportColumnDef(key: 'narration', label: 'Narration'),
        ReportColumnDef(key: 'debit', label: 'Debit', isNumeric: true),
        ReportColumnDef(key: 'credit', label: 'Credit', isNumeric: true),
        ReportColumnDef(key: 'balance', label: 'Balance', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'trial_balance',
      title: 'Trial Balance',
      category: 'Accounts',
      description: 'Opening, debit, credit and closing balance for every ledger account',
      columns: [
        ReportColumnDef(key: 'code', label: 'Code'),
        ReportColumnDef(key: 'name', label: 'Account Name'),
        ReportColumnDef(key: 'opening_debit', label: 'Opening Dr', isNumeric: true),
        ReportColumnDef(key: 'opening_credit', label: 'Opening Cr', isNumeric: true),
        ReportColumnDef(key: 'period_debit', label: 'Period Dr', isNumeric: true),
        ReportColumnDef(key: 'period_credit', label: 'Period Cr', isNumeric: true),
        ReportColumnDef(key: 'closing_debit', label: 'Closing Dr', isNumeric: true),
        ReportColumnDef(key: 'closing_credit', label: 'Closing Cr', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'income_expenditure',
      title: 'Income and Expenditure Statement',
      category: 'Accounts',
      description: 'Operational income vs expenditure and surplus/deficit',
      columns: [
        ReportColumnDef(key: 'group_name', label: 'Classification'),
        ReportColumnDef(key: 'account_name', label: 'Head'),
        ReportColumnDef(key: 'income', label: 'Income', isNumeric: true),
        ReportColumnDef(key: 'expense', label: 'Expense', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'balance_sheet',
      title: 'Balance Sheet',
      category: 'Accounts',
      description: 'Statement of assets, liabilities and society funds',
      parameters: [
        ReportParamDef(key: 'asOfDate', label: 'As of Date', type: ReportParamType.asOfDate),
      ],
      columns: [
        ReportColumnDef(key: 'side', label: 'Side'),
        ReportColumnDef(key: 'group_name', label: 'Group'),
        ReportColumnDef(key: 'account_name', label: 'Head'),
        ReportColumnDef(key: 'amount', label: 'Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'receipts_payments',
      title: 'Receipts and Payments Summary',
      category: 'Accounts',
      description: 'Total bank & cash movement grouped by contra head',
      columns: [
        ReportColumnDef(key: 'side', label: 'Type'),
        ReportColumnDef(key: 'account_name', label: 'Contra Head'),
        ReportColumnDef(key: 'amount', label: 'Amount', isNumeric: true),
      ],
    ),
    ReportDefinition(
      key: 'fund_movement',
      title: 'Statutory Fund Movement',
      category: 'Accounts',
      description: 'Opening balance, additions, appropriations and closing balance of funds',
      columns: [
        ReportColumnDef(key: 'account_name', label: 'Fund Name'),
        ReportColumnDef(key: 'opening', label: 'Opening Balance', isNumeric: true),
        ReportColumnDef(key: 'additions', label: 'Additions (Credits)', isNumeric: true),
        ReportColumnDef(key: 'utilization', label: 'Utilization (Debits)', isNumeric: true),
        ReportColumnDef(key: 'closing', label: 'Closing Balance', isNumeric: true),
      ],
    ),
  ];

  static ReportDefinition? find(String key) {
    for (final r in allReports) {
      if (r.key == key) return r;
    }
    return null;
  }
}
