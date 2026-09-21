// Static facade over SalaryMath used by the salary documents. The config
// comes from [configProvider]: the app points it at SalaryFormulaNotifier
// (the Salary Formula settings screen); the MCP server sets it from the
// database before generating documents.

import '../models/salary_formula_config_model.dart';
import 'salary_math.dart';

class SalaryFormulaEngine {
  SalaryFormulaEngine._();

  static SalaryFormulaConfigModel Function() configProvider =
      () => const SalaryFormulaConfigModel();

  static SalaryFormulaConfigModel get config => configProvider();

  static SalaryMath get _math => SalaryMath(configProvider());

  static double pf(double earnedBasic) => _math.pf(earnedBasic);

  static bool esicApplicable(double fullGrossSalary) =>
      _math.esicApplicable(fullGrossSalary);

  static double esic({
    required double fullGrossSalary,
    required double earnedGross,
  }) =>
      _math.esic(fullGrossSalary: fullGrossSalary, earnedGross: earnedGross);

  static double pt({
    required double earnedGross,
    required bool isFemale,
    required bool isFeb,
  }) =>
      _math.pt(earnedGross: earnedGross, isFemale: isFemale, isFeb: isFeb);

  static double employerPf(double totalEarnedBasic) =>
      _math.employerPf(totalEarnedBasic);

  static double employerEsic(double totalEarnedEsicEligibleGross) =>
      _math.employerEsic(totalEarnedEsicEligibleGross);

  static double attachmentBTotal(int employeeCount) =>
      _math.attachmentBTotal(employeeCount);
}
