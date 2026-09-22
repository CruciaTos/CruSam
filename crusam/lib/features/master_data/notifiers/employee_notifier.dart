import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import 'package:crusam_core/crusam_core.dart';

class EmployeeNotifier extends ChangeNotifier {
  // ----- singleton pattern -----
  EmployeeNotifier._();                                 // private constructor
  static final EmployeeNotifier instance = EmployeeNotifier._();
  // -----------------------------

  List<EmployeeModel> employees = [];
  List<EmployeeModel> filtered  = [];
  bool isLoading = false;
  String? error;

  String _query = '';

  /// [silent] skips the loading state (background refresh after an
  /// external change) and keeps the current search applied.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      error = null;
      notifyListeners();
    }
    try {
      final maps = await DatabaseHelper.instance.getAllEmployees();
      employees = maps.map(EmployeeModel.fromMap).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (silent) {
        _applySearch();
      } else {
        _query = '';
        filtered = List.of(employees);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void search(String q) {
    _query = q;
    _applySearch();
    notifyListeners();
  }

  void _applySearch() {
    final q = _query;
    if (q.trim().isEmpty) {
      filtered = List.of(employees);
    } else {
      final lower = q.toLowerCase();
      filtered = employees.where((e) =>
        e.name.toLowerCase().contains(lower) ||
        e.pfNo.toLowerCase().contains(lower)).toList();
    }
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteEmployee(id);
    await load();
  }

  Future<int> importEmployees(List<EmployeeModel> incoming) async {
    if (incoming.isEmpty) return 0;

    final existingMaps = await DatabaseHelper.instance.getAllEmployees();
    final existingKeys = existingMaps
        .map(EmployeeModel.fromMap)
        .map(_dedupeKey)
        .toSet();

    final incomingKeys = <String>{};
    final toInsert = <EmployeeModel>[];

    for (final employee in incoming) {
      final key = _dedupeKey(employee);
      if (existingKeys.contains(key) || incomingKeys.contains(key)) continue;
      incomingKeys.add(key);
      toInsert.add(employee);
    }

    if (toInsert.isNotEmpty) {
      await DatabaseHelper.instance.insertEmployeesBulk(toInsert);
    }

    await load();
    return toInsert.length;
  }

  String _dedupeKey(EmployeeModel employee) {
    final pfNo = employee.pfNo.trim().toLowerCase();
    if (pfNo.isNotEmpty && pfNo != '-') return 'pf:$pfNo';

    final uanNo = employee.uanNo.trim().toLowerCase();
    if (uanNo.isNotEmpty && uanNo != '-') return 'uan:$uanNo';

    final name = employee.name.trim().toLowerCase();
    final account = employee.accountNumber.trim().toLowerCase();
    return 'na:$name|$account';
  }
}