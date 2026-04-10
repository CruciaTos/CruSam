import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';

/// Excel export helper. The previous implementation delegated to a Python
/// script; this file implements bank-disbursement export purely in Dart using
/// the `excel` package.
class ExcelExportService {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Exports the Tax Invoice sheet and returns the saved file path.
  static Future<String> exportTaxInvoice(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final paths = await _runGenerator(voucher, config);
    return paths.invoicePath;
  }

  /// Exports the Bank Disbursement sheet and returns the saved file path.
  /// Implemented in pure Dart using package:excel.
  static Future<String> exportBankDisbursement(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    // Create workbook
    final excel = Excel.createExcel();
    // Remove default sheet if present so workbook has only our sheet
    try {
      if (excel.tables.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    } catch (_) {}

    const sheetName = 'Bank Disbursement';

    // Layout
    final int cols = 9;

    // Borders and styles
    final thin = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black);
    final thick = Border(borderStyle: BorderStyle.Thick, borderColorHex: ExcelColor.black);

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
    );

    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
    );

    final cellStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      fontSize: 10,
    );

    final amountStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      fontSize: 10,
      numberFormat: NumFormat.standard_2,
    );

    final totalsStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
      numberFormat: NumFormat.standard_2,
    );

    final totalsWordsStyle = CellStyle(
      italic: true,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
    );

    // Title row (merged across all columns)
    final title = '${config.companyName} : ${voucher.title.isEmpty ? 'Bank Disbursement' : voucher.title}';
    excel.merge(
      sheetName,
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: cols - 1, rowIndex: 0),
      customValue: TextCellValue(title),
    );
    excel.updateCell(
      sheetName,
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      TextCellValue(title),
      cellStyle: titleStyle,
    );

    // Header
    final header = [
      'Amount',
      'Debit A/c',
      'IFSC',
      'Credit A/c',
      'S/B Code',
      'Beneficiary Name',
      'Place',
      'Bank',
      'Debit Account Name',
    ];

    int rowIndex = 1;
    for (int c = 0; c < header.length; c++) {
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex),
        TextCellValue(header[c]),
        cellStyle: headerStyle,
      );
    }

    // Data rows
    for (final r in voucher.rows) {
      rowIndex++;
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        DoubleCellValue(r.amount),
        cellStyle: amountStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        TextCellValue(config.accountNo),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
        TextCellValue(r.ifscCode),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        TextCellValue(r.accountNumber),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
        TextCellValue(r.sbCode),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex),
        TextCellValue(r.employeeName),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex),
        TextCellValue(r.branch),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex),
        TextCellValue(r.bankDetails),
        cellStyle: cellStyle,
      );
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex),
        TextCellValue(config.companyName),
        cellStyle: cellStyle,
      );
    }

    // Totals row
    rowIndex++;
    excel.updateCell(
      sheetName,
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
      DoubleCellValue(voucher.baseTotal),
      cellStyle: totalsStyle,
    );
    excel.updateCell(
      sheetName,
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
      TextCellValue(numberToWords(voucher.baseTotal)),
      cellStyle: totalsWordsStyle,
    );

    // Summary block (3 rows x 2 columns) with boxed border
    double idbiToIdbi = 0.0;
    double idbiToOther = 0.0;
    for (final r in voucher.rows) {
      final ifsc = r.ifscCode.toUpperCase();
      if (ifsc.startsWith('IDIB')) {
        idbiToIdbi += r.amount;
      } else {
        idbiToOther += r.amount;
      }
    }

    // blank spacer row
    rowIndex++;
    final summaryStart = rowIndex + 1;
    final summaryLabels = [
      'From IDBI to Other Bank',
      'From IDBI to IDBI Bank',
      'Total',
    ];
    final summaryValues = [idbiToOther, idbiToIdbi, voucher.baseTotal];

    for (int i = 0; i < summaryLabels.length; i++) {
      final rIdx = summaryStart + i;
      // left cell (label) with left/top/bottom borders as needed
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rIdx),
        TextCellValue(summaryLabels[i]),
        cellStyle: CellStyle(
          horizontalAlign: HorizontalAlign.Left,
          leftBorder: thick,
          rightBorder: thin,
          topBorder: (i == 0) ? thick : thin,
          bottomBorder: (i == summaryLabels.length - 1) ? thick : thin,
        ),
      );

      // right cell (value)
      excel.updateCell(
        sheetName,
        CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rIdx),
        DoubleCellValue(summaryValues[i]),
        cellStyle: CellStyle(
          horizontalAlign: HorizontalAlign.Right,
          leftBorder: thin,
          rightBorder: thick,
          topBorder: (i == 0) ? thick : thin,
          bottomBorder: (i == summaryLabels.length - 1) ? thick : thin,
          numberFormat: NumFormat.standard_2,
        ),
      );
    }

    // Save the file to Downloads/Documents
    final outDir = await _outputDir();
    final safeTitle = (voucher.title.trim().isEmpty) ? 'voucher' : voucher.title;
    final sanitized = safeTitle.replaceAll(RegExp(r'[<>:\"/\\|?*]'), '').replaceAll(' ', '_');
    final now = DateTime.now();
    final datePart = '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final fileName = 'bank_disbursement_${sanitized}_$datePart.xlsx';
    final file = File('${outDir}${Platform.pathSeparator}$fileName');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to generate excel bytes');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Exports BOTH sheets in a single Python call (faster) and returns
  /// [_ExportPaths] with both paths.  The public methods above call this.
  static Future<_ExportPaths> exportAll(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) => _runGenerator(voucher, config);

  // ── Core ───────────────────────────────────────────────────────────────────

  static Future<_ExportPaths> _runGenerator(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    // 1. Ensure the Python script is in a writable directory
    final scriptPath = await _ensureScript();

    // 2. Resolve the output directory (Downloads → Documents)
    final outDir = await _outputDir();

    // 3. Serialise voucher + config to a temp JSON file
    final tmpDir = await getTemporaryDirectory();
    final jsonFile = File('${tmpDir.path}/ae_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await jsonFile.writeAsString(
      jsonEncode({
        'voucher': _voucherToMap(voucher),
        'config': _configToMap(config),
      }),
    );

    try {
      // 4. Determine the Python executable
      final python = _pythonExe();

      // 5. Run the script
      final result = await Process.run(
        python,
        [scriptPath, jsonFile.path, outDir],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) {
        throw Exception(
          'excel_generator.py exited with code ${result.exitCode}.\n'
          'STDERR:\n${result.stderr}\n'
          'STDOUT:\n${result.stdout}',
        );
      }

      // 6. Parse the two output paths from stdout (one path per line)
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.length < 2) {
        throw Exception(
          'excel_generator.py produced unexpected output:\n${result.stdout}',
        );
      }

      return _ExportPaths(invoicePath: lines[0], bankPath: lines[1]);
    } finally {
      // 7. Clean up temp JSON
      try {
        await jsonFile.delete();
      } catch (_) {}
    }
  }

  // ── Script management ─────────────────────────────────────────────────────

  /// Copies the bundled asset script to the app-support directory (once) and
  /// returns its absolute path.  On subsequent calls the existing file is used.
  static Future<String> _ensureScript() async {
    final supportDir = await getApplicationSupportDirectory();
    final scriptFile = File('${supportDir.path}/excel_generator.py');

    // Always overwrite so updates to the asset are picked up.
    final assetContent = await rootBundle.loadString('assets/scripts/excel_generator.py');
    await scriptFile.writeAsString(assetContent);

    return scriptFile.path;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<String> _outputDir() async {
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
    if (Platform.isWindows) {
      return Platform.environment['PYTHON_EXE'] ?? 'python';
    }
    return Platform.environment['PYTHON_EXE'] ?? 'python3';
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

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
        'rows': v.rows
            .map((r) => {
                  'employeeName': r.employeeName,
                  'amount': r.amount,
                  'fromDate': r.fromDate,
                  'toDate': r.toDate,
                  'ifscCode': r.ifscCode,
                  'accountNumber': r.accountNumber,
                  'sbCode': r.sbCode,
                  'bankDetails': r.bankDetails,
                  'branch': r.branch,
                })
            .toList(),
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
