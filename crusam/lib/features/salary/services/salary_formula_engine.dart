// lib/features/salary/services/salary_formula_engine.dart
//
// Single source of truth for the PF / ESIC / Professional Tax / employer-
// contribution math that used to be copy-pasted (with the same magic
// numbers) across salary_disbursement_service.dart,
// salary_statement_pdf_service.dart, salary_statement_excel_export_service.dart,
// Salary_pdf_export_service.dart, salary_snapshot_notifier.dart,
// salary_state_controller.dart, salary_entry_table.dart,
// salary_slip_preview.dart, salary_statement_preview.dart, and
// salary_statement_screen.dart.
//
// Every method here is a pure re-statement of the formula that already
// existed in those files — only the constants now come from
// SalaryFormulaNotifier.instance.config instead of being inlined, so
// editing them on the Salary Formula settings screen changes every
// consumer at once.
import '../../../data/models/salary_formula_config_model.dart';
import '../notifier/salary_formula_notifier.dart';

class SalaryFormulaEngine {
  SalaryFormulaEngine._();

  static SalaryFormulaConfigModel get _cfg =>
      SalaryFormulaNotifier.instance.config;

  /// Employee PF deduction: cfg.pfRate of earned basic, capped at
  /// cfg.pfCapAmount once earned basic reaches cfg.pfBasicThreshold.
  static double pf(double earnedBasic) {
    if (earnedBasic <= 0) return 0;
    final cfg = _cfg;
    return earnedBasic >= cfg.pfBasicThreshold
        ? cfg.pfCapAmount
        : (earnedBasic * cfg.pfRate).roundToDouble();
  }

  /// Whether the employee is ESIC-eligible at all, based on their full
  /// (non-prorated) monthly gross salary.
  static bool esicApplicable(double fullGrossSalary) =>
      fullGrossSalary <= _cfg.esicGrossThreshold;

  /// Employee ESIC deduction. Eligibility is based on [fullGrossSalary];
  /// the amount is cfg.esicRate of the earned/prorated gross ([earnedGross]).
  static double esic({
    required double fullGrossSalary,
    required double earnedGross,
  }) {
    if (!esicApplicable(fullGrossSalary)) return 0;
    if (earnedGross <= 0) return 0;
    return (earnedGross * _cfg.esicRate).ceilToDouble();
  }

  /// Professional Tax — gender- and month-dependent slabs, applied to the
  /// employee's earned/prorated gross.
  static double pt({
    required double earnedGross,
    required bool isFemale,
    required bool isFeb,
  }) {
    if (earnedGross <= 0) return 0;
    final cfg = _cfg;
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
  static double employerPf(double totalEarnedBasic) =>
      (totalEarnedBasic * _cfg.employerPfRate).roundToDouble();

  /// Employer ESIC contribution (Attachment A) — cfg.employerEsicRate of
  /// total earned gross of ESIC-eligible employees.
  static double employerEsic(double totalEarnedEsicEligibleGross) =>
      (totalEarnedEsicEligibleGross * _cfg.employerEsicRate).roundToDouble();

  /// Attachment B — fixed per-employee welfare contribution.
  static double attachmentBTotal(int employeeCount) =>
      employeeCount * _cfg.attachmentBPerEmployee;
}
