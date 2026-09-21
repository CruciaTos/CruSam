// lib/features/salary/services/salary_statement_pdf_service.dart
//
// Salary Statement — a landscape table document built by PdfHouseStyle.
// Column widths come from the Salary Statement screen and are scaled to
// fill the usable page width; the table flows over as many pages as needed.
//
// Basic / Other / Gross columns show EARNED (prorated) values.

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../export/export_hooks.dart';
import '../models/company_config_model.dart';
import '../models/employee_model.dart';
import 'pdf_house_style.dart';
import '../salary/salary_formula_engine.dart';

class SalaryStatementPdfService {
  SalaryStatementPdfService._();

  /// Default column widths (index 0–17). Relative — the PDF scales them to
  /// fill the page, the screen's column-width editor edits them.
  static const Map<int, double> defaultColumnWidths = {
    0: 26, // Sr. No
    1: 124, // Name
    2: 84, // PF NO.
    3: 92, // UAN NO.
    4: 30, // Code
    5: 38, // Zone
    6: 74, // IFSC
    7: 104, // Account Number
    8: 50, // Basic
    9: 50, // Other
    10: 38, // Arrears
    11: 54, // Gross
    12: 36, // PF
    13: 30, // MSW
    14: 30, // ESIC P
    15: 36, // P Tax
    16: 50, // Total Ded.
    17: 56, // Net Salary
  };

  static const List<String> columnLabels = [
    'Sr. No', 'Name', 'PF No.', 'UAN No.', 'Code', 'Zone', 'IFSC',
    'Account No.', 'Basic', 'Other', 'Arrears', 'Gross',
    'PF', 'MSW', 'ESIC P', 'P Tax', 'Total Ded.', 'Net Salary',
  ];

  static const _headers = [
    'Sr.\nNo.', 'Name of\nTechnician', 'PF NO.', 'UAN NO.', 'Code', 'Zone',
    'IFSC code', 'Account\nnumber', 'Basic', 'Other', 'Incr.\nArrs.',
    'Gross\nSalary', 'PF', 'MSW', 'ESIC\nP', 'P Tax', 'Total\nDed.',
    'Net Salary',
  ];

  static const _l = pw.TextAlign.left;
  static const _c = pw.TextAlign.center;
  static const _r = pw.TextAlign.right;
  static const _align = [
    _c, _l, _l, _l, _c, _c, _l, _l, _r, _r, _c, _r, _r, _c, _c, _c, _r, _r,
  ];

  // ── Per-employee payroll helpers ───────────────────────────────────────────
  static int _days(EmployeeModel e, Map<int, int> daysMap) =>
      daysMap[e.id ?? -1] ?? 0;

  static double _earnedBasic(EmployeeModel e, int days, int dim) {
    if (days == 0 || dim == 0) return 0;
    return e.basicCharges * days / dim;
  }

  static double _earnedOther(EmployeeModel e, int days, int dim) {
    if (days == 0 || dim == 0) return 0;
    return e.otherCharges * days / dim;
  }

  static double _earnedGross(EmployeeModel e, int days, int dim) {
    if (days == 0 || dim == 0) return 0;
    return e.grossSalary * days / dim;
  }

  static int _pf(EmployeeModel e, int days, int dim) =>
      SalaryFormulaEngine.pf(_earnedBasic(e, days, dim)).round();

  static int _esic(EmployeeModel e, int days, int dim) => SalaryFormulaEngine.esic(
        fullGrossSalary: e.grossSalary,
        earnedGross: _earnedGross(e, days, dim),
      ).round();

  static int _msw(bool isMsw, double mswAmount) => isMsw ? mswAmount.round() : 0;

  static int _pt(EmployeeModel e, int days, int dim, bool isFeb) => SalaryFormulaEngine.pt(
        earnedGross: _earnedGross(e, days, dim),
        isFemale: e.gender.toUpperCase() == 'F',
        isFeb: isFeb,
      ).round();

  static int _totalDed(
    EmployeeModel e, int days, int dim, bool isMsw, double mswAmount, bool isFeb,
  ) =>
      _pf(e, days, dim) + _esic(e, days, dim) + _msw(isMsw, mswAmount) + _pt(e, days, dim, isFeb);

