import 'package:excel/excel.dart';
import '../../core/money.dart';
import '../../data/models/society_models.dart';
import '../../data/models/statement_models.dart';

class StatementExcel {
  const StatementExcel._();

  static List<int>? incomeAndExpenditure({
    required Society society,
    required IncomeExpenditureStatement statement,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    sheet.appendRow([TextCellValue(society.name)]);
    sheet.appendRow([TextCellValue('Income & Expenditure Statement')]);
    sheet.appendRow([TextCellValue('Period: ${statement.fromDate} to ${statement.toDate}')]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue('Account Code'), TextCellValue('Particulars'), TextCellValue('Amount (INR)')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- INCOME ---'), TextCellValue('')]);
    for (final group in statement.incomeGroups) {
      sheet.appendRow([TextCellValue(''), TextCellValue(group.title), TextCellValue(formatPaise(group.totalPaise))]);
      for (final line in group.lines) {
        sheet.appendRow([TextCellValue(line.code), TextCellValue('  ${line.name}'), TextCellValue(formatPaise(line.amountPaise))]);
      }
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Income'), TextCellValue(formatPaise(statement.totalIncomePaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- EXPENDITURE ---'), TextCellValue('')]);
    for (final group in statement.expenseGroups) {
      sheet.appendRow([TextCellValue(''), TextCellValue(group.title), TextCellValue(formatPaise(group.totalPaise))]);
      for (final line in group.lines) {
        sheet.appendRow([TextCellValue(line.code), TextCellValue('  ${line.name}'), TextCellValue(formatPaise(line.amountPaise))]);
      }
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Expenditure'), TextCellValue(formatPaise(statement.totalExpensePaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(statement.isSurplus ? 'Net Surplus' : 'Net Deficit'),
      TextCellValue(formatPaise(statement.netSurplusDeficitPaise.abs())),
    ]);

    return excel.encode();
  }

  static List<int>? balanceSheet({
    required Society society,
    required BalanceSheetStatement statement,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    sheet.appendRow([TextCellValue(society.name)]);
    sheet.appendRow([TextCellValue('Balance Sheet')]);
    sheet.appendRow([TextCellValue('As of: ${statement.asOfDate}')]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue('Account Code'), TextCellValue('Particulars'), TextCellValue('Amount (INR)')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- LIABILITIES & FUNDS ---'), TextCellValue('')]);
    for (final group in statement.liabilityGroups) {
      sheet.appendRow([TextCellValue(''), TextCellValue(group.title), TextCellValue(formatPaise(group.totalPaise))]);
      for (final line in group.lines) {
        sheet.appendRow([TextCellValue(line.code), TextCellValue('  ${line.name}'), TextCellValue(formatPaise(line.amountPaise))]);
      }
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Liabilities & Funds'), TextCellValue(formatPaise(statement.totalLiabilitiesPaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- ASSETS ---'), TextCellValue('')]);
    for (final group in statement.assetGroups) {
      sheet.appendRow([TextCellValue(''), TextCellValue(group.title), TextCellValue(formatPaise(group.totalPaise))]);
      for (final line in group.lines) {
        sheet.appendRow([TextCellValue(line.code), TextCellValue('  ${line.name}'), TextCellValue(formatPaise(line.amountPaise))]);
      }
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Assets'), TextCellValue(formatPaise(statement.totalAssetsPaise))]);

    return excel.encode();
  }

  static List<int>? receiptsAndPayments({
    required Society society,
    required ReceiptsPaymentsStatement statement,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    sheet.appendRow([TextCellValue(society.name)]);
    sheet.appendRow([TextCellValue('Receipts & Payments Statement')]);
    sheet.appendRow([TextCellValue('Period: ${statement.fromDate} to ${statement.toDate}')]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue('Account Code'), TextCellValue('Particulars'), TextCellValue('Amount (INR)')]);
    sheet.appendRow([TextCellValue(''), TextCellValue('Opening Balance'), TextCellValue(formatPaise(statement.openingBalancePaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- RECEIPTS ---'), TextCellValue('')]);
    for (final r in statement.receipts) {
      sheet.appendRow([TextCellValue(r.code), TextCellValue(r.name), TextCellValue(formatPaise(r.amountPaise))]);
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Receipts'), TextCellValue(formatPaise(statement.totalReceiptsPaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('--- PAYMENTS ---'), TextCellValue('')]);
    for (final p in statement.payments) {
      sheet.appendRow([TextCellValue(p.code), TextCellValue(p.name), TextCellValue(formatPaise(p.amountPaise))]);
    }
    sheet.appendRow([TextCellValue(''), TextCellValue('Total Payments'), TextCellValue(formatPaise(statement.totalPaymentsPaise))]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([TextCellValue(''), TextCellValue('Closing Balance'), TextCellValue(formatPaise(statement.closingBalancePaise))]);

    return excel.encode();
  }
}
