import 'package:flutter/foundation.dart';
import 'ledger_models.dart';

@immutable
class BankAccount {
  final int id;
  final int societyId;
  final int accountId;
  final String bankName;
  final String? branch;
  final String? accountNumber;
  final String? ifsc;
  final String accountType; // 'savings', 'current', 'cash', 'other'
  final bool isActive;

  const BankAccount({
    required this.id,
    required this.societyId,
    required this.accountId,
    required this.bankName,
    this.branch,
    this.accountNumber,
    this.ifsc,
    required this.accountType,
    required this.isActive,
  });

  factory BankAccount.fromMap(Map<String, dynamic> map) {
    return BankAccount(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      accountId: map['account_id'] as int,
      bankName: map['bank_name'] as String,
      branch: map['branch'] as String?,
      accountNumber: map['account_number'] as String?,
      ifsc: map['ifsc'] as String?,
      accountType: map['account_type'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

@immutable
class BankAccountDraft {
  final int? accountId; // If null, creates new account in 1100 (Bank & Cash)
  final String? accountCode;
  final String bankName;
  final String? branch;
  final String? accountNumber;
  final String? ifsc;
  final String accountType; // 'savings', 'current', 'cash', 'other'
  final bool isActive;

  const BankAccountDraft({
    this.accountId,
    this.accountCode,
    required this.bankName,
    this.branch,
    this.accountNumber,
    this.ifsc,
    this.accountType = 'current',
    this.isActive = true,
  });
}

@immutable
class BankAccountRow {
  final BankAccount bankAccount;
  final Account account;
  final int balancePaise; // Current ledger balance (debit - credit)

  const BankAccountRow({
    required this.bankAccount,
    required this.account,
    required this.balancePaise,
  });
}

@immutable
class BankTransferDraft {
  final String transferDate;
  final int fromAccountId;
  final int toAccountId;
  final int amountPaise;
  final String? instrumentNo;
  final String? narration;

  const BankTransferDraft({
    required this.transferDate,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountPaise,
    this.instrumentNo,
    this.narration,
  });
}

@immutable
class BankTransfer {
  final int id;
  final int societyId;
  final int fyId;
  final String transferNo;
  final String transferDate;
  final int fromAccountId;
  final int toAccountId;
  final int amountPaise;
  final String? instrumentNo;
  final String? narration;
  final String status; // 'posted', 'reversed'
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? fromAccountName;
  final String? toAccountName;

  const BankTransfer({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.transferNo,
    required this.transferDate,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountPaise,
    this.instrumentNo,
    this.narration,
    required this.status,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    this.fromAccountName,
    this.toAccountName,
  });

  factory BankTransfer.fromMap(Map<String, dynamic> map) {
    return BankTransfer(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      transferNo: map['transfer_no'] as String,
      transferDate: map['transfer_date'] as String,
      fromAccountId: map['from_account_id'] as int,
      toAccountId: map['to_account_id'] as int,
      amountPaise: map['amount_paise'] as int,
      instrumentNo: map['instrument_no'] as String?,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      reversalReason: map['reversal_reason'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      fromAccountName: map['from_account_name'] as String?,
      toAccountName: map['to_account_name'] as String?,
    );
  }
}

@immutable
class BankBookFilter {
  final int bankAccountId;
  final String fromDate;
  final String toDate;
  final bool? clearedOnly; // true = cleared, false = uncleared, null = all

  const BankBookFilter({
    required this.bankAccountId,
    required this.fromDate,
    required this.toDate,
    this.clearedOnly,
  });
}

@immutable
class BankBookRow {
  final int journalLineId;
  final int journalEntryId;
  final String entryDate;
  final String entryNo;
  final String sourceType;
  final String narration;
  final String? contraAccountName;
  final int debitPaise; // Deposit / Receipt
  final int creditPaise; // Withdrawal / Payment
  final int runningBalancePaise;
  final bool isCleared;
  final String? clearedDate;
  final int? statementLineId;

  const BankBookRow({
    required this.journalLineId,
    required this.journalEntryId,
    required this.entryDate,
    required this.entryNo,
    required this.sourceType,
    required this.narration,
    this.contraAccountName,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
    required this.isCleared,
    this.clearedDate,
    this.statementLineId,
  });
}

@immutable
class StatementLineDraft {
  final String date;
  final String? description;
  final String? reference;
  final int withdrawalPaise;
  final int depositPaise;
  final int? balancePaise;

  const StatementLineDraft({
    required this.date,
    this.description,
    this.reference,
    this.withdrawalPaise = 0,
    this.depositPaise = 0,
    this.balancePaise,
  });
}

@immutable
class BankStatementLine {
  final int id;
  final int societyId;
  final int importId;
  final int bankAccountId;
  final String lineDate;
  final String? description;
  final String? reference;
  final int withdrawalPaise;
  final int depositPaise;
  final int? statementBalancePaise;
  final bool isMatched;

  const BankStatementLine({
    required this.id,
    required this.societyId,
    required this.importId,
    required this.bankAccountId,
    required this.lineDate,
    this.description,
    this.reference,
    required this.withdrawalPaise,
    required this.depositPaise,
    this.statementBalancePaise,
    this.isMatched = false,
  });

  factory BankStatementLine.fromMap(Map<String, dynamic> map) {
    return BankStatementLine(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      importId: map['import_id'] as int,
      bankAccountId: map['bank_account_id'] as int,
      lineDate: map['line_date'] as String,
      description: map['description'] as String?,
      reference: map['reference'] as String?,
      withdrawalPaise: map['withdrawal_paise'] as int? ?? 0,
      depositPaise: map['deposit_paise'] as int? ?? 0,
      statementBalancePaise: map['statement_balance_paise'] as int?,
      isMatched: (map['is_matched'] as int? ?? 0) == 1,
    );
  }
}

@immutable
class ReconciliationSummary {
  final int bookBalancePaise;
  final int unclearedReceiptsPaise;
  final int unclearedPaymentsPaise;
  final int expectedStatementBalancePaise;
  final int statementBalancePaise;
  final int differencePaise;

  const ReconciliationSummary({
    required this.bookBalancePaise,
    required this.unclearedReceiptsPaise,
    required this.unclearedPaymentsPaise,
    required this.expectedStatementBalancePaise,
    required this.statementBalancePaise,
    required this.differencePaise,
  });
}

@immutable
class ReconciliationView {
  final BankAccount bankAccount;
  final String asOfDate;
  final ReconciliationSummary summary;
  final List<BankBookRow> bookItems;
  final List<BankStatementLine> statementLines;

  const ReconciliationView({
    required this.bankAccount,
    required this.asOfDate,
    required this.summary,
    required this.bookItems,
    required this.statementLines,
  });
}

// Fixed Deposits
@immutable
class FixedDeposit {
  final int id;
  final int societyId;
  final int accountId;
  final String fdNo;
  final String bankName;
  final String startDate;
  final String maturityDate;
  final int principalPaise;
  final int rateBp; // Basis points (e.g. 750 = 7.50%)
  final String compounding; // 'none','monthly','quarterly','half_yearly','yearly'
  final String interestFrequency; // 'monthly','quarterly','half_yearly','yearly','on_maturity'
  final int tdsRateBp;
  final int? expectedMaturityPaise;
  final String? instructions;
  final String status; // 'active', 'closed'
  final Account? account;

  const FixedDeposit({
    required this.id,
    required this.societyId,
    required this.accountId,
    required this.fdNo,
    required this.bankName,
    required this.startDate,
    required this.maturityDate,
    required this.principalPaise,
    required this.rateBp,
    required this.compounding,
    required this.interestFrequency,
    required this.tdsRateBp,
    this.expectedMaturityPaise,
    this.instructions,
    required this.status,
    this.account,
  });

  factory FixedDeposit.fromMap(Map<String, dynamic> map, {Account? account}) {
    return FixedDeposit(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      accountId: map['account_id'] as int,
      fdNo: map['fd_no'] as String,
      bankName: map['bank_name'] as String,
      startDate: map['start_date'] as String,
      maturityDate: map['maturity_date'] as String,
      principalPaise: map['principal_paise'] as int,
      rateBp: map['rate_bp'] as int,
      compounding: map['compounding'] as String,
      interestFrequency: map['interest_frequency'] as String,
      tdsRateBp: map['tds_rate_bp'] as int? ?? 0,
      expectedMaturityPaise: map['expected_maturity_paise'] as int?,
      instructions: map['instructions'] as String?,
      status: map['status'] as String,
      account: account,
    );
  }
}

@immutable
class FixedDepositDraft {
  final String fdNo;
  final String bankName;
  final String startDate;
  final String maturityDate;
  final int principalPaise;
  final int rateBp;
  final String compounding; // 'none','monthly','quarterly','half_yearly','yearly'
  final String interestFrequency; // 'monthly','quarterly','half_yearly','yearly','on_maturity'
  final int tdsRateBp;
  final int? expectedMaturityPaise;
  final String? instructions;
  final int bankCashAccountId; // Account from which money was paid

  const FixedDepositDraft({
    required this.fdNo,
    required this.bankName,
    required this.startDate,
    required this.maturityDate,
    required this.principalPaise,
    required this.rateBp,
    this.compounding = 'quarterly',
    this.interestFrequency = 'quarterly',
    this.tdsRateBp = 1000, // 10% standard TDS
    this.expectedMaturityPaise,
    this.instructions,
    required this.bankCashAccountId,
  });
}

@immutable
class FdTransactionDraft {
  final int fdId;
  final String txnType; // 'open', 'interest_accrued', 'interest_received', 'close'
  final String txnDate;
  final int amountPaise;
  final int tdsPaise;
  final int? bankCashAccountId;
  final String? narration;

  const FdTransactionDraft({
    required this.fdId,
    required this.txnType,
    required this.txnDate,
    required this.amountPaise,
    this.tdsPaise = 0,
    this.bankCashAccountId,
    this.narration,
  });
}

@immutable
class FdTransaction {
  final int id;
  final int societyId;
  final int fdId;
  final int fyId;
  final String txnType;
  final String txnDate;
  final int amountPaise;
  final int tdsPaise;
  final int? bankCashAccountId;
  final String? narration;
  final String status;
  final int? journalEntryId;
  final int? reversalEntryId;

  const FdTransaction({
    required this.id,
    required this.societyId,
    required this.fdId,
    required this.fyId,
    required this.txnType,
    required this.txnDate,
    required this.amountPaise,
    required this.tdsPaise,
    this.bankCashAccountId,
    this.narration,
    required this.status,
    this.journalEntryId,
    this.reversalEntryId,
  });

  factory FdTransaction.fromMap(Map<String, dynamic> map) {
    return FdTransaction(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fdId: map['fd_id'] as int,
      fyId: map['fy_id'] as int,
      txnType: map['txn_type'] as String,
      txnDate: map['txn_date'] as String,
      amountPaise: map['amount_paise'] as int,
      tdsPaise: map['tds_paise'] as int? ?? 0,
      bankCashAccountId: map['bank_cash_account_id'] as int?,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
    );
  }
}

// Tax Registers
@immutable
class TaxRegisterLine {
  final String date;
  final String docType; // 'Member Bill', 'Other Invoice', 'Expense Bill', 'Debit Note'
  final String docNo;
  final String partyOrMemberName;
  final String? gstin;
  final String? stateCode;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalTaxPaise;
  final int totalPaise;

  const TaxRegisterLine({
    required this.date,
    required this.docType,
    required this.docNo,
    required this.partyOrMemberName,
    this.gstin,
    this.stateCode,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalTaxPaise,
    required this.totalPaise,
  });
}

@immutable
class TdsRegisterLine {
  final String date;
  final String docType; // 'Expense Bill', 'FD Accrual', 'FD Receipt'
  final String docNo;
  final String deducteeName;
  final String? pan;
  final String sectionCode;
  final int grossAmountPaise;
  final int tdsRateBp;
  final int tdsPaise;
  final bool isPayable; // true = deducted (liability 2604), false = receivable (asset 1604)

  const TdsRegisterLine({
    required this.date,
    required this.docType,
    required this.docNo,
    required this.deducteeName,
    this.pan,
    required this.sectionCode,
    required this.grossAmountPaise,
    required this.tdsRateBp,
    required this.tdsPaise,
    required this.isPayable,
  });
}

@immutable
class TaxRegister {
  final String fromDate;
  final String toDate;
  final String registerKind; // 'gst' or 'tds'
  final List<TaxRegisterLine> gstOutwardLines;
  final List<TaxRegisterLine> gstInwardLines;
  final List<TdsRegisterLine> tdsLines;
  final int totalTaxablePaise;
  final int totalCgstPaise;
  final int totalSgstPaise;
  final int totalIgstPaise;
  final int totalTdsPayablePaise;
  final int totalTdsReceivablePaise;

  const TaxRegister({
    required this.fromDate,
    required this.toDate,
    required this.registerKind,
    this.gstOutwardLines = const [],
    this.gstInwardLines = const [],
    this.tdsLines = const [],
    this.totalTaxablePaise = 0,
    this.totalCgstPaise = 0,
    this.totalSgstPaise = 0,
    this.totalIgstPaise = 0,
    this.totalTdsPayablePaise = 0,
    this.totalTdsReceivablePaise = 0,
  });
}
