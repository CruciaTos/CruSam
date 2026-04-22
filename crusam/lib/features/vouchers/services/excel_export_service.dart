import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';

/// Excel export helper. Uses Syncfusion XlsIO for bank disbursement sheets,
/// and a Python script for tax invoices (legacy).
class ExcelExportService {
  // ─────────────────────────────────────────────────────────────────────────────
  // 📌 BLANK LEFT COLUMN CONFIGURATION – EDIT THESE VALUES AS NEEDED
  // ─────────────────────────────────────────────────────────────────────────────
  static const bool _includeLeftBlankColumn = true;
  static const double _colWidthBlankLeft   = 3.0;

  // ─────────────────────────────────────────────────────────────────────────────
  // 🎯 COLUMN WIDTH CONFIGURATION (in Excel character units)
  // ─────────────────────────────────────────────────────────────────────────────
  static const double _colWidthAmount      = 22.0;
  static const double _colWidthDebitAc     = 20.0;
  static const double _colWidthIFSC        = 14.0;
  static const double _colWidthCreditAc    = 20.0;
  static const double _colWidthCode        = 10.0;
  static const double _colWidthBeneficiary = 22.0;
  static const double _colWidthPlace       = 29.0;
  static const double _colWidthBankDetails = 25.0;

  // ─────────────────────────────────────────────────────────────────────────────
  // 🖼️ SIGNATURE IMAGE CONFIGURATION
  // ─────────────────────────────────────────────────────────────────────────────
  static const int _signatureColOffset = 8;
  static const int _signatureRowOffset = 12;
  static const int _signatureSize      = 0;

  // ─────────────────────────────────────────────────────────────────────────────
  // 🖨️ PRINT AREA & PAGE SETUP
  // ─────────────────────────────────────────────────────────────────────────────
  static const String _printStartColumn = 'A';
  static const int    _printStartRow    = 1;
  static const bool   _fitToPage        = true;

  // ─────────────────────────────────────────────────────────────────────────────
  // 📊 BANK SPLIT SUMMARY CONFIGURATION
  // ─────────────────────────────────────────────────────────────────────────────
  static const bool _includeBankSplit = true;
  static const int _bankSplitOffset   = 2;
  static const String _bankSplitLabel = 'BANK TRANSFER SPLIT';
  static const bool _splitBoxUseBackground = false;
  static const bool _splitBoxOuterBorder = true;
  static const String _splitBoxBgColor   = '#FF1E293B';
  static const String _splitTextColor    = '#FFFFFFFF';
  static const String _splitLabelColor   = '#FF94A3B8';
  static const String _splitValueColor   = '#FFCBD5E1';
  static const int _bankSplitColumnOffset = 3;

  // ─────────────────────────────────────────────────────────────────────────────
  // 🔲 DATA TABLE OUTER BORDER
  // ─────────────────────────────────────────────────────────────────────────────
  static const bool _dataTableOuterBorder = true;

  // ─────────────────────────────────────────────────────────────────────────────
  // 📏 TOTAL IN WORDS CELL MERGING
  // ─────────────────────────────────────────────────────────────────────────────
  static const int _wordsCellMergeCount = 2;

  static int get _dataStartCol => _includeLeftBlankColumn ? 2 : 1;

  // ── Public API ─────────────────────────────────────────────────────────────

  static Future<String> exportTaxInvoice(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final paths = await _runGenerator(
      voucher,
      config,
      outputTarget: ExportPathTarget.taxInvoiceExcel,
    );
    return paths.invoicePath;
  }

  static Future<String> exportBankDisbursement(
    VoucherModel voucher,
    CompanyConfigModel config, {
    double idbiToOther = 0.0,
    double idbiToIdbi = 0.0,
  }) async {
    return _exportBankSheet(voucher, config,
        idbiToOther: idbiToOther, idbiToIdbi: idbiToIdbi);
  }

  static Future<_ExportPaths> exportAll(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) => _runGenerator(
        voucher,
        config,
        outputTarget: ExportPathTarget.taxInvoiceExcel,
      );

  // ── Bank Sheet ──────────────────────────────────────────────────────────────

