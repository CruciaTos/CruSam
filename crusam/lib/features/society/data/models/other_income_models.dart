class Party {
  final int id;
  final int societyId;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? pan;
  final String? gstin;
  final String? stateCode;
  final bool isActive;

  const Party({
    required this.id,
    required this.societyId,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.pan,
    this.gstin,
    this.stateCode,
    required this.isActive,
  });

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      name: map['name'] as String,
      contactName: map['contact_name'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      pan: map['pan'] as String?,
      gstin: map['gstin'] as String?,
      stateCode: map['state_code'] as String?,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'society_id': societyId,
      'name': name,
      'contact_name': contactName,
      'phone': phone,
      'email': email,
      'address': address,
      'pan': pan,
      'gstin': gstin,
      'state_code': stateCode,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class PartyDraft {
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? pan;
  final String? gstin;
  final String? stateCode;
  final bool isActive;

  const PartyDraft({
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.pan,
    this.gstin,
    this.stateCode,
    this.isActive = true,
  });
}

class PartyFilter {
  final String? search;
  final bool? isActive;

  const PartyFilter({this.search, this.isActive});
}

class PartyRow {
  final Party party;
  final int totalInvoicedPaise;
  final int totalPaidPaise;
  final int balancePaise;

  const PartyRow({
    required this.party,
    required this.totalInvoicedPaise,
    required this.totalPaidPaise,
    required this.balancePaise,
  });
}

class OtherInvoice {
  final int id;
  final int societyId;
  final int fyId;
  final String invoiceNo;
  final int partyId;
  final String invoiceDate;
  final String dueDate;
  final int subtotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalPaise;
  final String? narration;
  final String status; // 'posted', 'reversed'
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? partyName;

  const OtherInvoice({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.invoiceNo,
    required this.partyId,
    required this.invoiceDate,
    required this.dueDate,
    required this.subtotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalPaise,
    this.narration,
    required this.status,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    this.partyName,
  });

  factory OtherInvoice.fromMap(Map<String, dynamic> map) {
    return OtherInvoice(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      invoiceNo: map['invoice_no'] as String,
      partyId: map['party_id'] as int,
      invoiceDate: map['invoice_date'] as String,
      dueDate: map['due_date'] as String,
      subtotalPaise: map['subtotal_paise'] as int,
      cgstPaise: map['cgst_paise'] as int,
      sgstPaise: map['sgst_paise'] as int,
      igstPaise: map['igst_paise'] as int,
      totalPaise: map['total_paise'] as int,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      reversalReason: map['reversal_reason'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      partyName: map['party_name'] as String?,
    );
  }
}

class OtherInvoiceLine {
  final int id;
  final int societyId;
  final int invoiceId;
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

  const OtherInvoiceLine({
    required this.id,
    required this.societyId,
    required this.invoiceId,
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

  factory OtherInvoiceLine.fromMap(Map<String, dynamic> map) {
    return OtherInvoiceLine(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      invoiceId: map['invoice_id'] as int,
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

class OtherInvoiceLineDraft {
  final int accountId;
  final String? description;
  final String? hsnSac;
  final int amountPaise;
  final int gstRateBp;

  const OtherInvoiceLineDraft({
    required this.accountId,
    this.description,
    this.hsnSac,
    required this.amountPaise,
    this.gstRateBp = 0,
  });
}

class OtherInvoiceDraft {
  final int partyId;
  final String invoiceDate;
  final String dueDate;
  final List<OtherInvoiceLineDraft> lines;
  final String? narration;

  const OtherInvoiceDraft({
    required this.partyId,
    required this.invoiceDate,
    required this.dueDate,
    required this.lines,
    this.narration,
  });
}

class OtherReceipt {
  final int id;
  final int societyId;
  final int fyId;
  final String receiptNo;
  final int partyId;
  final String receiptDate;
  final int amountPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentBank;
  final int bankCashAccountId;
  final String? narration;
  final String status;
  final String? reversalReason;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? partyName;
  final String? bankCashAccountName;

  const OtherReceipt({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.receiptNo,
    required this.partyId,
    required this.receiptDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentBank,
    required this.bankCashAccountId,
    this.narration,
    required this.status,
    this.reversalReason,
    this.journalEntryId,
    this.reversalEntryId,
    this.partyName,
    this.bankCashAccountName,
  });

  factory OtherReceipt.fromMap(Map<String, dynamic> map) {
    return OtherReceipt(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      receiptNo: map['receipt_no'] as String,
      partyId: map['party_id'] as int,
      receiptDate: map['receipt_date'] as String,
      amountPaise: map['amount_paise'] as int,
      mode: map['mode'] as String,
      instrumentNo: map['instrument_no'] as String?,
      instrumentBank: map['instrument_bank'] as String?,
      bankCashAccountId: map['bank_cash_account_id'] as int,
      narration: map['narration'] as String?,
      status: map['status'] as String,
      reversalReason: map['reversal_reason'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      partyName: map['party_name'] as String?,
      bankCashAccountName: map['bank_account_name'] as String?,
    );
  }
}

class OtherReceiptAllocationDraft {
  final int invoiceId;
  final int allocatedPaise;

  const OtherReceiptAllocationDraft({
    required this.invoiceId,
    required this.allocatedPaise,
  });
}

class OtherReceiptDraft {
  final int partyId;
  final String receiptDate;
  final int amountPaise;
  final String mode;
  final String? instrumentNo;
  final String? instrumentBank;
  final int bankCashAccountId;
  final String? narration;
  final List<OtherReceiptAllocationDraft>? allocations;

  const OtherReceiptDraft({
    required this.partyId,
    required this.receiptDate,
    required this.amountPaise,
    required this.mode,
    this.instrumentNo,
    this.instrumentBank,
    required this.bankCashAccountId,
    this.narration,
    this.allocations,
  });
}

class PartyStatementRow {
  final String date;
  final String type; // 'Invoice', 'Receipt', 'Reversal'
  final String refNo;
  final String description;
  final int debitPaise;
  final int creditPaise;
  final int balancePaise;

  const PartyStatementRow({
    required this.date,
    required this.type,
    required this.refNo,
    required this.description,
    required this.debitPaise,
    required this.creditPaise,
    required this.balancePaise,
  });
}

class PartyStatement {
  final Party party;
  final String fromDate;
  final String toDate;
  final int openingBalancePaise;
  final List<PartyStatementRow> rows;
  final int closingBalancePaise;

  const PartyStatement({
    required this.party,
    required this.fromDate,
    required this.toDate,
    required this.openingBalancePaise,
    required this.rows,
    required this.closingBalancePaise,
  });
}
