import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../pdf/widgets/pdf_pages_preview.dart';
import 'package:crusam_core/crusam_core.dart';

/// Attachment B preview — renders the exact PDF page the export writes.
class AttachmentBPreview extends StatelessWidget {
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

  final int employeeCount;
  final String departmentCode;

  const AttachmentBPreview({
    super.key,
    required this.config,
    this.margins         = const EdgeInsets.all(24),
    this.customerName    = 'M/s Diversey India Hygiene Private Ltd.',
    this.customerAddress = '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093',
    this.customerGst     = '27AABCC1597Q1Z2',
    this.billNo          = 'AE/-/25-26',
    this.date            = '',
    this.poNo            = '-',
    this.itemDescription = 'Manpower Supply Charges',
    this.period          = '',
    this.employeeCount   = 0,
    this.departmentCode  = '',
  });

  @override
  Widget build(BuildContext context) => PdfPagesPreview(
        inputs: [
          config.toMap(), margins, customerName, customerAddress, customerGst,
          billNo, date, poNo, itemDescription, period, employeeCount,
          departmentCode,
        ],
        build: () => SalaryBillPdfService.buildBytes(
          config: config,
          margins: pw.EdgeInsets.fromLTRB(
              margins.left, margins.top, margins.right, margins.bottom),
          pages: [
            SalaryBillPdfService.attachmentBSpec(
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
              employeeCount: employeeCount,
            ),
          ],
        ),
      );
}
