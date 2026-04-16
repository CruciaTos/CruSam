class SalaryEntry {
  final int srNo;
  final String technicianName;
  final String pfNo;
  final String uanNo;
  final String code;
  final String ifscCode;
  final String accountNumber;
  final double basic;
  final double other;
  final double arrears;
  final double grossSalary;
  final double pf;
  final double msw;
  final double esic;
  final double pTax;
  final double totalDeduction;
  final double netSalary;

  const SalaryEntry({
    required this.srNo,
    required this.technicianName,
    required this.pfNo,
    required this.uanNo,
    required this.code,
    required this.ifscCode,
    required this.accountNumber,
    required this.basic,
    required this.other,
    required this.arrears,
    required this.grossSalary,
    required this.pf,
    required this.msw,
    required this.esic,
    required this.pTax,
    required this.totalDeduction,
    required this.netSalary,
  });
}