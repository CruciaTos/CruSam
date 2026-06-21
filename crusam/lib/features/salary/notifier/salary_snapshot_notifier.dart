// crusam/lib/features/salary/notifier/salary_snapshot_notifier.dart
import 'package:flutter/material.dart';

import 'package:crusam/data/db/salary_snapshot_repository.dart';
import '../models/salary_snapshot_model.dart';
import 'salary_data_notifier.dart';
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
  Future<void> loadSnapshotList() async {
    _loading = true;
    _error = '';
    notifyListeners();
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
    final isMsw = n.isMsw;
    final isFeb = n.isFeb;
    final totalDays = n.totalDays;

    final employeeData = <SalarySnapshotEmployeeData>[];
    for (final e in sc.employees) {
      final id = e.id;
      if (id == null) continue;

      final days = n.getDays(id);
      final earnedBasic =
          totalDays == 0 ? 0.0 : e.basicCharges * days / totalDays;
      final earnedOther =
          totalDays == 0 ? 0.0 : e.otherCharges * days / totalDays;
      final earnedGross = earnedBasic + earnedOther;

      final pf = earnedBasic >= 15000 ? 1800 : (earnedBasic * 0.12).round();
      final esic = e.grossSalary <= 21000 ? (earnedGross * 0.0075).ceil() : 0;
      final msw = isMsw ? 6 : 0;

      final isFemale = e.gender.toUpperCase() == 'F';
      int pt;
      if (isFemale) {
        pt = earnedGross < 25000 ? 0 : (isFeb ? 300 : 200);
      } else if (earnedGross < 7500) {
        pt = 0;
      } else if (earnedGross < 10000) {
        pt = 175;
      } else {
        pt = isFeb ? 300 : 200;
      }

      final totalDeduction = pf + esic + msw + pt;
      final netSalary = earnedGross - totalDeduction;

      employeeData.add(
        SalarySnapshotEmployeeData(
          employeeId: id,
          employeeName: e.name,
          code: e.code,
          pfNo: e.pfNo,
          days: days,
          basicCharges: e.basicCharges,
          otherCharges: e.otherCharges,
          grossSalary: e.grossSalary,
          earnedBasic: earnedBasic,
          earnedOther: earnedOther,
          earnedGross: earnedGross,
          pf: pf,
          esic: esic,
          msw: msw,
          pt: pt,
          totalDeduction: totalDeduction,
          netSalary: netSalary,
        ),
      );
    }

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
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
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
