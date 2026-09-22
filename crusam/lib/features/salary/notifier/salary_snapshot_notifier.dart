// crusam/lib/features/salary/notifier/salary_snapshot_notifier.dart
import 'package:flutter/material.dart';

import 'package:crusam/data/db/database_helper.dart';
import 'package:crusam/data/db/salary_snapshot_repository.dart';
import 'package:crusam_core/crusam_core.dart';
import 'salary_data_notifier.dart';
import 'salary_formula_notifier.dart';
import 'salary_state_controller.dart';

/// Lightweight display model pairing a saved salary period's metadata with
/// quick-glance totals (employee count + payroll amount) so the Saved Salary
/// list can render rich cards without re-decoding payloads on every build.
class SavedSalarySummary {
  final SalaryMonthSnapshotModel snapshot;
  final int employeeCount;
  final double totalPayroll;

  const SavedSalarySummary({
    required this.snapshot,
    required this.employeeCount,
    required this.totalPayroll,
  });

  String get periodLabel => '${snapshot.monthName} ${snapshot.year}';
}

class SalarySnapshotNotifier extends ChangeNotifier {
  SalarySnapshotNotifier._();
  static final SalarySnapshotNotifier instance = SalarySnapshotNotifier._();

  final SalarySnapshotRepository _repo = SalarySnapshotRepository.instance;

  List<SalaryMonthSnapshotModel> _snapshots = [];
  List<SavedSalarySummary> _summaries = [];
  bool _loading = false;
  bool _saving = false;
  String _error = '';

  /// The saved salary period currently loaded as the app's active working
  /// context (set by [loadMonth]). Stays set even if the user later edits
  /// the data — it only stops being "active" if they switch month/year away
  /// from it (see [isViewingSavedSalary]), or load a different saved salary.
  SalaryMonthSnapshotModel? _activeSnapshot;

  List<SalaryMonthSnapshotModel> get snapshots => _snapshots;
  List<SavedSalarySummary> get summaries => _summaries;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String get error => _error;

  SalaryMonthSnapshotModel? get activeSnapshot => _activeSnapshot;

  /// True when the live salary data (month/year currently active in
  /// [SalaryDataNotifier]) corresponds to a saved salary period the user
  /// explicitly loaded. Drives the "Viewing Saved Salary" indicator —
  /// manually switching the month dropdown away from that period clears
  /// this automatically, with no extra bookkeeping required.
  bool get isViewingSavedSalary {
    final snap = _activeSnapshot;
    if (snap == null) return false;
    final n = SalaryDataNotifier.instance;
    return snap.month == n.month && snap.year == n.year;
  }

  /// "June 2026"-style label for whichever saved salary is active. Empty
  /// when nothing is currently loaded.
  String get activeSavedSalaryLabel =>
      _activeSnapshot == null
          ? ''
          : '${_activeSnapshot!.monthName} ${_activeSnapshot!.year}';