  static Future<String> _exportBankSheet(
    VoucherModel voucher,
    CompanyConfigModel config, {
    required double idbiToOther,
    required double idbiToIdbi,
  }) async {
    final Workbook workbook = Workbook();
    workbook.worksheets.clear();
    final sheetName =
        'Bill-Data-${voucher.deptCode.replaceAll(RegExp(r'[/\\?\*:\[\]]'), '-')}';
    final Worksheet sheet = workbook.worksheets.addWithName(sheetName);

    _setColumnWidths(sheet);
    _writeTitleRow(sheet, voucher, config);
    _writeHeaderRow(sheet);

    final sortedRows = [...voucher.rows]..sort((a, b) {
        if (a.fromDate.isEmpty && b.fromDate.isEmpty) return 0;
        if (a.fromDate.isEmpty) return 1;
        if (b.fromDate.isEmpty) return -1;
        return a.fromDate.compareTo(b.fromDate);
      });

    int rowIndex = 4;
    for (final r in sortedRows) {
      _writeDataRow(sheet, rowIndex, r, config);
      rowIndex++;
    }
    final int lastDataRow = rowIndex;

    if (_dataTableOuterBorder) {
      final int headerRow = 4;
      final int startCol = _dataStartCol;
      final int endCol = startCol + 7; // 8 columns (indices 0..7)
      final Range tableRange = sheet.getRangeByIndex(headerRow, startCol, lastDataRow, endCol);
      _applyBorder(tableRange);
    }

    rowIndex++;
    final int totalRowIndex = rowIndex;
    _writeTotalRow(sheet, totalRowIndex, sortedRows.isNotEmpty, voucher.baseTotal, lastDataRow);
    final int totalRowExcel = totalRowIndex + 1;

    await _insertSignatureImage(sheet, lastDataRow);

    int nextRow = totalRowExcel;
    if (_includeBankSplit) {
      nextRow = _writeBankSplitSection(
        sheet,
        startRow: totalRowExcel + _bankSplitOffset,
        baseTotal: voucher.baseTotal,
        idbiToOther: idbiToOther,
        idbiToIdbi: idbiToIdbi,
      );
    }

    _configurePrintSetup(sheet, _includeBankSplit ? nextRow : totalRowExcel);

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    return await _saveExcelFileWithIncrement(
      bytes,
      voucher,
      'bank_disbursement',
      outputTarget: ExportPathTarget.bankDisbursementExcel,
    );
  }

  // ── Column widths ──────────────────────────────────────────────────────────

  static void _setColumnWidths(Worksheet sheet) {
    int col = 1;
    if (_includeLeftBlankColumn) {
      sheet.getRangeByIndex(1, col).columnWidth = _colWidthBlankLeft;
      col++;
    }
    // 8 columns: Amount, Debit A/C, IFSC, Credit A/C, Code, Beneficiary, Place, Bank Details
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthAmount;      col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthDebitAc;     col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthIFSC;        col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthCreditAc;    col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthCode;        col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthBeneficiary; col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthPlace;       col++;
    sheet.getRangeByIndex(1, col).columnWidth = _colWidthBankDetails;
  }

  static void _writeTitleRow(Worksheet sheet, VoucherModel voucher,
      CompanyConfigModel config) {
    // Title spans from start column to the 6th data column (Place)
    final int titleStartCol = _dataStartCol;
    final int titleEndCol = titleStartCol + 5; // columns: Amount..Place (6 columns)
    final Range titleRange = sheet.getRangeByIndex(2, titleStartCol, 2, titleEndCol);
    titleRange.merge();
    final titleText =
        '${config.companyName} : ${voucher.title.isEmpty ? 'Expenses Statement' : voucher.title}';
    titleRange.setText(titleText);
    _applyCellStyle(titleRange, bold: true, fontSize: 12, hAlign: HAlignType.left);

    // Department code in the rightmost column (Bank Details)
    final int deptCol = _dataStartCol + 7; // Bank Details column
    final Range deptRange = sheet.getRangeByIndex(2, deptCol);
    deptRange.setText(voucher.deptCode);
    _applyCellStyle(deptRange, bold: true, fontSize: 12, hAlign: HAlignType.right);
  }

  static void _writeHeaderRow(Worksheet sheet) {
    const headers = [
      'Amount', 'Debit A/C no.', 'IFSC', 'Credit A/c no.', 'Code',
      'Beneficiary', 'Place', 'Bank Details',
    ];
    final int row = 4;
    int col = _dataStartCol;
    for (int i = 0; i < headers.length; i++) {
      final Range cell = sheet.getRangeByIndex(row, col);
      cell.setText(headers[i]);
      _applyCellStyle(cell, bold: true, hAlign: HAlignType.center, border: true);
      col++;
    }
  }

