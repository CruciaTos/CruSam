import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';

class SettingsNotifier extends ChangeNotifier {
  CompanyConfigModel config = const CompanyConfigModel();
  bool isLoading = false;
  bool isSaving  = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    final map = await DatabaseHelper.instance.getCompanyConfig();
    config = map != null ? CompanyConfigModel.fromMap(map) : const CompanyConfigModel();
    isLoading = false;
    notifyListeners();
  }

  void update(CompanyConfigModel Function(CompanyConfigModel) fn) {
    config = fn(config);
    notifyListeners();
  }

  Future<bool> save() async {
    isSaving = true;
    notifyListeners();
    try {
      await DatabaseHelper.instance.saveCompanyConfig(config.toMap());
      return true;
    } catch (_) {
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }
}