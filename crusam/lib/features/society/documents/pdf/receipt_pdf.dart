import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/society_models.dart';

class ReceiptPdf {
  const ReceiptPdf._();

  static Future<Uint8List> generateBytes({
    required Society society,
    required Receipt receipt,
    required List<BillAllocation> allocations,
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
                          color: PdfColors.blueGrey800,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'PAYMENT RECEIPT',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Receipt No: ${receipt.receiptNo}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: ${receipt.receiptDate}', style: const pw.TextStyle(fontSize: 10)),
                      if (receipt.isReversed)
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

              // Payer info
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
                        pw.Text('Received with thanks from:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(receipt.payerName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('Unit: ${receipt.blockName}-${receipt.unitNo}', style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Payment Mode: ${receipt.mode.toUpperCase()}', style: const pw.TextStyle(fontSize: 10)),
                        if (receipt.instrumentNo != null && receipt.instrumentNo!.isNotEmpty)
                          pw.Text('Instrument No: ${receipt.instrumentNo}', style: const pw.TextStyle(fontSize: 10)),
                        if (receipt.instrumentBank != null && receipt.instrumentBank!.isNotEmpty)
                          pw.Text('Bank: ${receipt.instrumentBank}', style: const pw.TextStyle(fontSize: 10)),
                        if (receipt.bankCashAccountName != null)
                          pw.Text('Deposited in: ${receipt.bankCashAccountName}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Amount box
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Amount Received:', style: const pw.TextStyle(fontSize: 11)),
                        pw.Text('Rs. ${formatPlainAmount(receipt.amountPaise)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    if (receipt.tdsPaise > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TDS Deducted:', style: const pw.TextStyle(fontSize: 11)),
                          pw.Text('Rs. ${formatPlainAmount(receipt.tdsPaise)}', style: const pw.TextStyle(fontSize: 11)),
                        ],
                      ),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Total Credit:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Rs. ${formatPlainAmount(receipt.totalPaise)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Amount in Words: ${numberToWords(receipt.totalPaise)}',
                      style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
                    ),
                  ],
                ),
              ),

              if (allocations.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Settlement Details:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.TableHelper.fromTextArray(
                  headers: ['Bill No', 'Charge Head', 'Allocated Amount (Rs.)'],
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

              if (receipt.unallocatedPaise > 0) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  'Unallocated Advance: Rs. ${formatPlainAmount(receipt.unallocatedPaise)}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                ),
              ],

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Note: Subject to realization of cheque / instrument.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
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
