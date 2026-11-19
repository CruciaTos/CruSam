import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../data/models/bank_models.dart';
import '../../data/models/society_models.dart';

class ReconciliationPdf {
  const ReconciliationPdf._();

  static Future<Uint8List> generateBytes({
    required Society society,
    required ReconciliationView view,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final unclearedReceipts = view.bookItems.where((b) => !b.isCleared && b.debitPaise > 0).toList();
    final unclearedPayments = view.bookItems.where((b) => !b.isCleared && b.creditPaise > 0).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context ctx) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      society.name,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '${society.city}, ${society.state}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'BANK RECONCILIATION',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                    ),
                    pw.Text(
                      'As of: ${view.asOfDate}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // Account details
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bank: ${view.bankAccount.bankName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  if (view.bankAccount.accountNumber != null)
                    pw.Text('A/C No: ${view.bankAccount.accountNumber}', style: const pw.TextStyle(fontSize: 11)),
                  if (view.bankAccount.ifsc != null)
                    pw.Text('IFSC: ${view.bankAccount.ifsc}', style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Summary Table
            pw.Text('Reconciliation Summary', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(4),
                1: pw.FlexColumnWidth(2),
              },
              children: [
                _summaryRow('Balance as per Bank Book', formatPaise(view.summary.bookBalancePaise), isBold: true),
                _summaryRow('Less: Uncleared Receipts / Deposits in transit', '(${formatPaise(view.summary.unclearedReceiptsPaise)})'),
                _summaryRow('Add: Uncleared Payments / Cheques issued not presented', formatPaise(view.summary.unclearedPaymentsPaise)),
                _summaryRow('Expected Balance as per Bank Statement', formatPaise(view.summary.expectedStatementBalancePaise), isBold: true, bgColor: PdfColors.grey100),
                _summaryRow('Actual Balance as per Bank Statement', formatPaise(view.summary.statementBalancePaise), isBold: true),
                _summaryRow('Difference', formatPaise(view.summary.differencePaise), isBold: true, textColor: view.summary.differencePaise == 0 ? PdfColors.green800 : PdfColors.red800),
              ],
            ),
            pw.SizedBox(height: 20),

            // Uncleared Receipts
            if (unclearedReceipts.isNotEmpty) ...[
              pw.Text('Uncleared Receipts (${unclearedReceipts.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _th('Date'),
                      _th('Ref / Voucher'),
                      _th('Particulars'),
                      _th('Amount', alignRight: true),
                    ],
                  ),
                  ...unclearedReceipts.map((r) => pw.TableRow(
                    children: [
                      _td(r.entryDate),
                      _td(r.entryNo),
                      _td(r.narration.isEmpty ? (r.contraAccountName ?? '') : r.narration),
                      _td(formatPaise(r.debitPaise), alignRight: true),
                    ],
                  )),
                ],
              ),
              pw.SizedBox(height: 16),
            ],

            // Uncleared Payments
            if (unclearedPayments.isNotEmpty) ...[
              pw.Text('Uncleared Payments (${unclearedPayments.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _th('Date'),
                      _th('Ref / Voucher'),
                      _th('Particulars'),
                      _th('Amount', alignRight: true),
                    ],
                  ),
                  ...unclearedPayments.map((p) => pw.TableRow(
                    children: [
                      _td(p.entryDate),
                      _td(p.entryNo),
                      _td(p.narration.isEmpty ? (p.contraAccountName ?? '') : p.narration),
                      _td(formatPaise(p.creditPaise), alignRight: true),
                    ],
                  )),
                ],
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.TableRow _summaryRow(String title, String amount, {bool isBold = false, PdfColor? bgColor, PdfColor? textColor}) {
    return pw.TableRow(
      decoration: bgColor != null ? pw.BoxDecoration(color: bgColor) : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            amount,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: textColor),
          ),
        ),
      ],
    );
  }

  static pw.Widget _th(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _td(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }
}
