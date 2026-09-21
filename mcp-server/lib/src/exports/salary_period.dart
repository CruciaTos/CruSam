import 'package:crusam_core/crusam_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../db.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];

/// A saved salary month rebuilt into the inputs the salary documents need —
/// the same state the app is in after "Load" on the Saved Salary screen:
/// attendance and bill details from the saved month, employee master data
/// and formula settings as they are now.
class SalaryPeriod {
  final SalaryMonthSnapshotModel snapshot;
  final SalarySnapshotPayload payload;
  final List<EmployeeModel> allEmployees;
  final String companyCode;
  final SalaryFormulaConfigModel formula;

  SalaryPeriod._(this.snapshot, this.payload, this.allEmployees, this.companyCode,
      this.formula);

  static Future<SalaryPeriod> load(DatabaseExecutor db, int month, int year,
      {String? companyCode}) async {
    if ((await db.rawQuery("SELECT 1 FROM sqlite_master WHERE name='${SalarySnapshotStore.tableSnapshots}'")).isEmpty) {
      throw const ToolError('There are no saved salary months yet.');
    }
    final snap = await SalarySnapshotStore.getByPeriod(db, month, year);
    if (snap == null) {
      throw ToolError('No saved salary for ${_months[month - 1]} $year. Save it '
          'first with calculate_salary_month (save=true) or in the app.');
    }
    final payload = SalarySnapshotPayload.decode(snap.payload);
    final employees = (await EmployeeStore.listActive(db))
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
    final f = await db.query('salary_formula_config', limit: 1);
    return SalaryPeriod._(
      snap,
      payload,
      employees,
      companyCode ?? payload.selectedCompanyCode,
      f.isEmpty ? const SalaryFormulaConfigModel() : SalaryFormulaConfigModel.fromMap(f.first),
    );
  }

  int get month => payload.month;
  int get year => payload.year;
  String get monthName => _months[month - 1];
  String get periodLabel => '$monthName $year';
  int get daysInMonth => DateTime(year, month + 1, 0).day;
  bool get isFeb => month == 2;

  late final Map<int, int> daysMap = {
    for (final e in payload.employees) e.employeeId: e.days,
  };

  /// MSW isn't stored as a flag; it applied if any saved line carries it.
  late final double mswAmount = payload.employees
      .map((e) => e.msw.toDouble())
      .firstWhere((m) => m > 0, orElse: () => AppDefaults.mswAmount);
  late final bool isMsw = (month == 6 || month == 12) &&
      payload.employees.any((e) => e.msw > 0);

  /// Employees shown for [companyCode] (SalaryStateController.filteredEmployees).
  List<EmployeeModel> get employees => companyCode == 'All'
      ? allEmployees
      : allEmployees.where((e) => e.code == companyCode).toList();

  /// Employees who worked at least one day (what slips are printed for).
  List<EmployeeModel> get workedEmployees =>
      employees.where((e) => (daysMap[e.id] ?? 0) > 0).toList();

  String get departmentCode => companyCode == 'All' ? '' : companyCode;

  SalaryBillingTotals get totals => SalaryMonthCalculator(formula).billingTotals(
        allEmployees,
        (id) => daysMap[id] ?? 0,
        SalaryMonthInput(month: month, year: year, applyMsw: isMsw, mswAmount: mswAmount),
        companyCode: companyCode,
      );

  SalaryBillHeader get header => SalaryBillHeader(
        billNo: payload.billNo,
        date: _display(payload.dateIso),
        poNo: payload.poNo,
        customerName: payload.clientName,
        customerAddress: payload.clientAddr,
        customerGst: payload.clientGstin,
        departmentCode: departmentCode,
        period: periodLabel,
      );

  String get itemDescription => payload.itemDescription;
  String get attachmentADescription => payload.itemDescriptionAttachmentA.isNotEmpty
      ? payload.itemDescriptionAttachmentA
      : 'Salary for the month of $monthName $year-${year + 1}';
  String get attachmentBDescription => payload.itemDescriptionAttachmentB.isNotEmpty
      ? payload.itemDescriptionAttachmentB
      : 'Service charges for the month of $monthName $year-${year + 1}';

  static String _display(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