  static void _writeDataRow(
    Worksheet sheet,
    int rowIndex,
    dynamic r,
    CompanyConfigModel config,
  ) {
    int col = _dataStartCol;

    _setCellValue(sheet, rowIndex, col, r.amount, isNumber: true, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, config.accountNo, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.ifscCode, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.accountNumber, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.sbCode, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.employeeName, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.branch, hAlign: HAlignType.center); col++;
    _setCellValue(sheet, rowIndex, col, r.bankDetails, hAlign: HAlignType.center);

    for (int c = _dataStartCol; c < col; c++) {
      _applyBorder(sheet.getRangeByIndex(rowIndex + 1, c));
    }
  }

  static void _setCellValue(Worksheet sheet, int rowIndex, int col, dynamic value,
      {bool isNumber = false, HAlignType? hAlign}) {
    final Range cell = sheet.getRangeByIndex(rowIndex + 1, col);
    if (value == null) {
      cell.setText('');
    } else if (isNumber) {
      cell.setNumber(value.toDouble());
      cell.numberFormat = '#,##0.00';
    } else {
      cell.setText(value.toString());
    }
    cell.cellStyle.hAlign = hAlign ?? HAlignType.center;
  }

  static void _writeTotalRow(Worksheet sheet, int rowIndex, bool hasData, double baseTotal, int lastDataRow) {
    final int excelRow = rowIndex + 1;
    final int amountCol = _dataStartCol;

    final Range sumCell = sheet.getRangeByIndex(excelRow, amountCol);
    if (hasData) {
      sumCell.setFormula('SUM(${_colIndexToLetter(amountCol)}5:${_colIndexToLetter(amountCol)}$lastDataRow)');
    } else {
      sumCell.setNumber(0);
    }
    _applyCellStyle(sumCell, bold: true, hAlign: HAlignType.center, border: true);

    final int wordsStartCol = amountCol + 1;
    final int wordsEndCol = wordsStartCol + _wordsCellMergeCount;
    final Range wordsRange = sheet.getRangeByIndex(excelRow, wordsStartCol, excelRow, wordsEndCol);
    if (_wordsCellMergeCount > 0) {
      wordsRange.merge();
    }
    wordsRange.setText(numberToWords(baseTotal));
    _applyCellStyle(wordsRange, hAlign: HAlignType.center, border: true);
  }

