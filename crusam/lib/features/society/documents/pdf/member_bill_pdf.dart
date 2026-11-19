import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/money.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/society_models.dart';

class MemberBillPdf {
  const MemberBillPdf._();

  static String numberToWords(int paise) {
    if (paise == 0) return 'Zero Rupees Only';

    final rupees = paise ~/ 100;
    final paiseRemainder = paise % 100;

    String words = _convertChunk(rupees).trim();
    if (words.isEmpty) {
      words = 'Zero Rupees';
    } else {
      words = 'Rupees $words';
    }

    if (paiseRemainder > 0) {
      words += ' and ${_convertChunk(paiseRemainder).trim()} Paise';
    }

    return '$words Only';
  }

  static String _convertChunk(int n) {
    if (n == 0) return '';

    const units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen'
    ];
    const tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    ];

    if (n < 20) {
      return units[n];
    }
    if (n < 100) {
      return '${tens[n ~/ 10]} ${units[n % 10]}';
    }
    if (n < 1000) {
      return '${units[n ~/ 100]} Hundred ${_convertChunk(n % 100)}';
    }
    if (n < 100000) {
      return '${_convertChunk(n ~/ 1000)} Thousand ${_convertChunk(n % 1000)}';
    }
    if (n < 10000000) {
      return '${_convertChunk(n ~/ 100000)} Lakh ${_convertChunk(n % 100000)}';
    }
    return '${_convertChunk(n ~/ 10000000)} Crore ${_convertChunk(n % 10000000)}';
  }

  static Future<Uint8List> generatePdf({
    required Society society,
    required Bill bill,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(buildPage(society: society, bill: bill));
    return pdf.save();
  }

  static pw.Page buildPage({
    required Society society,
    required Bill bill,
  }) {
    return pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Society Header
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
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                        ),
                        if (society.addressLine1 != null)
                          pw.Text(
                            '${society.addressLine1}${society.city != null ? ", ${society.city}" : ""}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        if (society.registrationNo != null && society.registrationNo!.isNotEmpty)
                          pw.Text(
                            'Reg No: ${society.registrationNo}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        if (society.gstin != null && society.gstin!.isNotEmpty)
                          pw.Text(
                            'GSTIN: ${society.gstin}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.amber100,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          bill.billKind == 'debit_note' ? 'DEBIT NOTE' : 'MAINTENANCE BILL',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Invoice #: ${bill.billNo ?? "(Draft)"}',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Bill Date: ${bill.billDate}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Due Date: ${bill.dueDate}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 12),

              // Billed To & Period
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Billed To:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                      pw.Text(bill.billToName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Unit: ${bill.blockName}-${bill.unitNo}', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                  if (bill.periodFrom != null && bill.periodTo != null)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Billing Period:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.Text('${bill.periodFrom} to ${bill.periodTo}', style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                ],
              ),

              pw.SizedBox(height: 20),

              // Line Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('#', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Particulars / Charge Head', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Base Amount', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('GST', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Total (Rs.)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  // Rows
                  ...bill.lines.map((l) {
                    final lineGst = l.cgstPaise + l.sgstPaise + l.igstPaise;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${l.lineNo}', style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(l.chargeHeadName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                              if (l.description != null && l.description!.isNotEmpty)
                                pw.Text(l.description!, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(formatPlainAmount(l.amountPaise), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(lineGst > 0 ? formatPlainAmount(lineGst) : '-', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(formatPlainAmount(l.payablePaise), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 12),

              // Summary Box
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Amount in Words:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.Text(
                          numberToWords(bill.totalPaise),
                          style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 16),
                        pw.Text('Payment Instructions:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                        pw.Text('1. Please pay by the due date to avoid late payment interest charges.', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('2. Make payments via Cheque / NEFT / RTGS favouring the Society account.', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: 220,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      children: [
                        _buildSummaryRow('Current Charges:', formatPlainAmount(bill.subtotalPaise)),
                        if (bill.cgstPaise > 0) _buildSummaryRow('CGST:', formatPlainAmount(bill.cgstPaise)),
                        if (bill.sgstPaise > 0) _buildSummaryRow('SGST:', formatPlainAmount(bill.sgstPaise)),
                        if (bill.roundOffPaise != 0) _buildSummaryRow('Round Off:', formatPlainAmount(bill.roundOffPaise)),
                        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                        _buildSummaryRow('Total Due:', formatPlainAmount(bill.totalPaise), isBold: true),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // Footer Sign-off
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated by CruSam Society Workspace', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SizedBox(height: 24),
                      pw.Text('For ${society.name}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Authorized Signatory', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      );
  }

  static pw.Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }
}
