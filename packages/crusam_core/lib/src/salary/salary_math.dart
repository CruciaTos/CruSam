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

  /// Whether the employee is ESIC-eligible at all. Under the Code on Social
  /// Security wage definition the ESIC wage ceiling (cfg.esicGrossThreshold,
  /// Rs 21,000) is tested against the employee's full (non-prorated) monthly
  /// BASIC salary, not their gross. (The config field keeps its historical
  /// "gross" name so stored settings and the MCP tools keep working.)
  bool esicApplicable(double fullBasicSalary) =>
      fullBasicSalary <= cfg.esicGrossThreshold;

  /// Employee ESIC deduction. Eligibility is based on [fullBasicSalary];
  /// the amount is cfg.esicRate of the earned/prorated basic ([earnedBasic]).
  double esic({required double fullBasicSalary, required double earnedBasic}) {
    if (!esicApplicable(fullBasicSalary)) return 0;
    if (earnedBasic <= 0) return 0;
    return (earnedBasic * cfg.esicRate).ceilToDouble();
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
  /// total earned basic of ESIC-eligible employees.
  double employerEsic(double totalEarnedEsicEligibleBasic) =>
      (totalEarnedEsicEligibleBasic * cfg.employerEsicRate).roundToDouble();

  /// Attachment B — fixed per-employee welfare contribution.
  double attachmentBTotal(int employeeCount) =>
      employeeCount * cfg.attachmentBPerEmployee;
}
