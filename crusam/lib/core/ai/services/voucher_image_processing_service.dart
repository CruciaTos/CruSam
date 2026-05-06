// crusam/lib/core/ai/services/voucher_image_processing_service.dart

import 'dart:convert';
import 'package:crusam/core/ai/services/parsers/amount_parser.dart';
import 'package:crusam/core/ai/services/parsers/date_parser.dart';
import 'package:crusam/core/ai/services/parsers/name_resolver.dart';
import 'package:crusam/core/ai/services/voucher_image_parser.dart';
import 'package:crusam/data/models/employee_model.dart';

class VoucherImageProcessingService {
  VoucherImageProcessingService._();

  /// The prompt sent to the LLM (qwen2.3) after raw text extraction.
  /// This converts unstructured text → clean JSON.
  static String buildStructuringPrompt(String extractedText) => '''
You are a structured data extractor for Indian business vouchers.

Raw text extracted from a handwritten voucher/register image:
---
$extractedText
---

Extract ALL voucher rows and return ONLY valid JSON. No explanation. No markdown.

Rules:
1. "poNo": look for patterns like "PO 7000034713" or "PO7000042550"
2. For each data row extract:
   - "rawName": employee name exactly as written (e.g. "Pankay kumar", "Kumudबंधु")
   - "rawAmount": the numeric value next to X or + (e.g. "15438 X" → "15438", "340+" → "340")
   - "rawDates": the date range string as written (e.g. "1.3/31.3.26", "16.2/28.2.26")
3. Skip header rows, total rows, and separator lines
4. If a field is missing or unclear, use null — do NOT guess

Return format:
{
  "poNo": "PO7000034713" or null,
  "rows": [
    {
      "rawName": "Pankay kumar",
      "rawAmount": "15438",
      "rawDates": "1-2/28"
    }
  ]
}
''';

  /// Main processing function.
  static VoucherImageParseResult process({
    required String llmJsonResponse,
    required List<EmployeeModel> employees,
    required int inferYear,
    required int inferMonth,
  }) {
    final globalIssues = <String>[];
    final resolvedRows = <ParsedVoucherRow>[];
    final problematicRows = <ParsedVoucherRow>[];

    // 1. Parse LLM JSON
    Map<String, dynamic> parsed;
    try {
      // Strip markdown fences if present
      var json = llmJsonResponse.trim();
      if (json.startsWith('```')) {
        json = json.replaceAll(RegExp(r'```json|```'), '').trim();
      }
      parsed = jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      globalIssues.add('AI could not structure the extracted data. '
          'Raw response: ${llmJsonResponse.substring(0, 100)}…');
      return VoucherImageParseResult(
        resolvedRows: [],
        problematicRows: [],
        globalIssues: globalIssues,
      );
    }

    final poNo = parsed['poNo'] as String?;
    final rawRows = (parsed['rows'] as List<dynamic>?) ?? [];

    if (rawRows.isEmpty) {
      globalIssues.add('No data rows were found in the image.');
    }

    final nameResolver = NameResolver(employees);
    final dateParser = VoucherDateParser(
      inferYear: inferYear,
      inferMonth: inferMonth,
    );

    // 2. Process each row
    for (final rawRow in rawRows) {
      final row = rawRow as Map<String, dynamic>;
      final rawName = (row['rawName'] as String?) ?? '';
      final rawAmount = (row['rawAmount'] as String?) ?? '';
      final rawDates = (row['rawDates'] as String?) ?? '';
      final rowIssues = <String>[];

      // Parse amount
      final amount = AmountParser.parse(rawAmount);
      if (amount == null) {
        rowIssues.add('Amount not readable: "$rawAmount"');
      } else if (amount <= 0) {
        rowIssues.add('Amount is zero or negative: $amount');
      }

      // Parse dates
      final dateResult = dateParser.parse(rawDates);
      if (dateResult.issue != null) {
        rowIssues.add('Date issue: ${dateResult.issue}');
      } else if (dateResult.fromDate == null || dateResult.toDate == null) {
        rowIssues.add('Could not parse dates from: "$rawDates"');
      }

      // Resolve name
      final nameResult = nameResolver.resolve(rawName);
      if (nameResult.issue != null) {
        // Low confidence is a warning, not a blocker
        if (nameResult.confidence == NameMatchConfidence.low) {
          rowIssues.add('⚠️ ${nameResult.issue}');
        } else if (nameResult.confidence == NameMatchConfidence.none) {
          rowIssues.add('❌ ${nameResult.issue}');
        }
      }

      final parsedRow = ParsedVoucherRow(
        rawName: rawName,
        amount: amount,
        fromDate: dateResult.fromDate,
        toDate: dateResult.toDate,
        resolvedEmployee: nameResult.employee,
        issues: rowIssues,
      );

      // A row is "resolved" if it has no blocking issues
      // Low-confidence name match is allowed (creates row with warning)
      final hasBlockingIssue = rowIssues.any((i) => i.startsWith('❌'));
      if (!hasBlockingIssue &&
          amount != null &&
          dateResult.fromDate != null &&
          dateResult.toDate != null) {
        resolvedRows.add(parsedRow);
      } else {
        problematicRows.add(parsedRow);
      }
    }

    return VoucherImageParseResult(
      extractedPoNo: poNo,
      resolvedRows: resolvedRows,
      problematicRows: problematicRows,
      globalIssues: globalIssues,
    );
  }
}
