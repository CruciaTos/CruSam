import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import 'package:crusam/data/models/bank_column_widths_model.dart';

class BankColumnWidthsNotifier extends ChangeNotifier {
  BankColumnWidthsSettings _settings = const BankColumnWidthsSettings();

  BankColumnWidthsSettings get settings => _settings;

  Future<void> load() async {
    _settings = await DatabaseHelper.instance.getBankColumnWidths();
    notifyListeners();
  }

  Future<void> update(BankColumnWidthsSettings settings) async {
    _settings = settings;
    await DatabaseHelper.instance.saveBankColumnWidths(settings);
    notifyListeners();
  }
}