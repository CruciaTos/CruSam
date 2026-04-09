import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/margin_settings_model.dart';

class MarginSettingsNotifier extends ChangeNotifier {
  MarginSettings settings = const MarginSettings();

  Future<void> load() async {
    settings = await DatabaseHelper.instance.getMarginSettings();
    notifyListeners();
  }

  Future<void> update(MarginSettings s) async {
    settings = s;
    notifyListeners();
    await DatabaseHelper.instance.saveMarginSettings(s);
  }
}
