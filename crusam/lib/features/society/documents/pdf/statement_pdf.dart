import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/money.dart';
import '../../data/models/society_models.dart';
import '../../data/models/statement_models.dart';

class StatementPdf {
  const StatementPdf._();

  static Future<Uint8List> incomeAndExpenditure({
    required Society society,
    required IncomeExpenditureStatement statement,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _header(society, 'Income and Expenditure Statement', 'For the period: ${statement.fromDate} to ${statement.toDate}'),
            pw.SizedBox(height: 16),
            _sectionHeader('INCOME'),
            for (final grp in statement.incomeGroups) ...[
              _groupRow(grp.title, grp.totalPaise),
              for (final line in grp.lines) _itemRow(line.code, line.name, line.amountPaise),
            ],
            _totalRow('Total Income', statement.totalIncomePaise, PdfColors.green800),
            pw.SizedBox(height: 16),
            _sectionHeader('EXPENDITURE'),
            for (final grp in statement.expenseGroups) ...[
              _groupRow(grp.title, grp.totalPaise),
              for (final line in grp.lines) _itemRow(line.code, line.name, line.amountPaise),
            ],
            _totalRow('Total Expenditure', statement.totalExpensePaise, PdfColors.red800),
            pw.SizedBox(height: 20),
            _grandTotalRow(
              statement.isSurplus ? 'NET SURPLUS (Transferred to General Fund)' : 'NET DEFICIT (Transferred to General Fund)',
              statement.netSurplusDeficitPaise.abs(),
              statement.isSurplus ? PdfColors.green900 : PdfColors.red900,
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> balanceSheet({
    required Society society,
    required BalanceSheetStatement statement,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _header(society, 'Balance Sheet', 'As of ${statement.asOfDate}'),
            pw.SizedBox(height: 16),
            _sectionHeader('LIABILITIES & FUNDS'),
            for (final grp in statement.liabilityGroups) ...[
              _groupRow(grp.title, grp.totalPaise),
              for (final line in grp.lines) _itemRow(line.code, line.name, line.amountPaise),
            ],
            _totalRow('Total Liabilities & Funds', statement.totalLiabilitiesPaise, PdfColors.blue800),
            pw.SizedBox(height: 20),
            _sectionHeader('ASSETS'),
            for (final grp in statement.assetGroups) ...[
              _groupRow(grp.title, grp.totalPaise),
              for (final line in grp.lines) _itemRow(line.code, line.name, line.amountPaise),
            ],
            _totalRow('Total Assets', statement.totalAssetsPaise, PdfColors.blue800),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> receiptsAndPayments({
    required Society society,
    required ReceiptsPaymentsStatement statement,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _header(society, 'Receipts and Payments Account', 'For the period: ${statement.fromDate} to ${statement.toDate}'),
            pw.SizedBox(height: 16),
            _itemRow('', 'Opening Bank and Cash Balance', statement.openingBalancePaise, isBold: true),
            pw.SizedBox(height: 12),
            _sectionHeader('RECEIPTS'),
            for (final line in statement.receipts) _itemRow(line.code, line.name, line.amountPaise),
            _totalRow('Total Receipts', statement.totalReceiptsPaise, PdfColors.green800),
            pw.SizedBox(height: 16),
            _sectionHeader('PAYMENTS'),
            for (final line in statement.payments) _itemRow(line.code, line.name, line.amountPaise),
            _totalRow('Total Payments', statement.totalPaymentsPaise, PdfColors.red800),
            pw.SizedBox(height: 20),
            _grandTotalRow('Closing Bank and Cash Balance', statement.closingBalancePaise, PdfColors.blue900),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _header(Society society, String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(society.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        if (society.addressLine1 != null)
          pw.Text(society.addressLine1!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 8),
        pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _sectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: PdfColors.grey200,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900)),
          pw.Text('Amount (INR)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900)),
        ],
      ),
    );
  }

  static pw.Widget _groupRow(String title, int totalPaise) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8, bottom: 2, left: 4, right: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(formatPaise(totalPaise), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _itemRow(String code, String name, int amountPaise, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (code.isNotEmpty) ...[
                pw.SizedBox(width: 45, child: pw.Text(code, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
              ],
              pw.Text(name, style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
          pw.Text(formatPaise(amountPaise), style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, int totalPaise, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text(formatPaise(totalPaise), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _grandTotalRow(String label, int totalPaise, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey800, width: 1.5),
          bottom: pw.BorderSide(color: PdfColors.grey800, width: 1.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
          pw.Text(formatPaise(totalPaise), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
