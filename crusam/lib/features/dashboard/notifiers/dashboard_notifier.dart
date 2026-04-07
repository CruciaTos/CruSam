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
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> load() async {
    if (_isDisposed) return;

    isLoading = true;
    error = null;
    _safeNotifyListeners();
    try {
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      if (_isDisposed) return;
      employees = empMaps.map(EmployeeModel.fromMap).toList();

      final vMaps = await DatabaseHelper.instance.getAllVouchers();
      if (_isDisposed) return;
      final loaded = <VoucherModel>[];
      for (final v in vMaps) {
        final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
        if (_isDisposed) return;
        loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
      }
      vouchers = loaded;
    } catch (e) {
      if (_isDisposed) return;
      error = e.toString();
    } finally {
      if (!_isDisposed) {
        isLoading = false;
        _safeNotifyListeners();
      }
    }
  }
}