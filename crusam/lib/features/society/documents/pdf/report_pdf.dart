import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../data/models/society_models.dart';
import '../../domain/reports/report_definitions.dart';

class ReportPdf {
  const ReportPdf._();

  static Future<Uint8List> generateBytes({
    required Society society,
    required ReportResult report,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final isLandscape = report.columns.length > 5;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
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
                    pw.Text(society.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text(society.addressLine1 ?? '', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    if (society.registrationNo != null && society.registrationNo!.isNotEmpty)
                      pw.Text('Reg No: ${society.registrationNo}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(report.definition.title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                    pw.SizedBox(height: 2),
                    if (report.parameters.containsKey('fromDate') && report.parameters.containsKey('toDate'))
                      pw.Text('Period: ${report.parameters['fromDate']} to ${report.parameters['toDate']}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    if (report.parameters.containsKey('asOfDate'))
                      pw.Text('As of Date: ${report.parameters['asOfDate']}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('Generated: ${DateTime.now().toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 12),

            // Table
            if (report.rows.isEmpty)
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(32),
                  child: pw.Text('No records found for the selected parameters.', style: const pw.TextStyle(color: PdfColors.grey700)),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: report.columns.map((col) => _th(col.label, alignRight: col.isNumeric)).toList(),
                  ),
                  // Data Rows
                  ...report.rows.map((row) => pw.TableRow(
                    children: report.columns.map((col) {
                      final val = row[col.key]?.toString() ?? '-';
                      return _td(val, alignRight: col.isNumeric);
                    }).toList(),
                  )),
                ],
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _th(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _td(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }
}
