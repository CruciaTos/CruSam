// lib/shared/models/output_format.dart
//
// Which file format(s) an outgoing document email should attach — shared
// across Invoices, Salary Statement, and Disbursement send dialogs so the
// "choose your output" UI and behavior stays identical everywhere it
// appears. See output-format-selector blueprint §3.1.

import 'package:flutter/material.dart';

enum OutputFormat { pdf, excel }

extension OutputFormatX on OutputFormat {
  String get label => this == OutputFormat.pdf ? 'PDF' : 'Excel';

  IconData get icon => this == OutputFormat.pdf
      ? Icons.picture_as_pdf_outlined
      : Icons.table_chart_outlined;
}