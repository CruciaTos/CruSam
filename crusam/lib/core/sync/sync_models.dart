// lib/core/sync/sync_models.dart

import 'dart:convert';

import '../../data/models/voucher_row_model.dart';

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

// ── SyncInvoice ───────────────────────────────────────────────────────────────
// Full invoice/voucher record as stored in Drive: invoices/{cloud_id}.json

class SyncInvoice {
  final String cloudId;
  final String title;
  final String deptCode;
  final String billNo;
  final String poNo;
  final String itemDescription;
  final String clientName;
  final String clientAddress;
  final String clientGstin;
  final double baseTotal;
  final double cgst;
  final double sgst;
  final double totalTax;
  final double rawTotal;
  final double roundOff;
  final double finalTotal;
  final String totalInWords;
  final String status;
  final String createdBy;
  final String updatedBy;
  final String createdAt;
  final String updatedAt;
  final bool isDeleted;
  final String? deletedAt;
  final List<Map<String, dynamic>> rows;

  const SyncInvoice({
    required this.cloudId,
    this.title = '',
    this.deptCode = '',
    this.billNo = '',
    this.poNo = '',
    this.itemDescription = '',
    this.clientName = '',
    this.clientAddress = '',
    this.clientGstin = '',
    this.baseTotal = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.totalTax = 0,
    this.rawTotal = 0,
    this.roundOff = 0,
    this.finalTotal = 0,
    this.totalInWords = '',
    this.status = 'saved',
    this.createdBy = '',
    this.updatedBy = '',
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.rows = const <Map<String, dynamic>>[],
  });

  Map<String, dynamic> toJson() => {
        'cloud_id': cloudId,
        'title': title,
        'description': '',
        'dept_code': deptCode,
        'bill_no': billNo,
        'po_no': poNo,
        'item_description': itemDescription,
        'client_name': clientName,
        'client_address': clientAddress,
        'client_gstin': clientGstin,
        'base_total': baseTotal,
        'cgst': cgst,
        'sgst': sgst,
        'total_tax': totalTax,
        'raw_total': rawTotal,
        'round_off': roundOff,
        'final_total': finalTotal,
        'total_in_words': totalInWords,
        'status': status,
        'created_by': createdBy,
        'updated_by': updatedBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_deleted': isDeleted,
        'deleted_at': deletedAt,
        'rows': rows,
      };

