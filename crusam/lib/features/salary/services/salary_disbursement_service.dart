// lib/features/salary/services/salary_disbursement_service.dart
//
// Mirrors ExcelExportService.exportBankDisbursement layout exactly
// (columns, widths, row positions, total-with-words, bank split, print area).
// Data comes from the salary module: final salary amounts + employee bank details.
//
// 🛠️  Columns: Amount | Debit A/C no. | IFSC | Credit A/c no. | Code |
//               Beneficiary | Branch | Bank Details
//
// 🧩  Code -> always 10 for every employee
// 🧩  Branch -> actual branch (from EmployeeModel.branch)

import 'dart:io';
import 'dart:typed_data';
import 'package:crusam/data/db/salary_disbursement_repository.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:crusam/core/preferences/export_preferences_notifier.dart';
import 'package:crusam/data/db/database_helper.dart';
import 'package:crusam/data/models/company_config_model.dart';
import 'package:crusam/data/models/employee_model.dart';
import 'package:crusam/shared/utils/format_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/salary_disbursement_model.dart';
import '../notifier/salary_data_notifier.dart';

class SalaryDisbursementService {
  SalaryDisbursementService._();

  // ─────────────────────────────────────────────────────────────────────────
  // 📌 BLANK LEFT COLUMN — matches ExcelExportService
  // ─────────────────────────────────────────────────────────────────────────
  static const bool   _includeLeftBlankColumn = true;
  static const double _colWidthBlankLeft      = 3.0;

  // ─────────────────────────────────────────────────────────────────────────
  // 🎯 COLUMN WIDTHS (8 columns – same as ExcelExportService)
  // ─────────────────────────────────────────────────────────────────────────
  static const double _colWidthAmount       = 22.0;
  static const double _colWidthDebitAc      = 20.0;
  static const double _colWidthIFSC         = 14.0;
  static const double _colWidthCreditAc     = 20.0;
  static const double _colWidthCode         = 10.0;
  static const double _colWidthBeneficiary  = 22.0;
  static const double _colWidthBranch       = 29.0;   // was Place, now Branch
  static const double _colWidthBankDetails  = 25.0;

  // ─────────────────────────────────────────────────────────────────────────
  // 🖨️ PRINT SETUP
  // ─────────────────────────────────────────────────────────────────────────
  static const String _printStartCol = 'A';
  static const int    _printStartRow = 1;
  static const bool   _fitToPage     = true;

  // ─────────────────────────────────────────────────────────────────────────
  // 📊 BANK SPLIT SUMMARY CONFIGURATION
  // ─────────────────────────────────────────────────────────────────────────
  static const bool   _includeBankSplit        = true;
  static const int    _bankSplitOffset         = 2;
  static const String _bankSplitLabel          = 'BANK TRANSFER SPLIT';
  static const bool   _splitBoxUseBackground   = false;
  static const bool   _splitBoxOuterBorder     = true;
  static const String _splitBoxBgColor         = '#FF1E293B';
  static const String _splitTextColor          = '#FFFFFFFF';
  static const String _splitLabelColor         = '#FF94A3B8';
  static const String _splitValueColor         = '#FFCBD5E1';
  static const int    _bankSplitColumnOffset   = 3;

  // ─────────────────────────────────────────────────────────────────────────
  // 🔲 DATA TABLE OUTER BORDER
  // ─────────────────────────────────────────────────────────────────────────
  static const bool _dataTableOuterBorder = true;

  // ─────────────────────────────────────────────────────────────────────────
  // 📏 TOTAL IN WORDS CELL MERGING (in the total row)
  // ─────────────────────────────────────────────────────────────────────────
  static const int _wordsCellMergeCount = 2; // merges Debit A/C + IFSC + Credit A/C

  // ─────────────────────────────────────────────────────────────────────────
  // 🖼️ SIGNATURE IMAGE (kept for format parity – no real image loaded)
  // ─────────────────────────────────────────────────────────────────────────
  static const int _signatureColOffset = 8;
  static const int _signatureRowOffset = 12;

  // ─────────────────────────────────────────────────────────────────────────
  // 📏 Column helpers
  // ─────────────────────────────────────────────────────────────────────────
  static int get _dataStartCol => _includeLeftBlankColumn ? 2 : 1;
  static int get _dataEndCol   => _dataStartCol + 7; // 8 columns (0..7)

