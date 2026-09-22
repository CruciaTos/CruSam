// PF / ESIC / Professional Tax / employer-contribution math, parameterised by
// a SalaryFormulaConfigModel. The app's SalaryFormulaEngine delegates here
// with the live config from SalaryFormulaNotifier.

import '../models/salary_formula_config_model.dart';

class SalaryMath {
  final SalaryFormulaConfigModel cfg;
  const SalaryMath(this.cfg);

  /// Employee PF deduction: cfg.pfRate of earned basic, capped at
  /// cfg.pfCapAmount once earned basic reaches cfg.pfBasicThreshold.
  double pf(double earnedBasic) {
    if (earnedBasic <= 0) return 0;
    return earnedBasic >= cfg.pfBasicThreshold
        ? cfg.pfCapAmount
        : (earnedBasic * cfg.pfRate).roundToDouble();
  }

  /// Whether the employee is ESIC-eligible at all, based on their full
  /// (non-prorated) monthly gross salary.
  bool esicApplicable(double fullGrossSalary) =>
      fullGrossSalary <= cfg.esicGrossThreshold;

  /// Employee ESIC deduction. Eligibility is based on [fullGrossSalary];
  /// the amount is cfg.esicRate of the earned/prorated gross ([earnedGross]).
  double esic({required double fullGrossSalary, required double earnedGross}) {
    if (!esicApplicable(fullGrossSalary)) return 0;
    if (earnedGross <= 0) return 0;
    return (earnedGross * cfg.esicRate).ceilToDouble();
  }

  /// Professional Tax — gender- and month-dependent slabs, applied to the
  /// employee's earned/prorated gross.
  double pt({
    required double earnedGross,
    required bool isFemale,
    required bool isFeb,
  }) {
    if (earnedGross <= 0) return 0;
    final standard = isFeb ? cfg.ptFebAmount : cfg.ptStandardAmount;
    if (isFemale) {
      return earnedGross < cfg.ptFemaleThreshold ? 0 : standard;
    }
    if (earnedGross < cfg.ptMaleTier1Threshold) return 0;
    if (earnedGross < cfg.ptMaleTier2Threshold) return cfg.ptMaleTier2Amount;
    return standard;
  }

  /// Employer PF contribution (Attachment A) — cfg.employerPfRate of total
  /// earned basic across the filtered employee set.
  double employerPf(double totalEarnedBasic) =>
      (totalEarnedBasic * cfg.employerPfRate).roundToDouble();

  /// Employer ESIC contribution (Attachment A) — cfg.employerEsicRate of
  /// total earned gross of ESIC-eligible employees.
  double employerEsic(double totalEarnedEsicEligibleGross) =>
      (totalEarnedEsicEligibleGross * cfg.employerEsicRate).roundToDouble();

  /// Attachment B — fixed per-employee welfare contribution.
  double attachmentBTotal(int employeeCount) =>
      employeeCount * cfg.attachmentBPerEmployee;
}
