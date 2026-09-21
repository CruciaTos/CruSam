// Builds a salary month (per-employee earnings/deductions + Attachment A/B
// billing totals) from attendance. The per-employee loop is the one that
// used to live in SalarySnapshotNotifier._buildPayload; the totals mirror
// SalaryStateController's getters.

import '../models/employee_model.dart';
import '../models/salary_formula_config_model.dart';
import '../models/salary_snapshot_model.dart';
import 'salary_math.dart';

class SalaryMonthInput {
  final int month;
  final int year;
  final bool applyMsw; // only takes effect in June/December
  final double mswAmount;
  const SalaryMonthInput({
    required this.month,
    required this.year,
    this.applyMsw = true,
    this.mswAmount = 6,
  });

  int get totalDays => DateTime(year, month + 1, 0).day;
  bool get isMswEligibleMonth => month == 6 || month == 12;
  bool get isMsw => isMswEligibleMonth && applyMsw;
  bool get isFeb => month == 2;
}

class SalaryBillingTotals {
  final int activeEmployeeCount;
  final double totalEarnedBasic;
  final double totalEarnedGross;
  final double totalEarnedEsicEligibleGross;
  final double attachmentAPf;
  final double attachmentAEsic;
  final double attachmentASubtotal;
  final double attachmentATotal;
  final double attachmentARoundOff;
  final double attachmentBTotal;
  final double invoiceTotal;
  final double totalNetSalary;
  final double totalDeductions;

  const SalaryBillingTotals({
    required this.activeEmployeeCount,
    required this.totalEarnedBasic,
    required this.totalEarnedGross,
    required this.totalEarnedEsicEligibleGross,
    required this.attachmentAPf,
    required this.attachmentAEsic,
    required this.attachmentASubtotal,
    required this.attachmentATotal,
    required this.attachmentARoundOff,
    required this.attachmentBTotal,
    required this.invoiceTotal,
    required this.totalNetSalary,
    required this.totalDeductions,
  });

  Map<String, Object?> toJson() => {
        'active_employee_count': activeEmployeeCount,
        'total_earned_basic': totalEarnedBasic,
        'total_earned_gross': totalEarnedGross,
        'total_earned_esic_eligible_gross': totalEarnedEsicEligibleGross,
        'attachment_a_pf': attachmentAPf,
        'attachment_a_esic': attachmentAEsic,
        'attachment_a_subtotal': attachmentASubtotal,
        'attachment_a_total': attachmentATotal,
        'attachment_a_round_off': attachmentARoundOff,
        'attachment_b_total': attachmentBTotal,
        'invoice_total': invoiceTotal,
        'total_net_salary': totalNetSalary,
        'total_deductions': totalDeductions,
      };
}

class SalaryMonthCalculator {
  final SalaryMath math;
  SalaryMonthCalculator(SalaryFormulaConfigModel cfg) : math = SalaryMath(cfg);

  /// Earnings and deductions for one employee.
  SalarySnapshotEmployeeData employeeData(
      EmployeeModel e, int days, SalaryMonthInput input) {
    final totalDays = input.totalDays;
    final earnedBasic = totalDays == 0 ? 0.0 : e.basicCharges * days / totalDays;
    final earnedOther = totalDays == 0 ? 0.0 : e.otherCharges * days / totalDays;
    final earnedGross = earnedBasic + earnedOther;

    final pf = math.pf(earnedBasic).round();
    final esic =
        math.esic(fullGrossSalary: e.grossSalary, earnedGross: earnedGross).round();
    final msw = input.isMsw ? input.mswAmount.round() : 0;
    final pt = math
        .pt(
          earnedGross: earnedGross,
          isFemale: e.gender.toUpperCase() == 'F',
          isFeb: input.isFeb,
        )
        .round();

    final totalDeduction = pf + esic + msw + pt;
    return SalarySnapshotEmployeeData(
      employeeId: e.id ?? 0,
      employeeName: e.name,
      code: e.code,
      pfNo: e.pfNo,
      days: days,
      basicCharges: e.basicCharges,
      otherCharges: e.otherCharges,
      grossSalary: e.grossSalary,
      earnedBasic: earnedBasic,
      earnedOther: earnedOther,
      earnedGross: earnedGross,
      pf: pf,
      esic: esic,
      msw: msw,
      pt: pt,
      totalDeduction: totalDeduction,
      netSalary: earnedGross - totalDeduction,
    );
  }

  /// One entry per employee with an id (days default to 0), same as the
  /// app's saved-salary payload.
  List<SalarySnapshotEmployeeData> employeesData(
    List<EmployeeModel> employees,
    int Function(int employeeId) daysFor,
    SalaryMonthInput input,
  ) =>
      [
        for (final e in employees)
          if (e.id != null) employeeData(e, daysFor(e.id!), input),
      ];

  /// Attachment A/B billing totals for [employees] filtered by
  /// [companyCode] ('All' = everyone), as shown on the Salary Bills screen.
  SalaryBillingTotals billingTotals(
    List<EmployeeModel> employees,
    int Function(int employeeId) daysFor,
    SalaryMonthInput input, {
    String companyCode = 'All',
  }) {
    final filtered = companyCode == 'All'
        ? employees
        : employees.where((e) => e.code == companyCode).toList();
    final totalDays = input.totalDays;
    double earnedBasic = 0, earnedGross = 0, earnedEsic = 0, net = 0, ded = 0;
    var active = 0;
    for (final e in filtered) {
      final days = daysFor(e.id ?? 0);
      if (days > 0) active++;
      if (totalDays == 0) continue;
      earnedBasic += e.basicCharges * days / totalDays;
      final g = e.grossSalary * days / totalDays;
      earnedGross += g;
      if (math.esicApplicable(e.grossSalary)) earnedEsic += g;
      final d = employeeData(e, days, input);
      net += d.netSalary;
      ded += d.totalDeduction;
    }
    final aPf = math.employerPf(earnedBasic);
    final aEsic = math.employerEsic(earnedEsic);
    final aSub = earnedGross + aPf + aEsic;
    final aTotal = aSub.ceilToDouble();
    final bTotal = math.attachmentBTotal(active);
    return SalaryBillingTotals(
      activeEmployeeCount: active,
      totalEarnedBasic: earnedBasic,
      totalEarnedGross: earnedGross,
      totalEarnedEsicEligibleGross: earnedEsic,
      attachmentAPf: aPf,
      attachmentAEsic: aEsic,
      attachmentASubtotal: aSub,
      attachmentATotal: aTotal,
      attachmentARoundOff: aTotal - aSub,
      attachmentBTotal: bTotal,
      invoiceTotal: aTotal + bTotal,
      totalNetSalary: net,
      totalDeductions: ded,
    );
  }
}