  // ─────────────────────────────────────────────────────────────────────────
  // Net salary calculation (unchanged)
  // ─────────────────────────────────────────────────────────────────────────
  static double _computeNetSalary({
    required EmployeeModel employee,
    required int days,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) {
    if (days == 0 || daysInMonth == 0) return 0;
    final eBasic = employee.basicCharges * days / daysInMonth;
    final eGross = employee.grossSalary  * days / daysInMonth;
    final pf     = eBasic >= 15000 ? 1800.0 : (eBasic * 0.12).round().toDouble();
    final esic   = employee.grossSalary <= 21000
        ? (eGross * 0.0075).ceilToDouble()
        : 0.0;
    final msw    = isMsw ? 6.0 : 0.0;
    final female = employee.gender.toUpperCase() == 'F';
    double pt;
    if (female) {
      pt = eGross < 25000 ? 0 : (isFeb ? 300 : 200);
    } else {
      if (eGross < 7500)       pt = 0;
      else if (eGross < 10000) pt = 175;
      else                     pt = isFeb ? 300 : 200;
    }
    return eGross - pf - esic - msw - pt;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build candidate items
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<SalaryDisbursementItemModel>> buildCandidateItems({
    required List<EmployeeModel> employees,
    required SalaryDataNotifier  salaryData,
    required Set<int>            alreadyDisbursedIds,
  }) async {
    final items = <SalaryDisbursementItemModel>[];

    for (final emp in employees) {
      final id = emp.id;
      if (id == null) continue;
      if (alreadyDisbursedIds.contains(id)) continue;

      final days = salaryData.getDays(id);
      final net  = _computeNetSalary(
        employee:    emp,
        days:        days,
        daysInMonth: salaryData.totalDays,
        isMsw:       salaryData.isMsw,
        isFeb:       salaryData.isFeb,
      );

      if (net <= 0) continue;
      if (emp.accountNumber.trim().isEmpty || emp.ifscCode.trim().isEmpty) {
        continue;
      }

      // ✅ Use actual branch from EmployeeModel.branch
      final String branch = emp.branch;

      items.add(SalaryDisbursementItemModel(
        disbursementId: 0,
        employeeId:     id,
        employeeName:   emp.name,
        bankName:       emp.bankDetails,   // bank name
        accountNumber:  emp.accountNumber,
        ifscCode:       emp.ifscCode,
        amount:         double.parse(net.toStringAsFixed(2)),
        sbCode:         '10',              // not used in Excel; Code column is always 10
        branch:         branch,            // actual branch
      ));
    }

    items.sort((a, b) => a.employeeName
        .trim()
        .toLowerCase()
        .compareTo(b.employeeName.trim().toLowerCase()));

    return items;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Persist a new disbursement batch (referenceNo removed)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<SalaryDisbursementModel> createDisbursement({
    required int     month,
    required int     year,
    required String  deptCode,
    required List<SalaryDisbursementItemModel> items,
  }) async {
    final model = SalaryDisbursementModel(
      month:       month,
      year:        year,
      deptCode:    deptCode,
      status:      SalaryDisbursementStatus.generated,
      generatedAt: DateTime.now().toIso8601String(),
    );
    final id = await DatabaseHelper.instance.insertSalaryDisbursement(model);
    await DatabaseHelper.instance.insertDisbursementItems(id, items);
    return model.copyWith(id: id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Generate Excel (mirrors ExcelExportService._exportBankSheet)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> generateExcel({
    required SalaryDisbursementModel           disbursement,
    required List<SalaryDisbursementItemModel> items,
    required CompanyConfigModel                config,
    required String                            monthName,
    double idbiToOther = 0.0,
    double idbiToIdbi  = 0.0,
  }) async {
    if (items.isEmpty) return null;

    final Workbook  workbook  = Workbook();
    workbook.worksheets.clear();
    final sheetName =
        'Salary-Disb-${disbursement.deptCode.replaceAll(RegExp(r'[/\\?\*:\[\]]'), '-')}';
    final Worksheet sheet = workbook.worksheets.addWithName(sheetName);

    _setColumnWidths(sheet);
    _writeTitleRow(sheet, disbursement, monthName, config);
    _writeHeaderRow(sheet);   // row 4

    int    rowIndex = 4;               // first data row will be 5
    double total    = 0;
    for (final item in items) {
      _writeDataRow(sheet, rowIndex, item, config);
      total += item.amount;
      rowIndex++;
    }
    final int lastDataRow = rowIndex;  // next row after last data

    // Outer border around the entire data table
    if (_dataTableOuterBorder) {
      final int headerRow = 4;
      final Range tableRange = sheet.getRangeByIndex(
          headerRow, _dataStartCol, lastDataRow, _dataEndCol);
      _applyBorder(tableRange);
    }

    // ── Total row ──────────────────────────────────────────────────────────
    rowIndex++;
    final int totalRowIndex = rowIndex;
    _writeTotalRow(sheet, totalRowIndex, items.isNotEmpty, total, lastDataRow);
    final int totalRowExcel = totalRowIndex + 1;

    // ── Signature image placeholder ────────────────────────────────────────
    await _insertSignatureImage(sheet, lastDataRow);

    // ── Bank Transfer Split box ────────────────────────────────────────────
    int nextRow = totalRowExcel;
    if (_includeBankSplit) {
      nextRow = _writeBankSplitSection(
        sheet,
        startRow:    totalRowExcel + _bankSplitOffset,
        baseTotal:   total,
        idbiToOther: idbiToOther,
        idbiToIdbi:  idbiToIdbi,
      );
    }

    _configurePrintSetup(sheet, nextRow);

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    // Auto-incrementing file name: Salary_Disbursement_June_2025,
    // Salary_Disbursement_June_2025_1, _2, etc.
    final fileName =
        'Salary_Disbursement_${monthName.replaceAll(' ', '_')}_${disbursement.year}';
    return _saveExcelFileWithIncrement(bytes, fileName);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Column widths (8 columns)
  // ─────────────────────────────────────────────────────────────────────────
  static void _setColumnWidths(Worksheet sheet) {
    int col = 1;
    if (_includeLeftBlankColumn) {
      sheet.getRangeByIndex(1, col).columnWidth = _colWidthBlankLeft;
      col++;
    }
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthAmount;       col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthDebitAc;      col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthIFSC;         col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthCreditAc;     col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthCode;         col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthBeneficiary;  col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthBranch;       col++; // Branch
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthBankDetails;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Title row (row 2) – spans Amount..Place (6 cols), dept code on right
  // ─────────────────────────────────────────────────────────────────────────
  static void _writeTitleRow(
    Worksheet sheet,
    SalaryDisbursementModel disbursement,
    String monthName,
    CompanyConfigModel config,
  ) {
    final int titleStartCol = _dataStartCol;
    final int titleEndCol   = titleStartCol + 5; // Amount..Place (now Branch)
    final Range titleRange  =
        sheet.getRangeByIndex(2, titleStartCol, 2, titleEndCol);
    titleRange.merge();
    titleRange.setText(
      '${config.companyName} : Salary Disbursement — $monthName ${disbursement.year}',
    );
    _applyCellStyle(titleRange,
        bold: true, fontSize: 12, hAlign: HAlignType.left);

    // Department code in the rightmost column (Bank Details)
    final Range deptRange = sheet.getRangeByIndex(2, _dataEndCol);
    deptRange.setText(disbursement.deptCode.isEmpty ? '' : disbursement.deptCode);
    _applyCellStyle(deptRange,
        bold: true, fontSize: 12, hAlign: HAlignType.right);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header row (row 4)
  // ─────────────────────────────────────────────────────────────────────────
  static void _writeHeaderRow(Worksheet sheet) {
    const headers = [
      'Amount', 'Debit A/C no.', 'IFSC', 'Credit A/c no.', 'Code',
      'Beneficiary', 'Branch', 'Bank Details',   // ✅ Branch instead of Place
    ];
    int col = _dataStartCol;
    for (final h in headers) {
      final Range cell = sheet.getRangeByIndex(4, col);
      cell.setText(h);
      _applyCellStyle(cell, bold: true, hAlign: HAlignType.center, border: true);
      col++;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Data row
  // ─────────────────────────────────────────────────────────────────────────
  static void _writeDataRow(
    Worksheet sheet,
    int rowIndex,    // rowIndex=4 writes to Excel row 5
    SalaryDisbursementItemModel item,
    CompanyConfigModel config,
  ) {
    int col = _dataStartCol;

    void set(dynamic value, {bool isNumber = false}) {
      final Range cell = sheet.getRangeByIndex(rowIndex + 1, col);
      if (value == null) {
        cell.setText('');
      } else if (isNumber) {
        cell.setNumber((value as num).toDouble());
        cell.numberFormat = '#,##0.00';
      } else {
        cell.setText(value.toString());
      }
      cell.cellStyle.hAlign = HAlignType.center;
      col++;
    }

    set(item.amount,        isNumber: true);
    set(config.accountNo);
    set(item.ifscCode);
    set(item.accountNumber);
    set('10');               // ✅ Code always 10
    set(item.employeeName);
    set(item.branch);        // ✅ Branch (actual branch)
    set(item.bankName);      // Bank Details column remains

    // Apply border to all cells in this row
    for (int c = _dataStartCol; c < col; c++) {
      _applyBorder(sheet.getRangeByIndex(rowIndex + 1, c));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Total row
  // ─────────────────────────────────────────────────────────────────────────
  static void _writeTotalRow(
    Worksheet sheet,
    int rowIndex,
    bool hasData,
    double baseTotal,
    int lastDataRow,
  ) {
    final int excelRow   = rowIndex + 1;
    final int amountCol  = _dataStartCol;

    final Range sumCell = sheet.getRangeByIndex(excelRow, amountCol);
    if (hasData) {
      final String colLetter = _colIndexToLetter(amountCol);
      sumCell.setFormula('SUM(${colLetter}5:${colLetter}$lastDataRow)');
    } else {
      sumCell.setNumber(0);
    }
    sumCell.numberFormat = '#,##0.00';
    _applyCellStyle(sumCell, bold: true, hAlign: HAlignType.center, border: true);

    // Words merged over Debit A/C, IFSC, Credit A/C (3 columns)
    final int wordsStartCol = amountCol + 1;
    final int wordsEndCol   = wordsStartCol + _wordsCellMergeCount;
    final Range wordsRange  =
        sheet.getRangeByIndex(excelRow, wordsStartCol, excelRow, wordsEndCol);
    if (_wordsCellMergeCount > 0) {
      wordsRange.merge();
    }
    wordsRange.setText(numberToWords(baseTotal));
    _applyCellStyle(wordsRange, hAlign: HAlignType.center, border: true);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Signature image placeholder (does nothing – asset path is empty)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> _insertSignatureImage(Worksheet sheet, int lastDataRow) async {
    try {
      final ByteData data = await rootBundle.load('');
      final Uint8List bytes = data.buffer.asUint8List();
      // … decode and add picture (code omitted – will fail safely)
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bank Transfer Split section
  // ─────────────────────────────────────────────────────────────────────────
  static int _writeBankSplitSection(
    Worksheet sheet, {
    required int    startRow,
    required double baseTotal,
    required double idbiToOther,
    required double idbiToIdbi,
  }) {
    int row = startRow;
    final int labelCol = _dataStartCol;
    final int valueCol = labelCol + _bankSplitColumnOffset;

    // Title
    final Range titleRange =
        sheet.getRangeByIndex(row, labelCol, row, valueCol);
    titleRange.merge();
    titleRange.setText(_bankSplitLabel);
    _applyCellStyle(titleRange,
        bold: true, fontSize: 11, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      titleRange.cellStyle.backColor = _splitBoxBgColor;
      titleRange.cellStyle.fontColor = _splitLabelColor;
    }
    row++;

    _writeSplitRow(sheet, row, labelCol, valueCol,
        'From IDBI to Other Bank', idbiToOther);
    row++;
    _writeSplitRow(sheet, row, labelCol, valueCol,
        'From IDBI to IDBI Bank', idbiToIdbi);
    row++;

    // Divider
    row++;
    final Range dividerRange =
        sheet.getRangeByIndex(row, labelCol, row, valueCol);
    dividerRange.merge();
    dividerRange.cellStyle.borders.bottom.lineStyle = LineStyle.thin;
    if (_splitBoxUseBackground) {
      dividerRange.cellStyle.borders.bottom.color = _splitLabelColor;
    }
    row++;

    // Total Base Amount
    final Range totalLabel = sheet.getRangeByIndex(row, labelCol);
    totalLabel.setText('Total Base Amount');
    _applyCellStyle(totalLabel,
        bold: true, fontSize: 12, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      totalLabel.cellStyle.backColor = _splitBoxBgColor;
      totalLabel.cellStyle.fontColor = _splitTextColor;
    }

    final Range totalValue = sheet.getRangeByIndex(row, valueCol);
    totalValue.setNumber(baseTotal);
    totalValue.numberFormat = '#,##0.00';
    _applyCellStyle(totalValue,
        bold: true, fontSize: 12, hAlign: HAlignType.right, border: true);
    if (_splitBoxUseBackground) {
      totalValue.cellStyle.backColor = _splitBoxBgColor;
      totalValue.cellStyle.fontColor = _splitTextColor;
    }

    if (_splitBoxOuterBorder) {
      final Range outerBox =
          sheet.getRangeByIndex(startRow, labelCol, row, valueCol);
      _applyBorder(outerBox);
    }

    return row;
  }

  static void _writeSplitRow(
    Worksheet sheet,
    int row,
    int labelCol,
    int valueCol,
    String label,
    double value,
  ) {
    final Range labelCell = sheet.getRangeByIndex(row, labelCol);
    labelCell.setText(label);
    _applyCellStyle(labelCell,
        fontSize: 11, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      labelCell.cellStyle.backColor = _splitBoxBgColor;
      labelCell.cellStyle.fontColor = _splitLabelColor;
    }

    final Range valueCell = sheet.getRangeByIndex(row, valueCol);
    valueCell.setNumber(value);
    valueCell.numberFormat = '#,##0.00';
    _applyCellStyle(valueCell,
        fontSize: 11, hAlign: HAlignType.right, border: true);
    if (_splitBoxUseBackground) {
      valueCell.cellStyle.backColor = _splitBoxBgColor;
      valueCell.cellStyle.fontColor = _splitValueColor;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Print setup (8 columns)
  // ─────────────────────────────────────────────────────────────────────────
  static void _configurePrintSetup(Worksheet sheet, int lastRow) {
    final int    toColumnIndex = _dataStartCol + 7;
    final String endColLetter  = _colIndexToLetter(toColumnIndex);
    sheet.pageSetup.printArea =
        '$_printStartCol$_printStartRow:$endColLetter$lastRow';
    if (_fitToPage) {
      sheet.pageSetup.fitToPagesTall = 1;
      sheet.pageSetup.fitToPagesWide = 1;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Style helpers
  // ─────────────────────────────────────────────────────────────────────────
  static void _applyCellStyle(
    Range range, {
    bool        bold     = false,
    double      fontSize = 11,
    HAlignType  hAlign   = HAlignType.left,
    bool        border   = false,
  }) {
    range.cellStyle.bold     = bold;
    range.cellStyle.fontSize = fontSize;
    range.cellStyle.hAlign   = hAlign;
    range.cellStyle.vAlign   = VAlignType.center;
    if (border) _applyBorder(range);
  }

  static void _applyBorder(Range range) {
    range.cellStyle.borders.all.lineStyle = LineStyle.thin;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Column index → letter
  // ─────────────────────────────────────────────────────────────────────────
  static String _colIndexToLetter(int index) {
    String result = '';
    int n = index;
    while (n > 0) {
      final int rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Save file with auto-increment
  //
  // Base name:  Salary_Disbursement_June_2025.xlsx
  // Subsequent: Salary_Disbursement_June_2025_1.xlsx
  //             Salary_Disbursement_June_2025_2.xlsx  …
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> _saveExcelFileWithIncrement(
      List<int> bytes, String baseName) async {
    try {
      final prefs = ExportPreferencesNotifier.instance;
      Directory? dir;

      if (prefs.excelPath.isNotEmpty) {
        final d = Directory(prefs.excelPath);
        if (await d.exists()) dir = d;
      }
      dir ??= await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();

      // First attempt: baseName.xlsx (no suffix)
      String filePath = '${dir.path}${Platform.pathSeparator}$baseName.xlsx';
      File   file     = File(filePath);

      int counter = 1;
      while (await file.exists()) {
        filePath =
            '${dir.path}${Platform.pathSeparator}${baseName}_$counter.xlsx';
        file    = File(filePath);
        counter++;
      }

      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}