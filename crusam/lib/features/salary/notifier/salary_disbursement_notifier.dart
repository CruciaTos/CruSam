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
  SalaryDisbursementNotifier._() {
    // Whenever the active salary period changes elsewhere (e.g. a Saved
    // Salary gets loaded from the Employee Salary screen), refresh the
    // candidate/preview data so this screen never shows figures for the
    // wrong month. Entering attendance for the *current* month also notifies
    // SalaryDataNotifier, but month/year won't have changed then, so this
    // stays a no-op in that case — no extra reload churn.
    SalaryDataNotifier.instance.addListener(_onActivePeriodChanged);
  }
  static final SalaryDisbursementNotifier instance =
      SalaryDisbursementNotifier._();

  // ── State ──────────────────────────────────────────────────────────────────
  List<EmployeeModel> _employees = [];
  List<SalaryDisbursementItemModel> _candidates = [];
  Set<int> _selected = {};
  Set<int> _disbursedIds = {};
  CompanyConfigModel _config = const CompanyConfigModel();
  List<SalaryDisbursementModel> _history = [];

  bool _loading = false;
  bool _generating = false;
  String _error = '';

  bool _hasLoadedOnce = false;
  int? _trackedMonth;
  int? _trackedYear;

  void _onActivePeriodChanged() {
    if (!_hasLoadedOnce) return;
    final n = SalaryDataNotifier.instance;
    if (_trackedMonth == n.month && _trackedYear == n.year) return;
    load(forceReload: true);
  }

  // ── Accessors ──────────────────────────────────────────────────────────────
  List<EmployeeModel> get employees => _employees;
  List<SalaryDisbursementItemModel> get candidates => _candidates;
  Set<int> get selected => _selected;
  Set<int> get disbursedIds => _disbursedIds;
  CompanyConfigModel get config => _config;
  List<SalaryDisbursementModel> get history => _history;

  bool get isLoading => _loading;
  bool get isGenerating => _generating;
  String get error => _error;

  double get selectedTotal => _candidates
      .where((c) => _selected.contains(c.employeeId))
      .fold(0.0, (s, c) => s + c.amount);

  int get selectedCount => _selected.length;

  bool isEmployeeSelected(int employeeId) => _selected.contains(employeeId);

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> load({bool forceReload = false}) async {
    if (_loading && !forceReload) return;
    _loading = true;
    _error = '';
    notifyListeners();

    try {
      final n = SalaryDataNotifier.instance;
      _trackedMonth = n.month;
      _trackedYear = n.year;
      _hasLoadedOnce = true;

      // Load employees
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      _employees =
          empMaps
              .map(EmployeeModel.fromMap)
              .where((e) => e.name.trim().isNotEmpty)
              .toList();

      // Load config
      final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
      if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);

      // Load already-disbursed IDs (used only for history, not to restrict candidates)
      _disbursedIds = await DatabaseHelper.instance.getDisbursedEmployeeIds(
        month: n.month,
        year: n.year,
      );

      // Build ALL candidates – no filtering, no status marking
      _candidates = await SalaryDisbursementService.buildCandidateItems(
        employees: _employees,
        salaryData: n,
        alreadyDisbursedIds: {}, // show everyone
      );

      // Load disbursement history
      _history = await DatabaseHelper.instance.getAllSalaryDisbursements();

      // Reset selection to only existing candidates
      _selected =
          _selected
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
    // No longer blocked by exported status – all employees can be toggled.
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

  // ── Generate + Export (one step) ──────────────────────────────────────────
  //
  // Persists the disbursement, exports Excel, and simply clears the selection.
  // Candidates remain fully interactive – you can select and generate again.

  Future<String?> generateDisbursement({required String deptCode}) async {
    if (_selected.isEmpty) return null;
    _generating = true;
    _error = '';
    notifyListeners();

    try {
      final n = SalaryDataNotifier.instance;
      final selectedItems =
          _candidates.where((c) => _selected.contains(c.employeeId)).toList();

      // 1. Persist the batch
      final disbursement = await SalaryDisbursementService.createDisbursement(
        month: n.month,
        year: n.year,
        deptCode: deptCode,
        items: selectedItems,
      );

      // 2. Fetch persisted items
      final persistedItems = await DatabaseHelper.instance.getDisbursementItems(
        disbursement.id!,
      );

      // 3. Generate Excel
      final path = await SalaryDisbursementService.generateExcel(
        disbursement: disbursement,
        items: persistedItems,
        config: _config,
        monthName: n.monthName,
      );

      // 4. Mark as exported
      if (path != null) {
        final updated = disbursement.copyWith(
          status: SalaryDisbursementStatus.exported,
          exportedAt: DateTime.now().toIso8601String(),
        );
        await DatabaseHelper.instance.updateSalaryDisbursement(updated);
      }

      // 5. Refresh disbursed IDs and history (no candidate status change)
      _disbursedIds = await DatabaseHelper.instance.getDisbursedEmployeeIds(
        month: n.month,
        year: n.year,
      );
      _history = await DatabaseHelper.instance.getAllSalaryDisbursements();

      // Clear the selection so the Generate button resets
      _selected = {};

      return path;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  // ── Re-export an existing batch (uses its own month name) ────────────────

  Future<String?> exportDisbursementExcel(
    SalaryDisbursementModel disbursement,
  ) async {
    final items = await DatabaseHelper.instance.getDisbursementItems(
      disbursement.id!,
    );

    // Derive the month name from the batch, NOT from current SalaryDataNotifier
    final monthName = _monthName(disbursement.month);

    final path = await SalaryDisbursementService.generateExcel(
      disbursement: disbursement,
      items: items,
      config: _config,
      monthName: monthName,
    );

    if (path != null) {
      final updated = disbursement.copyWith(
        status: SalaryDisbursementStatus.exported,
        exportedAt: DateTime.now().toIso8601String(),
      );
      await DatabaseHelper.instance.updateSalaryDisbursement(updated);
      // Refresh history
      _history = await DatabaseHelper.instance.getAllSalaryDisbursements();
      notifyListeners();
    }

    return path;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> deleteDisbursement(int id) async {
    await DatabaseHelper.instance.deleteSalaryDisbursement(id);
    await load(forceReload: true);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}
