// lib/features/salary/notifier/salary_disbursement_notifier.dart

import 'package:flutter/foundation.dart';

import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/company_config_model.dart';
import '../models/salary_disbursement_model.dart';
import 'package:crusam/data/db/salary_disbursement_repository.dart';
import '../notifier/salary_data_notifier.dart';
import '../services/salary_disbursement_service.dart';

class SalaryDisbursementNotifier extends ChangeNotifier {
  SalaryDisbursementNotifier._();
  static final SalaryDisbursementNotifier instance =
      SalaryDisbursementNotifier._();

  // ── State ──────────────────────────────────────────────────────────────────
  List<EmployeeModel>                  _employees    = [];
  List<SalaryDisbursementItemModel>    _candidates   = [];
  Set<int>                             _selected     = {};
  Set<int>                             _disbursedIds = {};
  CompanyConfigModel                   _config       = const CompanyConfigModel();
  List<SalaryDisbursementModel>        _history      = [];

  bool _loading      = false;
  bool _generating   = false;
  String _error      = '';

  // ── Accessors ──────────────────────────────────────────────────────────────
  List<EmployeeModel>               get employees    => _employees;
  List<SalaryDisbursementItemModel> get candidates   => _candidates;
  Set<int>                          get selected     => _selected;
  Set<int>                          get disbursedIds => _disbursedIds;
  CompanyConfigModel                get config       => _config;
  List<SalaryDisbursementModel>     get history      => _history;

  bool   get isLoading    => _loading;
  bool   get isGenerating => _generating;
  String get error        => _error;

  double get selectedTotal =>
      _candidates
          .where((c) => _selected.contains(c.employeeId))
          .fold(0.0, (s, c) => s + c.amount);

  int get selectedCount => _selected.length;

  bool isEmployeeSelected(int employeeId) => _selected.contains(employeeId);

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> load({bool forceReload = false}) async {
    if (_loading && !forceReload) return;
    _loading = true;
    _error   = '';
    notifyListeners();

    try {
      final n = SalaryDataNotifier.instance;

      // Load employees
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      _employees = empMaps
          .map(EmployeeModel.fromMap)
          .where((e) => e.name.trim().isNotEmpty)
          .toList();

      // Load config
      final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
      if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);

      // Load already-disbursed IDs for this month/year
      _disbursedIds = await DatabaseHelper.instance
          .getDisbursedEmployeeIds(month: n.month, year: n.year);

      // Build candidate items from current salary data
      _candidates = await SalaryDisbursementService.buildCandidateItems(
        employees:          _employees,
        salaryData:         n,
        alreadyDisbursedIds: _disbursedIds,
      );

      // Load disbursement history
      _history = await DatabaseHelper.instance.getAllSalaryDisbursements();

      // Reset selection to only valid candidates
      _selected = _selected
          .where((id) => _candidates.any((c) => c.employeeId == id))
          .toSet();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void toggleEmployee(int employeeId) {
    if (_selected.contains(employeeId)) {
      _selected = {..._selected}..remove(employeeId);
    } else {
      _selected = {..._selected, employeeId};
    }
    notifyListeners();
  }

  void selectAll() {
    _selected = _candidates.map((c) => c.employeeId).toSet();
    notifyListeners();
  }

  void deselectAll() {
    _selected = {};
    notifyListeners();
  }

  bool get allSelected =>
      _candidates.isNotEmpty &&
      _candidates.every((c) => _selected.contains(c.employeeId));

  // ── Generate + Export ──────────────────────────────────────────────────────

  Future<SalaryDisbursementModel?> generateDisbursement({
    required String referenceNo,
    required String deptCode,
  }) async {
    if (_selected.isEmpty) return null;
    _generating = true;
    _error      = '';
    notifyListeners();

    try {
      final n = SalaryDataNotifier.instance;
      final selectedItems = _candidates
          .where((c) => _selected.contains(c.employeeId))
          .toList();

      final disbursement = await SalaryDisbursementService.createDisbursement(
        referenceNo: referenceNo,
        month:       n.month,
        year:        n.year,
        deptCode:    deptCode,
        items:       selectedItems,
      );

      // Refresh history + candidates
      await load(forceReload: true);
      return disbursement;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  Future<String?> exportDisbursementExcel(
    SalaryDisbursementModel disbursement,
  ) async {
    final items = await DatabaseHelper.instance
        .getDisbursementItems(disbursement.id!);

    final n = SalaryDataNotifier.instance;
    final path = await SalaryDisbursementService.generateExcel(
      disbursement: disbursement,
      items:        items,
      config:       _config,
      monthName:    n.monthName,
    );

    if (path != null) {
      // Update status to exported
      final updated = disbursement.copyWith(
        status:     SalaryDisbursementStatus.exported,
        exportedAt: DateTime.now().toIso8601String(),
      );
      await DatabaseHelper.instance.updateSalaryDisbursement(updated);
      await load(forceReload: true);
    }

    return path;
  }

  Future<void> markDisbursed(SalaryDisbursementModel disbursement) async {
    final updated = disbursement.copyWith(
      status:      SalaryDisbursementStatus.disbursed,
      disbursedAt: DateTime.now().toIso8601String(),
    );
    await DatabaseHelper.instance.updateSalaryDisbursement(updated);
    await load(forceReload: true);
  }

  Future<void> deleteDisbursement(int id) async {
    await DatabaseHelper.instance.deleteSalaryDisbursement(id);
    await load(forceReload: true);
  }
}