// crusam/lib/core/ai/services/salary_pdf_parser.dart
//
// Purpose-built parser for Aarti Enterprises salary statement PDFs.
// Uses only syncfusion_flutter_pdf — zero vision model involvement.
//
// Handles the exact column layout seen in the salary PDF:
//   Sr. No | Name of Technician | PF NO. | UAN No. | Code |
//   IFSC code | Account number | Basic | Other | Arrears Salary |
//   Gross Salary (Total) | PF | MSW | ESIC | P Tax | Total Ded. | Net Salary
//
// Key improvements over the generic FileExtractionService:
//  1. Detects salary statement pages by header keyword matching
//  2. Parses multi-word employee names robustly (Syncfusion splits tokens)
//  3. Extracts salary figures as typed numbers, not strings
//  4. Groups employees by their Code (F&B, I&L, P&S, AP, etc.)
//  5. Validates row totals (Basic + Other == Gross) as a data quality check

import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

// ── Parsed salary row ───────────────────────────────────────────────────────

class SalaryRow {
  SalaryRow({
    required this.srNo,
    required this.name,
    required this.pfNo,
    required this.uanNo,
    required this.code,
    required this.ifscCode,
    required this.accountNumber,
    required this.basic,
    required this.other,
    required this.arrears,
    required this.grossSalary,
    required this.pf,
    required this.msw,
    required this.esic,
    required this.pTax,
    required this.totalDed,
    required this.netSalary,
    required this.pageNumber,
  });

  final int srNo;
  final String name;
  final String pfNo;
  final String uanNo;
  final String code;
  final String ifscCode;
  final String accountNumber;
  final double basic;
  final double other;
  final double arrears;
  final double grossSalary;
  final double pf;
  final double msw;
  final double esic;
  final double pTax;
  final double totalDed;
  final double netSalary;
  final int pageNumber;

  /// True if the row's numbers add up correctly.
  bool get isValid {
    final expectedGross = (basic + other + arrears).roundToDouble();
    final actualGross   = grossSalary.roundToDouble();
    return (expectedGross - actualGross).abs() < 2;
  }

  @override
  String toString() =>
      '[Sr$srNo] $name | Code:$code | PF:$pfNo | UAN:$uanNo | '
      'Basic:$basic | Other:$other | Gross:$grossSalary | Net:$netSalary';
}

// ── Parse result ────────────────────────────────────────────────────────────

class SalaryPdfParseResult {
  SalaryPdfParseResult({
    required this.month,
    required this.companyName,
    required this.rows,
    required this.pageCount,
    required this.invalidRows,
  });

  final String month;
  final String companyName;
  final List<SalaryRow> rows;
  final int pageCount;
  final List<SalaryRow> invalidRows; // rows whose totals don't add up

  Map<String, List<SalaryRow>> get byCode {
    final map = <String, List<SalaryRow>>{};
    for (final row in rows) {
      map.putIfAbsent(row.code, () => []).add(row);
    }
    return map;
  }

  double get grandTotalGross  => rows.fold(0, (s, r) => s + r.grossSalary);
  double get grandTotalNet    => rows.fold(0, (s, r) => s + r.netSalary);
  double get grandTotalPf     => rows.fold(0, (s, r) => s + r.pf);

  String toSummary() {
    final buf = StringBuffer();
    buf.writeln('=== $companyName — $month ===');
    buf.writeln('Total employees : ${rows.length}');
    buf.writeln('Grand Gross     : ₹${grandTotalGross.toStringAsFixed(2)}');
    buf.writeln('Grand Net       : ₹${grandTotalNet.toStringAsFixed(2)}');
    buf.writeln('Grand PF        : ₹${grandTotalPf.toStringAsFixed(2)}');
    buf.writeln('');
    for (final entry in byCode.entries) {
      final deptRows = entry.value;
      final deptGross = deptRows.fold(0.0, (s, r) => s + r.grossSalary);
      buf.writeln('  ${entry.key}: ${deptRows.length} employees, '
          'Gross ₹${deptGross.toStringAsFixed(2)}');
    }
    if (invalidRows.isNotEmpty) {
      buf.writeln('');
      buf.writeln('⚠️ ${invalidRows.length} rows had mismatched totals:');
      for (final r in invalidRows) {
        buf.writeln('  - ${r.name} (Sr.${r.srNo})');
      }
    }
    return buf.toString().trim();
  }
}

