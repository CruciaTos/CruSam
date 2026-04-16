// lib/features/salary/services/salary_excel_export_service.dart
//
// Excel export service for salary data.
// _outputDir() checks ExportPreferencesNotifier.excelPath first,
// then falls back to the platform default (Downloads / app documents).

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../notifier/salary_data_notifier.dart';

class SalaryExcelExportService {
  SalaryExcelExportService._();

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC: Export salary data for all employees as a .xlsx workbook.
  //
  // Sheet layout:
  //   Row 1  — Header (bold, highlighted)
  //   Row 2+ — One row per employee with earned basic, earned gross,
  //            PF, ESIC, MSW, PT, net pay, and days worked.
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> exportSalarySheet({
    required CompanyConfigModel config,
    required List<EmployeeModel> employees,
    required String monthName,
    required int year,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) async {
    final n      = SalaryDataNotifier.instance;
    final excel  = Excel.createExcel();
    final sheet  = excel['Salary $monthName $year'];

    // ── Remove the default blank sheet ──────────────────────────────────────
    excel.delete('Sheet1');

    // ── Header style ─────────────────────────────────────────────────────────
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E3E8F4'),
      horizontalAlign: HorizontalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    // ── Column headers ───────────────────────────────────────────────────────
    final headers = [
      'Sr.', 'Employee Name', 'Dept.', 'Days Worked',
      'Basic (Monthly)', 'Earned Basic',
      'Gross (Monthly)', 'Earned Gross',
      'PF (12%)', 'ESIC', 'MSW', 'PT',
      'Total Deductions', 'Net Pay',
    ];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: i, rowIndex: 0));
      cell.value  = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // ── Data rows ─────────────────────────────────────────────────────────────
    for (var idx = 0; idx < employees.length; idx++) {
      final emp  = employees[idx];
      final days = n.getDays(emp.id ?? 0);

      final eB   = daysInMonth == 0 ? 0.0 : emp.basicCharges * days / daysInMonth;
      final eO   = daysInMonth == 0 ? 0.0 : emp.otherCharges * days / daysInMonth;
      final eG   = eB + eO;
      final pf   = (eB * 0.12).round().toDouble();
      // ESIC: only for employees with gross < 21 000; rate = 0.75 % (employee share)
      final esic  = emp.grossSalary < 21000
          ? (eG * 0.0075).ceil().toDouble()
          : 0.0;
      final msw  = isMsw ? 6.0 : 0.0;

      final female = emp.gender.toUpperCase() == 'F';
      double pt;
      if (female) {
        pt = eG < 25000 ? 0 : (isFeb ? 300 : 200);
      } else {
        if (eG < 7500)       pt = 0;
        else if (eG < 10000) pt = 175;
        else                  pt = isFeb ? 300 : 200;
      }

      final totalDed = pf + esic + msw + pt;
      final netPay   = eG - totalDed;

      // Alternate-row shading
      final rowStyle = CellStyle(
        backgroundColorHex: idx.isOdd
            ? ExcelColor.fromHexString('#F8FAFC')
            : ExcelColor.fromHexString('#FFFFFF'),
      );

      final rowValues = [
        IntCellValue(idx + 1),
        TextCellValue(emp.name),
        TextCellValue(emp.code),
        IntCellValue(days),
        DoubleCellValue(_r(emp.basicCharges)),
        DoubleCellValue(_r(eB)),
        DoubleCellValue(_r(emp.grossSalary)),
        DoubleCellValue(_r(eG)),
        DoubleCellValue(_r(pf)),
        DoubleCellValue(_r(esic)),
        DoubleCellValue(_r(msw)),
        DoubleCellValue(_r(pt)),
        DoubleCellValue(_r(totalDed)),
        DoubleCellValue(_r(netPay)),
      ];

      for (var col = 0; col < rowValues.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
            columnIndex: col, rowIndex: idx + 1));
        cell.value     = rowValues[col];
        cell.cellStyle = rowStyle;
      }
    }

    // ── Totals row ────────────────────────────────────────────────────────────
    final totalsRowIdx = employees.length + 1;
    final totalsStyle  = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#D6DCF5'),
    );

    double sumEarnedBasic = 0, sumEarnedGross = 0, sumPf = 0,
           sumEsic = 0, sumMsw = 0, sumPt = 0, sumDed = 0, sumNet = 0;

    for (final emp in employees) {
      final days = n.getDays(emp.id ?? 0);
      final eB   = daysInMonth == 0 ? 0.0 : emp.basicCharges * days / daysInMonth;
      final eO   = daysInMonth == 0 ? 0.0 : emp.otherCharges * days / daysInMonth;
      final eG   = eB + eO;
      final pf   = (eB * 0.12).round().toDouble();
      final esic = emp.grossSalary < 21000 ? (eG * 0.0075).ceil().toDouble() : 0.0;
      final msw  = isMsw ? 6.0 : 0.0;
      final female = emp.gender.toUpperCase() == 'F';
      double pt;
      if (female) {
        pt = eG < 25000 ? 0 : (isFeb ? 300 : 200);
      } else {
        if (eG < 7500)       pt = 0;
        else if (eG < 10000) pt = 175;
        else                  pt = isFeb ? 300 : 200;
      }
      sumEarnedBasic += eB; sumEarnedGross += eG;
      sumPf += pf; sumEsic += esic; sumMsw += msw; sumPt += pt;
      sumDed += (pf + esic + msw + pt);
      sumNet += (eG - pf - esic - msw - pt);
    }

    final totals = [
      TextCellValue(''),                          // Sr.
      TextCellValue('TOTAL'),                     // Name
      TextCellValue(''),                          // Dept.
      TextCellValue(''),                          // Days
      TextCellValue(''),                          // Basic monthly
      DoubleCellValue(_r(sumEarnedBasic)),
      TextCellValue(''),                          // Gross monthly
      DoubleCellValue(_r(sumEarnedGross)),
      DoubleCellValue(_r(sumPf)),
      DoubleCellValue(_r(sumEsic)),
      DoubleCellValue(_r(sumMsw)),
      DoubleCellValue(_r(sumPt)),
      DoubleCellValue(_r(sumDed)),
      DoubleCellValue(_r(sumNet)),
    ];
    for (var col = 0; col < totals.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: col, rowIndex: totalsRowIdx));
      cell.value     = totals[col];
      cell.cellStyle = totalsStyle;
    }

    // ── Auto column widths (approximate) ─────────────────────────────────────
    const colWidths = [5.0, 24.0, 10.0, 10.0, 14.0, 12.0,
                       14.0, 12.0, 10.0, 8.0, 8.0, 8.0, 14.0, 12.0];
    for (var i = 0; i < colWidths.length; i++) {
      sheet.setColumnWidth(i, colWidths[i]);
    }

    // ── Save & share ──────────────────────────────────────────────────────────
    final slug     = '${monthName.toLowerCase()}_$year';
    final fileName = 'salary_$slug.xlsx';
    final dir      = await _outputDir();
    final path     = '${dir.path}${Platform.pathSeparator}$fileName';

    final bytes = excel.save();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Excel encode returned empty bytes');
    }
    await File(path).writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: fileName)],
      subject: 'Salary Sheet – $monthName $year',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Round to 2 decimal places.
  static double _r(double v) => double.parse(v.toStringAsFixed(2));

  /// Resolve output directory:
  ///   1. User-chosen Excel path (from ExportPreferencesNotifier)
  ///   2. Platform default  (Downloads on desktop, app docs on mobile)
  static Future<Directory> _outputDir() async {
    // 1. User-chosen path (set via Profile → Export Paths).
    final savedPath = ExportPreferencesNotifier.instance.excelPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir;
      // Saved path no longer exists — fall through to platform default.
    }

    // 2. Platform default.
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final downloads = Directory(
      Platform.isWindows ? '$home\\Downloads' : '$home/Downloads',
    );
    if (await downloads.exists()) return downloads;
    return getApplicationDocumentsDirectory();
  }
}