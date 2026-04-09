import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';

/// Generates pixel-perfect Excel files by delegating to a bundled Python
/// script (excel_generator.py) that uses openpyxl.
///
/// Setup:
///   1. Add  assets/scripts/excel_generator.py  to your pubspec.yaml:
///        flutter:
///          assets:
///            - assets/scripts/excel_generator.py
///   2. Ensure Python 3 is available on the host machine.
///      On the target Windows machine run once:  pip install openpyxl
///   3. Replace the old ExcelExportService with this file.
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
  static Future<String> exportBankDisbursement(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final paths = await _runGenerator(voucher, config);
    return paths.bankPath;
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
    final tmpDir    = await getTemporaryDirectory();
    final jsonFile  = File('${tmpDir.path}/ae_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await jsonFile.writeAsString(
      jsonEncode({
        'voucher': _voucherToMap(voucher),
        'config':  _configToMap(config),
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
      try { await jsonFile.delete(); } catch (_) {}
    }
  }

  // ── Script management ─────────────────────────────────────────────────────

  /// Copies the bundled asset script to the app-support directory (once) and
  /// returns its absolute path.  On subsequent calls the existing file is used.
  static Future<String> _ensureScript() async {
    final supportDir = await getApplicationSupportDirectory();
    final scriptFile = File('${supportDir.path}/excel_generator.py');

    // Always overwrite so updates to the asset are picked up.
    final assetContent = await rootBundle.loadString(
        'assets/scripts/excel_generator.py');
    await scriptFile.writeAsString(assetContent);

    return scriptFile.path;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<String> _outputDir() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? '.';
      final dl   = Directory('$home\\Downloads');
      if (await dl.exists()) return dl.path;
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      final dl   = Directory('$home/Downloads');
      if (await dl.exists()) return dl.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  static String _pythonExe() {
    if (Platform.isWindows) {
      // Try 'python' first (Microsoft Store Python uses 'python3.exe' alias).
      // Callers can also set a PYTHON_EXE env var to override.
      return Platform.environment['PYTHON_EXE'] ?? 'python';
    }
    return Platform.environment['PYTHON_EXE'] ?? 'python3';
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _voucherToMap(VoucherModel v) => {
    'billNo':          v.billNo,
    'poNo':            v.poNo,
    'clientName':      v.clientName,
    'clientAddress':   v.clientAddress,
    'clientGstin':     v.clientGstin,
    'date':            v.date,
    'title':           v.title,
    'deptCode':        v.deptCode,
    'itemDescription': v.itemDescription,
    'baseTotal':       v.baseTotal,
    'cgst':            v.cgst,
    'sgst':            v.sgst,
    'totalTax':        v.totalTax,
    'roundOff':        v.roundOff,
    'finalTotal':      v.finalTotal,
    'rows': v.rows.map((r) => {
      'employeeName':  r.employeeName,
      'amount':        r.amount,
      'fromDate':      r.fromDate,
      'toDate':        r.toDate,
      'ifscCode':      r.ifscCode,
      'accountNumber': r.accountNumber,
      'sbCode':        r.sbCode,
      'bankDetails':   r.bankDetails,
      'branch':        r.branch,
    }).toList(),
  };

  static Map<String, dynamic> _configToMap(CompanyConfigModel c) => {
    'companyName':     c.companyName,
    'address':         c.address,
    'gstin':           c.gstin,
    'pan':             c.pan,
    'jurisdiction':    c.jurisdiction,
    'declarationText': c.declarationText,
    'bankName':        c.bankName,
    'branch':          c.branch,
    'accountNo':       c.accountNo,
    'ifscCode':        c.ifscCode,
    'phone':           c.phone,
  };
}

class _ExportPaths {
  final String invoicePath;
  final String bankPath;
  const _ExportPaths({required this.invoicePath, required this.bankPath});
}