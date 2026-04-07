import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';

class DashboardNotifier extends ChangeNotifier {
  List<EmployeeModel> employees = [];
  List<VoucherModel>  vouchers  = [];
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      employees = empMaps.map(EmployeeModel.fromMap).toList();

      final vMaps = await DatabaseHelper.instance.getAllVouchers();
      final loaded = <VoucherModel>[];
      for (final v in vMaps) {
        final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
        loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
      }
      vouchers = loaded;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}