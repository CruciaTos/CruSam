class Receipt {
  final int id;
  final int societyId;
  final int fyId;
  final String receiptNo;
  final String receiptKind;
  final int unitId;
  final String blockName;
  final String unitNo;
  final int? payerPersonId;
  final String payerName;
  final String receiptDate;
  final int amountPaise;
  final int tdsPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentDate;
  final String? instrumentBank;
  final int? bankCashAccountId;
  final String? bankCashAccountName;
  final int? unidentifiedId;
  final String? narration;
  final String status;
  final String? reversalKind;
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String createdAt;
  final int allocatedPaise;

  const Receipt({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.receiptNo,
    required this.receiptKind,
    required this.unitId,
    required this.blockName,
    required this.unitNo,
    this.payerPersonId,
    required this.payerName,
    required this.receiptDate,
    required this.amountPaise,
    this.tdsPaise = 0,
    required this.mode,
    this.instrumentNo,
    this.instrumentDate,
    this.instrumentBank,
    this.bankCashAccountId,
    this.bankCashAccountName,
    this.unidentifiedId,
    this.narration,
    this.status = 'posted',
    this.reversalKind,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    required this.createdAt,
    this.allocatedPaise = 0,
  });

  int get totalPaise => amountPaise + tdsPaise;
  int get unallocatedPaise => totalPaise - allocatedPaise;
  bool get isReversed => status == 'reversed';

  factory Receipt.fromMap(Map<String, Object?> m, [int allocated = 0]) {
    return Receipt(
      id: m['id'] as int,
      societyId: m['society_id'] as int,
      fyId: m['fy_id'] as int,
      receiptNo: m['receipt_no'] as String,
      receiptKind: (m['receipt_kind'] as String?) ?? 'bill',
      unitId: m['unit_id'] as int,
      blockName: (m['block_name'] as String?) ?? '',
      unitNo: (m['unit_no'] as String?) ?? '',
      payerPersonId: m['payer_person_id'] as int?,
      payerName: (m['payer_name'] as String?) ?? '',
      receiptDate: m['receipt_date'] as String,
      amountPaise: (m['amount_paise'] as int?) ?? 0,
      tdsPaise: (m['tds_paise'] as int?) ?? 0,
      mode: (m['mode'] as String?) ?? 'bank',
      instrumentNo: m['instrument_no'] as String?,
      instrumentDate: m['instrument_date'] as String?,
      instrumentBank: m['instrument_bank'] as String?,
      bankCashAccountId: m['bank_cash_account_id'] as int?,
      bankCashAccountName: m['bank_account_name'] as String?,
      unidentifiedId: m['unidentified_id'] as int?,
      narration: m['narration'] as String?,
      status: (m['status'] as String?) ?? 'posted',
      reversalKind: m['reversal_kind'] as String?,
      reversalReason: m['reversal_reason'] as String?,
      journalEntryId: m['journal_entry_id'] as int?,
      reversalEntryId: m['reversal_entry_id'] as int?,
      createdAt: (m['created_at'] as String?) ?? '',
      allocatedPaise: allocated,
    );
  }
}

class AllocationDraft {
  final int billLineId;
  final int amountPaise;

  const AllocationDraft({
    required this.billLineId,
    required this.amountPaise,
  });
}

class ReceiptDraft {
  final String receiptKind;
  final int unitId;
  final int? payerPersonId;
  final String payerName;
  final String receiptDate;
  final int amountPaise;
  final int tdsPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentDate;
  final String? instrumentBank;
  final int? bankCashAccountId;
  final int? unidentifiedId;
  final String? narration;
  final List<AllocationDraft>? customAllocations;

  const ReceiptDraft({
    this.receiptKind = 'bill',
    required this.unitId,
    this.payerPersonId,
    required this.payerName,
    required this.receiptDate,
    required this.amountPaise,
    this.tdsPaise = 0,
    required this.mode,
    this.instrumentNo,
    this.instrumentDate,
    this.instrumentBank,
    this.bankCashAccountId,
    this.unidentifiedId,
    this.narration,
    this.customAllocations,
  });