// ── Parser ──────────────────────────────────────────────────────────────────

class SalaryPdfParser {
  SalaryPdfParser._();

  /// Column header keywords for Aarti Enterprises salary statements.
  static const _expectedHeaders = [
    'sr', 'name', 'technician', 'pf', 'uan', 'code',
    'ifsc', 'account', 'basic', 'other', 'gross', 'salary',
  ];

  static const _totalKeyword = 'TOTAL';

  // ── Public entry point ───────────────────────────────────────────────────

  static Future<SalaryPdfParseResult> parse(Uint8List bytes) async {
    PdfDocument? doc;
    try {
      doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final pageCount = doc.pages.count;

      String month = '';
      String companyName = 'Aarti Enterprises';
      final allRows = <SalaryRow>[];

      for (int p = 0; p < pageCount; p++) {
        final rawText = extractor
            .extractText(startPageIndex: p, endPageIndex: p)
            .trim();
        if (rawText.isEmpty) continue;

        final lines = rawText
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();

        // ── Extract month/year from title line ─────────────────────────
        if (month.isEmpty) {
          for (final line in lines.take(5)) {
            final lower = line.toLowerCase();
            if (lower.contains('salary statement') &&
                lower.contains('month')) {
              month = line;
              // e.g. "Aarti Enterprises Salary Statement for the month of APRIL - 2026"
              if (line.toLowerCase().startsWith('aarti')) {
                companyName = 'Aarti Enterprises';
              }
              break;
            }
          }
        }

        // ── Find header row ────────────────────────────────────────────
        int headerIndex = -1;
        for (int i = 0; i < lines.length; i++) {
          final lower = lines[i].toLowerCase();
          int hits = 0;
          for (final kw in _expectedHeaders) {
            if (lower.contains(kw)) hits++;
          }
          if (hits >= 4) {
            headerIndex = i;
            break;
          }
        }
        if (headerIndex == -1) continue;

        // ── Parse data rows ────────────────────────────────────────────
        final pageRows = _parseDataRows(
          lines.sublist(headerIndex + 1),
          pageNumber: p + 1,
        );
        allRows.addAll(pageRows);
      }

      final invalid = allRows.where((r) => !r.isValid).toList();

      return SalaryPdfParseResult(
        month: month,
        companyName: companyName,
        rows: allRows,
        pageCount: pageCount,
        invalidRows: invalid,
      );
    } finally {
      doc?.dispose();
    }
  }

  // ── Row parsing ──────────────────────────────────────────────────────────

  static List<SalaryRow> _parseDataRows(
    List<String> lines,
    {required int pageNumber}
  ) {
    final rows = <SalaryRow>[];

    for (final line in lines) {
      // Stop at the TOTAL row
      if (line.toUpperCase().startsWith(_totalKeyword)) break;

      final row = _parseLine(line, pageNumber: pageNumber);
      if (row != null) rows.add(row);
    }

    return rows;
  }

