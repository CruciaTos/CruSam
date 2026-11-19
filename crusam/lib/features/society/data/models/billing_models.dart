class ChargeHead {
  final int id;
  final int societyId;
  final String name;
  final int accountId;
  final String? accountCode;
  final String? accountName;
  final String headKind; // 'charge', 'interest'
  final bool isInterestBearing;
  final bool isGstApplicable;
  final int? defaultGstRateBp;
  final String? hsnSac;
  final int sortOrder;
  final String? systemKey;
  final bool isActive;

  const ChargeHead({
    required this.id,
    required this.societyId,
    required this.name,
    required this.accountId,
    this.accountCode,
    this.accountName,
    this.headKind = 'charge',
    this.isInterestBearing = true,
    this.isGstApplicable = false,
    this.defaultGstRateBp,
    this.hsnSac,
    this.sortOrder = 0,
    this.systemKey,
    this.isActive = true,
  });

  factory ChargeHead.fromMap(Map<String, Object?> map) {
    return ChargeHead(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      name: map['name'] as String,
      accountId: map['account_id'] as int,
      accountCode: map['account_code'] as String?,
      accountName: map['account_name'] as String?,
      headKind: (map['head_kind'] as String?) ?? 'charge',
      isInterestBearing: (map['is_interest_bearing'] as int) == 1,
      isGstApplicable: (map['is_gst_applicable'] as int) == 1,
      defaultGstRateBp: map['default_gst_rate_bp'] as int?,
      hsnSac: map['hsn_sac'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      systemKey: map['system_key'] as String?,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class ChargeHeadDraft {
  final String name;
  final int accountId;
  final String headKind;
  final bool isInterestBearing;
  final bool isGstApplicable;
  final int? defaultGstRateBp;
  final String? hsnSac;
  final int sortOrder;
  final String? systemKey;
  final bool isActive;

  const ChargeHeadDraft({
    required this.name,
    required this.accountId,
    this.headKind = 'charge',
    this.isInterestBearing = true,
    this.isGstApplicable = false,
    this.defaultGstRateBp,
    this.hsnSac,
    this.sortOrder = 0,
    this.systemKey,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'name': name.trim(),
      'account_id': accountId,
      'head_kind': headKind,
      'is_interest_bearing': isInterestBearing ? 1 : 0,
      'is_gst_applicable': isGstApplicable ? 1 : 0,
      'default_gst_rate_bp': defaultGstRateBp,
      'hsn_sac': hsnSac?.trim(),
      'sort_order': sortOrder,
      'system_key': systemKey,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class MeterSlab {
  final int id;
  final int meterTypeId;
  final int seq;
  final int? upToMilli;
  final int ratePaise;

  const MeterSlab({
    required this.id,
    required this.meterTypeId,
    required this.seq,
    this.upToMilli,
    required this.ratePaise,
  });

  factory MeterSlab.fromMap(Map<String, Object?> map) {
    return MeterSlab(
      id: map['id'] as int,
      meterTypeId: map['meter_type_id'] as int,
      seq: map['seq'] as int,
      upToMilli: map['up_to_milli'] as int?,
      ratePaise: map['rate_paise'] as int,
    );
  }
}

class MeterSlabDraft {
  final int seq;
  final int? upToMilli;
  final int ratePaise;

  const MeterSlabDraft({
    required this.seq,
    this.upToMilli,
    required this.ratePaise,
  });

  Map<String, Object?> toMap(int societyId, int meterTypeId) {
    return {
      'society_id': societyId,
      'meter_type_id': meterTypeId,
      'seq': seq,
      'up_to_milli': upToMilli,
      'rate_paise': ratePaise,
    };
  }
}

class MeterType {
  final int id;
  final int societyId;
  final String name;
  final int chargeHeadId;
  final String? chargeHeadName;
  final bool isCumulative;
  final int minimumPaise;
  final bool isActive;
  final List<MeterSlab> slabs;

  const MeterType({
    required this.id,
    required this.societyId,
    required this.name,
    required this.chargeHeadId,
    this.chargeHeadName,
    this.isCumulative = true,
    this.minimumPaise = 0,
    this.isActive = true,
    this.slabs = const [],
  });

  factory MeterType.fromMap(Map<String, Object?> map, [List<MeterSlab> slabs = const []]) {
    return MeterType(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      name: map['name'] as String,
      chargeHeadId: map['charge_head_id'] as int,
      chargeHeadName: map['charge_head_name'] as String?,
      isCumulative: (map['is_cumulative'] as int) == 1,
      minimumPaise: (map['minimum_paise'] as int?) ?? 0,
      isActive: (map['is_active'] as int) == 1,
      slabs: slabs,
    );
  }
}

class MeterTypeDraft {
  final String name;
  final int chargeHeadId;
  final bool isCumulative;
  final int minimumPaise;
  final bool isActive;
  final List<MeterSlabDraft> slabs;

  const MeterTypeDraft({
    required this.name,
    required this.chargeHeadId,
    this.isCumulative = true,
    this.minimumPaise = 0,
    this.isActive = true,
    this.slabs = const [],
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'name': name.trim(),
      'charge_head_id': chargeHeadId,
      'is_cumulative': isCumulative ? 1 : 0,
      'minimum_paise': minimumPaise,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class BillingRule {
  final int id;
  final int societyId;
  final int chargeHeadId;
  final String chargeHeadName;
  final int? unitTypeId;
  final String? unitTypeName;
  final String ruleType; // 'area_and_fixed', 'percent_of_heads', 'metered_slab'
  final int rate1Paise;
  final int rate2Paise;
  final int fixedPaise;
  final int percentBp;
  final List<int> baseHeadIds;
  final String? occupancyFilter; // 'owner_occupied', 'tenanted', 'vacant'
  final int? meterTypeId;
  final String? meterTypeName;
  final String effectiveFrom;
  final String? effectiveTo;
  final bool isActive;

  const BillingRule({
    required this.id,
    required this.societyId,
    required this.chargeHeadId,
    required this.chargeHeadName,
    this.unitTypeId,
    this.unitTypeName,
    required this.ruleType,
    this.rate1Paise = 0,
    this.rate2Paise = 0,
    this.fixedPaise = 0,
    this.percentBp = 0,
    this.baseHeadIds = const [],
    this.occupancyFilter,
    this.meterTypeId,
    this.meterTypeName,
    required this.effectiveFrom,
    this.effectiveTo,
    this.isActive = true,
  });

  factory BillingRule.fromMap(Map<String, Object?> map) {
    final rawBase = map['base_head_ids'] as String?;
    final baseIds = <int>[];
    if (rawBase != null && rawBase.isNotEmpty) {
      for (final s in rawBase.split(',')) {
        final id = int.tryParse(s.trim());
        if (id != null) baseIds.add(id);
      }
    }

    return BillingRule(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      chargeHeadId: map['charge_head_id'] as int,
      chargeHeadName: (map['charge_head_name'] as String?) ?? '',
      unitTypeId: map['unit_type_id'] as int?,
      unitTypeName: map['unit_type_name'] as String?,
      ruleType: map['rule_type'] as String,
      rate1Paise: (map['rate1_paise'] as int?) ?? 0,
      rate2Paise: (map['rate2_paise'] as int?) ?? 0,
      fixedPaise: (map['fixed_paise'] as int?) ?? 0,
      percentBp: (map['percent_bp'] as int?) ?? 0,
      baseHeadIds: baseIds,
      occupancyFilter: map['occupancy_filter'] as String?,
      meterTypeId: map['meter_type_id'] as int?,
      meterTypeName: map['meter_type_name'] as String?,
      effectiveFrom: map['effective_from'] as String,
      effectiveTo: map['effective_to'] as String?,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class BillingRuleDraft {
  final int chargeHeadId;
  final int? unitTypeId;
  final String ruleType;
  final int rate1Paise;
  final int rate2Paise;
  final int fixedPaise;
  final int percentBp;
  final List<int> baseHeadIds;
  final String? occupancyFilter;
  final int? meterTypeId;
  final String effectiveFrom;
  final String? effectiveTo;
  final bool isActive;

  const BillingRuleDraft({
    required this.chargeHeadId,
    this.unitTypeId,
    required this.ruleType,
    this.rate1Paise = 0,
    this.rate2Paise = 0,
    this.fixedPaise = 0,
    this.percentBp = 0,
    this.baseHeadIds = const [],
    this.occupancyFilter,
    this.meterTypeId,
    required this.effectiveFrom,
    this.effectiveTo,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'charge_head_id': chargeHeadId,
      'unit_type_id': unitTypeId,
      'rule_type': ruleType,
      'rate1_paise': rate1Paise,
      'rate2_paise': rate2Paise,
      'fixed_paise': fixedPaise,
      'percent_bp': percentBp,
      'base_head_ids': baseHeadIds.join(','),
      'occupancy_filter': occupancyFilter,
      'meter_type_id': meterTypeId,
      'effective_from': effectiveFrom,
      'effective_to': effectiveTo,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class Meter {
  final int id;
  final int societyId;
  final int unitId;
  final String unitNo;
  final String blockName;
  final int meterTypeId;
  final String meterTypeName;
  final String? meterNo;
  final int openingReadingMilli;
  final bool isActive;
  final int? lastReadingMilli;
  final String? lastReadingDate;

  const Meter({
    required this.id,
    required this.societyId,
    required this.unitId,
    required this.unitNo,
    required this.blockName,
    required this.meterTypeId,
    required this.meterTypeName,
    this.meterNo,
    this.openingReadingMilli = 0,
    this.isActive = true,
    this.lastReadingMilli,
    this.lastReadingDate,
  });

  factory Meter.fromMap(Map<String, Object?> map) {
    return Meter(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      unitId: map['unit_id'] as int,
      unitNo: (map['unit_no'] as String?) ?? '',
      blockName: (map['block_name'] as String?) ?? '',
      meterTypeId: map['meter_type_id'] as int,
      meterTypeName: (map['meter_type_name'] as String?) ?? '',
      meterNo: map['meter_no'] as String?,
      openingReadingMilli: (map['opening_reading_milli'] as int?) ?? 0,
      isActive: (map['is_active'] as int) == 1,
      lastReadingMilli: map['last_reading_milli'] as int?,
      lastReadingDate: map['last_reading_date'] as String?,
    );
  }
}

class MeterDraft {
  final int unitId;
  final int meterTypeId;
  final String? meterNo;
  final int openingReadingMilli;
  final bool isActive;

  const MeterDraft({
    required this.unitId,
    required this.meterTypeId,
    this.meterNo,
    this.openingReadingMilli = 0,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'unit_id': unitId,
      'meter_type_id': meterTypeId,
      'meter_no': meterNo?.trim(),
      'opening_reading_milli': openingReadingMilli,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class MeterReading {
  final int id;
  final int societyId;
  final int meterId;
  final String periodFrom;
  final String periodTo;
  final String readingDate;
  final int readingMilli;

  const MeterReading({
    required this.id,
    required this.societyId,
    required this.meterId,
    required this.periodFrom,
    required this.periodTo,
    required this.readingDate,
    required this.readingMilli,
  });

  factory MeterReading.fromMap(Map<String, Object?> map) {
    return MeterReading(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      meterId: map['meter_id'] as int,
      periodFrom: map['period_from'] as String,
      periodTo: map['period_to'] as String,
      readingDate: map['reading_date'] as String,
      readingMilli: map['reading_milli'] as int,
    );
  }
}

class BillRun {
  final int id;
  final int societyId;
  final int fyId;
  final String frequency;
  final String periodFrom;
  final String periodTo;
  final String billDate;
  final String dueDate;
  final String? interestThrough;
  final String status; // 'draft', 'posted', 'cancelled'
  final String? notes;
  final String createdAt;
  final String? postedAt;
  final int billCount;
  final int totalPaise;

  const BillRun({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.frequency,
    required this.periodFrom,
    required this.periodTo,
    required this.billDate,
    required this.dueDate,
    this.interestThrough,
    required this.status,
    this.notes,
    required this.createdAt,
    this.postedAt,
    this.billCount = 0,
    this.totalPaise = 0,
  });

  bool get isDraft => status == 'draft';
  bool get isPosted => status == 'posted';

  factory BillRun.fromMap(Map<String, Object?> map) {
    return BillRun(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      frequency: map['frequency'] as String,
      periodFrom: map['period_from'] as String,
      periodTo: map['period_to'] as String,
      billDate: map['bill_date'] as String,
      dueDate: map['due_date'] as String,
      interestThrough: map['interest_through'] as String?,
      status: map['status'] as String,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String,
      postedAt: map['posted_at'] as String?,
      billCount: (map['bill_count'] as int?) ?? 0,
      totalPaise: (map['total_paise'] as int?) ?? 0,
    );
  }
}

class BillRunDraft {
  final String frequency;
  final String periodFrom;
  final String periodTo;
  final String billDate;
  final String dueDate;
  final String? interestThrough;
  final String? notes;

  const BillRunDraft({
    required this.frequency,
    required this.periodFrom,
    required this.periodTo,
    required this.billDate,
    required this.dueDate,
    this.interestThrough,
    this.notes,
  });
}

class BillLine {
  final int id;
  final int societyId;
  final int billId;
  final int lineNo;
  final int chargeHeadId;
  final String chargeHeadName;
  final String lineKind; // 'charge', 'interest'
  final String? description;
  final int? quantityMilli;
  final int? ratePaise;
  final int amountPaise;
  final int gstRateBp;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int payablePaise;
  final bool isInterestBearing;

  const BillLine({
    required this.id,
    required this.societyId,
    required this.billId,
    required this.lineNo,
    required this.chargeHeadId,
    required this.chargeHeadName,
    this.lineKind = 'charge',
    this.description,
    this.quantityMilli,
    this.ratePaise,
    required this.amountPaise,
    this.gstRateBp = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.roundOffPaise = 0,
    required this.payablePaise,
    this.isInterestBearing = false,
  });

  factory BillLine.fromMap(Map<String, Object?> map) {
    return BillLine(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      billId: map['bill_id'] as int,
      lineNo: map['line_no'] as int,
      chargeHeadId: map['charge_head_id'] as int,
      chargeHeadName: (map['charge_head_name'] as String?) ?? '',
      lineKind: (map['line_kind'] as String?) ?? 'charge',
      description: map['description'] as String?,
      quantityMilli: map['quantity_milli'] as int?,
      ratePaise: map['rate_paise'] as int?,
      amountPaise: map['amount_paise'] as int,
      gstRateBp: (map['gst_rate_bp'] as int?) ?? 0,
      cgstPaise: (map['cgst_paise'] as int?) ?? 0,
      sgstPaise: (map['sgst_paise'] as int?) ?? 0,
      igstPaise: (map['igst_paise'] as int?) ?? 0,
      roundOffPaise: (map['round_off_paise'] as int?) ?? 0,
      payablePaise: map['payable_paise'] as int,
      isInterestBearing: (map['is_interest_bearing'] as int) == 1,
    );
  }
}

class BillLineDraft {
  final int chargeHeadId;
  final String lineKind;
  final String? description;
  final int? quantityMilli;
  final int? ratePaise;
  final int amountPaise;
  final int gstRateBp;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int payablePaise;
  final bool isInterestBearing;

  const BillLineDraft({
    required this.chargeHeadId,
    this.lineKind = 'charge',
    this.description,
    this.quantityMilli,
    this.ratePaise,
    required this.amountPaise,
    this.gstRateBp = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.roundOffPaise = 0,
    required this.payablePaise,
    this.isInterestBearing = false,
  });
}

class Bill {
  final int id;
  final int societyId;
  final int fyId;
  final int? runId;
  final String? billNo;
  final String billKind; // 'regular', 'supplementary', 'manual', 'debit_note'
  final int unitId;
  final String unitNo;
  final String blockName;
  final int? billToPersonId;
  final String billToName;
  final String billDate;
  final String dueDate;
  final String? periodFrom;
  final String? periodTo;
  final int subtotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int totalPaise;
  final int previousDuePaise;
  final String status; // 'draft', 'posted', 'reversed'
  final String? comment;
  final int? journalEntryId;
  final int? reversalEntryId;
  final String? reversalReason;
  final List<BillLine> lines;

  const Bill({
    required this.id,
    required this.societyId,
    required this.fyId,
    this.runId,
    this.billNo,
    required this.billKind,
    required this.unitId,
    required this.unitNo,
    required this.blockName,
    this.billToPersonId,
    required this.billToName,
    required this.billDate,
    required this.dueDate,
    this.periodFrom,
    this.periodTo,
    required this.subtotalPaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.roundOffPaise = 0,
    required this.totalPaise,
    this.previousDuePaise = 0,
    required this.status,
    this.comment,
    this.journalEntryId,
    this.reversalEntryId,
    this.reversalReason,
    this.lines = const [],
  });

  bool get isDraft => status == 'draft';
  bool get isPosted => status == 'posted';
  bool get isReversed => status == 'reversed';

  factory Bill.fromMap(Map<String, Object?> map, [List<BillLine> lines = const []]) {
    return Bill(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      runId: map['run_id'] as int?,
      billNo: map['bill_no'] as String?,
      billKind: map['bill_kind'] as String,
      unitId: map['unit_id'] as int,
      unitNo: (map['unit_no'] as String?) ?? '',
      blockName: (map['block_name'] as String?) ?? '',
      billToPersonId: map['bill_to_person_id'] as int?,
      billToName: map['bill_to_name'] as String,
      billDate: map['bill_date'] as String,
      dueDate: map['due_date'] as String,
      periodFrom: map['period_from'] as String?,
      periodTo: map['period_to'] as String?,
      subtotalPaise: map['subtotal_paise'] as int,
      cgstPaise: (map['cgst_paise'] as int?) ?? 0,
      sgstPaise: (map['sgst_paise'] as int?) ?? 0,
      igstPaise: (map['igst_paise'] as int?) ?? 0,
      roundOffPaise: (map['round_off_paise'] as int?) ?? 0,
      totalPaise: map['total_paise'] as int,
      previousDuePaise: (map['previous_due_paise'] as int?) ?? 0,
      status: map['status'] as String,
      comment: map['comment'] as String?,
      journalEntryId: map['journal_entry_id'] as int?,
      reversalEntryId: map['reversal_entry_id'] as int?,
      reversalReason: map['reversal_reason'] as String?,
      lines: lines,
    );
  }
}

class ManualBillDraft {
  final int unitId;
  final String billKind; // 'manual', 'debit_note', 'supplementary'
  final String billDate;
  final String dueDate;
  final String? periodFrom;
  final String? periodTo;
  final String? comment;
  final List<BillLineDraft> lines;

  const ManualBillDraft({
    required this.unitId,
    this.billKind = 'manual',
    required this.billDate,
    required this.dueDate,
    this.periodFrom,
    this.periodTo,
    this.comment,
    required this.lines,
  });
}