  int get totalPaise => amountPaise + tdsPaise;
}

class BillAllocation {
  final int id;
  final int societyId;
  final String sourceType;
  final int sourceId;
  final int billLineId;
  final int allocatedPaise;
  final String allocationDate;
  final bool isActive;
  final String createdAt;
  final int? billId;
  final String? billNo;
  final String? chargeHeadName;

  const BillAllocation({
    required this.id,
    required this.societyId,
    required this.sourceType,
    required this.sourceId,
    required this.billLineId,
    required this.allocatedPaise,
    required this.allocationDate,
    required this.isActive,
    required this.createdAt,
    this.billId,
    this.billNo,
    this.chargeHeadName,
  });

  factory BillAllocation.fromMap(Map<String, Object?> m) {
    return BillAllocation(
      id: m['id'] as int,
      societyId: m['society_id'] as int,
      sourceType: m['source_type'] as String,
      sourceId: m['source_id'] as int,
      billLineId: m['bill_line_id'] as int,
      allocatedPaise: (m['allocated_paise'] as int?) ?? 0,
      allocationDate: m['allocation_date'] as String,
      isActive: (m['is_active'] as int?) == 1,
      createdAt: (m['created_at'] as String?) ?? '',
      billId: m['bill_id'] as int?,
      billNo: m['bill_no'] as String?,
      chargeHeadName: m['charge_head_name'] as String?,
    );
  }
}

class CreditNote {
  final int id;
  final int societyId;
  final int fyId;
  final String noteNo;
  final String scope;
  final int unitId;
  final String blockName;
  final String unitNo;
  final String noteDate;
  final int? chargeHeadId;
  final String? chargeHeadName;
  final int amountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalPaise;
  final String reason;
  final String status;
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;

  const CreditNote({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.noteNo,
    required this.scope,
    required this.unitId,
    required this.blockName,
    required this.unitNo,
    required this.noteDate,
    this.chargeHeadId,
    this.chargeHeadName,
    required this.amountPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    required this.totalPaise,
    required this.reason,
    this.status = 'posted',
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
  });

  bool get isReversed => status == 'reversed';