  factory SyncInvoice.fromJson(Map<String, dynamic> json) => SyncInvoice(
        cloudId: (json['cloud_id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        deptCode: (json['dept_code'] as String?) ?? '',
        billNo: (json['bill_no'] as String?) ?? '',
        poNo: (json['po_no'] as String?) ?? '',
        itemDescription: (json['item_description'] as String?) ?? '',
        clientName: (json['client_name'] as String?) ?? '',
        clientAddress: (json['client_address'] as String?) ?? '',
        clientGstin: (json['client_gstin'] as String?) ?? '',
        baseTotal: (json['base_total'] as num?)?.toDouble() ?? 0,
        cgst: (json['cgst'] as num?)?.toDouble() ?? 0,
        sgst: (json['sgst'] as num?)?.toDouble() ?? 0,
        totalTax: (json['total_tax'] as num?)?.toDouble() ?? 0,
        rawTotal: (json['raw_total'] as num?)?.toDouble() ?? 0,
        roundOff: (json['round_off'] as num?)?.toDouble() ?? 0,
        finalTotal: (json['final_total'] as num?)?.toDouble() ?? 0,
        totalInWords: (json['total_in_words'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'saved',
        createdBy: (json['created_by'] as String?) ?? '',
        updatedBy: (json['updated_by'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
        updatedAt: (json['updated_at'] as String?) ?? '',
        isDeleted: _parseBool(json['is_deleted']),
        deletedAt: json['deleted_at'] as String?,
        rows: ((json['rows'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  factory SyncInvoice.fromDbMaps(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> rowMaps,
  ) =>
      SyncInvoice(
        cloudId: (header['cloud_id'] as String?) ?? '',
        title: (header['title'] as String?) ?? '',
        deptCode: (header['dept_code'] as String?) ?? '',
        billNo: (header['bill_no'] as String?) ?? '',
        poNo: (header['po_no'] as String?) ?? '',
        itemDescription: (header['item_description'] as String?) ?? '',
        clientName: (header['client_name'] as String?) ?? '',
        clientAddress: (header['client_address'] as String?) ?? '',
        clientGstin: (header['client_gstin'] as String?) ?? '',
        baseTotal: (header['base_total'] as num?)?.toDouble() ?? 0,
        cgst: (header['cgst'] as num?)?.toDouble() ?? 0,
        sgst: (header['sgst'] as num?)?.toDouble() ?? 0,
        totalTax: (header['total_tax'] as num?)?.toDouble() ?? 0,
        rawTotal: (header['raw_total'] as num?)?.toDouble() ?? 0,
        roundOff: (header['round_off'] as num?)?.toDouble() ?? 0,
        finalTotal: (header['final_total'] as num?)?.toDouble() ?? 0,
        totalInWords: (header['total_in_words'] as String?) ?? '',
        status: (header['status'] as String?) ?? 'saved',
        createdBy: (header['created_by'] as String?) ?? '',
        updatedBy: (header['updated_by'] as String?) ?? '',
        createdAt: (header['created_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        updatedAt: (header['updated_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
        isDeleted: ((header['is_deleted'] as num?)?.toInt() ?? 0) == 1,
        deletedAt: header['deleted_at'] as String?,
        rows: rowMaps
            .map((r) => VoucherRowModel.fromDbMap(r).toJson())
            .toList(growable: false),
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
  final String entityType; // 'employee' | 'invoice'
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

// ── DriveDevice ───────────────────────────────────────────────────────────────
class DriveDevice {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;
  final int dbSchemaVersion;
  final String lastSeen;

  const DriveDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
    required this.dbSchemaVersion,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': appVersion,
        'db_schema_version': dbSchemaVersion,
        'last_seen': lastSeen,
      };

  factory DriveDevice.fromJson(Map json) => DriveDevice(
        deviceId: (json['device_id'] as String?) ?? '',
        deviceName: (json['device_name'] as String?) ?? '',
        platform: (json['platform'] as String?) ?? '',
        appVersion: (json['app_version'] as String?) ?? '',
        dbSchemaVersion: (json['db_schema_version'] as num?)?.toInt() ?? 0,
        lastSeen: (json['last_seen'] as String?) ?? '',
      );
}

// ── DriveMetadata ─────────────────────────────────────────────────────────────
class DriveMetadata {
  final int schemaVersion;
  final String updatedAt;
  final List<DriveDevice> devices;
  final Map<String, dynamic> indexHashes;
  final String settingsHash;

  const DriveMetadata({
    this.schemaVersion = 4,
    required this.updatedAt,
    this.devices = const <DriveDevice>[],
    this.indexHashes = const <String, dynamic>{},
    this.settingsHash = '',
  });

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'updated_at': updatedAt,
        'devices': devices.map((d) => d.toJson()).toList(),
        'index_hashes': indexHashes,
        'settings_hash': settingsHash,
      };

  factory DriveMetadata.fromJson(Map json) {
    final rawIndex = (json['index_hashes'] as Map?) ?? {};
    final idx = <String, dynamic>{};
    rawIndex.forEach((k, v) {
      idx[k.toString()] = v;
    });

    return DriveMetadata(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 4,
      updatedAt: (json['updated_at'] as String?) ?? '',
      devices: ((json['devices'] as List?) ?? [])
          .map((d) => DriveDevice.fromJson(d as Map))
          .toList(),
      indexHashes: idx,
      settingsHash: (json['settings_hash'] as String?) ?? '',
    );
  }

  DriveMetadata copyWith({
    int? schemaVersion,
    String? updatedAt,
    List<DriveDevice>? devices,
    Map<String, dynamic>? indexHashes,
    String? settingsHash,
  }) =>
      DriveMetadata(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        updatedAt: updatedAt ?? this.updatedAt,
        devices: devices ?? this.devices,
        indexHashes: indexHashes ?? this.indexHashes,
        settingsHash: settingsHash ?? this.settingsHash,
      );
}