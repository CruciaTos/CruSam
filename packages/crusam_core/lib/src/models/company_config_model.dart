class CompanyConfigModel {
  final int?   id;
  final String companyName;
  final String address;
  final String gstin;
  final String pan;
  final String jurisdiction;
  final String declarationText;
  final String bankName;
  final String branch;
  final String accountNo;
  final String ifscCode;
  final String phone;

  const CompanyConfigModel({
    this.id,
    this.companyName    = 'AARTI ENTERPRISES',
    this.address        = 'Dahisar Preeti Co-op Hsg. Soc., Shop No. 5, Opp. Janseva Bank, Maratha Colony, W. S. Road, Dahisar (E), Mumbai - 400 068.',
    this.gstin          = '27AAQFA5248L2ZW',
    this.pan            = 'AAQFA5248L',
    this.jurisdiction   = 'Mumbai',
    this.declarationText= 'Certified that particulars given above are true and correct.',
    this.bankName       = 'IDBI Bank Ltd.',
    this.branch         = 'Dahisar - East',
    this.accountNo      = '0680651100000338',
    this.ifscCode       = 'IBKL0000680',
    this.phone          = '28282906',
  });

  CompanyConfigModel copyWith({
    String? companyName, String? address, String? gstin, String? pan,
    String? jurisdiction, String? declarationText, String? bankName,
    String? branch, String? accountNo, String? ifscCode, String? phone,
  }) => CompanyConfigModel(
    id: id,
    companyName:     companyName     ?? this.companyName,
    address:         address         ?? this.address,
    gstin:           gstin           ?? this.gstin,
    pan:             pan             ?? this.pan,
    jurisdiction:    jurisdiction    ?? this.jurisdiction,
    declarationText: declarationText ?? this.declarationText,
    bankName:        bankName        ?? this.bankName,
    branch:          branch          ?? this.branch,
    accountNo:       accountNo       ?? this.accountNo,
    ifscCode:        ifscCode        ?? this.ifscCode,
    phone:           phone           ?? this.phone,
  );

  factory CompanyConfigModel.fromMap(Map<String, dynamic> m) => CompanyConfigModel(
    id:              m['id']              as int?,
    companyName:    (m['company_name']    as String?) ?? 'AARTI ENTERPRISES',
    address:        (m['address']         as String?) ?? '',
    gstin:          (m['gstin']           as String?) ?? '',
    pan:            (m['pan']             as String?) ?? '',
    jurisdiction:   (m['jurisdiction']    as String?) ?? 'Mumbai',
    declarationText:(m['declaration_text']as String?) ?? '',
    bankName:       (m['bank_name']       as String?) ?? '',
    branch:         (m['branch']          as String?) ?? '',
    accountNo:      (m['account_no']      as String?) ?? '',
    ifscCode:       (m['ifsc_code']       as String?) ?? '',
    phone:          (m['phone']           as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'company_name':     companyName,
    'address':          address,
    'gstin':            gstin,
    'pan':              pan,
    'jurisdiction':     jurisdiction,
    'declaration_text': declarationText,
    'bank_name':        bankName,
    'branch':           branch,
    'account_no':       accountNo,
    'ifsc_code':        ifscCode,
    'phone':            phone,
  };
}