  factory CreditNote.fromMap(Map<String, Object?> m) {
    return CreditNote(
      id: m['id'] as int,
      societyId: m['society_id'] as int,
      fyId: m['fy_id'] as int,
      noteNo: m['note_no'] as String,
      scope: (m['scope'] as String?) ?? 'general',
      unitId: m['unit_id'] as int,
      blockName: (m['block_name'] as String?) ?? '',
      unitNo: (m['unit_no'] as String?) ?? '',
      noteDate: m['note_date'] as String,
      chargeHeadId: m['charge_head_id'] as int?,
      chargeHeadName: m['charge_head_name'] as String?,
      amountPaise: (m['amount_paise'] as int?) ?? 0,
      cgstPaise: (m['cgst_paise'] as int?) ?? 0,
      sgstPaise: (m['sgst_paise'] as int?) ?? 0,
      igstPaise: (m['igst_paise'] as int?) ?? 0,
      totalPaise: (m['total_paise'] as int?) ?? 0,
      reason: (m['reason'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'posted',
      reversalReason: m['reversal_reason'] as String?,
      journalEntryId: m['journal_entry_id'] as int?,
      reversalEntryId: m['reversal_entry_id'] as int?,
    );
  }
}

class CreditNoteDraft {
  final String scope;
  final int unitId;
  final String noteDate;
  final int? chargeHeadId;
  final int amountPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final String reason;
  final List<AllocationDraft>? customAllocations;

  const CreditNoteDraft({
    this.scope = 'general',
    required this.unitId,
    required this.noteDate,
    this.chargeHeadId,
    required this.amountPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    required this.reason,
    this.customAllocations,
  });

  int get totalPaise => amountPaise + cgstPaise + sgstPaise + igstPaise;
}

class UnidentifiedReceipt {
  final int id;
  final int societyId;
  final int fyId;
  final String referenceNo;
  final String receiptDate;
  final int amountPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentBank;
  final int bankCashAccountId;
  final String? bankCashAccountName;
  final String? narration;
  final String status;
  final int? resolvedReceiptId;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? reversalReason;

  const UnidentifiedReceipt({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.referenceNo,
    required this.receiptDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentBank,
    required this.bankCashAccountId,
    this.bankCashAccountName,
    this.narration,
    this.status = 'open',
    this.resolvedReceiptId,
    this.journalEntryId,
    this.reversalEntryId,
    this.reversalReason,
  });

  bool get isOpen => status == 'open';

  factory UnidentifiedReceipt.fromMap(Map<String, Object?> m) {
    return UnidentifiedReceipt(
      id: m['id'] as int,
      societyId: m['society_id'] as int,
      fyId: m['fy_id'] as int,
      referenceNo: m['reference_no'] as String,
      receiptDate: m['receipt_date'] as String,
      amountPaise: (m['amount_paise'] as int?) ?? 0,
      mode: (m['mode'] as String?) ?? 'bank',
      instrumentNo: m['instrument_no'] as String?,
      instrumentBank: m['instrument_bank'] as String?,
      bankCashAccountId: m['bank_cash_account_id'] as int,
      bankCashAccountName: m['bank_account_name'] as String?,
      narration: m['narration'] as String?,
      status: (m['status'] as String?) ?? 'open',
      resolvedReceiptId: m['resolved_receipt_id'] as int?,
      journalEntryId: m['journal_entry_id'] as int?,
      reversalEntryId: m['reversal_entry_id'] as int?,
      reversalReason: m['reversal_reason'] as String?,
    );
  }
}

class UnidentifiedReceiptDraft {
  final String receiptDate;
  final int amountPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentBank;
  final int bankCashAccountId;
  final String? narration;

  const UnidentifiedReceiptDraft({
    required this.receiptDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentBank,
    required this.bankCashAccountId,
    this.narration,
  });
}

class OpenBillLine {
  final int billId;
  final String billNo;
  final String billDate;
  final String dueDate;
  final int billLineId;
  final int lineNo;
  final int chargeHeadId;
  final String chargeHeadName;
  final String headKind;
  final bool isInterestBearing;
  final int payablePaise;
  final int allocatedPaise;

  const OpenBillLine({
    required this.billId,
    required this.billNo,
    required this.billDate,
    required this.dueDate,
    required this.billLineId,
    required this.lineNo,
    required this.chargeHeadId,
    required this.chargeHeadName,
    required this.headKind,
    required this.isInterestBearing,
    required this.payablePaise,
    required this.allocatedPaise,
  });

  int get remainingPaise => payablePaise - allocatedPaise;
}

class UnitStatementRow {
  final String date;
  final String docType;
  final String docNo;
  final String description;
  final int debitPaise;
  final int creditPaise;
  final int runningBalancePaise;

  const UnitStatementRow({
    required this.date,
    required this.docType,
    required this.docNo,
    required this.description,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
  });
}

class UnitDueSummary {
  final int unitId;
  final String unitNo;
  final String blockName;
  final String? ownerName;
  final String? phone;
  final int membersReceivablePaise;
  final int advancePaise;
  final int netDuePaise;
  final int age0to30Paise;
  final int age31to60Paise;
  final int age61to90Paise;
  final int age90PlusPaise;

  const UnitDueSummary({
    required this.unitId,
    required this.unitNo,
    required this.blockName,
    this.ownerName,
    this.phone,
    required this.membersReceivablePaise,
    this.advancePaise = 0,
    required this.netDuePaise,
    this.age0to30Paise = 0,
    this.age31to60Paise = 0,
    this.age61to90Paise = 0,
    this.age90PlusPaise = 0,
  });
}
