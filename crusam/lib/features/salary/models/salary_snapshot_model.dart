// crusam/lib/features/salary/models/salary_snapshot_model.dart
import 'dart:convert';

/// Per-employee flattened salary data captured inside a snapshot payload.
class SalarySnapshotEmployeeData {
  final int employeeId;
  final String employeeName;
  final String code;
  final String pfNo;
  final int days;
  final double basicCharges;
  final double otherCharges;
  final double grossSalary;
  final double earnedBasic;
  final double earnedOther;
  final double earnedGross;
  final int pf;
  final int esic;
  final int msw;
  final int pt;
  final int totalDeduction;
  final double bonus;
  final double netSalary;

  const SalarySnapshotEmployeeData({
    required this.employeeId,
    required this.employeeName,
    this.code = '',
    this.pfNo = '',
    required this.days,
    required this.basicCharges,
    required this.otherCharges,
    required this.grossSalary,
    required this.earnedBasic,
    required this.earnedOther,
    required this.earnedGross,
    required this.pf,
    required this.esic,
    required this.msw,
    required this.pt,
    required this.totalDeduction,
    this.bonus = 0,
    required this.netSalary,
  });

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'employeeName': employeeName,
    'code': code,
    'pfNo': pfNo,
    'days': days,
    'basicCharges': basicCharges,
    'otherCharges': otherCharges,
    'grossSalary': grossSalary,
    'earnedBasic': earnedBasic,
    'earnedOther': earnedOther,
    'earnedGross': earnedGross,
    'pf': pf,
    'esic': esic,
    'msw': msw,
    'pt': pt,
    'totalDeduction': totalDeduction,
    'bonus': bonus,
    'netSalary': netSalary,
  };

  factory SalarySnapshotEmployeeData.fromJson(Map<String, dynamic> m) =>
      SalarySnapshotEmployeeData(
        employeeId: (m['employeeId'] as num?)?.toInt() ?? 0,
        employeeName: (m['employeeName'] as String?) ?? '',
        code: (m['code'] as String?) ?? '',
        pfNo: (m['pfNo'] as String?) ?? '',
        days: (m['days'] as num?)?.toInt() ?? 0,
        basicCharges: (m['basicCharges'] as num?)?.toDouble() ?? 0.0,
        otherCharges: (m['otherCharges'] as num?)?.toDouble() ?? 0.0,
        grossSalary: (m['grossSalary'] as num?)?.toDouble() ?? 0.0,
        earnedBasic: (m['earnedBasic'] as num?)?.toDouble() ?? 0.0,
        earnedOther: (m['earnedOther'] as num?)?.toDouble() ?? 0.0,
        earnedGross: (m['earnedGross'] as num?)?.toDouble() ?? 0.0,
        pf: (m['pf'] as num?)?.toInt() ?? 0,
        esic: (m['esic'] as num?)?.toInt() ?? 0,
        msw: (m['msw'] as num?)?.toInt() ?? 0,
        pt: (m['pt'] as num?)?.toInt() ?? 0,
        totalDeduction: (m['totalDeduction'] as num?)?.toInt() ?? 0,
        bonus: (m['bonus'] as num?)?.toDouble() ?? 0.0,
        netSalary: (m['netSalary'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Full serialized salary-month state. This is what gets stored (as JSON)
/// inside `salary_month_snapshots.payload`.
class SalarySnapshotPayload {
  static const int currentVersion = 2;

  final int version;
  final int month;
  final int year;
  final String dateIso;
  final String poNo;
  final String billNo;
  final String clientName;
  final String clientAddr;
  final String clientGstin;
  final String deptCode;
  final String selectedCompanyCode;
  final String itemDescription;
  final List<SalarySnapshotEmployeeData> employees;

  const SalarySnapshotPayload({
    this.version = currentVersion,
    required this.month,
    required this.year,
    required this.dateIso,
    required this.poNo,
    required this.billNo,
    required this.clientName,
    required this.clientAddr,
    required this.clientGstin,
    required this.deptCode,
    required this.selectedCompanyCode,
    this.itemDescription = 'Manpower Supply Charges',
    required this.employees,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'month': month,
    'year': year,
    'dateIso': dateIso,
    'poNo': poNo,
    'billNo': billNo,
    'clientName': clientName,
    'clientAddr': clientAddr,
    'clientGstin': clientGstin,
    'deptCode': deptCode,
    'selectedCompanyCode': selectedCompanyCode,
    'itemDescription': itemDescription,
    'employees': employees.map((e) => e.toJson()).toList(),
  };

  /// Versioning hook: branch on `rawVersion` here if a future payload shape
  /// needs different field handling before falling through to this logic.
  factory SalarySnapshotPayload.fromJson(Map<String, dynamic> m) {
    final rawVersion = (m['version'] as num?)?.toInt() ?? 1;
    final empList = (m['employees'] as List?) ?? const [];
    return SalarySnapshotPayload(
      version: rawVersion,
      month: (m['month'] as num?)?.toInt() ?? 1,
      year: (m['year'] as num?)?.toInt() ?? DateTime.now().year,
      dateIso: (m['dateIso'] as String?) ?? '',
      poNo: (m['poNo'] as String?) ?? '-',
      billNo: (m['billNo'] as String?) ?? '',
      clientName: (m['clientName'] as String?) ?? '',
      clientAddr: (m['clientAddr'] as String?) ?? '',
      clientGstin: (m['clientGstin'] as String?) ?? '',
      deptCode: (m['deptCode'] as String?) ?? '',
      selectedCompanyCode: (m['selectedCompanyCode'] as String?) ?? 'All',
      itemDescription:
          (m['itemDescription'] as String?) ?? 'Manpower Supply Charges',
      employees:
          empList
              .whereType<Map>()
              .map(
                (e) => SalarySnapshotEmployeeData.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList(),
    );
  }

  String encode() => jsonEncode(toJson());
  static SalarySnapshotPayload decode(String raw) =>
      SalarySnapshotPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Row model for `salary_month_snapshots`.
class SalaryMonthSnapshotModel {
  final int? id;
  final String snapshotKey;
  final String snapshotName;
  final int month;
  final int year;
  final String payload;
  final String createdAt;
  final String updatedAt;

  const SalaryMonthSnapshotModel({
    this.id,
    required this.snapshotKey,
    required this.snapshotName,
    required this.month,
    required this.year,
    required this.payload,
    this.createdAt = '',
    this.updatedAt = '',
  });

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  String get monthName => _monthNames[(month - 1).clamp(0, 11)];

  SalaryMonthSnapshotModel copyWith({
    int? id,
    String? snapshotKey,
    String? snapshotName,
    int? month,
    int? year,
    String? payload,
    String? createdAt,
    String? updatedAt,
  }) => SalaryMonthSnapshotModel(
    id: id ?? this.id,
    snapshotKey: snapshotKey ?? this.snapshotKey,
    snapshotName: snapshotName ?? this.snapshotName,
    month: month ?? this.month,
    year: year ?? this.year,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toDbMap() => {
    if (id != null) 'id': id,
    'snapshot_key': snapshotKey,
    'snapshot_name': snapshotName,
    'month': month,
    'year': year,
    'payload': payload,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory SalaryMonthSnapshotModel.fromDbMap(Map<String, dynamic> m) =>
      SalaryMonthSnapshotModel(
        id: m['id'] as int?,
        snapshotKey: (m['snapshot_key'] as String?) ?? '',
        snapshotName: (m['snapshot_name'] as String?) ?? '',
        month: (m['month'] as int?) ?? 1,
        year: (m['year'] as int?) ?? DateTime.now().year,
        payload: (m['payload'] as String?) ?? '{}',
        createdAt: (m['created_at'] as String?) ?? '',
        updatedAt: (m['updated_at'] as String?) ?? '',
      );
}

/// Row model for `salary_month_employees` (flattened employee history —
/// used for search / reporting / analytics, not for state restoration).
class SalarySnapshotEmployeeRecord {
  final int? id;
  final int snapshotId;
  final int employeeId;
  final String employeeName;
  final String code;
  final String pfNo;
  final int month;
  final int year;
  final int attendance;
  final double grossSalary;
  final double deductions;
  final double bonus;
  final double netSalary;
  final String createdAt;

  const SalarySnapshotEmployeeRecord({
    this.id,
    required this.snapshotId,
    required this.employeeId,
    required this.employeeName,
    this.code = '',
    this.pfNo = '',
    required this.month,
    required this.year,
    required this.attendance,
    required this.grossSalary,
    required this.deductions,
    this.bonus = 0,
    required this.netSalary,
    this.createdAt = '',
  });

  Map<String, dynamic> toDbMap() => {
    if (id != null) 'id': id,
    'snapshot_id': snapshotId,
    'employee_id': employeeId,
    'employee_name': employeeName,
    'code': code,
    'pf_no': pfNo,
    'month': month,
    'year': year,
    'attendance': attendance,
    'gross_salary': grossSalary,
    'deductions': deductions,
    'bonus': bonus,
    'net_salary': netSalary,
    'created_at': createdAt,
  };

  factory SalarySnapshotEmployeeRecord.fromDbMap(Map<String, dynamic> m) =>
      SalarySnapshotEmployeeRecord(
        id: m['id'] as int?,
        snapshotId: (m['snapshot_id'] as int?) ?? 0,
        employeeId: (m['employee_id'] as int?) ?? 0,
        employeeName: (m['employee_name'] as String?) ?? '',
        code: (m['code'] as String?) ?? '',
        pfNo: (m['pf_no'] as String?) ?? '',
        month: (m['month'] as int?) ?? 1,
        year: (m['year'] as int?) ?? DateTime.now().year,
        attendance: (m['attendance'] as int?) ?? 0,
        grossSalary: ((m['gross_salary'] as num?)?.toDouble()) ?? 0.0,
        deductions: ((m['deductions'] as num?)?.toDouble()) ?? 0.0,
        bonus: ((m['bonus'] as num?)?.toDouble()) ?? 0.0,
        netSalary: ((m['net_salary'] as num?)?.toDouble()) ?? 0.0,
        createdAt: (m['created_at'] as String?) ?? '',
      );
}