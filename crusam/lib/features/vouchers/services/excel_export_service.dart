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
  /// Format matches the reference Excel: no header row, data starts at B3,
  /// from/to date columns (K/L), SUM formula total row.
  static Future<String> exportBankDisbursement(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final excel = Excel.createExcel();
    try {
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    } catch (_) {}

    // Sheet name: "Bill-Data-{deptCode}"
    final sheetName =
        'Bill-Data-${voucher.deptCode.replaceAll(RegExp(r'[/\\?\*:\[\]]'), '-')}';

    // ── Styles ──────────────────────────────────────────────────────────────
    final bold11   = CellStyle(bold: true, fontSize: 11);
    final norm11   = CellStyle(fontSize: 11);
    final ctr11    = CellStyle(fontSize: 11, horizontalAlign: HorizontalAlign.Center);
    final boldLeft = CellStyle(bold: true, fontSize: 11, horizontalAlign: HorizontalAlign.Left);

    // ── Row 2 (rowIdx 1): Title at B2, dept code at I2 ──────────────────────
    final title =
        '${config.companyName} : ${voucher.title.isEmpty ? 'Expenses Statement' : voucher.title}';
    _set(excel, sheetName, 1, 1, TextCellValue(title), bold11);
    _set(excel, sheetName, 8, 1, TextCellValue(voucher.deptCode), bold11);

    // ── Sort rows by fromDate ─────────────────────────────────────────────────
    final rows = [...voucher.rows]..sort((a, b) {
        if (a.fromDate.isEmpty && b.fromDate.isEmpty) return 0;
        if (a.fromDate.isEmpty) return 1;
        if (b.fromDate.isEmpty) return -1;
        return a.fromDate.compareTo(b.fromDate);
      });

    // ── Data rows: rowIdx 2 → Excel row 3 ────────────────────────────────────
    // Columns (all start at B = colIdx 1):
    //  B(1)=Amount  C(2)=DebitAc  D(3)=IFSC     E(4)=CreditAc  F(5)=Code
    //  G(6)=Name    H(7)=Place    I(8)=BankDet  J(9)=DebitName
    //  K(10)=From   L(11)=To
    int rowIdx = 2;
    for (final r in rows) {
      _set(excel, sheetName,  1, rowIdx, DoubleCellValue(r.amount),                    norm11);
      _set(excel, sheetName,  2, rowIdx, TextCellValue(config.accountNo),              ctr11);
      _set(excel, sheetName,  3, rowIdx, TextCellValue(r.ifscCode),                    ctr11);
      _set(excel, sheetName,  4, rowIdx, TextCellValue(r.accountNumber),               ctr11);
      _set(excel, sheetName,  5, rowIdx, TextCellValue(r.sbCode),                      ctr11);
      _set(excel, sheetName,  6, rowIdx, TextCellValue(r.employeeName),                norm11);
      _set(excel, sheetName,  7, rowIdx, TextCellValue(r.branch),                      ctr11);
      _set(excel, sheetName,  8, rowIdx, TextCellValue(r.bankDetails),                 norm11);
      _set(excel, sheetName,  9, rowIdx, TextCellValue(config.companyName.toLowerCase()), ctr11);
      _set(excel, sheetName, 10, rowIdx, TextCellValue(_fmtDate(r.fromDate)),          ctr11);
      _set(excel, sheetName, 11, rowIdx, TextCellValue(_fmtDate(r.toDate)),            ctr11);
      rowIdx++;
    }

    // ── Total row ─────────────────────────────────────────────────────────────
    // rowIdx is now (2 + n). Last data Excel row = rowIdx (0-indexed rowIdx-1 → 1-indexed = rowIdx).
    // SUM range: B3:B{rowIdx}
    _set(excel, sheetName, 1, rowIdx,
        FormulaCellValue('SUM(B3:B$rowIdx)'), bold11);
    _set(excel, sheetName, 2, rowIdx,
        TextCellValue(numberToWords(voucher.baseTotal)), boldLeft);

    // ── Save ──────────────────────────────────────────────────────────────────
    final outDir   = await _outputDir();
    final safe     = (voucher.title.trim().isEmpty ? 'voucher' : voucher.title)
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(' ', '_');
    final now      = DateTime.now();
    final datePart = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final file     = File('${outDir}${Platform.pathSeparator}bank_disbursement_${safe}_$datePart.xlsx');

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

  static void _set(
    Excel excel,
    String sheet,
    int col,
    int row,
    CellValue value,
    CellStyle style,
  ) {
    excel.updateCell(
      sheet,
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      value,
      cellStyle: style,
    );
  }

  /// Converts ISO date (yyyy-MM-dd) → DD/MM/YYYY for Excel cells.
  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    if (iso.length == 10 && iso.contains('-')) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

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