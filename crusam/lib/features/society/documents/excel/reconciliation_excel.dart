import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../../core/money.dart';
import '../../data/models/bank_models.dart';
import '../../data/models/society_models.dart';

class ReconciliationExcel {
  const ReconciliationExcel._();

  static List<int>? generateBytes({
    required Society society,
    required ReconciliationView view,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    // Header
    sheet.appendRow([TextCellValue(society.name)]);
    sheet.appendRow([TextCellValue('Bank Reconciliation Statement - As of ${view.asOfDate}')]);
    sheet.appendRow([TextCellValue('Account: ${view.bankAccount.bankName} (${view.bankAccount.accountNumber ?? ""})')]);
    sheet.appendRow([TextCellValue('')]);

    // Summary
    sheet.appendRow([TextCellValue('Reconciliation Summary'), TextCellValue('Amount (INR)')]);
    sheet.appendRow([TextCellValue('Balance as per Bank Book'), TextCellValue(formatPaise(view.summary.bookBalancePaise, symbol: false))]);
    sheet.appendRow([TextCellValue('Less: Uncleared Receipts'), TextCellValue('(${formatPaise(view.summary.unclearedReceiptsPaise, symbol: false)})')]);
    sheet.appendRow([TextCellValue('Add: Uncleared Payments'), TextCellValue(formatPaise(view.summary.unclearedPaymentsPaise, symbol: false))]);
    sheet.appendRow([TextCellValue('Expected Balance as per Statement'), TextCellValue(formatPaise(view.summary.expectedStatementBalancePaise, symbol: false))]);
    sheet.appendRow([TextCellValue('Actual Balance as per Statement'), TextCellValue(formatPaise(view.summary.statementBalancePaise, symbol: false))]);
    sheet.appendRow([TextCellValue('Difference'), TextCellValue(formatPaise(view.summary.differencePaise, symbol: false))]);
    sheet.appendRow([TextCellValue('')]);

    // Uncleared Receipts
    final unclearedReceipts = view.bookItems.where((b) => !b.isCleared && b.debitPaise > 0).toList();
    sheet.appendRow([TextCellValue('Uncleared Receipts (${unclearedReceipts.length})')]);
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Voucher No'),
      TextCellValue('Particulars'),
      TextCellValue('Amount (INR)'),
    ]);
    for (final r in unclearedReceipts) {
      sheet.appendRow([
        TextCellValue(r.entryDate),
        TextCellValue(r.entryNo),
        TextCellValue(r.narration.isEmpty ? (r.contraAccountName ?? '') : r.narration),
        TextCellValue(formatPaise(r.debitPaise, symbol: false)),
      ]);
    }
    sheet.appendRow([TextCellValue('')]);

    // Uncleared Payments
    final unclearedPayments = view.bookItems.where((b) => !b.isCleared && b.creditPaise > 0).toList();
    sheet.appendRow([TextCellValue('Uncleared Payments (${unclearedPayments.length})')]);
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Voucher No'),
      TextCellValue('Particulars'),
      TextCellValue('Amount (INR)'),
    ]);
    for (final p in unclearedPayments) {
      sheet.appendRow([
        TextCellValue(p.entryDate),
        TextCellValue(p.entryNo),
        TextCellValue(p.narration.isEmpty ? (p.contraAccountName ?? '') : p.narration),
        TextCellValue(formatPaise(p.creditPaise, symbol: false)),
      ]);
    }

    return excel.encode();
  }
}
