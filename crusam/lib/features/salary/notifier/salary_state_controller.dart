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

  int get employeeCount => filteredEmployees.length;

  // ── Full (non-day-prorated) totals — used for Attachment A billing ─────────
  double get totalBasicFull =>
      filteredEmployees.fold(0.0, (s, e) => s + e.basicCharges);

  double get totalGrossFull =>
      filteredEmployees.fold(0.0, (s, e) => s + e.grossSalary);

  double get totalEsicEligibleGrossFull =>
      filteredEmployees.where((e) => e.grossSalary >= 21000).fold(
        0.0, (s, e) => s + e.grossSalary);

  // ── Day-prorated totals — used for earned salary display ──────────────────
  double get totalBasic    => totalBasicFull;
  double get totalGross    => totalGrossFull;

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

  // ── Attachment A calculations (use full, non-earned values) ───────────────
  /// PF = 13.61% of Total Basic Salary (full, not earned)
  double get attachmentAPf       => totalBasicFull * 0.1361;
  /// ESIC = 3.25% of Total Gross Salary of ESIC-eligible employees (gross > 21000)
  double get attachmentAEsic     => totalEsicEligibleGrossFull * 0.0325;
  double get attachmentASubtotal => totalGrossFull + attachmentAPf + attachmentAEsic;
  double get attachmentATotal    => attachmentASubtotal.ceilToDouble();
  double get attachmentARoundOff => attachmentATotal - attachmentASubtotal;

  // ── Attachment B calculations ──────────────────────────────────────────────
  double get attachmentBTotal => employeeCount * 1753.0;

  // ── Salary Invoice total (Attachment A + Attachment B) ────────────────────
  double get invoiceTotal => attachmentATotal + attachmentBTotal;

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

  void notifyDaysChanged() {
    if (_disposed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }
}