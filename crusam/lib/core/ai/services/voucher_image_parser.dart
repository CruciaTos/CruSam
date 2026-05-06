// crusam/lib/core/ai/services/voucher_image_parser.dart

import 'package:crusam/data/models/employee_model.dart';

/// Result of parsing one extracted row from an image.
class ParsedVoucherRow {
  final String rawName;
  final double? amount;
  final String? fromDate; // ISO YYYY-MM-DD or null
  final String? toDate;
  final EmployeeModel? resolvedEmployee;
  final List<String> issues; // per-row issues

  const ParsedVoucherRow({
    required this.rawName,
    this.amount,
    this.fromDate,
    this.toDate,
    this.resolvedEmployee,
    this.issues = const [],
  });

  bool get isFullyResolved =>
      amount != null &&
      fromDate != null &&
      toDate != null &&
      resolvedEmployee != null &&
      issues.isEmpty;
}

/// Final result returned to the chat notifier.
class VoucherImageParseResult {
  final String? extractedPoNo;
  final List<ParsedVoucherRow> resolvedRows; // ready to add
  final List<ParsedVoucherRow> problematicRows; // need user review
  final List<String> globalIssues; // PO number issues, etc.

  const VoucherImageParseResult({
    this.extractedPoNo,
    required this.resolvedRows,
    required this.problematicRows,
    this.globalIssues = const [],
  });

  bool get hasIssues => problematicRows.isNotEmpty || globalIssues.isNotEmpty;

  /// Human-readable issue summary for the chat UI.
  String buildIssueReport() {
    final sb = StringBuffer();
    sb.writeln('**⚠️ Issues found during image parsing:**\n');

    if (globalIssues.isNotEmpty) {
      for (final issue in globalIssues) {
        sb.writeln('- $issue');
      }
      sb.writeln();
    }

    if (problematicRows.isNotEmpty) {
      sb.writeln('**Rows that could not be created:**\n');
      for (final row in problematicRows) {
        sb.writeln(
          '**"${row.rawName}"** (₹${row.amount?.toStringAsFixed(0) ?? "?"}):',
        );
        for (final issue in row.issues) {
          sb.writeln('  - $issue');
        }
        sb.writeln();
      }
    }

    sb.writeln('---');
    sb.writeln(
      '${resolvedRows.length} row(s) created successfully. '
      '${problematicRows.length} row(s) need manual review.',
    );
    return sb.toString().trim();
  }
}
