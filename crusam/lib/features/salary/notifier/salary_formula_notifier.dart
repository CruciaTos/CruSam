// lib/features/salary/notifier/salary_formula_notifier.dart
//
// Holds the live SalaryFormulaConfigModel used by SalaryFormulaEngine.
// Singleton (like ExportPreferencesNotifier / EmployeeNotifier) so services
// and static calculators scattered across the salary module can read
// `.instance.config` synchronously without threading it through every call.
import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/salary_formula_config_model.dart';

class SalaryFormulaNotifier extends ChangeNotifier {
  SalaryFormulaNotifier._();
  static final SalaryFormulaNotifier instance = SalaryFormulaNotifier._();

  SalaryFormulaConfigModel config = const SalaryFormulaConfigModel();
  bool isLoading = false;
  bool isSaving  = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    final map = await DatabaseHelper.instance.getSalaryFormulaConfig();
    config = map != null
        ? SalaryFormulaConfigModel.fromMap(map)
        : const SalaryFormulaConfigModel();
    isLoading = false;
    notifyListeners();
  }

  void update(SalaryFormulaConfigModel Function(SalaryFormulaConfigModel) fn) {
    config = fn(config);
    notifyListeners();
  }

  Future<bool> save() async {
    isSaving = true;
    notifyListeners();
    try {
      await DatabaseHelper.instance.saveSalaryFormulaConfig(config.toMap());
      return true;
    } catch (_) {
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}
