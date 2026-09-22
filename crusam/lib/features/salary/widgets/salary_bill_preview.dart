import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../pdf/widgets/pdf_pages_preview.dart';
import 'package:crusam_core/crusam_core.dart';

/// Salary Invoice preview — renders the exact PDF page the export writes.
class SalaryBillPreview extends StatelessWidget {
  final CompanyConfigModel config;
  final EdgeInsets margins;

  final String customerName;
  final String customerAddress;
  final String customerGst;
  final String billNo;
  final String date;
  final String poNo;
  final String itemDescription;

  /// e.g. "March 2026", shown in the subject line.
  final String period;

  /// Base invoice amount = Attachment A total + Attachment B total
  final double invoiceBaseAmount;
  final String departmentCode;

  const SalaryBillPreview({
    super.key,
    required this.config,
    this.margins              = const EdgeInsets.all(24),
    this.customerName         = 'M/s Diversey India Hygiene Pvt Ltd.',
    this.customerAddress      = '501, 5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093',
    this.customerGst          = '27AABCC1597Q1Z2',
    this.billNo               = 'AE/-/25-26',
    this.date                 = '',
    this.poNo                 = '-',
    this.itemDescription      = 'Manpower Supply Charges',
    this.period               = '',
    this.invoiceBaseAmount    = 0,
    this.departmentCode       = '',
  });

  @override
  Widget build(BuildContext context) => PdfPagesPreview(
        inputs: [
          config.toMap(), margins, customerName, customerAddress, customerGst,
          billNo, date, poNo, itemDescription, period, invoiceBaseAmount,
          departmentCode,
        ],
        build: () => SalaryBillPdfService.buildBytes(
          config: config,
          margins: pw.EdgeInsets.fromLTRB(
              margins.left, margins.top, margins.right, margins.bottom),
          pages: [
            SalaryBillPdfService.salaryInvoiceSpec(
              header: SalaryBillHeader(
                billNo: billNo,
                date: date,
                poNo: poNo,
                customerName: customerName,
                customerAddress: customerAddress,
                customerGst: customerGst,
                departmentCode: departmentCode,
                period: period,
              ),
              itemDescription: itemDescription,
              invoiceBaseAmount: invoiceBaseAmount,
            ),
          ],
        ),
      );
}
