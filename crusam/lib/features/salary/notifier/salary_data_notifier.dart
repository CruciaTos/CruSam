
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_constants.dart';

class SalaryDataNotifier extends ChangeNotifier {
  SalaryDataNotifier._();
  static final SalaryDataNotifier instance = SalaryDataNotifier._();
  bool _disposed = false;

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;
  String _dateIso      = _todayIso();
  String _poNo         = '-';
  String _billNo       = 'AE/-/25-26';
  String _clientName   = AppConstants.defaultClientName;
  String _clientAddr   = AppConstants.defaultClientAddress;
  String _clientGstin  = AppConstants.defaultClientGstin;
  String _deptCode    = '';

  final Map<int, int> _days = {};
  final Map<int, TextEditingController> _controllers = {};

  int    get month     => _month;
  int    get year      => _year;
  int    get totalDays => DateTime(_year, _month + 1, 0).day;
  bool   get isMsw     => _month == 6 || _month == 12;
  bool   get isFeb     => _month == 2;
  String get dateIso   => _dateIso;
  String get dateDisplay => _formatDisplayDate(_dateIso);
  String get poNo      => _poNo;
  String get billNo    => _billNo;
  String get clientName  => _clientName;
  String get clientAddr  => _clientAddr;
  String get clientGstin => _clientGstin;
  String get deptCode    => _deptCode;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  String get monthName => _monthNames[_month - 1];

  static String _todayIso() => DateTime.now().toIso8601String().split('T').first;

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
    _year  = year;
    _safeNotify();
  }

  void setDateIso(String value) {
    final normalized = DateTime.tryParse(value)?.toIso8601String().split('T').first;
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

  int getDays(int employeeId) => _days[employeeId] ?? 0;
}