  static String _colIndexToLetter(int index) {
    String result = '';
    int n = index;
    while (n > 0) {
      int rem = (n - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }
    return result;
  }

  static int _writeBankSplitSection(
    Worksheet sheet, {
    required int startRow,
    required double baseTotal,
    required double idbiToOther,
    required double idbiToIdbi,
  }) {
    int row = startRow;
    final int labelCol = _dataStartCol;
    final int valueCol = labelCol + _bankSplitColumnOffset;

    final Range titleRange = sheet.getRangeByIndex(row, labelCol, row, valueCol);
    titleRange.merge();
    titleRange.setText(_bankSplitLabel);
    _applyCellStyle(titleRange, bold: true, fontSize: 11, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      titleRange.cellStyle.backColor = _splitBoxBgColor;
      titleRange.cellStyle.fontColor = _splitLabelColor;
    }
    row++;

    _writeSplitRow(sheet, row, labelCol, valueCol, 'From IDBI to Other Bank', idbiToOther);
    row++;
    _writeSplitRow(sheet, row, labelCol, valueCol, 'From IDBI to IDBI Bank', idbiToIdbi);
    row++;
    row++;
    final Range dividerRange = sheet.getRangeByIndex(row, labelCol, row, valueCol);
    dividerRange.merge();
    dividerRange.cellStyle.borders.bottom.lineStyle = LineStyle.thin;
    if (_splitBoxUseBackground) {
      dividerRange.cellStyle.borders.bottom.color = _splitLabelColor;
    }
    row++;
    final Range totalLabel = sheet.getRangeByIndex(row, labelCol);
    totalLabel.setText('Total Base Amount');
    _applyCellStyle(totalLabel, bold: true, fontSize: 12, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      totalLabel.cellStyle.backColor = _splitBoxBgColor;
      totalLabel.cellStyle.fontColor = _splitTextColor;
    }
    final Range totalValue = sheet.getRangeByIndex(row, valueCol);
    totalValue.setNumber(baseTotal);
    totalValue.numberFormat = '#,##0.00';
    _applyCellStyle(totalValue, bold: true, fontSize: 12, hAlign: HAlignType.right, border: true);
    if (_splitBoxUseBackground) {
      totalValue.cellStyle.backColor = _splitBoxBgColor;
      totalValue.cellStyle.fontColor = _splitTextColor;
    }
    if (_splitBoxOuterBorder) {
      final Range outerBox = sheet.getRangeByIndex(startRow, labelCol, row, valueCol);
      _applyBorder(outerBox);
    }
    return row;
  }

  static void _writeSplitRow(Worksheet sheet, int row, int labelCol, int valueCol,
      String label, double value) {
    final Range labelCell = sheet.getRangeByIndex(row, labelCol);
    labelCell.setText(label);
    _applyCellStyle(labelCell, fontSize: 11, hAlign: HAlignType.left, border: true);
    if (_splitBoxUseBackground) {
      labelCell.cellStyle.backColor = _splitBoxBgColor;
      labelCell.cellStyle.fontColor = _splitLabelColor;
    }
    final Range valueCell = sheet.getRangeByIndex(row, valueCol);
    valueCell.setNumber(value);
    valueCell.numberFormat = '#,##0.00';
    _applyCellStyle(valueCell, fontSize: 11, hAlign: HAlignType.right, border: true);
    if (_splitBoxUseBackground) {
      valueCell.cellStyle.backColor = _splitBoxBgColor;
      valueCell.cellStyle.fontColor = _splitValueColor;
    }
  }

  static Future<void> _insertSignatureImage(Worksheet sheet, int lastDataRow) async {
    try {
      final ByteData data = await rootBundle.load('');
      final Uint8List bytes = data.buffer.asUint8List();

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final int naturalWidth = frameInfo.image.width;
      final int naturalHeight = frameInfo.image.height;
      frameInfo.image.dispose();
      codec.dispose();

      final int startCol = _dataStartCol + _signatureColOffset;
      final int imageRow = lastDataRow + _signatureRowOffset;

      double targetWidthPx;
      if (_signatureSize == 0) {
        targetWidthPx = 200.0; // fallback width
      } else {
        targetWidthPx = _signatureSize.toDouble();
      }

      final double aspectRatio = naturalHeight / naturalWidth;
      final int targetHeightPx = (targetWidthPx * aspectRatio).round();

      final Picture picture = sheet.pictures.addBase64(
        imageRow,
        startCol,
        base64.encode(bytes),
      );
      picture.height = targetHeightPx;
      picture.width = targetWidthPx.round();
    } catch (_) {
      // Asset not found or decode failed – skip
    }
  }

  static void _configurePrintSetup(Worksheet sheet, int lastRow) {
    final int toColumnIndex = _dataStartCol + 7; // 8 columns (0..7)
    final String endColLetter = _colIndexToLetter(toColumnIndex);
    final String printArea = '$_printStartColumn$_printStartRow:$endColLetter$lastRow';
    sheet.pageSetup.printArea = printArea;
    if (_fitToPage) {
      sheet.pageSetup.fitToPagesTall = 1;
      sheet.pageSetup.fitToPagesWide = 1;
    }
  }

  // ── Style helpers ──────────────────────────────────────────────────────────
  static void _applyCellStyle(Range range,
      {bool bold = false,
      double fontSize = 11,
      HAlignType hAlign = HAlignType.left,
      bool border = false}) {
    range.cellStyle.bold = bold;
    range.cellStyle.fontSize = fontSize;
    range.cellStyle.hAlign = hAlign;
    if (border) _applyBorder(range);
  }

  static void _applyBorder(Range range) {
    range.cellStyle.borders.all.lineStyle = LineStyle.thin;
  }

  // ── Month name from voucher date (YYYY-MM-DD) ──────────────────────────────
  static String _monthFromDate(String date) {
    if (date.isEmpty) return '';
    try {
      final dt = DateTime.parse(date);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return months[dt.month - 1];
    } catch (_) {
      return '';
    }
  }

  // ── File saving with auto‑increment ───────────────────────────────────────
  static Future<String> _saveExcelFileWithIncrement(
    List<int> bytes,
    VoucherModel voucher,
    String prefix, {
    ExportPathTarget? outputTarget,
  }) async {
    final outDir = await _outputDir(outputTarget);
    final safeTitle = (voucher.title.trim().isEmpty ? 'voucher' : voucher.title)
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(' ', '_');
    final now = DateTime.now();
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    String baseName = '${prefix}_${safeTitle}_$datePart';
    String filePath = '$outDir${Platform.pathSeparator}$baseName.xlsx';
    File file = File(filePath);

    int counter = 1;
    while (await file.exists()) {
      filePath = '$outDir${Platform.pathSeparator}${baseName}_$counter.xlsx';
      file = File(filePath);
      counter++;
    }

    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ── Python‑based invoice export (unchanged) ────────────────────────────────
  static Future<_ExportPaths> _runGenerator(
    VoucherModel voucher,
    CompanyConfigModel config,
    {ExportPathTarget? outputTarget}
  ) async {
    final scriptPath = await _ensureScript();
    final outDir = await _outputDir(outputTarget);
    final tmpDir = await getTemporaryDirectory();
    final jsonFile = File('${tmpDir.path}/ae_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await jsonFile.writeAsString(jsonEncode({
      'voucher': _voucherToMap(voucher),
      'config': _configToMap(config),
    }));
    try {
      final python = _pythonExe();
      final result = await Process.run(python, [scriptPath, jsonFile.path, outDir],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      if (result.exitCode != 0) {
        throw Exception('excel_generator.py error:\n${result.stderr}');
      }
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length < 2) throw Exception('Unexpected output from excel_generator.py');
      return _ExportPaths(invoicePath: lines[0], bankPath: lines[1]);
    } finally {
      try { await jsonFile.delete(); } catch (_) {}
    }
  }

