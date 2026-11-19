class PageRequest {
  final int limit;
  final int offset;
  final String search;
  const PageRequest({this.limit = 50, this.offset = 0, this.search = ''});
}

class PageResult<T> {
  final List<T> rows;
  final int total;
  const PageResult(this.rows, this.total);
}

class ValidationIssue {
  final String field;
  final String message;
  final int? rowNumber;
  const ValidationIssue(this.field, this.message, {this.rowNumber});
}

class SocietyDraft {
  final String name;
  final String? shortName;
  final String? registrationNo;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String state;
  final String stateCode;
  final String? pincode;
  final String? phone;
  final String? email;
  final String? pan;
  final String? tan;
  final String? gstin;
  final bool gstRegistered;
  final String? gstEffectiveFrom;
  final String booksStartDate;
  final String? logoPath;
  final bool isActive;

  const SocietyDraft({
    required this.name,
    this.shortName,
    this.registrationNo,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state = 'Maharashtra',
    this.stateCode = '27',
    this.pincode,
    this.phone,
    this.email,
    this.pan,
    this.tan,
    this.gstin,
    this.gstRegistered = false,
    this.gstEffectiveFrom,
    required this.booksStartDate,
    this.logoPath,
    this.isActive = true,
  });

  Map<String, Object?> toInsertMap() {
    return {
      'name': name.trim(),
      'short_name': shortName?.trim(),
      'registration_no': registrationNo?.trim(),
      'address_line1': addressLine1?.trim(),
      'address_line2': addressLine2?.trim(),
      'city': city?.trim(),
      'state': state.trim(),
      'state_code': stateCode.trim(),
      'pincode': pincode?.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'pan': pan?.trim().toUpperCase(),
      'tan': tan?.trim().toUpperCase(),
      'gstin': gstin?.trim().toUpperCase(),
      'gst_registered': gstRegistered ? 1 : 0,
      'gst_effective_from': gstEffectiveFrom?.trim(),
      'books_start_date': booksStartDate.trim(),
      'logo_path': logoPath?.trim(),
      'is_active': isActive ? 1 : 0,
    };
  }
}

class Society {
  final int id;
  final String name;
  final String? shortName;
  final String? registrationNo;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String state;
  final String stateCode;
  final String? pincode;
  final String? phone;
  final String? email;
  final String? pan;
  final String? tan;
  final String? gstin;
  final bool gstRegistered;
  final String? gstEffectiveFrom;
  final String booksStartDate;
  final String? logoPath;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  const Society({
    required this.id,
    required this.name,
    this.shortName,
    this.registrationNo,
    this.addressLine1,
    this.addressLine2,
    this.city,
    required this.state,
    required this.stateCode,
    this.pincode,
    this.phone,
    this.email,
    this.pan,
    this.tan,
    this.gstin,
    required this.gstRegistered,
    this.gstEffectiveFrom,
    required this.booksStartDate,
    this.logoPath,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Society.fromMap(Map<String, Object?> map) {
    return Society(
      id: map['id'] as int,
      name: map['name'] as String,
      shortName: map['short_name'] as String?,
      registrationNo: map['registration_no'] as String?,
      addressLine1: map['address_line1'] as String?,
      addressLine2: map['address_line2'] as String?,
      city: map['city'] as String?,
      state: (map['state'] as String?) ?? 'Maharashtra',
      stateCode: (map['state_code'] as String?) ?? '27',
      pincode: map['pincode'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      pan: map['pan'] as String?,
      tan: map['tan'] as String?,
      gstin: map['gstin'] as String?,
      gstRegistered: (map['gst_registered'] as int? ?? 0) == 1,
      gstEffectiveFrom: map['gst_effective_from'] as String?,
      booksStartDate: map['books_start_date'] as String,
      logoPath: map['logo_path'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: (map['created_at'] as String?) ?? '',
      updatedAt: (map['updated_at'] as String?) ?? '',
    );
  }
}

class SocietySummary {
  final int id;
  final String name;
  final String? city;
  final bool isActive;
  final int? activeFyId;
  final String? activeFyCode;

  const SocietySummary({
    required this.id,
    required this.name,
    this.city,
    required this.isActive,
    this.activeFyId,
    this.activeFyCode,
  });

  factory SocietySummary.fromMap(Map<String, Object?> map) {
    return SocietySummary(
      id: map['id'] as int,
      name: map['name'] as String,
      city: map['city'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      activeFyId: map['active_fy_id'] as int?,
      activeFyCode: map['active_fy_code'] as String?,
    );
  }
}

class FinancialYear {
  final int id;
  final int societyId;
  final String code;
  final String startDate;
  final String endDate;
  final String status;
  final int? closingEntryId;
  final String? closedAt;

  const FinancialYear({
    required this.id,
    required this.societyId,
    required this.code,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.closingEntryId,
    this.closedAt,
  });

  bool get isOpen => status == 'open';

  factory FinancialYear.fromMap(Map<String, Object?> map) {
    return FinancialYear(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      code: map['code'] as String,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String,
      status: (map['status'] as String?) ?? 'open',
      closingEntryId: map['closing_entry_id'] as int?,
      closedAt: map['closed_at'] as String?,
    );
  }
}

class NumberSeries {
  final int id;
  final int societyId;
  final int fyId;
  final String docType;
  final String prefix;
  final int nextNo;
  final int pad;

  const NumberSeries({
    required this.id,
    required this.societyId,
    required this.fyId,
    required this.docType,
    required this.prefix,
    required this.nextNo,
    required this.pad,
  });

  factory NumberSeries.fromMap(Map<String, Object?> map) {
    return NumberSeries(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fyId: map['fy_id'] as int,
      docType: map['doc_type'] as String,
      prefix: map['prefix'] as String,
      nextNo: map['next_no'] as int,
      pad: map['pad'] as int,
    );
  }
}

class AuditLogEntry {
  final int id;
  final int? societyId;
  final String action;
  final String entityType;
  final int? entityId;
  final String summary;
  final String createdAt;

  const AuditLogEntry({
    required this.id,
    this.societyId,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.summary,
    required this.createdAt,
  });

  factory AuditLogEntry.fromMap(Map<String, Object?> map) {
    return AuditLogEntry(
      id: map['id'] as int,
      societyId: map['society_id'] as int?,
      action: map['action'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int?,
      summary: map['summary'] as String,
      createdAt: (map['created_at'] as String?) ?? '',
    );
  }
}
