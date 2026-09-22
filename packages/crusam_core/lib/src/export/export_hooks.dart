// The few things document generation needs from its host. The Flutter app
// wires these to rootBundle / DatabaseHelper / the Export Paths settings /
// the live salary notifiers (see crusam/lib/main.dart); the MCP server wires
// them to files next to server.exe and to its own database connection.

import 'dart:typed_data';

import '../models/bank_column_widths_model.dart';
import '../models/margin_settings_model.dart';
import '../models/voucher_column_widths_model.dart';

/// Which Export Paths folder a document goes to.
enum ExportPathTarget {
  taxInvoice,                // Tax Invoice & Voucher PDF
  salary,                    // Salary Documents PDF
  general,                   // Fallback (uses general PDF path)
  salaryStatementExcel,      // Salary Statement Excel (monthly statement)
  taxInvoiceExcel,           // Tax Invoice Excel (generated via Python)
  bankDisbursementExcel;     // Bank Disbursement Excel sheet

  /// Returns true for PDF targets, false for Excel targets.
  bool get usesPdfDefaults =>
      this != salaryStatementExcel &&
      this != taxInvoiceExcel &&
      this != bankDisbursementExcel;
}

typedef PdfSaver = Future<String> Function(
  Uint8List bytes, {
  required String fileName,
  required ExportPathTarget target,
});

class ExportHooks {
  ExportHooks._();

  /// Loads a bundled asset such as 'assets/fonts/NotoSans-Regular.ttf'.
  static Future<ByteData> Function(String path) loadAsset = (path) =>
      throw StateError('ExportHooks.loadAsset is not configured ($path)');

  /// The saved PDF margin setting.
  static Future<MarginSettings> Function() margins =
      () async => const MarginSettings();

  static Future<VoucherColumnWidthsSettings> Function() voucherColumnWidths =
      () async => const VoucherColumnWidthsSettings();

  static Future<BankColumnWidthsSettings> Function() bankColumnWidths =
      () async => const BankColumnWidthsSettings();

  /// Writes a PDF to the folder for [target]; returns the path written.
  static PdfSaver savePdf = (bytes, {required fileName, required target}) =>
      throw StateError('ExportHooks.savePdf is not configured');

  /// Attendance (employee id → days) of the salary month open in the app.
  /// Only used when a caller does not pass attendance explicitly.
  static int Function(int employeeId) liveSalaryDaysFor = (id) =>
      throw StateError('No attendance given and no live salary data available');

  static double Function() liveMswAmount = () => 6;

  /// A bill number made safe for a file name; a timestamp when empty.
  static String slug(String billNo) => billNo.trim().isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
}
