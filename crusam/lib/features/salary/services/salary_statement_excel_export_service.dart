import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';

/// Service to export Salary Statement to Excel (.xlsx) format.
class ExcelExportService {
  // --------------------------------------------------------------------------
  // Column Widths (in Excel units)
  // --------------------------------------------------------------------------
  static const double _colWidthSrNo = 6.0;
  static const double _colWidthName = 24.0;
  static const double _colWidthPfNo = 14.0;
  static const double _colWidthUanNo = 16.0;
  static const double _colWidthCode = 8.0;
  static const double _colWidthZone = 8.0;
  static const double _colWidthIfsc = 14.0;
  static const double _colWidthAccountNo = 18.0;
  static const double _colWidthBasic = 12.0;
  static const double _colWidthOther = 12.0;
  static const double _colWidthArrears = 10.0;
  static const double _colWidthGross = 12.0;
  static const double _colWidthPf = 10.0;
  static const double _colWidthMsw = 8.0;
  static const double _colWidthEsicP = 8.0;
  static const double _colWidthPTax = 8.0;
  static const double _colWidthTotalDed = 12.0;
  static const double _colWidthNetSalary = 12.0;

  static const List<double> _columnWidths = [
    _colWidthSrNo,
    _colWidthName,
    _colWidthPfNo,
    _colWidthUanNo,
    _colWidthCode,
    _colWidthZone,
    _colWidthIfsc,
    _colWidthAccountNo,
    _colWidthBasic,
    _colWidthOther,
    _colWidthArrears,
    _colWidthGross,
    _colWidthPf,
    _colWidthMsw,
    _colWidthEsicP,
    _colWidthPTax,
    _colWidthTotalDed,
    _colWidthNetSalary,
  ];

  static const List<String> _headers = [
    'Sr. No',
    'Name',
    'PF No.',
    'UAN No.',
    'Code',
    'Zone',
    'IFSC',
    'Account No.',
    'Basic',
    'Other',
    'Arrears',
    'Gross',
    'PF',
    'MSW',
    'ESIC P',
    'P Tax',
    'Total Ded.',
    'Net Salary',
  ];

