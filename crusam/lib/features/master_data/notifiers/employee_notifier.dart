import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';

class EmployeeNotifier extends ChangeNotifier {
  List<EmployeeModel> employees = [];
  List<EmployeeModel> filtered  = [];
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final maps = await DatabaseHelper.instance.getAllEmployees();
      employees = filtered = maps.map(EmployeeModel.fromMap).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void search(String q) {
    if (q.trim().isEmpty) {
      filtered = employees;
    } else {
      final lower = q.toLowerCase();
      filtered = employees.where((e) =>
        e.name.toLowerCase().contains(lower) ||
        e.pfNo.toLowerCase().contains(lower)).toList();
    }
    notifyListeners();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteEmployee(id);
    await load();
  }
}