import 'package:flutter/foundation.dart';

class SalaryDataNotifier extends ChangeNotifier {
  SalaryDataNotifier._();
  static final SalaryDataNotifier instance = SalaryDataNotifier._();

  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;
  String _poNo = '';

  final Map<int, int> _days = {};

  int    get month     => _month;
  int    get year      => _year;
  int    get totalDays => DateTime(_year, _month + 1, 0).day;
  bool   get isMsw     => _month == 6 || _month == 12;
  bool   get isFeb     => _month == 2;
  String get poNo      => _poNo;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  String get monthName => _monthNames[_month - 1];

  void setMonthYear(int month, int year) {
    if (_month == month && _year == year) return;
    _month = month;
    _year  = year;
    notifyListeners();
  }

  void setDays(int employeeId, int days) {
    if (_days[employeeId] == days) return;
    _days[employeeId] = days;
    notifyListeners();
  }

  void setPoNo(String poNo) {
    if (_poNo == poNo) return;
    _poNo = poNo;
    notifyListeners();
  }

  int getDays(int employeeId) => _days[employeeId] ?? 0;
}