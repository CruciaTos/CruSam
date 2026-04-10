import 'package:crusam/data/models/voucher_column_widths_model.dart';
import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';

class VoucherColumnWidthsNotifier extends ChangeNotifier {
  VoucherColumnWidthsSettings _settings = const VoucherColumnWidthsSettings();

  VoucherColumnWidthsSettings get settings => _settings;

  Future<void> load() async {
    _settings = await DatabaseHelper.instance.getVoucherColumnWidths();
    notifyListeners();
  }

  Future<void> update(VoucherColumnWidthsSettings settings) async {
    _settings = settings;
    await DatabaseHelper.instance.saveVoucherColumnWidths(settings);
    notifyListeners();
  }
}