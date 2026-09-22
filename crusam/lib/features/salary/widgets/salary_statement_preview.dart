import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../pdf/widgets/pdf_pages_preview.dart';
import 'package:crusam_core/crusam_core.dart';

/// Salary Statement preview — renders the exact landscape PDF pages the
/// export writes.
///
/// All columns (Basic, Other, Gross, PF, MSW, ESIC, PT, Net) use
/// **prorated (earned)** values based on days present from [daysMap].
///
/// Column index map (18 columns total):
///  0  Sr. No        1  Name           2  PF NO.         3  UAN NO.
///  4  Code          5  Zone           6  IFSC           7  Account Number
///  8  Basic         9  Other         10  Arrears        11  Gross
/// 12  PF            13  MSW           14  ESIC P        15  P Tax
/// 16  Total Ded.    17  Net Salary
class SalaryStatementPreview extends StatelessWidget {
  /// Landscape A4 at 96 px per inch.
  static const double pageWidth = 1122.5;

  static const Map<int, double> defaultColumnWidths =
      SalaryStatementPdfService.defaultColumnWidths;

  static const List<String> columnLabels =
      SalaryStatementPdfService.columnLabels;

  final CompanyConfigModel  config;

  /// PDF margins in points; the saved margin setting when null.
  final EdgeInsets?         margins;
  final List<EmployeeModel> employees;
  final String              monthName;
  final int                 year;
  final bool                isMsw;
  final double              mswAmount;
  final bool                isFeb;
  final bool                applyMsw;

  /// Maps employee ID → days present.  Absent / 0 → all columns show 0.
  final Map<int, int> daysMap;

  /// Total calendar days in the selected month (e.g. 31 for March).
  final int daysInMonth;

  /// Override individual column widths by index (0–17).
  final Map<int, double> columnWidths;

  /// Department code shown in the reference strip (e.g. 'F&B').
  final String departmentCode;

  const SalaryStatementPreview({
    super.key,
    required this.config,
    this.margins,
    required this.employees,
    required this.monthName,
    required this.year,
    this.isMsw        = false,
    this.mswAmount    = 6,
    this.isFeb        = false,
    this.applyMsw     = true,
    this.daysMap      = const {},
    this.daysInMonth  = 0,
    this.columnWidths = const {},
    this.departmentCode = '',
  });

  @override
  Widget build(BuildContext context) {
    final m = margins;
    return PdfPagesPreview(
      inputs: [
        config.toMap(), m, [for (final e in employees) e.toMap()], monthName,
        year, isMsw, mswAmount, isFeb, applyMsw, daysMap, daysInMonth,
        columnWidths, departmentCode,
      ],
      build: () => SalaryStatementPdfService.buildSalaryStatementBytes(
        config: config,
        employees: employees,
        monthName: monthName,
        year: year,
        isMsw: isMsw && applyMsw,
        mswAmount: mswAmount,
        isFeb: isFeb,
        daysMap: daysMap,
        daysInMonth: daysInMonth,
        columnWidths: columnWidths,
        departmentCode: departmentCode,
        margins: m == null
            ? null
            : pw.EdgeInsets.fromLTRB(m.left, m.top, m.right, m.bottom),
      ),
    );
  }
}
