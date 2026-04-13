// lib/features/salary/notifier/salary_state_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/db/database_helper.dart';
import 'salary_data_notifier.dart';

class SalaryStateController extends ChangeNotifier {
  SalaryStateController._();
  static final SalaryStateController instance = SalaryStateController._();

  List<EmployeeModel> _employees = [];
  String _selectedCompanyCode = 'All';
  bool isLoading = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Safe notify: defers if called during a frame build to avoid
  /// "setState called during build" errors from TextEditingController listeners.
  void _safeNotify() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  // ── Accessors ──────────────────────────────────────────────────────────────
  List<EmployeeModel> get employees => _employees;
  String get selectedCompanyCode => _selectedCompanyCode;

  List<EmployeeModel> get filteredEmployees {
    if (_selectedCompanyCode == 'All') return _employees;
    return _employees.where((e) => e.code == _selectedCompanyCode).toList();
  }

  List<String> get companyCodes {
    final codes = _employees
        .map((e) => e.code.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return codes;
  }

  int    get employeeCount => filteredEmployees.length;
  double get totalBasic    => filteredEmployees.fold(0.0, (s, e) => s + e.basicCharges);
  double get totalGross    => filteredEmployees.fold(0.0, (s, e) => s + e.grossSalary);

  double get totalEarnedBasic {
    final n = SalaryDataNotifier.instance;
    if (n.totalDays == 0) return 0;
    return filteredEmployees.fold(0.0, (s, e) =>
        s + e.basicCharges * n.getDays(e.id ?? 0) / n.totalDays);
  }

  double get totalEarnedGross {
    final n = SalaryDataNotifier.instance;
    if (n.totalDays == 0) return 0;
    return filteredEmployees.fold(0.0, (s, e) =>
        s + e.grossSalary * n.getDays(e.id ?? 0) / n.totalDays);
  }

  /// ESIC eligible = grossSalary <= 21000
  double get totalEsicEligibleGross {
    final n = SalaryDataNotifier.instance;
    if (n.totalDays == 0) return 0;
    return filteredEmployees
        .where((e) => e.grossSalary <= 21000)
        .fold(0.0, (s, e) =>
            s + e.grossSalary * n.getDays(e.id ?? 0) / n.totalDays);
  }

  double get attachmentAPf       => totalEarnedBasic * 0.1361;
  double get attachmentAEsic     => totalEsicEligibleGross * 0.0325;
  double get attachmentASubtotal => totalEarnedGross + attachmentAPf + attachmentAEsic;
  double get attachmentATotal    => attachmentASubtotal.ceilToDouble();
  double get attachmentARoundOff => attachmentATotal - attachmentASubtotal;
  double get attachmentBTotal    => employeeCount * 1753.0;
  double get invoiceTotal        => attachmentATotal + attachmentBTotal;

  // ── Mutations ──────────────────────────────────────────────────────────────
  void setCompanyCode(String code) {
    if (_selectedCompanyCode == code) return;
    _selectedCompanyCode = code;
    _safeNotify();
  }

  void setEmployees(List<EmployeeModel> employees) {
    _employees = employees;
    if (_selectedCompanyCode != 'All' &&
        !employees.any((e) => e.code == _selectedCompanyCode)) {
      _selectedCompanyCode = 'All';
    }
    _safeNotify();
  }

  Future<void> loadEmployees() async {
    isLoading = true;
    _safeNotify();
    try {
      final maps = await DatabaseHelper.instance.getAllEmployees();
      _employees = maps
          .map(EmployeeModel.fromMap)
          .where((e) => e.name.trim().isNotEmpty)
          .toList();
      if (_selectedCompanyCode != 'All' &&
          !_employees.any((e) => e.code == _selectedCompanyCode)) {
        _selectedCompanyCode = 'All';
      }
    } finally {
      isLoading = false;
      _safeNotify();
    }
  }

  /// Always post-frame deferred — TextEditingController listeners fire
  /// synchronously during text layout which is mid-frame.
  void notifyDaysChanged() {
    if (_disposed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }
}