  static SalaryRow? _parseLine(String line, {required int pageNumber}) {
    // Syncfusion collapses multiple spaces; we split on 2+ spaces
    // which typically marks column boundaries in salary statement PDFs.
    final tokens = line
        .split(RegExp(r'\s{2,}'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.length < 10) return null;

    // First token must be a row number
    final srNo = int.tryParse(tokens[0]);
    if (srNo == null) return null;

    // Extract numeric tokens from the end of the line (salary figures)
    // The last 10 numbers are:
    // Basic | Other | Arrears | Gross | PF | MSW | ESIC | PTax | TotalDed | Net
    final numericTokens = <double>[];
    int lastTextIndex = tokens.length - 1;

    for (int i = tokens.length - 1; i >= 1; i--) {
      final d = _parseDouble(tokens[i]);
      if (d != null) {
        numericTokens.insert(0, d);
        lastTextIndex = i - 1;
      } else if (numericTokens.length >= 10) {
        break;
      } else {
        // reset if we hit non-numeric before getting 10 numbers
        numericTokens.clear();
        lastTextIndex = i;
      }
    }

    if (numericTokens.length < 8) return null;

    // Remaining tokens between srNo and the numbers are text fields:
    // name, pfNo, uanNo, code, ifscCode, accountNumber
    final textTokens = tokens.sublist(1, lastTextIndex + 1);
    if (textTokens.length < 3) return null;

    // Try to identify known code values (F&B, I&L, P&S, AP, A&P)
    const knownCodes = {'F&B', 'I&L', 'P&S', 'AP', 'A&P'};
    int codeIndex = -1;
    for (int i = 0; i < textTokens.length; i++) {
      if (knownCodes.contains(textTokens[i].toUpperCase())) {
        codeIndex = i;
        break;
      }
    }
    if (codeIndex == -1) return null;

    // PF No and UAN No are typically just before code
    // Pattern: name... | pfNo | uanNo | code | ifsc | accountNo
    // PF format: MH/212395/XXXX
    // UAN: 12-digit number
    // We work backwards from codeIndex

    String code = textTokens[codeIndex];
    String pfNo = '';
    String uanNo = '';
    String ifscCode = '';
    String accountNumber = '';
    String name = '';

    if (codeIndex >= 2) {
      uanNo = textTokens[codeIndex - 1];
      pfNo  = textTokens[codeIndex - 2];
      name  = textTokens.sublist(0, codeIndex - 2).join(' ');
    } else if (codeIndex == 1) {
      pfNo  = textTokens[0]; // might be name+pfNo merged
      name  = '';
    }

    // After code: IFSC, Account Number
    if (codeIndex + 1 < textTokens.length) {
      ifscCode = textTokens[codeIndex + 1];
    }
    if (codeIndex + 2 < textTokens.length) {
      accountNumber = textTokens[codeIndex + 2];
    }

    // Handle "00000" UAN (means no UAN assigned)
    if (uanNo == '00000' || uanNo == '0') uanNo = '';

    // Map numeric tokens → salary columns
    // Columns: Basic Other Arrears Gross PF MSW ESIC PTax TotalDed Net
    // Some rows have only 9 numbers (MSW is 0 and omitted)
    double basic = 0, other = 0, arrears = 0, gross = 0;
    double pf = 0, msw = 0, esic = 0, pTax = 0, totalDed = 0, net = 0;

    if (numericTokens.length >= 10) {
      basic     = numericTokens[numericTokens.length - 10];
      other     = numericTokens[numericTokens.length - 9];
      arrears   = numericTokens[numericTokens.length - 8];
      gross     = numericTokens[numericTokens.length - 7];
      pf        = numericTokens[numericTokens.length - 6];
      msw       = numericTokens[numericTokens.length - 5];
      esic      = numericTokens[numericTokens.length - 4];
      pTax      = numericTokens[numericTokens.length - 3];
      totalDed  = numericTokens[numericTokens.length - 2];
      net       = numericTokens[numericTokens.length - 1];
    } else if (numericTokens.length >= 9) {
      // Assume MSW = 0
      basic     = numericTokens[0];
      other     = numericTokens[1];
      arrears   = numericTokens[2];
      gross     = numericTokens[3];
      pf        = numericTokens[4];
      esic      = numericTokens[5];
      pTax      = numericTokens[6];
      totalDed  = numericTokens[7];
      net       = numericTokens[8];
    }

    if (name.isEmpty || gross == 0) return null;

    return SalaryRow(
      srNo: srNo,
      name: _cleanName(name),
      pfNo: pfNo,
      uanNo: uanNo,
      code: code,
      ifscCode: ifscCode,
      accountNumber: accountNumber,
      basic: basic,
      other: other,
      arrears: arrears,
      grossSalary: gross,
      pf: pf,
      msw: msw,
      esic: esic,
      pTax: pTax,
      totalDed: totalDed,
      netSalary: net,
      pageNumber: pageNumber,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static double? _parseDouble(String s) {
    // Remove commas (e.g. 1,00,000)
    final clean = s.replaceAll(',', '').trim();
    return double.tryParse(clean);
  }

  static String _cleanName(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}