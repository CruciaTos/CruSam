class Block {
  final int id;
  final int societyId;
  final String name;
  final bool isActive;

  const Block({
    required this.id,
    required this.societyId,
    required this.name,
    this.isActive = true,
  });

  factory Block.fromMap(Map<String, Object?> map) {
    return Block(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      name: map['name'] as String,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class BlockDraft {
  final String name;
  final bool isActive;

  const BlockDraft({
    required this.name,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'name': name.trim(),
      'is_active': isActive ? 1 : 0,
    };
  }
}

class UnitType {
  final int id;
  final int societyId;
  final String name;
  final int sortOrder;
  final bool isActive;

  const UnitType({
    required this.id,
    required this.societyId,
    required this.name,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory UnitType.fromMap(Map<String, Object?> map) {
    return UnitType(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      name: map['name'] as String,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as int) == 1,
    );
  }
}

class UnitTypeDraft {
  final String name;
  final int sortOrder;
  final bool isActive;

  const UnitTypeDraft({
    required this.name,
    this.sortOrder = 0,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'name': name.trim(),
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class UnitRow {
  final int id;
  final int societyId;
  final int blockId;
  final String blockName;
  final String unitNo;
  final int unitTypeId;
  final String unitTypeName;
  final int area1Centi;
  final int area2Centi;
  final String? floorNo;
  final String occupancy;
  final String? notes;
  final bool isActive;
  final String? primaryContactName;
  final String? primaryContactPhone;
  final String? billToName;

  const UnitRow({
    required this.id,
    required this.societyId,
    required this.blockId,
    required this.blockName,
    required this.unitNo,
    required this.unitTypeId,
    required this.unitTypeName,
    this.area1Centi = 0,
    this.area2Centi = 0,
    this.floorNo,
    required this.occupancy,
    this.notes,
    this.isActive = true,
    this.primaryContactName,
    this.primaryContactPhone,
    this.billToName,
  });

  factory UnitRow.fromMap(Map<String, Object?> map) {
    return UnitRow(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      blockId: map['block_id'] as int,
      blockName: (map['block_name'] as String?) ?? '',
      unitNo: map['unit_no'] as String,
      unitTypeId: map['unit_type_id'] as int,
      unitTypeName: (map['unit_type_name'] as String?) ?? '',
      area1Centi: (map['area1_centi'] as int?) ?? 0,
      area2Centi: (map['area2_centi'] as int?) ?? 0,
      floorNo: map['floor_no'] as String?,
      occupancy: (map['occupancy'] as String?) ?? 'owner_occupied',
      notes: map['notes'] as String?,
      isActive: (map['is_active'] as int) == 1,
      primaryContactName: map['primary_contact_name'] as String?,
      primaryContactPhone: map['primary_contact_phone'] as String?,
      billToName: map['bill_to_name'] as String?,
    );
  }
}

class UnitDraft {
  final int blockId;
  final String unitNo;
  final int unitTypeId;
  final int area1Centi;
  final int area2Centi;
  final String? floorNo;
  final String occupancy;
  final String? notes;
  final bool isActive;

  const UnitDraft({
    required this.blockId,
    required this.unitNo,
    required this.unitTypeId,
    this.area1Centi = 0,
    this.area2Centi = 0,
    this.floorNo,
    this.occupancy = 'owner_occupied',
    this.notes,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'block_id': blockId,
      'unit_no': unitNo.trim(),
      'unit_type_id': unitTypeId,
      'area1_centi': area1Centi,
      'area2_centi': area2Centi,
      'floor_no': floorNo?.trim(),
      'occupancy': occupancy,
      'notes': notes?.trim(),
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class Person {
  final int id;
  final int societyId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? alternateEmail;
  final String? pan;
  final String? gstin;
  final String? address;
  final bool isActive;
  final List<String> assignedUnits;

  const Person({
    required this.id,
    required this.societyId,
    required this.fullName,
    this.phone,
    this.email,
    this.alternateEmail,
    this.pan,
    this.gstin,
    this.address,
    this.isActive = true,
    this.assignedUnits = const [],
  });

  factory Person.fromMap(Map<String, Object?> map, [List<String> units = const []]) {
    return Person(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      fullName: map['full_name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      alternateEmail: map['alternate_email'] as String?,
      pan: map['pan'] as String?,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      isActive: (map['is_active'] as int) == 1,
      assignedUnits: units,
    );
  }
}

class PersonDraft {
  final String fullName;
  final String? phone;
  final String? email;
  final String? alternateEmail;
  final String? pan;
  final String? gstin;
  final String? address;
  final bool isActive;

  const PersonDraft({
    required this.fullName,
    this.phone,
    this.email,
    this.alternateEmail,
    this.pan,
    this.gstin,
    this.address,
    this.isActive = true,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'full_name': fullName.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'alternate_email': alternateEmail?.trim(),
      'pan': pan?.trim(),
      'gstin': gstin?.trim(),
      'address': address?.trim(),
      'is_active': isActive ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

class UnitPerson {
  final int id;
  final int societyId;
  final int unitId;
  final int personId;
  final String personFullName;
  final String? personPhone;
  final String? personEmail;
  final String role; // 'owner', 'co_owner', 'tenant', 'nominee'
  final bool isPrimaryContact;
  final bool isBillTo;
  final String? shareCertificateNo;
  final String fromDate;
  final String? toDate;

  const UnitPerson({
    required this.id,
    required this.societyId,
    required this.unitId,
    required this.personId,
    required this.personFullName,
    this.personPhone,
    this.personEmail,
    required this.role,
    this.isPrimaryContact = false,
    this.isBillTo = false,
    this.shareCertificateNo,
    required this.fromDate,
    this.toDate,
  });

  bool get isCurrent => toDate == null;

  factory UnitPerson.fromMap(Map<String, Object?> map) {
    return UnitPerson(
      id: map['id'] as int,
      societyId: map['society_id'] as int,
      unitId: map['unit_id'] as int,
      personId: map['person_id'] as int,
      personFullName: (map['full_name'] as String?) ?? '',
      personPhone: map['phone'] as String?,
      personEmail: map['email'] as String?,
      role: map['role'] as String,
      isPrimaryContact: (map['is_primary_contact'] as int) == 1,
      isBillTo: (map['is_bill_to'] as int) == 1,
      shareCertificateNo: map['share_certificate_no'] as String?,
      fromDate: map['from_date'] as String,
      toDate: map['to_date'] as String?,
    );
  }
}

class UnitPersonDraft {
  final int unitId;
  final int personId;
  final String role;
  final bool isPrimaryContact;
  final bool isBillTo;
  final String? shareCertificateNo;
  final String fromDate;
  final String? toDate;

  const UnitPersonDraft({
    required this.unitId,
    required this.personId,
    required this.role,
    this.isPrimaryContact = false,
    this.isBillTo = false,
    this.shareCertificateNo,
    required this.fromDate,
    this.toDate,
  });

  Map<String, Object?> toMap(int societyId) {
    return {
      'society_id': societyId,
      'unit_id': unitId,
      'person_id': personId,
      'role': role,
      'is_primary_contact': isPrimaryContact ? 1 : 0,
      'is_bill_to': isBillTo ? 1 : 0,
      'share_certificate_no': shareCertificateNo?.trim(),
      'from_date': fromDate,
      'to_date': toDate,
    };
  }
}

class OwnershipTransferDraft {
  final int unitId;
  final int newOwnerPersonId;
  final String transferDate;
  final String? shareCertificateNo;
  final bool setAsPrimaryContact;
  final bool setAsBillTo;

  const OwnershipTransferDraft({
    required this.unitId,
    required this.newOwnerPersonId,
    required this.transferDate,
    this.shareCertificateNo,
    this.setAsPrimaryContact = true,
    this.setAsBillTo = true,
  });
}

class UnitOpeningBalanceDraft {
  final int unitId;
  final int debitPaise;
  final int creditPaise;
  final String asOfDate;
  final String? narration;

  const UnitOpeningBalanceDraft({
    required this.unitId,
    this.debitPaise = 0,
    this.creditPaise = 0,
    required this.asOfDate,
    this.narration,
  });
}