  // --------------------------------------------------------------------------
  // Public Export Method
  // --------------------------------------------------------------------------
  static Future<String?> exportSalaryStatement({
    required CompanyConfigModel config,
    required List<EmployeeModel> employees,
    required String monthName,
    required int year,
    required bool isMsw,
    required bool isFeb,
    required Map<int, int> daysMap,
    required int daysInMonth,
    Map<int, double>? columnWidths,
  }) async {
    if (employees.isEmpty) return null;

    final sorted = List<EmployeeModel>.from(employees)..sort(_deptThenName);

    final _ = columnWidths; // Unused for now

    final Workbook workbook = Workbook();
    workbook.worksheets.clear();
    final Worksheet sheet = workbook.worksheets.addWithName('Salary Statement');

    for (int i = 0; i < _columnWidths.length; i++) {
      sheet.getRangeByIndex(1, i + 1).columnWidth = _columnWidths[i];
    }

    int currentRow = 1;

    final String title =
        '${config.companyName}\nSALARY STATEMENT FOR THE MONTH OF ${monthName.toUpperCase()} $year';
    _writeTitleRow(sheet, currentRow++, title, _headers.length);
    _writeHeaderRow(sheet, currentRow++);

    double sumBasic = 0;
    double sumOther = 0;
    double sumGross = 0;
    double sumNet = 0;
    int sumPf = 0;
    int sumMsw = 0;
    int sumEsicP = 0;
    int sumPt = 0;
    int sumTd = 0;

    for (int idx = 0; idx < sorted.length; idx++) {
      final e = sorted[idx];
      final days = daysMap[e.id] ?? 0;
      final hasDays = days > 0;

      final earnedBasic =
          hasDays && daysInMonth > 0 ? e.basicCharges * days / daysInMonth : 0.0;
      final earnedGross =
          hasDays && daysInMonth > 0 ? e.grossSalary * days / daysInMonth : 0.0;
      final pf = hasDays ? (earnedBasic * 0.12).round() : 0;
      final esicInt =
          e.grossSalary >= 21000 ? 0 : (hasDays ? (earnedGross * 0.0075).ceil() : 0);
      final msw = isMsw ? 6 : 0;
      final displayedMsw = hasDays ? msw : 0;
      final pt = _calculatePT(earnedGross, e.gender, isFeb);
      final totalDed = pf + esicInt + msw + pt;
      final displayedTotalDed = hasDays ? totalDed : 0;
      final net = hasDays ? earnedGross - totalDed : 0.0;

      sumBasic += e.basicCharges;
      sumOther += e.otherCharges;
      sumGross += e.grossSalary;
      sumPf += pf;
      sumMsw += msw;
      sumEsicP += esicInt;
      sumPt += pt;
      sumTd += totalDed;
      sumNet += net;

      int col = 1;
      _setCellValue(sheet, currentRow, col++, '${idx + 1}', hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, e.name, hAlign: HAlignType.left);
      _setCellValue(sheet, currentRow, col++, e.pfNo, hAlign: HAlignType.left);
      _setCellValue(sheet, currentRow, col++, e.uanNo, hAlign: HAlignType.left);
      _setCellValue(sheet, currentRow, col++, e.code, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, e.zone, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, e.ifscCode, hAlign: HAlignType.left);
      _setCellValue(sheet, currentRow, col++, e.accountNumber, hAlign: HAlignType.left);
      _setCellValue(sheet, currentRow, col++, e.basicCharges, isNumber: true);
      _setCellValue(sheet, currentRow, col++, e.otherCharges, isNumber: true);
      _setCellValue(sheet, currentRow, col++, 0, isNumber: true, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, e.grossSalary, isNumber: true);
      _setCellValue(sheet, currentRow, col++, hasDays ? pf : 0, isNumber: true);
      _setCellValue(sheet, currentRow, col++, displayedMsw, isNumber: true, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, hasDays ? esicInt : 0, isNumber: true, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, hasDays ? pt : 0, isNumber: true, hAlign: HAlignType.center);
      _setCellValue(sheet, currentRow, col++, displayedTotalDed, isNumber: true);
      _setCellValue(sheet, currentRow, col++, net, isNumber: true, decimalPlaces: 0);

      // Gray out deduction columns and net salary if no days (columns 13 to 18 in 1‑based index)
      if (!hasDays) {
        for (int c = 13; c <= 18; c++) {
          final cell = sheet.getRangeByIndex(currentRow, c);
          cell.cellStyle.fontColor = '#BBBBBB';
        }
      }

      currentRow++;
    }

    _writeTotalRow(
      sheet,
      currentRow++,
      sumBasic: sumBasic,
      sumOther: sumOther,
      sumGross: sumGross,
      sumPf: sumPf,
      sumMsw: sumMsw,
      sumEsicP: sumEsicP,
      sumPt: sumPt,
      sumTd: sumTd,
      sumNet: sumNet,
    );

    final Range tableRange =
        sheet.getRangeByIndex(2, 1, currentRow - 1, _headers.length);
    _applyBorder(tableRange);

    final Range headerRange = sheet.getRangeByIndex(2, 1, 2, _headers.length);
    headerRange.cellStyle.bold = true;

    final Range totalRange =
        sheet.getRangeByIndex(currentRow - 1, 1, currentRow - 1, _headers.length);
    totalRange.cellStyle.bold = true;
    totalRange.cellStyle.backColor = '#D6DCF5';

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final fileName = 'Salary_Statement_${monthName}_$year.xlsx';
    return _saveExcelFile(bytes, fileName);
  }

  // --------------------------------------------------------------------------
  // Helper Methods
  // --------------------------------------------------------------------------
  static void _writeTitleRow(
    Worksheet sheet,
    int row,
    String title,
    int columnCount,
  ) {
    final Range range = sheet.getRangeByIndex(row, 1, row, columnCount);
    range.merge();
    range.setText(title);
    range.cellStyle.bold = true;
    range.cellStyle.fontSize = 14;
    range.cellStyle.hAlign = HAlignType.center;
    range.cellStyle.vAlign = VAlignType.center;
    range.rowHeight = 30;
  }

