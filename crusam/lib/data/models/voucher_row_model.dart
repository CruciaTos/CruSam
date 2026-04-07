class VoucherRowModel {
  final String id;
  final int?   dbId;
  final String employeeId;
  final String employeeName;
  final double amount;
  final String fromDate;
  final String toDate;
  final String ifscCode;
  final String accountNumber;
  final String sbCode;
  final String bankDetails;
  final String branch;
  final String deptCode;
  final String debitAccountNumber;
  final String debitAccountName;

  const VoucherRowModel({
    required this.id,
    this.dbId,
    this.employeeId        = '',
    this.employeeName      = '',
    this.amount            = 0,
    this.fromDate          = '',
    this.toDate            = '',
    this.ifscCode          = '',
    this.accountNumber     = '',
    this.sbCode            = '10',
    this.bankDetails       = '',
    this.branch            = '',
    this.deptCode          = '',
    this.debitAccountNumber= '',
    this.debitAccountName  = '',
  });

  VoucherRowModel copyWith({
    String? employeeId, String? employeeName, double? amount,
    String? fromDate, String? toDate, String? ifscCode, String? accountNumber,
    String? sbCode, String? bankDetails, String? branch, String? deptCode,
    String? debitAccountNumber, String? debitAccountName,
  }) => VoucherRowModel(
    id: id, dbId: dbId,
    employeeId:         employeeId         ?? this.employeeId,
    employeeName:       employeeName       ?? this.employeeName,
    amount:             amount             ?? this.amount,
    fromDate:           fromDate           ?? this.fromDate,
    toDate:             toDate             ?? this.toDate,
    ifscCode:           ifscCode           ?? this.ifscCode,
    accountNumber:      accountNumber      ?? this.accountNumber,
    sbCode:             sbCode             ?? this.sbCode,
    bankDetails:        bankDetails        ?? this.bankDetails,
    branch:             branch             ?? this.branch,
    deptCode:           deptCode           ?? this.deptCode,
    debitAccountNumber: debitAccountNumber ?? this.debitAccountNumber,
    debitAccountName:   debitAccountName   ?? this.debitAccountName,
  );

  Map<String, dynamic> toDbMap(int voucherId) => {
    'voucher_id':        voucherId,
    'employee_name':     employeeName,
    'amount':            amount,
    'from_date':         fromDate,
    'to_date':           toDate,
    'ifsc_code':         ifscCode,
    'credit_account':    accountNumber,
    'sb_code':           sbCode,
    'bank_detail':       bankDetails,
    'place':             branch,
    'dept_code':         deptCode,
    'debit_account':     debitAccountNumber,
    'debit_account_name':debitAccountName,
  };

  factory VoucherRowModel.fromDbMap(Map<String, dynamic> m) => VoucherRowModel(
    id:                 (m['id'] as int).toString(),
    dbId:               m['id'] as int?,
    employeeName:       (m['employee_name']      as String?) ?? '',
    amount:             (m['amount'] as num?)?.toDouble()   ?? 0,
    fromDate:           (m['from_date']           as String?) ?? '',
    toDate:             (m['to_date']             as String?) ?? '',
    ifscCode:           (m['ifsc_code']           as String?) ?? '',
    accountNumber:      (m['credit_account']      as String?) ?? '',
    sbCode:             (m['sb_code']             as String?) ?? '',
    bankDetails:        (m['bank_detail']         as String?) ?? '',
    branch:             (m['place']               as String?) ?? '',
    deptCode:           (m['dept_code']           as String?) ?? '',
    debitAccountNumber: (m['debit_account']       as String?) ?? '',
    debitAccountName:   (m['debit_account_name']  as String?) ?? '',
  );
}