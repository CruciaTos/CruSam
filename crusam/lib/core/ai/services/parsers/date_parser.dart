// crusam/lib/core/ai/services/parsers/date_parser.dart

class DateParseResult {
  final String? fromDate; // ISO YYYY-MM-DD
  final String? toDate;
  final String? issue; // non-null if parsing was uncertain

  const DateParseResult({this.fromDate, this.toDate, this.issue});
}

class VoucherDateParser {
  final int inferYear;
  final int inferMonth; // used when only day is given

  VoucherDateParser({
    required this.inferYear,
    required this.inferMonth,
  });

  /// Parses date strings from the raw extracted text.
  /// Handles formats observed in the images:
  ///   "1.3/31.3.26"   → 01/03/2026 to 31/03/2026
  ///   "16.2/28.2.26"  → 16/02/2026 to 28/02/2026
  ///   "1-2/28"        → 01/02/year to 28/02/year
  ///   "21.4/30.4.26"  → 21/04/2026 to 30/04/2026
  ///   "1.4/30.4.26"   → 01/04/2026 to 30/04/2026
  ///   "2.3/15.3.26"   → 02/03/2026 to 15/03/2026
  ///   "1.4/15.4.26"   → 01/04/2026 to 15/04/2026
  DateParseResult parse(String raw) {
    if (raw.isEmpty) {
      return const DateParseResult(issue: 'No date found');
    }

    final cleaned = raw.trim();

    // Try format: "D.M/D.M.YY" or "D.M/D.M.YYYY"
    // e.g. "1.3/31.3.26" or "16.2/28.2.26"
    final dotSlashDot = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\s*/\s*(\d{1,2})\.(\d{1,2})\.(\d{2,4})$',
    );
    var match = dotSlashDot.firstMatch(cleaned);
    if (match != null) {
      final fromDay = int.parse(match.group(1)!);
      final fromMonth = int.parse(match.group(2)!);
      final toDay = int.parse(match.group(3)!);
      final toMonth = int.parse(match.group(4)!);
      final year = _parseYear(match.group(5)!);
      return DateParseResult(
        fromDate: _toIso(year, fromMonth, fromDay),
        toDate: _toIso(year, toMonth, toDay),
      );
    }

    // Try format: "D-M/D" (e.g. "1-2/28" = from 1st to 28th of month 2)
    final dashSlash = RegExp(r'^(\d{1,2})-(\d{1,2})/(\d{1,2})$');
    match = dashSlash.firstMatch(cleaned);
    if (match != null) {
      final fromDay = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final toDay = int.parse(match.group(3)!);
      return DateParseResult(
        fromDate: _toIso(inferYear, month, fromDay),
        toDate: _toIso(inferYear, month, toDay),
      );
    }

    // Try format: "D.M.YY/D.M.YY" (both sides have year)
    final bothSides = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{2,4})\s*/\s*(\d{1,2})\.(\d{1,2})\.(\d{2,4})$',
    );
    match = bothSides.firstMatch(cleaned);
    if (match != null) {
      final fromDay = int.parse(match.group(1)!);
      final fromMonth = int.parse(match.group(2)!);
      final fromYear = _parseYear(match.group(3)!);
      final toDay = int.parse(match.group(4)!);
      final toMonth = int.parse(match.group(5)!);
      final toYear = _parseYear(match.group(6)!);
      return DateParseResult(
        fromDate: _toIso(fromYear, fromMonth, fromDay),
        toDate: _toIso(toYear, toMonth, toDay),
      );
    }

    // Try format: "DD/MM - DD/MM" (no year, infer)
    final ddMM = RegExp(
      r'^(\d{1,2})[/.](\d{1,2})\s*[-–to]+\s*(\d{1,2})[/.](\d{1,2})$',
    );
    match = ddMM.firstMatch(cleaned);
    if (match != null) {
      final fromDay = int.parse(match.group(1)!);
      final fromMonth = int.parse(match.group(2)!);
      final toDay = int.parse(match.group(3)!);
      final toMonth = int.parse(match.group(4)!);
      return DateParseResult(
        fromDate: _toIso(inferYear, fromMonth, fromDay),
        toDate: _toIso(inferYear, toMonth, toDay),
        issue: 'Year inferred as $inferYear — please verify',
      );
    }

    return DateParseResult(
      issue: 'Could not parse date: "$raw"',
    );
  }

  static int _parseYear(String raw) {
    final y = int.parse(raw);
    if (y < 100) return 2000 + y; // "26" → 2026
    return y;
  }

  static String _toIso(int year, int month, int day) {
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
}