  static const _monthNames = [
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

  String defaultNameFor(int month, int year) =>
      '${_monthNames[(month - 1).clamp(0, 11)]} $year';

  // ── Browse ─────────────────────────────────────────────────────────────────
  Future<void> loadSnapshotList({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = '';
      notifyListeners();
    }
    try {
      _snapshots = await _repo.getSnapshots();
      _summaries = _snapshots.map(_summarize).toList();

      // Keep the active-snapshot reference fresh (e.g. after a rename) by
      // re-pointing it at the matching entry in the refreshed list.
      final active = _activeSnapshot;
      if (active != null) {
        final refreshed = _snapshots.where((s) => s.id == active.id);
        _activeSnapshot = refreshed.isEmpty ? _activeSnapshot : refreshed.first;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Decodes a snapshot's payload just enough to surface employee count and
  /// total payroll for the list view. Falls back to zeros if a payload is
  /// malformed rather than letting one bad row break the whole list.
  SavedSalarySummary _summarize(SalaryMonthSnapshotModel m) {
    try {
      final payload = SalarySnapshotPayload.decode(m.payload);
      final total = payload.employees.fold<double>(
        0.0,
        (s, e) => s + e.netSalary,
      );
      return SavedSalarySummary(
        snapshot: m,
        employeeCount: payload.employees.length,
        totalPayroll: total,
      );
    } catch (_) {
      return SavedSalarySummary(snapshot: m, employeeCount: 0, totalPayroll: 0);
    }
  }

  // ── Build payload from current live state ──────────────────────────────────
  SalarySnapshotPayload _buildPayload() {
    final n = SalaryDataNotifier.instance;
    final sc = SalaryStateController.instance;
    // Per-employee math shared with the MCP server (crusam_core).
    final input = SalaryMonthInput(
      month: n.month,
      year: n.year,
      applyMsw: n.applyMsw,
      mswAmount: n.mswAmount,
    );
    final employeeData = SalaryMonthCalculator(
      SalaryFormulaNotifier.instance.config,
    ).employeesData(sc.employees, n.getDays, input);

    return SalarySnapshotPayload(
      month: n.month,
      year: n.year,
      dateIso: n.dateIso,
      poNo: n.poNo,
      billNo: n.billNo,
      clientName: n.clientName,
      clientAddr: n.clientAddr,
      clientGstin: n.clientGstin,
      deptCode: n.deptCode,
      selectedCompanyCode: sc.selectedCompanyCode,
      itemDescription: n.itemDescription,
      itemDescriptionAttachmentA: n.itemDescriptionAttachmentARaw,
      itemDescriptionAttachmentB: n.itemDescriptionAttachmentBRaw,
      employees: employeeData,
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<bool> saveCurrentMonth({String? name}) async {
    _saving = true;
    _error = '';
    notifyListeners();
    try {
      final sc = SalaryStateController.instance;
      if (sc.employees.isEmpty) {
        await sc.loadEmployees();
      }
      final payload = _buildPayload();
      final label =
          (name == null || name.trim().isEmpty)
              ? defaultNameFor(payload.month, payload.year)
              : name.trim();
      await _repo.saveSnapshot(snapshotName: label, payload: payload);
      await loadSnapshotList();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ── Restore payload back into live notifiers ────────────────────────────────
  void _applyPayload(SalarySnapshotPayload payload) {
    final n = SalaryDataNotifier.instance;
    final sc = SalaryStateController.instance;

    // 1. Clear existing day entries for every known employee.
    for (final e in sc.employees) {
      final id = e.id;
      if (id != null) n.setDays(id, 0);
    }

    // 2. Restore bill / client / month metadata.
    n.setMonthYear(payload.month, payload.year);
    n.setDateIso(payload.dateIso);
    n.setPoNo(payload.poNo);
    n.setBillNo(payload.billNo);
    n.setClientName(payload.clientName);
    n.setClientAddr(payload.clientAddr);
    n.setClientGstin(payload.clientGstin);
    n.setDeptCode(payload.deptCode);
    n.setItemDescription(payload.itemDescription);
    // Applied after setMonthYear so an empty override correctly recomputes
    // against the *restored* month/year rather than whatever was active
    // before the load.
    n.setItemDescriptionAttachmentA(payload.itemDescriptionAttachmentA);
    n.setItemDescriptionAttachmentB(payload.itemDescriptionAttachmentB);
    sc.setCompanyCode(payload.selectedCompanyCode);

    // 3. Restore per-employee attendance, syncing any already-cached
    //    TextEditingControllers so visible fields refresh immediately.
    for (final emp in payload.employees) {
      n.setDays(emp.employeeId, emp.days);
      final ctrl = n.getOrCreateController(emp.employeeId);
      final text = emp.days == 0 ? '' : '${emp.days}';
      if (ctrl.text != text) {
        ctrl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  //
  // Loading a saved salary makes it the app's active working context: every
  // screen bound to SalaryDataNotifier / SalaryStateController (Employee
  // Salary, Statements, Bills, Attachments, Disbursement) immediately
  // reflects the restored period because they all read from those same live
  // singletons — no parallel state system needed.
  Future<bool> loadMonth(int snapshotId) async {
    _error = '';
    notifyListeners();
    try {
      final sc = SalaryStateController.instance;
      if (sc.employees.isEmpty) {
        await sc.loadEmployees();
      }
      final payload = await _repo.loadSnapshot(snapshotId);
      if (payload == null) {
        _error = 'Saved salary not found.';
        notifyListeners();
        return false;
      }
      final meta = await _repo.getSnapshot(snapshotId);
      _applyPayload(payload);
      _activeSnapshot = meta;
      // The user chose a month themselves; nothing to go back to.
      _parked = null;
      _parkedActive = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Follow Claude: show Claude's saved month without losing yours ─────────
  //
  // Claude works on SAVED months; the salary screens show the live month.
  // To show the user what Claude is doing, the live month is parked (exactly
  // as Save would capture it, unsaved attendance included), Claude's month
  // is applied, and [restoreParkedMonth] puts the user's month back.

  SalarySnapshotPayload? _parked;
  SalaryMonthSnapshotModel? _parkedActive;
  String _claudePeriod = '';

  /// "May 2026" while Claude's month is on screen instead of the user's.
  String? get claudeMonthLabel => _parked == null ? null : _claudePeriod;

  /// Shows the saved month [month]/[year] on the salary screens. Returns
  /// false when there is no such saved month.
  Future<bool> showMonthForClaude(int month, int year) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final meta = await SalarySnapshotStore.getByPeriod(db, month, year);
      if (meta == null) return false;
      final sc = SalaryStateController.instance;
      if (sc.employees.isEmpty) await sc.loadEmployees();
      if (_parked == null) {
        _parked = _buildPayload();
        _parkedActive = _activeSnapshot;
      }
      // Re-applied every time: Claude may have just re-saved it.
      _applyPayload(SalarySnapshotPayload.decode(meta.payload));
      _activeSnapshot = meta;
      _claudePeriod = defaultNameFor(month, year);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('showMonthForClaude: $e');
      return false;
    }
  }

  /// Puts the user's own month back after [showMonthForClaude].
  void restoreParkedMonth() {
    final parked = _parked;
    if (parked == null) return;
    _applyPayload(parked);
    _activeSnapshot = _parkedActive;
    _parked = null;
    _parkedActive = null;
    notifyListeners();
  }

  // Aliases kept for naming-convention parity with the original brief.
  Future<bool> importSnapshot(int snapshotId) => loadMonth(snapshotId);
  Future<bool> exportSnapshot({String? name}) => saveCurrentMonth(name: name);

  // ── Rename ─────────────────────────────────────────────────────────────────
  Future<void> renameSnapshot(int snapshotId, String newName) async {
    if (newName.trim().isEmpty) return;
    await _repo.renameSnapshot(snapshotId, newName.trim());
    await loadSnapshotList();
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> deleteSnapshot(int snapshotId) async {
    await _repo.deleteSnapshot(snapshotId);
    if (_activeSnapshot?.id == snapshotId) {
      _activeSnapshot = null;
    }
    await loadSnapshotList();
  }
}