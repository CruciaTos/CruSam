// lib/shared/models/generated_document.dart
//
// One generated file ready to attach to an email — bytes + filename + mime
// type. Shared shape for every document type (Invoice PDF/Excel, Salary
// Statement PDF/Excel, Disbursement Excel) so GmailService and every send
// dialog move the same object around instead of raw Uint8List plus
// separately-tracked filename/mimeType. See output-format-selector
// blueprint §3.2.
//
// Promoted out of salary_email_export_service.dart, which previously
// defined the identical shape as SalaryDocumentBytes — that name now lives
// on as a typedef alias there (see that file) so existing call sites keep
// compiling unchanged.

import 'dart:typed_data';

class GeneratedDocument {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const GeneratedDocument({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  static const String pdfMime = 'application/pdf';
  static const String xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}