  static void _writeHeaderRow(Worksheet sheet, int row) {
    for (int i = 0; i < _headers.length; i++) {
      final Range cell = sheet.getRangeByIndex(row, i + 1);
      cell.setText(_headers[i]);
      cell.cellStyle.bold = true;
      cell.cellStyle.hAlign = HAlignType.center;
      cell.cellStyle.vAlign = VAlignType.center;
      cell.cellStyle.backColor = '#E3E8F4';
      cell.cellStyle.wrapText = true;
    }
    sheet.getRangeByIndex(row, 1, row, _headers.length).rowHeight = 36;
  }

  static void _writeTotalRow(
    Worksheet sheet,
    int row, {
    required double sumBasic,
    required double sumOther,
    required double sumGross,
    required int sumPf,
    required int sumMsw,
    required int sumEsicP,
    required int sumPt,
    required int sumTd,
    required double sumNet,
  }) {
    int col = 1;
    _setCellValue(sheet, row, col++, 'TOTAL :-', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, '', hAlign: HAlignType.left);
    _setCellValue(sheet, row, col++, sumBasic, isNumber: true);
    _setCellValue(sheet, row, col++, sumOther, isNumber: true);
    _setCellValue(sheet, row, col++, 0, isNumber: true, hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, sumGross, isNumber: true);
    _setCellValue(sheet, row, col++, sumPf, isNumber: true);
    _setCellValue(sheet, row, col++, sumMsw, isNumber: true, hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, sumEsicP, isNumber: true, hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, sumPt, isNumber: true, hAlign: HAlignType.center);
    _setCellValue(sheet, row, col++, sumTd, isNumber: true);
    _setCellValue(sheet, row, col++, sumNet, isNumber: true);
  }

  static void _setCellValue(
    Worksheet sheet,
    int row,
    int col,
    dynamic value, {
    bool isNumber = false,
    int decimalPlaces = 0,
    HAlignType hAlign = HAlignType.right,
    bool zeroAsEmpty = false,
  }) {
    final Range cell = sheet.getRangeByIndex(row, col);

    if (value == null || (zeroAsEmpty && value == 0)) {
      cell.setText('');
    } else if (isNumber) {
      cell.setNumber((value as num).toDouble());
      cell.numberFormat =
          decimalPlaces > 0 ? '#,##0.${'0' * decimalPlaces}' : '#,##0';
    } else {
      cell.setText(value.toString());
    }

    cell.cellStyle.hAlign = hAlign;
    cell.cellStyle.vAlign = VAlignType.center;
  }

  static void _applyBorder(Range range) {
    range.cellStyle.borders.all.lineStyle = LineStyle.thin;
    range.cellStyle.borders.all.color = '#000000';
  }

  static int _calculatePT(double earnedGross, String gender, bool isFeb) {
    if (earnedGross == 0) return 0;

    final isFemale = gender.toUpperCase() == 'F';
    if (isFemale) {
      return earnedGross < 25000 ? 0 : (isFeb ? 300 : 200);
    }
    if (earnedGross < 7500) return 0;
    if (earnedGross < 10000) return 175;
    return isFeb ? 300 : 200;
  }

  static Future<String?> _saveExcelFile(List<int> bytes, String fileName) async {
    try {
      Directory? directory;
      final savedPath = ExportPreferencesNotifier.instance
          .resolvedPathForTarget(ExportPathTarget.salaryStatementExcel);

      if (savedPath.isNotEmpty) {
        final customDir = Directory(savedPath);
        if (await customDir.exists()) {
          directory = customDir;
        }
      }

      if (directory == null && (Platform.isAndroid || Platform.isIOS)) {
        directory = await getApplicationDocumentsDirectory();
      } else if (directory == null) {
        directory = await getDownloadsDirectory();
        directory ??= await getApplicationDocumentsDirectory();
      }

      final String path = '${directory.path}/$fileName';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return path;
    } catch (e) {
      debugPrint('Error saving Excel file: $e');
      return null;
    }
  }

  // ── Sort: department code first, then alphabetically by name ───────────────
  static int _deptThenName(EmployeeModel a, EmployeeModel b) {
    final codeCompare = a.code.trim().toLowerCase()
        .compareTo(b.code.trim().toLowerCase());
    if (codeCompare != 0) return codeCompare;
    return a.name.trim().toLowerCase()
        .compareTo(b.name.trim().toLowerCase());
  }
}