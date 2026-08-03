import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_constants.dart';

class SalaryDataNotifier extends ChangeNotifier {
  SalaryDataNotifier._();
  static final SalaryDataNotifier instance = SalaryDataNotifier._();
  bool _disposed = false;

  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  String _dateIso = _todayIso();
  String _poNo = '-';
  String _billNo = 'AE/-/25-26';
  String _clientName = AppConstants.defaultClientName;
  String _clientAddr = AppConstants.defaultClientAddress;
  String _clientGstin = AppConstants.defaultClientGstin;
  String _deptCode = '';
  // "Item Description" for the Salary Invoice screen only. Living here —
  // alongside billNo/poNo/client fields — means it survives navigating
  // between screens (they all get destroyed/recreated by go_router) and
  // gets captured/restored by SalarySnapshotNotifier just like the rest of
  // the bill header.
  //
  // NOTE: Attachment A and Attachment B used to read/write this exact same
  // field, so editing the description on any one of the three screens
  // silently changed it on the other two. They now have their own
  // independent fields below (_itemDescriptionAttachmentARaw /
  // _itemDescriptionAttachmentBRaw) — this field is Salary Invoice-only.
  String _itemDescription = 'Manpower Supply Charges';

  // Attachment A / Attachment B item descriptions — independent of each
  // other and of the Salary Invoice's _itemDescription above (no more
  // cross-screen sync). Both screens dropped the "saved descriptions"
  // dropdown in favour of a plain editable field, so there's no preset
  // list backing these.
  //
  // Empty string means "not customised — show the computed month/year
  // default". Setting a value equal to the *current* computed default is
  // treated the same as clearing it, so the field keeps tracking the
  // active period automatically until the user actually types something
  // different. See itemDescriptionAttachmentA/B getters below.
  String _itemDescriptionAttachmentARaw = '';
  String _itemDescriptionAttachmentBRaw = '';

  // MSW (June/December welfare deduction) is split into two concepts:
  //  - isMswEligibleMonth: whether the selected month is June or December.
  //  - applyMsw: whether the (user-toggleable) deduction should actually be
  //    applied for an eligible month. Defaults to on, matching the old
  //    always-on behaviour for eligible months.
  //  - mswAmount: the per-employee deduction amount, editable while
  //    applyMsw is on. Defaults to the historical hardcoded ₹6.
  bool _applyMsw = true;
  double _mswAmount = 6;

  final Map<int, int> _days = {};
  final Map<int, TextEditingController> _controllers = {};

  int get month => _month;
  int get year => _year;
  int get totalDays => DateTime(_year, _month + 1, 0).day;
  bool get isMswEligibleMonth => _month == 6 || _month == 12;
  bool get applyMsw => _applyMsw;
  double get mswAmount => _mswAmount;
  bool get isMsw => isMswEligibleMonth && _applyMsw;
  bool get isFeb => _month == 2;
  String get dateIso => _dateIso;
  String get dateDisplay => _formatDisplayDate(_dateIso);
  String get poNo => _poNo;
  String get billNo => _billNo;
  String get clientName => _clientName;
  String get clientAddr => _clientAddr;
  String get clientGstin => _clientGstin;
  String get deptCode => _deptCode;
  String get itemDescription => _itemDescription;

  /// Computed defaults, e.g. "Salary for the month of June 2026-2027" /
  /// "Service charges for the month of June 2026-2027" for the currently
  /// active month/year.
  String get defaultItemDescriptionAttachmentA =>
      'Salary for the month of $monthName $year-${year + 1}';
  String get defaultItemDescriptionAttachmentB =>
      'Service charges for the month of $monthName $year-${year + 1}';

  /// Effective description shown/used for each attachment: the user's
  /// literal override if they've set one, otherwise the computed default
  /// above (which stays in sync with month/year until the user types
  /// something else).
  String get itemDescriptionAttachmentA =>
      _itemDescriptionAttachmentARaw.isEmpty
          ? defaultItemDescriptionAttachmentA
          : _itemDescriptionAttachmentARaw;
  String get itemDescriptionAttachmentB =>
      _itemDescriptionAttachmentBRaw.isEmpty
          ? defaultItemDescriptionAttachmentB
          : _itemDescriptionAttachmentBRaw;