  static double _net(
    EmployeeModel e, int days, int dim, bool isMsw, double mswAmount, bool isFeb,
  ) {
    final eg = _earnedGross(e, days, dim);
    return eg == 0 ? 0 : eg - _totalDed(e, days, dim, isMsw, mswAmount, isFeb);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportSalaryStatement({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required bool                isMsw,
    required double              mswAmount,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    Map<int, double>             columnWidths = const {},
    String                       departmentCode = '',
    pw.EdgeInsets?               margins,
  }) async {
    final bytes = await buildSalaryStatementBytes(
      config: config,
      employees: employees,
      monthName: monthName,
      year: year,
      isMsw: isMsw,
      mswAmount: mswAmount,
      isFeb: isFeb,
      daysMap: daysMap,
      daysInMonth: daysInMonth,
      columnWidths: columnWidths,
      departmentCode: departmentCode,
      margins: margins,
    );
    await ExportHooks.savePdf(
      bytes,
      fileName: 'salary_statement_${monthName.toLowerCase()}_$year',
      target: ExportPathTarget.salary,
    );
  }

  /// Bytes only, no disk write — for email sending and on-screen preview.
  static Future<Uint8List> buildSalaryStatementBytes({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required bool                isMsw,
    required double              mswAmount,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    Map<int, double>             columnWidths = const {},
    String                       departmentCode = '',
    pw.EdgeInsets?               margins,
  }) async {
    await PdfHouseStyle.ensureLoaded();
    final doc = PdfHouseStyle.newDocument(
        title: 'Salary Statement $monthName $year');
    doc.addPage(statementPages(
      config: config,
      margins: margins ?? await PdfHouseStyle.savedMargins(),
      employees: employees,
      monthName: monthName,
      year: year,
      isMsw: isMsw,
      mswAmount: mswAmount,
      isFeb: isFeb,
      daysMap: daysMap,
      daysInMonth: daysInMonth,
      columnWidths: columnWidths,
      departmentCode: departmentCode,
    ));
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    return bytes;
  }

  /// The statement's pages, for appending to another document (the
  /// finalised salary bill). Call PdfHouseStyle.ensureLoaded() first.
  static pw.MultiPage statementPages({
    required CompanyConfigModel  config,
    required pw.EdgeInsets       margins,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required bool                isMsw,
    required double              mswAmount,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    Map<int, double>             columnWidths = const {},
    String                       departmentCode = '',
  }) {
    final sorted = List<EmployeeModel>.from(employees)
      ..sort((a, b) {
        final c = a.code.trim().toLowerCase()
            .compareTo(b.code.trim().toLowerCase());
        if (c != 0) return c;
        return a.name.trim().toLowerCase()
            .compareTo(b.name.trim().toLowerCase());
      });

    final dim = daysInMonth;
    double sumBasic = 0, sumOther = 0, sumGross = 0, sumNet = 0;
    int sumPf = 0, sumMsw = 0, sumEsic = 0, sumPt = 0, sumTd = 0;
    final rows = <List<String>>[];

    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final d = _days(e, daysMap);
      final hasDays = d > 0;

      final eBasic = _earnedBasic(e, d, dim);
      final eOther = _earnedOther(e, d, dim);
      final eGross = _earnedGross(e, d, dim);
      final pf = _pf(e, d, dim);
      final esic = _esic(e, d, dim);
      final msw = _msw(isMsw, mswAmount);
      final pt = _pt(e, d, dim, isFeb);
      final td = _totalDed(e, d, dim, isMsw, mswAmount, isFeb);
      final net = _net(e, d, dim, isMsw, mswAmount, isFeb);

      sumBasic += eBasic;
      sumOther += eOther;
      sumGross += eGross;
      sumPf += pf;
      sumMsw += msw;
      sumEsic += esic;
      sumPt += pt;
      sumTd += td;
      sumNet += net;

      rows.add([
        '${i + 1}',
        e.name,
        e.pfNo,
        e.uanNo,
        e.code,
        e.zone,
        e.ifscCode,
        e.accountNumber,
        hasDays ? _n(eBasic) : '0',
        hasDays ? _n(eOther) : '0',
        '0',
        hasDays ? _n(eGross) : '0',
        hasDays ? '$pf' : '0',
        hasDays ? '$msw' : '0',
        hasDays ? '$esic' : '0',
        hasDays ? '$pt' : '0',
        hasDays ? '$td' : '0',
        hasDays ? _n(net) : '0',
      ]);
    }

    return PdfHouseStyle.tablePages(
      config: config,
      margins: margins,
      title: 'Salary Statement for the month of $monthName $year',
      referencesRight: [
        if (departmentCode.trim().isNotEmpty)
          ('Dept. Code', departmentCode.trim()),
      ],
      columns: [
        for (var i = 0; i < _headers.length; i++)
          PdfTableColumn(
            _headers[i],
            columnWidths[i] ?? defaultColumnWidths[i]!,
            align: _align[i],
          ),
      ],
      rows: rows,
      totalRow: [
        '', 'TOTAL :-', '', '', '', '', '', '',
        _n(sumBasic),
        _n(sumOther),
        '0',
        _n(sumGross),
        '$sumPf',
        '$sumMsw',
        '$sumEsic',
        '$sumPt',
        '$sumTd',
        _n(sumNet),
      ],
      closing: PdfHouseStyle.tableClosing(config),
    );
  }

  static String _n(double v) => v.toStringAsFixed(0);
}
