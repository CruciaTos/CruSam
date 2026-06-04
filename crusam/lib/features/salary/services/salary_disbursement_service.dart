// lib/features/salary/services/salary_disbursement_service.dart
//
// Mirrors ExcelExportService.exportBankDisbursement but sources
// employee bank details + final salary amounts from the salary module
// instead of voucher rows.
//
// "Final salary amount" = earned gross - total deductions (net payable).

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../models/salary_disbursement_model.dart';
import 'package:crusam/data/db/salary_disbursement_repository.dart';
import '../notifier/salary_data_notifier.dart';

// ── Column widths (same proportions as invoice bank sheet) ────────────────────

class SalaryDisbursementService {
  SalaryDisbursementService._();

  // ── Column width constants (matches ExcelExportService proportions) ───────
  static const double _colWidthAmount      = 22.0;
  static const double _colWidthBeneficiary = 26.0;
  static const double _colWidthAccountNo   = 22.0;
  static const double _colWidthIfsc        = 16.0;
  static const double _colWidthBankName    = 24.0;
  static const double _colWidthRefNo       = 20.0;
  static const double _colWidthRemarks     = 28.0;

  static const List<String> _headers = [
    'Amount',
    'Beneficiary Name',
    'Account Number',
    'IFSC Code',
    'Bank Name',
    'Reference No.',
    'Remarks',
  ];

  // ── Net salary calculation (mirrors SalaryStatementPdfService) ────────────

  static double _computeNetSalary({
    required EmployeeModel employee,
    required int days,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) {
    if (days == 0 || daysInMonth == 0) return 0;
    final eBasic  = employee.basicCharges * days / daysInMonth;
    final eGross  = employee.grossSalary  * days / daysInMonth;
    final pf      = (eBasic * 0.12).round().toDouble();
    final esic    = employee.grossSalary >= 21000
        ? 0.0
        : (eGross * 0.0075).ceilToDouble();
    final msw     = isMsw ? 6.0 : 0.0;
    final female  = employee.gender.toUpperCase() == 'F';
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

  // ── Build candidate items from current salary state ───────────────────────
  //
  // Returns items that are ELIGIBLE for disbursement (net > 0, not already
  // disbursed, have valid bank details).

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
        employee:   emp,
        days:       days,
        daysInMonth: salaryData.totalDays,
        isMsw:      salaryData.isMsw,
        isFeb:      salaryData.isFeb,
      );

      if (net <= 0) continue;
      if (emp.accountNumber.trim().isEmpty || emp.ifscCode.trim().isEmpty) continue;

      items.add(SalaryDisbursementItemModel(
        disbursementId: 0,      // filled in on persist
        employeeId:     id,
        employeeName:   emp.name,
        bankName:       emp.bankDetails,
        accountNumber:  emp.accountNumber,
        ifscCode:       emp.ifscCode,
        amount:         double.parse(net.toStringAsFixed(2)),
      ));
    }

    // Sort: dept code (via employee list order) then name
    items.sort((a, b) => a.employeeName
        .trim()
        .toLowerCase()
        .compareTo(b.employeeName.trim().toLowerCase()));

