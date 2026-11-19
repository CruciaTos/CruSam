import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/society_models.dart';

class CreditNotePdf {
  const CreditNotePdf._();

  static Future<Uint8List> generateBytes({
    required Society society,
    required CreditNote note,
    List<BillAllocation> allocations = const [],
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          society.name,
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                        ),
                        if (society.addressLine1 != null && society.addressLine1!.isNotEmpty)
                          pw.Text(society.addressLine1!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.Text(
                          '${society.city}, ${society.state} - ${society.pincode}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        if (society.gstin != null && society.gstin!.isNotEmpty)
                          pw.Text('GSTIN: ${society.gstin}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.teal800,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'CREDIT NOTE',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Note No: ${note.noteNo}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: ${note.noteDate}', style: const pw.TextStyle(fontSize: 10)),
                      if (note.isReversed)
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 4),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          color: PdfColors.red100,
                          child: pw.Text('REVERSED', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                        ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 12),

              // Unit info
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
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
                        pw.Text('Issued to Unit:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text('${note.blockName}-${note.unitNo}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Reason for Credit:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(note.reason, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Breakdown table
              pw.TableHelper.fromTextArray(
                headers: ['Particulars', 'Amount (Rs.)'],
                data: [
                  ['Credit Amount ${note.chargeHeadName != null ? "(${note.chargeHeadName})" : ""}', formatPlainAmount(note.amountPaise)],
                  if (note.cgstPaise > 0) ['CGST Adjustment', formatPlainAmount(note.cgstPaise)],
                  if (note.sgstPaise > 0) ['SGST Adjustment', formatPlainAmount(note.sgstPaise)],
                  if (note.igstPaise > 0) ['IGST Adjustment', formatPlainAmount(note.igstPaise)],
                  ['Total Credit', formatPlainAmount(note.totalPaise)],
                ],
                headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                },
              ),

              pw.SizedBox(height: 12),
              pw.Text(
                'Amount in Words: ${numberToWords(note.totalPaise)}',
                style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
              ),

              if (allocations.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Applied Against Bills:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: ['Bill No', 'Charge Head', 'Adjusted Amount (Rs.)'],
                  data: allocations.map((a) => [
                    a.billNo ?? '-',
                    a.chargeHeadName ?? '-',
                    formatPlainAmount(a.allocatedPaise),
                  ]).toList(),
                  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerRight,
                  },
                ),
              ],

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('This credit note reduces your account dues.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey600),
                      pw.SizedBox(height: 4),
                      pw.Text('For ${society.name}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Authorized Signatory', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
