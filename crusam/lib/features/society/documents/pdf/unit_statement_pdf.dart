import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';

class UnitStatementPdf {
  const UnitStatementPdf._();

  static Future<Uint8List> generateBytes({
    required Society society,
    required UnitRow unit,
    required List<UnitStatementRow> rows,
    String? fromDate,
    String? toDate,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final closingBalance = rows.isNotEmpty ? rows.last.runningBalancePaise : 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(society.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${society.city}, ${society.state}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Text('ACCOUNT STATEMENT', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.SizedBox(height: 8),
            ],
          );
        },
        footer: (pw.Context ctx) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CruSam Society Workspace', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          );
        },
        build: (pw.Context ctx) {
          return [
            // Statement Details Box
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Unit: ${unit.blockName}-${unit.unitNo}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Member: ${unit.billToName ?? unit.primaryContactName ?? "Resident"}', style: const pw.TextStyle(fontSize: 10)),
                      if (unit.primaryContactPhone != null)
                        pw.Text('Phone: ${unit.primaryContactPhone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Period:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      pw.Text('${fromDate ?? society.booksStartDate} to ${toDate ?? "Present"}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        closingBalance >= 0
                            ? 'Net Due: Rs. ${formatPlainAmount(closingBalance)}'
                            : 'Advance Balance: Rs. ${formatPlainAmount(-closingBalance)}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: closingBalance > 0 ? PdfColors.red800 : PdfColors.green800),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // Ledger Table
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Type', 'Ref No', 'Particulars', 'Debit (Rs.)', 'Credit (Rs.)', 'Balance (Rs.)'],
              data: rows.map((r) => [
                r.date,
                r.docType.replaceAll('_', ' ').toUpperCase(),
                r.docNo,
                r.description,
                r.debitPaise > 0 ? formatPlainAmount(r.debitPaise) : '-',
                r.creditPaise > 0 ? formatPlainAmount(r.creditPaise) : '-',
                r.runningBalancePaise >= 0
                    ? '${formatPlainAmount(r.runningBalancePaise)} Dr'
                    : '${formatPlainAmount(-r.runningBalancePaise)} Cr',
              ]).toList(),
              headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
            ),

            pw.SizedBox(height: 20),

            // Summary Footer
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        closingBalance >= 0 ? 'Closing Balance (Due):' : 'Closing Balance (Advance):',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Rs. ${formatPlainAmount(closingBalance.abs())}',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: closingBalance > 0 ? PdfColors.red900 : PdfColors.green900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