  static Future<String> _ensureScript() async {
    final supportDir = await getApplicationSupportDirectory();
    final scriptFile = File('${supportDir.path}/excel_generator.py');
    final assetContent = await rootBundle.loadString('assets/scripts/excel_generator.py');
    await scriptFile.writeAsString(assetContent);
    return scriptFile.path;
  }

  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    if (iso.length == 10 && iso.contains('-')) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static Future<String> _outputDir([ExportPathTarget? target]) async {
    final savedPath = target != null
        ? ExportPreferencesNotifier.instance.resolvedPathForTarget(target)
        : ExportPreferencesNotifier.instance.excelPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir.path;
    }

    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '.';
      final dl = Directory('$home\\Downloads');
      if (await dl.exists()) return dl.path;
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      final dl = Directory('$home/Downloads');
      if (await dl.exists()) return dl.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  static String _pythonExe() {
    if (Platform.isWindows) return Platform.environment['PYTHON_EXE'] ?? 'python';
    return Platform.environment['PYTHON_EXE'] ?? 'python3';
  }

  static Map<String, dynamic> _voucherToMap(VoucherModel v) => {
        'billNo': v.billNo,
        'poNo': v.poNo,
        'clientName': v.clientName,
        'clientAddress': v.clientAddress,
        'clientGstin': v.clientGstin,
        'date': v.date,
        'title': v.title,
        'deptCode': v.deptCode,
        'itemDescription': v.itemDescription,
        'baseTotal': v.baseTotal,
        'cgst': v.cgst,
        'sgst': v.sgst,
        'totalTax': v.totalTax,
        'roundOff': v.roundOff,
        'finalTotal': v.finalTotal,
        'rows': v.rows.map((r) => {
          'employeeName': r.employeeName,
          'amount': r.amount,
          'fromDate': r.fromDate,
          'toDate': r.toDate,
          'ifscCode': r.ifscCode,
          'accountNumber': r.accountNumber,
          'sbCode': r.sbCode,
          'bankDetails': r.bankDetails,
          'branch': r.branch,
        }).toList(),
      };

  static Map<String, dynamic> _configToMap(CompanyConfigModel c) => {
        'companyName': c.companyName,
        'address': c.address,
        'gstin': c.gstin,
        'pan': c.pan,
        'jurisdiction': c.jurisdiction,
        'declarationText': c.declarationText,
        'bankName': c.bankName,
        'branch': c.branch,
        'accountNo': c.accountNo,
        'ifscCode': c.ifscCode,
        'phone': c.phone,
      };
}

class _ExportPaths {
  final String invoicePath;
  final String bankPath;
  const _ExportPaths({required this.invoicePath, required this.bankPath});
}