    return items;
  }

  // ── Persist a new disbursement batch ──────────────────────────────────────

  static Future<SalaryDisbursementModel> createDisbursement({
    required String  referenceNo,
    required int     month,
    required int     year,
    required String  deptCode,
    required List<SalaryDisbursementItemModel> items,
  }) async {
    final model = SalaryDisbursementModel(
      referenceNo: referenceNo,
      month:       month,
      year:        year,
      deptCode:    deptCode,
      status:      SalaryDisbursementStatus.generated,
      generatedAt: DateTime.now().toIso8601String(),
    );
    final id = await DatabaseHelper.instance
        .insertSalaryDisbursement(model);
    await DatabaseHelper.instance
        .insertDisbursementItems(id, items);
    return model.copyWith(id: id);
  }

  // ── Generate Excel (same structure as invoice bank disbursement sheet) ────

  static Future<String?> generateExcel({
    required SalaryDisbursementModel             disbursement,
    required List<SalaryDisbursementItemModel>   items,
    required CompanyConfigModel                  config,
    required String                              monthName,
  }) async {
    if (items.isEmpty) return null;

    final Workbook workbook = Workbook();
    workbook.worksheets.clear();
    final sheetName =
        'Salary-Disb-${monthName.substring(0, 3)}-${disbursement.year}';
    final Worksheet sheet = workbook.worksheets.addWithName(sheetName);

    _setColumnWidths(sheet);
    _writeTitleRow(sheet, disbursement, monthName, config);
    _writeHeaderRow(sheet);

    int rowIndex = 4;
    double total = 0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      _writeDataRow(sheet, rowIndex, i + 1, item, disbursement.referenceNo);
      total += item.amount;
      rowIndex++;
    }
    final int lastDataRow = rowIndex;

    // Total row
    rowIndex++;
    _writeTotalRow(sheet, rowIndex, total, lastDataRow);

    // Outer table border
    _applyBorder(sheet.getRangeByIndex(3, 1, lastDataRow, _headers.length));

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final fileName =
        'Salary_Disbursement_${monthName}_${disbursement.year}.xlsx';
    return _saveExcelFile(bytes, fileName);
  }

  // ── Column widths ──────────────────────────────────────────────────────────

  static void _setColumnWidths(Worksheet sheet) {
    sheet.getRangeByIndex(1, 1).columnWidth = _colWidthAmount;
    sheet.getRangeByIndex(1, 2).columnWidth = _colWidthBeneficiary;
    sheet.getRangeByIndex(1, 3).columnWidth = _colWidthAccountNo;
    sheet.getRangeByIndex(1, 4).columnWidth = _colWidthIfsc;
    sheet.getRangeByIndex(1, 5).columnWidth = _colWidthBankName;
    sheet.getRangeByIndex(1, 6).columnWidth = _colWidthRefNo;
    sheet.getRangeByIndex(1, 7).columnWidth = _colWidthRemarks;
  }

  static void _writeTitleRow(
    Worksheet sheet,
    SalaryDisbursementModel disbursement,
    String monthName,
    CompanyConfigModel config,
  ) {
    final Range titleRange =
        sheet.getRangeByIndex(1, 1, 1, _headers.length);
    titleRange.merge();
    titleRange.setText(
      '${config.companyName} : Salary Disbursement — $monthName ${disbursement.year}',
    );
    titleRange.cellStyle.bold     = true;
    titleRange.cellStyle.fontSize = 12;
    titleRange.cellStyle.hAlign   = HAlignType.left;
    // Reference No in last column header area
    sheet.getRangeByIndex(2, _headers.length).setText(
      disbursement.referenceNo.isEmpty ? '' : 'Ref: ${disbursement.referenceNo}',
    );
    sheet.getRangeByIndex(2, _headers.length).cellStyle.hAlign =
        HAlignType.right;
  }

  static void _writeHeaderRow(Worksheet sheet) {
    for (int i = 0; i < _headers.length; i++) {
      final cell = sheet.getRangeByIndex(3, i + 1);
      cell.setText(_headers[i]);
      cell.cellStyle.bold      = true;
      cell.cellStyle.hAlign    = HAlignType.center;
      cell.cellStyle.vAlign    = VAlignType.center;
      cell.cellStyle.backColor = '#E3E8F4';
      _applyBorder(cell);
    }
    sheet.getRangeByIndex(3, 1, 3, _headers.length).rowHeight = 30;
  }

  static void _writeDataRow(
    Worksheet sheet,
    int rowIndex,
    int srNo,
    SalaryDisbursementItemModel item,
    String referenceNo,
  ) {
    void set(int col, dynamic value,
        {bool isNumber = false, HAlignType align = HAlignType.left}) {
      final cell = sheet.getRangeByIndex(rowIndex, col);
      if (isNumber) {
        cell.setNumber((value as num).toDouble());
        cell.numberFormat = '#,##0.00';
      } else {
        cell.setText(value?.toString() ?? '');
      }
      cell.cellStyle.hAlign = align;
      cell.cellStyle.vAlign = VAlignType.center;
      _applyBorder(cell);
    }

    set(1, item.amount,        isNumber: true, align: HAlignType.right);
    set(2, item.employeeName,  align: HAlignType.left);
    set(3, item.accountNumber, align: HAlignType.center);
    set(4, item.ifscCode,      align: HAlignType.center);
    set(5, item.bankName,      align: HAlignType.left);
    set(6, referenceNo,        align: HAlignType.center);
    set(7, 'Salary ${item.employeeName}', align: HAlignType.left);
  }

  static void _writeTotalRow(
      Worksheet sheet, int rowIndex, double total, int lastDataRow) {
    final labelCell = sheet.getRangeByIndex(rowIndex, 2);
    labelCell.setText('TOTAL :-');
    labelCell.cellStyle.bold   = true;
    labelCell.cellStyle.hAlign = HAlignType.left;

    final amtCell = sheet.getRangeByIndex(rowIndex, 1);
    amtCell.setFormula('SUM(A4:A$lastDataRow)');
    amtCell.numberFormat      = '#,##0.00';
    amtCell.cellStyle.bold    = true;
    amtCell.cellStyle.hAlign  = HAlignType.right;

    final rowRange = sheet.getRangeByIndex(rowIndex, 1, rowIndex, _headers.length);
    rowRange.cellStyle.bold      = true;
    rowRange.cellStyle.backColor = '#D6DCF5';
    _applyBorder(rowRange);
  }

  static void _applyBorder(Range range) {
    range.cellStyle.borders.all.lineStyle = LineStyle.thin;
    range.cellStyle.borders.all.color     = '#000000';
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  static Future<String?> _saveExcelFile(
      List<int> bytes, String fileName) async {
    try {
      final prefs = ExportPreferencesNotifier.instance;
      Directory? dir;

      if (prefs.excelPath.isNotEmpty) {
        final d = Directory(prefs.excelPath);
        if (await d.exists()) dir = d;
      }
      dir ??= await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();

      final path = '${dir.path}${Platform.pathSeparator}$fileName';
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }
}