class TdsSection {
  final int id;
  final int societyId;
  final String code;
  final String name;
  final int? defaultRateBp;
  final int? thresholdPaise;
  final bool isActive;

  const TdsSection({
    required this.id,
    required this.societyId,
    required this.code,
    required this.name,
    this.defaultRateBp,
    this.thresholdPaise,
    required this.isActive,
  });

  factory TdsSection.fromMap(Map<String, dynamic> map) {
    return TdsSection(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      code: map['code'] as String,
      name: map['name'] as String,
      defaultRateBp: map['default_rate_bp'] as int?,
      thresholdPaise: map['threshold_paise'] as int?,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class Vendor {
  final int id;
  final int societyId;
  final String? vendorCode;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? alternateEmails;
  final String? notes;
  final String? address;
  final String? stateCode;
  final String? pan;
  final String? gstin;
  final int? defaultGstRateBp;
  final String? legalType;
  final String? payeeName;
  final String? bankAccountNo;
  final String? bankBranch;
  final String? ifsc;
  final int? defaultExpenseAccountId;
  final int? tdsSectionId;
  final int? tdsRateBp;
  final bool isActive;
  final String? defaultExpenseAccountName;
  final String? tdsSectionCode;

  const Vendor({
    required this.id,
    required this.societyId,
    this.vendorCode,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.alternateEmails,
    this.notes,
    this.address,
    this.stateCode,
    this.pan,
    this.gstin,
    this.defaultGstRateBp,
    this.legalType,
    this.payeeName,
    this.bankAccountNo,
    this.bankBranch,
    this.ifsc,
    this.defaultExpenseAccountId,
    this.tdsSectionId,
    this.tdsRateBp,
    required this.isActive,
    this.defaultExpenseAccountName,
    this.tdsSectionCode,
  });

  factory Vendor.fromMap(Map<String, dynamic> map) {
    return Vendor(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      vendorCode: map['vendor_code'] as String?,
      name: map['name'] as String,
      contactName: map['contact_name'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      alternateEmails: map['alternate_emails'] as String?,
      notes: map['notes'] as String?,
      address: map['address'] as String?,
      stateCode: map['state_code'] as String?,
      pan: map['pan'] as String?,
      gstin: map['gstin'] as String?,
      defaultGstRateBp: map['default_gst_rate_bp'] as int?,
      legalType: map['legal_type'] as String?,
      payeeName: map['payee_name'] as String?,
      bankAccountNo: map['bank_account_no'] as String?,
      bankBranch: map['bank_branch'] as String?,
      ifsc: map['ifsc'] as String?,
      defaultExpenseAccountId: map['default_expense_account_id'] as int?,
      tdsSectionId: map['tds_section_id'] as int?,
      tdsRateBp: map['tds_rate_bp'] as int?,
      isActive: (map['is_active'] as int) == 1,
      defaultExpenseAccountName: map['default_expense_account_name'] as String?,
      tdsSectionCode: map['tds_section_code'] as String?,
    );
  }
}

class VendorDraft {
  final String? vendorCode;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? alternateEmails;
  final String? notes;
  final String? address;
  final String? stateCode;
  final String? pan;
  final String? gstin;
  final int? defaultGstRateBp;
  final String? legalType;
  final String? payeeName;
  final String? bankAccountNo;
  final String? bankBranch;
  final String? ifsc;
  final int? defaultExpenseAccountId;
  final int? tdsSectionId;
  final int? tdsRateBp;
  final bool isActive;

  const VendorDraft({
    this.vendorCode,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.alternateEmails,
    this.notes,
    this.address,
    this.stateCode,
    this.pan,
    this.gstin,
    this.defaultGstRateBp,
    this.legalType,
    this.payeeName,
    this.bankAccountNo,
    this.bankBranch,
    this.ifsc,
    this.defaultExpenseAccountId,
    this.tdsSectionId,
    this.tdsRateBp,
    this.isActive = true,
  });
}

class VendorFilter {
  final String? search;
  final bool? isActive;

  const VendorFilter({this.search, this.isActive});
}

class VendorRow {
  final Vendor vendor;
  final int billedPaise;
  final int paidPaise;
  final int advancePaise;
  final int balancePaise;

  const VendorRow({
    required this.vendor,
    required this.billedPaise,
    required this.paidPaise,
    required this.advancePaise,
    required this.balancePaise,
  });
}

class VendorDetail {
  final Vendor vendor;
  final int totalBilledPaise;
  final int totalPaidPaise;
  final int advancePaise;
  final int balancePaise;
  final int openBillsCount;

  const VendorDetail({
    required this.vendor,
    required this.totalBilledPaise,
    required this.totalPaidPaise,
    required this.advancePaise,
    required this.balancePaise,
    required this.openBillsCount,
  });
}

class ExpenseBill {
  final int id;
  final int societyId;
  final int fyId;
  final String voucherNo;
  final String billKind; // 'bill', 'debit_note'
  final int vendorId;
  final String vendorBillNo;
  final String billDate;
  final String postDate;
  final String? dueDate;
  final int subtotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int? tdsSectionId;
  final int? tdsRateBp;
  final int tdsPaise;
  final int totalPaise;
  final int payablePaise;
  final String? payeeName;
  final String? narration;
  final String status; // 'posted', 'reversed'
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? vendorName;
  final int paidPaise;

  const ExpenseBill({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.voucherNo,
    required this.billKind,
    required this.vendorId,
    required this.vendorBillNo,
    required this.billDate,
    required this.postDate,
    this.dueDate,
    required this.subtotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    this.tdsSectionId,
    this.tdsRateBp,
    required this.tdsPaise,
    required this.totalPaise,
    required this.payablePaise,
    this.payeeName,
    this.narration,
    required this.status,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    this.vendorName,
    this.paidPaise = 0,
  });

  int get balancePaise => payablePaise - paidPaise;
  int get taxTotalPaise => cgstPaise + sgstPaise + igstPaise;

  factory ExpenseBill.fromMap(Map<String, dynamic> map, {int paidPaise = 0}) {
    return ExpenseBill(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      voucherNo: map['voucher_no'] as String,
      billKind: map['bill_kind'] as String,
      vendorId: map['vendor_id'] as int,
      vendorBillNo: map['vendor_bill_no'] as String,
      billDate: map['bill_date'] as String,
      postDate: map['post_date'] as String,
      dueDate: map['due_date'] as String?,
      subtotalPaise: map['subtotal_paise'] as int,
      cgstPaise: map['cgst_paise'] as int,
      sgstPaise: map['sgst_paise'] as int,
      igstPaise: map['igst_paise'] as int,
      tdsSectionId: map['tds_section_id'] as int?,
      tdsRateBp: map['tds_rate_bp'] as int?,
      tdsPaise: map['tds_paise'] as int,
      totalPaise: map['total_paise'] as int,
      payablePaise: map['payable_paise'] as int,
      payeeName: map['payee_name'] as String?,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      reversalReason: map['reversal_reason'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      vendorName: map['vendor_name'] as String?,
      paidPaise: paidPaise,
    );
  }
}

class ExpenseLine {
  final int id;
  final int societyId;
  final int expenseBillId;
  final int lineNo;
  final int accountId;
  final String? description;
  final String? hsnSac;
  final int amountPaise;
  final int gstRateBp;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final String? accountName;
  final String? accountCode;

  const ExpenseLine({
    required this.id,
    required this.societyId,
    required this.expenseBillId,
    required this.lineNo,
    required this.accountId,
    this.description,
    this.hsnSac,
    required this.amountPaise,
    required this.gstRateBp,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    this.accountName,
    this.accountCode,
  });

  factory ExpenseLine.fromMap(Map<String, dynamic> map) {
    return ExpenseLine(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      expenseBillId: map['expense_bill_id'] as int,
      lineNo: map['line_no'] as int,
      accountId: map['account_id'] as int,
      description: map['description'] as String?,
      hsnSac: map['hsn_sac'] as String?,
      amountPaise: map['amount_paise'] as int,
      gstRateBp: map['gst_rate_bp'] as int,
      cgstPaise: map['cgst_paise'] as int,
      sgstPaise: map['sgst_paise'] as int,
      igstPaise: map['igst_paise'] as int,
      accountName: map['account_name'] as String?,
      accountCode: map['account_code'] as String?,
    );
  }
}

class ExpenseLineDraft {
  final int accountId;
  final String? description;
  final String? hsnSac;
  final int amountPaise;
  final int gstRateBp;

  const ExpenseLineDraft({
    required this.accountId,
    this.description,
    this.hsnSac,
    required this.amountPaise,
    this.gstRateBp = 0,
  });
}

class ExpenseBillDraft {
  final String billKind; // 'bill', 'debit_note'
  final int vendorId;
  final String vendorBillNo;
  final String billDate;
  final String postDate;
  final String? dueDate;
  final List<ExpenseLineDraft> lines;
  final int? tdsSectionId;
  final int? tdsRateBp;
  final int? customTdsPaise;
  final String? payeeName;
  final String? narration;

  const ExpenseBillDraft({
    this.billKind = 'bill',
    required this.vendorId,
    required this.vendorBillNo,
    required this.billDate,
    required this.postDate,
    this.dueDate,
    required this.lines,
    this.tdsSectionId,
    this.tdsRateBp,
    this.customTdsPaise,
    this.payeeName,
    this.narration,
  });
}

class OpenExpenseBill {
  final ExpenseBill bill;
  final int allocatedPaise;

  const OpenExpenseBill({
    required this.bill,
    required this.allocatedPaise,
  });

  int get payablePaise => bill.payablePaise;
  int get duePaise => bill.payablePaise - allocatedPaise;
}

class VendorPaymentAllocationDraft {
  final int expenseBillId;
  final int allocatedPaise;

  const VendorPaymentAllocationDraft({
    required this.expenseBillId,
    required this.allocatedPaise,
  });
}

class VendorPaymentDraft {
  final String paymentKind; // 'against_bills', 'advance', 'direct_expense'
  final int? vendorId;
  final int? expenseAccountId;
  final String paymentDate;
  final int amountPaise;
  final String mode; // 'cash', 'cheque', 'neft', 'rtgs', 'imps', 'upi', 'card', 'other'
  final String? instrumentNo;
  final String? instrumentDate;
  final String? payeeName;
  final int bankCashAccountId;
  final String? narration;
  final List<VendorPaymentAllocationDraft>? allocations;

  const VendorPaymentDraft({
    required this.paymentKind,
    this.vendorId,
    this.expenseAccountId,
    required this.paymentDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentDate,
    this.payeeName,
    required this.bankCashAccountId,
    this.narration,
    this.allocations,
  });
}

class VendorPayment {
  final int id;
  final int societyId;
  final int fyId;
  final String paymentNo;
  final String paymentKind;
  final int? vendorId;
  final int? expenseAccountId;
  final String paymentDate;
  final int amountPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentDate;
  final String? payeeName;
  final int bankCashAccountId;
  final String? narration;
  final String status;
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? vendorName;
  final String? expenseAccountName;
  final String? bankCashAccountName;

  const VendorPayment({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.paymentNo,
    required this.paymentKind,
    this.vendorId,
    this.expenseAccountId,
    required this.paymentDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentDate,
    this.payeeName,
    required this.bankCashAccountId,
    this.narration,
    required this.status,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    this.vendorName,
    this.expenseAccountName,
    this.bankCashAccountName,
  });

  factory VendorPayment.fromMap(Map<String, dynamic> map) {
    return VendorPayment(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      paymentNo: map['payment_no'] as String,
      paymentKind: map['payment_kind'] as String,
      vendorId: map['vendor_id'] as int?,
      expenseAccountId: map['expense_account_id'] as int?,
      paymentDate: map['payment_date'] as String,
      amountPaise: map['amount_paise'] as int,
      mode: map['mode'] as String,
      instrumentNo: map['instrument_no'] as String?,
      instrumentDate: map['instrument_date'] as String?,
      payeeName: map['payee_name'] as String?,
      bankCashAccountId: map['bank_cash_account_id'] as int,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      reversalReason: map['reversal_reason'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      vendorName: map['vendor_name'] as String?,
      expenseAccountName: map['expense_account_name'] as String?,
      bankCashAccountName: map['bank_account_name'] as String?,
    );
  }
}

class VendorPaymentAllocation {
  final int id;
  final int societyId;
  final int paymentId;
  final int expenseBillId;
  final int allocatedPaise;
  final String allocationDate;
  final bool isActive;

  const VendorPaymentAllocation({
    required this.id,
    required this.societyId,
    required this.paymentId,
    required this.expenseBillId,
    required this.allocatedPaise,
    required this.allocationDate,
    required this.isActive,
  });

  factory VendorPaymentAllocation.fromMap(Map<String, dynamic> map) {
    return VendorPaymentAllocation(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      paymentId: map['payment_id'] as int,
      expenseBillId: map['expense_bill_id'] as int,
      allocatedPaise: map['allocated_paise'] as int,
      allocationDate: map['allocation_date'] as String,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class VendorAdvanceAdjustmentDraft {
  final int vendorId;
  final int expenseBillId;
  final int amountPaise;
  final String date;
  final String? narration;

  const VendorAdvanceAdjustmentDraft({
    required this.vendorId,
    required this.expenseBillId,
    required this.amountPaise,
    required this.date,
    this.narration,
  });
}

class VendorStatementRow {
  final String date;
  final String type; // 'Bill', 'Payment', 'Debit Note', 'Adjustment', 'Reversal'
  final String refNo;
  final String description;
  final int debitPaise;
  final int creditPaise;
  final int balancePaise;

  const VendorStatementRow({
    required this.date,
    required this.type,
    required this.refNo,
    required this.description,
    required this.debitPaise,
    required this.creditPaise,
    required this.balancePaise,
  });
}

class VendorStatement {
  final Vendor vendor;
  final String fromDate;
  final String toDate;
  final int openingBalancePaise;
  final List<VendorStatementRow> rows;
  final int closingBalancePaise;

  const VendorStatement({
    required this.vendor,
    required this.fromDate,
    required this.toDate,
    required this.openingBalancePaise,
    required this.rows,
    required this.closingBalancePaise,
  });
}

class BudgetDraft {
  final int accountId;
  final int amountPaise;

  const BudgetDraft({
    required this.accountId,
    required this.amountPaise,
  });
}

class BudgetRow {
  final int accountId;
  final String accountCode;
  final String accountName;
  final String groupName;
  final int budgetPaise;
  final int actualPaise;
  final int variancePaise; // budget - actual
  final double variancePercent;

  const BudgetRow({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.groupName,
    required this.budgetPaise,
    required this.actualPaise,
    required this.variancePaise,
    required this.variancePercent,
  });
}

class BudgetReport {
  final int fyId;
  final String asOf;
  final List<BudgetRow> rows;
  final int totalBudgetPaise;
  final int totalActualPaise;
  final int totalVariancePaise;

  const BudgetReport({
    required this.fyId,
    required this.asOf,
    required this.rows,
    required this.totalBudgetPaise,
    required this.totalActualPaise,
    required this.totalVariancePaise,
  });
}

class ComparisonPeriod {
  final String label;
  final String fromDate;
  final String toDate;

  const ComparisonPeriod({
    required this.label,
    required this.fromDate,
    required this.toDate,
  });
}

class ComparisonRequest {
  final String mode; // 'monthly', 'quarterly', 'yearly'
  final int fyId;
  final List<int>? accountIds;

  const ComparisonRequest({
    required this.mode,
    required this.fyId,
    this.accountIds,
  });
}

class ComparisonColumn {
  final String label;
  final Map<int, int> accountAmountPaise;

  const ComparisonColumn({
    required this.label,
    required this.accountAmountPaise,
  });
}

class ExpenseComparison {
  final List<ComparisonColumn> columns;
  final List<Map<String, dynamic>> accounts; // id, code, name, group

  const ExpenseComparison({
    required this.columns,
    required this.accounts,
  });
}
