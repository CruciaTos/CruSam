// lib/features/salary/models/salary_disbursement_model.dart

enum SalaryDisbursementStatus {
  pending,
  generated,
  exported,
  disbursed;

  static SalaryDisbursementStatus fromString(String s) =>
      SalaryDisbursementStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => SalaryDisbursementStatus.pending,
      );

  String get label => switch (this) {
        pending   => 'Pending',
        generated => 'Generated',
        exported  => 'Exported',
        disbursed => 'Disbursed',
      };
}

// ── Disbursement batch ────────────────────────────────────────────────────────

class SalaryDisbursementModel {
  final int?    id;
  final String  referenceNo;
  final int     month;
  final int     year;
  final String  deptCode;
  final SalaryDisbursementStatus status;
  final String? generatedAt;
  final String? exportedAt;
  final String? disbursedAt;
  final String  createdAt;
  final String  updatedAt;

  const SalaryDisbursementModel({
    this.id,
    required this.referenceNo,
    required this.month,
    required this.year,
    this.deptCode = 'All',
    this.status   = SalaryDisbursementStatus.pending,
    this.generatedAt,
    this.exportedAt,
    this.disbursedAt,
    this.createdAt = '',
    this.updatedAt = '',
  });

  SalaryDisbursementModel copyWith({
    int?    id,
    String? referenceNo,
    int?    month,
    int?    year,
    String? deptCode,
    SalaryDisbursementStatus? status,
    String? generatedAt,
    String? exportedAt,
    String? disbursedAt,
    String? createdAt,
    String? updatedAt,
  }) => SalaryDisbursementModel(
        id:          id          ?? this.id,
        referenceNo: referenceNo ?? this.referenceNo,
        month:       month       ?? this.month,
        year:        year        ?? this.year,
        deptCode:    deptCode    ?? this.deptCode,
        status:      status      ?? this.status,
        generatedAt: generatedAt ?? this.generatedAt,
        exportedAt:  exportedAt  ?? this.exportedAt,
        disbursedAt: disbursedAt ?? this.disbursedAt,
        createdAt:   createdAt   ?? this.createdAt,
        updatedAt:   updatedAt   ?? this.updatedAt,
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'reference_no': referenceNo,
        'month':        month,
        'year':         year,
        'dept_code':    deptCode,
        'status':       status.name,
        'generated_at': generatedAt,
        'exported_at':  exportedAt,
        'disbursed_at': disbursedAt,
        'created_at':   createdAt,
        'updated_at':   updatedAt,
      };

  factory SalaryDisbursementModel.fromDbMap(Map<String, dynamic> m) =>
      SalaryDisbursementModel(
        id:          m['id'] as int?,
        referenceNo: (m['reference_no'] as String?) ?? '',
        month:       (m['month'] as int?) ?? 1,
        year:        (m['year']  as int?) ?? DateTime.now().year,
        deptCode:    (m['dept_code'] as String?) ?? 'All',
        status:      SalaryDisbursementStatus.fromString(
                         (m['status'] as String?) ?? 'pending'),
        generatedAt: m['generated_at'] as String?,
        exportedAt:  m['exported_at']  as String?,
        disbursedAt: m['disbursed_at'] as String?,
        createdAt:   (m['created_at'] as String?) ?? '',
        updatedAt:   (m['updated_at'] as String?) ?? '',
      );
}

// ── Disbursement item (one per employee) ──────────────────────────────────────

class SalaryDisbursementItemModel {
  final int?   id;
  final int    disbursementId;
  final int    employeeId;
  final String employeeName;
  final String bankName;
  final String accountNumber;
  final String ifscCode;
  final double amount;
  final int?   salaryStatementId;
  final SalaryDisbursementStatus status;
  final String createdAt;

  const SalaryDisbursementItemModel({
    this.id,
    required this.disbursementId,
    required this.employeeId,
    required this.employeeName,
    required this.bankName,
    required this.accountNumber,
    required this.ifscCode,
    required this.amount,
    this.salaryStatementId,
    this.status    = SalaryDisbursementStatus.pending,
    this.createdAt = '',
  });

  SalaryDisbursementItemModel copyWith({
    int?    id,
    int?    disbursementId,
    int?    employeeId,
    String? employeeName,
    String? bankName,
    String? accountNumber,
    String? ifscCode,
    double? amount,
    int?    salaryStatementId,
    SalaryDisbursementStatus? status,
    String? createdAt,
  }) => SalaryDisbursementItemModel(
        id:                  id                  ?? this.id,
        disbursementId:      disbursementId      ?? this.disbursementId,
        employeeId:          employeeId          ?? this.employeeId,
        employeeName:        employeeName        ?? this.employeeName,
        bankName:            bankName            ?? this.bankName,
        accountNumber:       accountNumber       ?? this.accountNumber,
        ifscCode:            ifscCode            ?? this.ifscCode,
        amount:              amount              ?? this.amount,
        salaryStatementId:   salaryStatementId   ?? this.salaryStatementId,
        status:              status              ?? this.status,
        createdAt:           createdAt           ?? this.createdAt,
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'disbursement_id':     disbursementId,
        'employee_id':         employeeId,
        'employee_name':       employeeName,
        'bank_name':           bankName,
        'account_number':      accountNumber,
        'ifsc_code':           ifscCode,
        'amount':              amount,
        'salary_statement_id': salaryStatementId,
        'status':              status.name,
        'created_at':          createdAt,
      };

  factory SalaryDisbursementItemModel.fromDbMap(Map<String, dynamic> m) =>
      SalaryDisbursementItemModel(
        id:                  m['id'] as int?,
        disbursementId:      (m['disbursement_id']  as int?) ?? 0,
        employeeId:          (m['employee_id']       as int?) ?? 0,
        employeeName:        (m['employee_name']     as String?) ?? '',
        bankName:            (m['bank_name']         as String?) ?? '',
        accountNumber:       (m['account_number']    as String?) ?? '',
        ifscCode:            (m['ifsc_code']         as String?) ?? '',
        amount:              ((m['amount']           as num?)?.toDouble()) ?? 0.0,
        salaryStatementId:   m['salary_statement_id'] as int?,
        status:              SalaryDisbursementStatus.fromString(
                                 (m['status'] as String?) ?? 'pending'),
        createdAt:           (m['created_at'] as String?) ?? '',
      );
}