import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import 'package:crusam_core/crusam_core.dart';

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
