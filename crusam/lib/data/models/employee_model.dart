class EmployeeModel {
  final int?   id;
  final int    srNo;
  final String name;
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

  const EmployeeModel({
    this.id,
    this.srNo = 0,
    required this.name,
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
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> m) => EmployeeModel(
    id:            m['id'] as int?,
    srNo:          (m['sr_no'] as int?) ?? 0,
    name:          (m['name']           as String?) ?? '',
    pfNo:          (m['pf_no']          as String?) ?? '',
    uanNo:         (m['uan_no']         as String?) ?? '',
    code:          (m['code']           as String?) ?? '',
    ifscCode:      (m['ifsc_code']      as String?) ?? '',
    accountNumber: (m['account_number'] as String?) ?? '',
    aartiAcNo:     (m['aarti_ac_no']    as String?) ?? '',
    sbCode:        (m['sb_code']        as String?) ?? '10',
    bankDetails:   (m['bank_details']   as String?) ?? '',
    branch:        (m['branch']         as String?) ?? '',
    zone:          (m['zone']           as String?) ?? '',
    dateOfJoining: (m['date_of_joining']as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sr_no':          srNo,
    'name':           name,
    'pf_no':          pfNo,
    'uan_no':         uanNo,
    'code':           code,
    'ifsc_code':      ifscCode,
    'account_number': accountNumber,
    'aarti_ac_no':    aartiAcNo,
    'sb_code':        sbCode,
    'bank_details':   bankDetails,
    'branch':         branch,
    'zone':           zone,
    'date_of_joining':dateOfJoining,
  };

  EmployeeModel copyWith({
    int? id, int? srNo, String? name, String? pfNo, String? uanNo,
    String? code, String? ifscCode, String? accountNumber, String? aartiAcNo,
    String? sbCode, String? bankDetails, String? branch, String? zone, String? dateOfJoining,
  }) => EmployeeModel(
    id: id ?? this.id, srNo: srNo ?? this.srNo, name: name ?? this.name,
    pfNo: pfNo ?? this.pfNo, uanNo: uanNo ?? this.uanNo, code: code ?? this.code,
    ifscCode: ifscCode ?? this.ifscCode, accountNumber: accountNumber ?? this.accountNumber,
    aartiAcNo: aartiAcNo ?? this.aartiAcNo, sbCode: sbCode ?? this.sbCode,
    bankDetails: bankDetails ?? this.bankDetails, branch: branch ?? this.branch,
    zone: zone ?? this.zone, dateOfJoining: dateOfJoining ?? this.dateOfJoining,
  );
}