  /// Raw literal override (may be empty) — used by SalarySnapshotNotifier
  /// so saved snapshots can distinguish "user left this on the default" from
  /// "user typed something specific", and correctly recompute the default
  /// for whatever month/year the snapshot restores to.
  String get itemDescriptionAttachmentARaw => _itemDescriptionAttachmentARaw;
  String get itemDescriptionAttachmentBRaw => _itemDescriptionAttachmentBRaw;

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
  String get monthName => _monthNames[_month - 1];

  /// "June 2026"-style label for the currently active salary period. Reused
  /// by the Saved Salary list and the "Viewing Saved Salary" indicator so
  /// period formatting stays consistent across the module.
  String get periodLabel => '$monthName $year';

  static String _todayIso() =>
      DateTime.now().toIso8601String().split('T').first;

  static String _formatDisplayDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  static String? _parseDisplayDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    final dt = DateTime.tryParse(
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (dt == null || dt.day != day || dt.month != month || dt.year != year) {
      return null;
    }
    return dt.toIso8601String().split('T').first;
  }

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

  // ---------- Controller cache for days fields ----------
  TextEditingController getOrCreateController(int employeeId) {
    return _controllers.putIfAbsent(employeeId, () {
      final c = TextEditingController(
        text: (_days[employeeId] ?? 0) == 0 ? '' : '${_days[employeeId]}',
      );
      c.addListener(() {
        final d = int.tryParse(c.text) ?? 0;
        setDays(employeeId, d);
      });
      return c;
    });
  }

  void disposeController(int employeeId) {
    _controllers.remove(employeeId)?.dispose();
  }

  void disposeAllControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  // ---------- Existing setters & getters ----------
  void setMonthYear(int month, int year) {
    if (_month == month && _year == year) return;
    _month = month;
    _year = year;
    _safeNotify();
  }

  void setDateIso(String value) {
    final normalized =
        DateTime.tryParse(value)?.toIso8601String().split('T').first;
    if (normalized == null || _dateIso == normalized) return;
    _dateIso = normalized;
    _safeNotify();
  }

  void setDateDisplay(String value) {
    final parsed = _parseDisplayDate(value);
    if (parsed == null || _dateIso == parsed) return;
    _dateIso = parsed;
    _safeNotify();
  }

  void setDays(int employeeId, int days) {
    if (_days[employeeId] == days) return;
    _days[employeeId] = days;
    _safeNotify();
  }

  void setPoNo(String poNo) {
    if (_poNo == poNo) return;
    _poNo = poNo;
    _safeNotify();
  }

  void setBillNo(String v) {
    if (_billNo == v) return;
    _billNo = v;
    _safeNotify();
  }

  void setClientName(String v) {
    if (_clientName == v) return;
    _clientName = v;
    _safeNotify();
  }

  void setClientAddr(String v) {
    if (_clientAddr == v) return;
    _clientAddr = v;
    _safeNotify();
  }

  void setClientGstin(String v) {
    if (_clientGstin == v) return;
    _clientGstin = v;
    _safeNotify();
  }

  void setDeptCode(String v) {
    if (_deptCode == v) return;
    _deptCode = v;
    _safeNotify();
  }

  void setItemDescription(String v) {
    if (_itemDescription == v) return;
    _itemDescription = v;
    _safeNotify();
  }

  /// Setting a value equal to the *currently computed* default collapses
  /// back to '' (i.e. "follow the default"), rather than locking in that
  /// exact string. This is what lets the field keep tracking month/year
  /// changes made elsewhere (e.g. on the Employee Salary screen) right up
  /// until the user actually types something different from the default.
  void setItemDescriptionAttachmentA(String v) {
    final next = v == defaultItemDescriptionAttachmentA ? '' : v;
    if (_itemDescriptionAttachmentARaw == next) return;
    _itemDescriptionAttachmentARaw = next;
    _safeNotify();
  }

  void setItemDescriptionAttachmentB(String v) {
    final next = v == defaultItemDescriptionAttachmentB ? '' : v;
    if (_itemDescriptionAttachmentBRaw == next) return;
    _itemDescriptionAttachmentBRaw = next;
    _safeNotify();
  }

  void setApplyMsw(bool v) {
    if (_applyMsw == v) return;
    _applyMsw = v;
    _safeNotify();
  }

  void setMswAmount(double v) {
    if (_mswAmount == v) return;
    _mswAmount = v;
    _safeNotify();
  }

  int getDays(int employeeId) => _days[employeeId] ?? 0;
}