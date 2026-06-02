// lib/core/sync/sync_models.dart

import 'dart:convert';

bool _parseBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true' || value == '1';
  return false;
}

// ── SyncEmployee ──────────────────────────────────────────────────────────────
// Full employee record as stored in Drive: employees/{cloud_id}.json

class SyncEmployee {
  final String cloudId;
  final String name;
  final String mobile;
  final double charge;
  final String createdAt;
  final String updatedAt;
  final bool isDeleted;
  final String? deletedAt;

  // Full employee fields
  final int srNo;
  final String pfNo;
  final String uanNo;
  final String code;
  final String ifscCode;
  final String accountNumber;
  final String aartiAcNo;
  final String sbCode;
  final String bankDetails;
  final String branch;
  final String zone;
  final String dateOfJoining;
  final double basicCharges;
  final double otherCharges;
  final String gender;

  const SyncEmployee({
    required this.cloudId,
    required this.name,
    this.mobile = '',
    this.charge = 0,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.srNo = 0,
    this.pfNo = '',
    this.uanNo = '',
    this.code = '',
    this.ifscCode = '',
    this.accountNumber = '',
    this.aartiAcNo = '',
    this.sbCode = '10',
    this.bankDetails = '',
    this.branch = '',
    this.zone = '',
    this.dateOfJoining = '',
    this.basicCharges = 0,
    this.otherCharges = 0,
    this.gender = 'M',
  });

  Map<String, dynamic> toJson() => {
        'cloud_id': cloudId,
        'name': name,
        'mobile': mobile,
        'charge': charge,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'deleted_at': deletedAt,
        'sr_no': srNo,
        'pf_no': pfNo,
        'uan_no': uanNo,
        'code': code,
        'ifsc_code': ifscCode,
        'account_number': accountNumber,
        'aarti_ac_no': aartiAcNo,
        'sb_code': sbCode,
        'bank_details': bankDetails,
        'branch': branch,
        'zone': zone,
        'date_of_joining': dateOfJoining,
        'basic_charges': basicCharges,
        'other_charges': otherCharges,
        'gender': gender,
      };

  factory SyncEmployee.fromJson(Map<String, dynamic> json) => SyncEmployee(
        cloudId: (json['cloud_id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        mobile: (json['mobile'] as String?) ?? '',
        charge: (json['charge'] as num?)?.toDouble() ?? 0,
        createdAt: (json['created_at'] as String?) ?? '',
        updatedAt: (json['updated_at'] as String?) ?? '',
        isDeleted: _parseBool(json['is_deleted']),
        deletedAt: json['deleted_at'] as String?,
        srNo: (json['sr_no'] as num?)?.toInt() ?? 0,
        pfNo: (json['pf_no'] as String?) ?? '',
        uanNo: (json['uan_no'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
        ifscCode: (json['ifsc_code'] as String?) ?? '',
        accountNumber: (json['account_number'] as String?) ?? '',
        aartiAcNo: (json['aarti_ac_no'] as String?) ?? '',
        sbCode: (json['sb_code'] as String?) ?? '10',
        bankDetails: (json['bank_details'] as String?) ?? '',
        branch: (json['branch'] as String?) ?? '',
        zone: (json['zone'] as String?) ?? '',
        dateOfJoining: (json['date_of_joining'] as String?) ?? '',
        basicCharges: (json['basic_charges'] as num?)?.toDouble() ?? 0,
        otherCharges: (json['other_charges'] as num?)?.toDouble() ?? 0,
        gender: (json['gender'] as String?) ?? 'M',
      );

  /// Build from a raw SQLite row (includes sync columns).
  factory SyncEmployee.fromDbMap(Map<String, dynamic> m) => SyncEmployee(
        cloudId: (m['cloud_id'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        mobile: '',
        charge: (m['basic_charges'] as num?)?.toDouble() ?? 0,
        createdAt: (m['created_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: (m['updated_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        isDeleted: ((m['is_deleted'] as num?)?.toInt() ?? 0) == 1,
        deletedAt: m['deleted_at'] as String?,
        srNo: (m['sr_no'] as num?)?.toInt() ?? 0,
        pfNo: (m['pf_no'] as String?) ?? '',
        uanNo: (m['uan_no'] as String?) ?? '',
        code: (m['code'] as String?) ?? '',
        ifscCode: (m['ifsc_code'] as String?) ?? '',
        accountNumber: (m['account_number'] as String?) ?? '',
        aartiAcNo: (m['aarti_ac_no'] as String?) ?? '',
        sbCode: (m['sb_code'] as String?) ?? '10',
        bankDetails: (m['bank_details'] as String?) ?? '',
        branch: (m['branch'] as String?) ?? '',
        zone: (m['zone'] as String?) ?? '',
        dateOfJoining: (m['date_of_joining'] as String?) ?? '',
        basicCharges: (m['basic_charges'] as num?)?.toDouble() ?? 0,
        otherCharges: (m['other_charges'] as num?)?.toDouble() ?? 0,
        gender: (m['gender'] as String?) ?? 'M',
      );
}

// ── SyncIndexEntry ────────────────────────────────────────────────────────────
// One line in employees/index.json → entries[]

class SyncIndexEntry {
  final String cloudId;
  final String updatedAt;
  final bool isDeleted;

  const SyncIndexEntry({
    required this.cloudId,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() => {
        'cloud_id': cloudId,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
      };

  factory SyncIndexEntry.fromJson(Map<String, dynamic> json) => SyncIndexEntry(
        cloudId: (json['cloud_id'] as String?) ?? '',
        updatedAt: (json['updated_at'] as String?) ?? '',
        isDeleted: _parseBool(json['is_deleted']),
      );
}

// ── SyncIndex ─────────────────────────────────────────────────────────────────
// Root of employees/index.json

class SyncIndex {
  final String updatedAt;
  final List<SyncIndexEntry> entries;

  const SyncIndex({required this.updatedAt, required this.entries});

  Map<String, dynamic> toJson() => {
        'updated_at': updatedAt,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory SyncIndex.fromJson(Map<String, dynamic> json) => SyncIndex(
        updatedAt: (json['updated_at'] as String?) ?? '',
        entries: ((json['entries'] as List<dynamic>?) ?? [])
            .map((e) => SyncIndexEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── SyncPendingEntry ──────────────────────────────────────────────────────────
// Row in the local sync_pending SQLite table

class SyncPendingEntry {
  final int? id;
  final String entityType; // 'employee'
  final String cloudId;
  final String operation; // 'create' | 'update' | 'delete'
  final Map<String, dynamic> payload; // full JSON of the entity
  final String localUpdatedAt;
  final String? createdAt;

  const SyncPendingEntry({
    this.id,
    required this.entityType,
    required this.cloudId,
    required this.operation,
    required this.payload,
    required this.localUpdatedAt,
    this.createdAt,
  });

  factory SyncPendingEntry.fromDbMap(Map<String, dynamic> m) =>
      SyncPendingEntry(
        id: m['id'] as int?,
        entityType: (m['entity_type'] as String?) ?? '',
        cloudId: (m['cloud_id'] as String?) ?? '',
        operation: (m['operation'] as String?) ?? '',
        payload: jsonDecode((m['payload'] as String?) ?? '{}')
            as Map<String, dynamic>,
        localUpdatedAt: (m['local_updated_at'] as String?) ?? '',
        createdAt: m['created_at'] as String?,
      );
}