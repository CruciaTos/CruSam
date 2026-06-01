// crusam/lib/core/ai/services/structured_voucher_creation_service.dart
//
// Purpose-built parser for structured markdown tables containing employee
// payment data. Converts structured input into VoucherRow data ready for
// direct tool execution — no AI model involved, fully deterministic.
//
// Supported input format:
//
//   ## Payment & Schedule List (PO 700042550)
//   | No. | Name | Amount | From Date | To Date |
//   |-----|------|--------|-----------|---------|
//   |  1  | Marimuthu | 19,055 | 16/04/2026 | 30/04/2026 |
//   |  2  | V. Karthickkumar | 21,982 | 16/04/2026 | 30/04/2026 |
//   | Total | | 102,748 | | |
//
// Metadata is extracted from the surrounding prompt text:
//   - title    : "named X", "title X", "voucher name X"
//   - billNo   : "bill no X" or "same bill no" (→ uses title value)
//   - poNo     : "PO 7000042550", "(PO 7000042550)", "po no. X"

import 'package:crusam/data/models/employee_model.dart';

// ── Parsed row ─────────────────────────────────────────────────────────────

class StructuredVoucherRow {
  final String rawName;
  final double amount;
  final String fromDate; // ISO YYYY-MM-DD (empty string if not parsed)
  final String toDate;   // ISO YYYY-MM-DD (empty string if not parsed)

  const StructuredVoucherRow({
    required this.rawName,
    required this.amount,
    required this.fromDate,
    required this.toDate,
  });
}

// ── Parsed meta ────────────────────────────────────────────────────────────

class StructuredVoucherMeta {
  final String? title;
  final String? billNo;
  final String? poNo;
  final List<StructuredVoucherRow> rows;

  const StructuredVoucherMeta({
    this.title,
    this.billNo,
    this.poNo,
    required this.rows,
  });

  bool get hasRows => rows.isNotEmpty;
}

// ── Service ────────────────────────────────────────────────────────────────

class StructuredVoucherCreationService {
  StructuredVoucherCreationService._();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Parses [userMessage] for a markdown table and extracts voucher metadata.
  /// Returns null if no valid table with at least one data row is found.
  static StructuredVoucherMeta? parse(String userMessage) {
    final rows = _parseMarkdownTable(userMessage);
    if (rows.isEmpty) return null;

    final title = _extractTitle(userMessage);
    final billNo = _extractBillNo(userMessage, title: title);
    final poNo = _extractPoNo(userMessage);

    return StructuredVoucherMeta(
      title: title,
      billNo: billNo,
      poNo: poNo,
      rows: rows,
    );
  }

  /// Looks up the department code for [employeeName] from [employees].
  ///
  /// Matching is attempted in priority order — stops at the first hit:
  ///   1. Exact normalised match
  ///   2. All significant words from query appear in employee name
  ///   3. Spaceless comparison (e.g. "V. Karthickkumar" ↔ "V Karthick Kumar")
  ///   4. Word-prefix / word-infix match (one word is a prefix/suffix of another
  ///      corresponding word, handles split/merged spellings like
  ///      "karthickkumar" ↔ "karthick kumar")
  ///   5. Token-set overlap ≥ 60 % (handles partial-name records)
  ///   6. First significant word contained in employee name (original fuzzy)
  ///
  /// Returns null if not found or if the found employee has no code.
  static String? lookupDeptCode(
    String employeeName,
    List<EmployeeModel> employees,
  ) {
    if (employees.isEmpty || employeeName.isEmpty) return null;

    // Normalise: lower-case, strip punctuation/diacritics, collapse spaces.
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final normalized = norm(employeeName);
    final words = normalized.split(' ').where((w) => w.length > 2).toList();

    // ── 1. Exact match ──────────────────────────────────────────────────────
    for (final emp in employees) {
      if (norm(emp.name) == normalized && emp.code.isNotEmpty) {
        return emp.code;
      }
    }

    // ── 2. All significant words appear in employee name ────────────────────
    if (words.isNotEmpty) {
      for (final emp in employees) {
        final empNorm = norm(emp.name);
        if (words.every((w) => empNorm.contains(w)) &&
            emp.code.isNotEmpty) {
          return emp.code;
        }
      }
    }

    // ── 3. Spaceless comparison ─────────────────────────────────────────────
    // "V. Karthickkumar" → "vkarthickkumar"
    // "V Karthick Kumar" → "vkarthickkumar"  ← exact match ✓
    // Also catches reversed space merges and minor punctuation differences.
    final noSpace = normalized.replaceAll(' ', '');
    if (noSpace.isNotEmpty) {
      for (final emp in employees) {
        final empNoSpace = norm(emp.name).replaceAll(' ', '');
        if (empNoSpace == noSpace && emp.code.isNotEmpty) {
          return emp.code;
        }
        // Also try if one is a sub-sequence of the other (handles initials)
        if ((empNoSpace.contains(noSpace) || noSpace.contains(empNoSpace)) &&
            empNoSpace.isNotEmpty &&
            noSpace.isNotEmpty &&
            emp.code.isNotEmpty) {
          // Length ratio guard: avoid matching "vi" against "vivek subramaniam"
          final shorter =
              empNoSpace.length < noSpace.length ? empNoSpace : noSpace;
          final longer =
              empNoSpace.length >= noSpace.length ? empNoSpace : noSpace;
          if (shorter.length / longer.length >= 0.55) {
            return emp.code;
          }
        }
      }
    }

    // ── 4. Word-prefix / word-infix match ───────────────────────────────────
    // Handles split/merged word spellings between input and master data.
    // e.g. query word "karthickkumar" matches master words ["karthick","kumar"]
    //      because the master words joined = "karthickkumar".
    if (words.isNotEmpty) {
      for (final emp in employees) {
        final empNorm = norm(emp.name);
        final empWords =
            empNorm.split(' ').where((w) => w.length > 1).toList();
        final empJoined = empWords.join('');

        bool allWordsMatch = words.every((qw) {
          // Direct substring in joined employee name (handles merging)
          if (empJoined.contains(qw)) return true;
          // Or any employee word starts with / contains the query word
          if (empWords.any((ew) =>
              ew.startsWith(qw) ||
              qw.startsWith(ew) ||
              ew.contains(qw) ||
              qw.contains(ew))) return true;
          return false;
        });

        if (allWordsMatch && emp.code.isNotEmpty) return emp.code;
      }

      // Reverse: check if employee words appear in the query's joined form
      final queryJoined = words.join('');
      for (final emp in employees) {
        final empNorm = norm(emp.name);
        final empWords =
            empNorm.split(' ').where((w) => w.length > 2).toList();
        if (empWords.isEmpty) continue;

        bool allEmpWordsMatch = empWords.every((ew) =>
            queryJoined.contains(ew) ||
            words.any((qw) =>
                qw.startsWith(ew) ||
                ew.startsWith(qw) ||
                qw.contains(ew) ||
                ew.contains(qw)));

        if (allEmpWordsMatch && emp.code.isNotEmpty) return emp.code;
      }
    }

    // ── 5. Token-set overlap ≥ 60 % ────────────────────────────────────────
    // Useful when records have extra/fewer name parts (e.g. middle names).
    if (words.length >= 2) {
      final querySet = words.toSet();
      for (final emp in employees) {
        if (emp.code.isEmpty) continue;
        final empWords = norm(emp.name)
            .split(' ')
            .where((w) => w.length > 2)
            .toSet();
        if (empWords.isEmpty) continue;

        final intersection =
            querySet.intersection(empWords).length.toDouble();
        final union = querySet.union(empWords).length.toDouble();
        if (union > 0 && intersection / union >= 0.60) {
          return emp.code;
        }
      }
    }

    // ── 6. First significant word contained in employee name (fallback) ─────
    if (words.isNotEmpty) {
      for (final emp in employees) {
        final empNorm = norm(emp.name);
        if (empNorm.contains(words.first) && emp.code.isNotEmpty) {
          return emp.code;
        }
      }
    }

    // ── 7. Edit-distance (Levenshtein) fuzzy match ──────────────────────────
    // Catches spelling mistakes / typos such as:
    //   "soham boridkar"  →  "saham boradikar"   (1 edit per word)
    //   "karthik"         →  "karthick"           (1 insertion)
    // Every significant query word must find a master word whose
    // similarity >= threshold. Single-word queries use a tighter threshold.
    if (words.isNotEmpty) {
      const double multiWordThreshold  = 0.75;
      const double singleWordThreshold = 0.85;
      final threshold =
          words.length == 1 ? singleWordThreshold : multiWordThreshold;

      for (final emp in employees) {
        if (emp.code.isEmpty) continue;
        final empWords = norm(emp.name)
            .split(' ')
            .where((w) => w.length > 1)
            .toList();
        if (empWords.isEmpty) continue;

        final allMatch = words.every((qw) {
          for (final ew in empWords) {
            if (_stringSimilarity(qw, ew) >= threshold) return true;
          }
          return false;
        });

        if (allMatch) return emp.code;
      }
    }

    return null;
  }

  // ── Edit-distance helpers ──────────────────────────────────────────────────

  /// Character-level similarity: 1 − (editDistance / maxLength).
  /// Returns 1.0 for identical strings, 0.0 for completely different ones.
  static double _stringSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - dist / maxLen;
  }

  /// Standard Levenshtein edit distance (insert / delete / substitute = 1).
  /// Uses a single rolling row — O(n) memory, O(m×n) time.
  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List<int>.generate(n + 1, (j) => j);
    for (int i = 1; i <= m; i++) {
      int prev = dp[0];
      dp[0] = i;
      for (int j = 1; j <= n; j++) {
        final temp = dp[j];
        dp[j] = a[i - 1] == b[j - 1]
            ? prev
            : 1 + _min3(prev, dp[j], dp[j - 1]);
        prev = temp;
      }
    }
    return dp[n];
  }

  static int _min3(int a, int b, int c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);

  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the best-matching [EmployeeModel] for [rawName] from [employees],
  /// applying all 7 strategies directly against the employee list so it works
  /// correctly even when multiple employees share the same department code.
  /// Returns null if no confident match is found.
  static EmployeeModel? findBestEmployee(
    String rawName,
    List<EmployeeModel> employees,
  ) {
    if (employees.isEmpty || rawName.isEmpty) return null;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final normalized = norm(rawName);
    final words = normalized.split(' ').where((w) => w.length > 2).toList();

    // 1. Exact
    for (final emp in employees) {
      if (norm(emp.name) == normalized) return emp;
    }

    // 2. All words in master name
    if (words.isNotEmpty) {
      for (final emp in employees) {
        final en = norm(emp.name);
        if (words.every((w) => en.contains(w))) return emp;
      }
    }

    // 3. Spaceless
    final noSpace = normalized.replaceAll(' ', '');
    if (noSpace.isNotEmpty) {
      for (final emp in employees) {
        final ens = norm(emp.name).replaceAll(' ', '');
        if (ens == noSpace) return emp;
        if (ens.isNotEmpty &&
            (ens.contains(noSpace) || noSpace.contains(ens))) {
          final shorter = ens.length < noSpace.length ? ens : noSpace;
          final longer  = ens.length >= noSpace.length ? ens : noSpace;
          if (shorter.length / longer.length >= 0.55) return emp;
        }
      }
    }

    // 4. Word-prefix / infix
    if (words.isNotEmpty) {
      for (final emp in employees) {
        final ew = norm(emp.name).split(' ').where((w) => w.length > 1).toList();
        final ej = ew.join('');
        if (words.every((qw) =>
            ej.contains(qw) ||
            ew.any((e) =>
                e.startsWith(qw) || qw.startsWith(e) ||
                e.contains(qw)   || qw.contains(e)))) return emp;
      }
      final qj = words.join('');
      for (final emp in employees) {
        final ew = norm(emp.name).split(' ').where((w) => w.length > 2).toList();
        if (ew.isEmpty) continue;
        if (ew.every((e) =>
            qj.contains(e) ||
            words.any((qw) =>
                qw.startsWith(e) || e.startsWith(qw) ||
                qw.contains(e)   || e.contains(qw)))) return emp;
      }
    }

    // 5. Token-set overlap >= 60 %
    if (words.length >= 2) {
      final qs = words.toSet();
      for (final emp in employees) {
        final es = norm(emp.name).split(' ').where((w) => w.length > 2).toSet();
        if (es.isEmpty) continue;
        final inter = qs.intersection(es).length.toDouble();
        final union = qs.union(es).length.toDouble();
        if (union > 0 && inter / union >= 0.60) return emp;
      }
    }

    // 6. First word in master
    if (words.isNotEmpty) {
      for (final emp in employees) {
        if (norm(emp.name).contains(words.first)) return emp;
      }
    }

    // 7. Edit-distance fuzzy
    if (words.isNotEmpty) {
      const multiThreshold  = 0.75;
      const singleThreshold = 0.85;
      final threshold = words.length == 1 ? singleThreshold : multiThreshold;
      for (final emp in employees) {
        final ew = norm(emp.name).split(' ').where((w) => w.length > 1).toList();
        if (ew.isEmpty) continue;
        if (words.every((qw) =>
            ew.any((e) => _stringSimilarity(qw, e) >= threshold))) return emp;
      }
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Table parser
  // ─────────────────────────────────────────────────────────────────────────

  static List<StructuredVoucherRow> _parseMarkdownTable(String text) {
    final rows = <StructuredVoucherRow>[];
    final lines = text.split('\n');

    // Find header row: first pipe-line that has both a name-like column
    // header AND an amount-like column header.
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('|')) continue;
      final lower = line.toLowerCase();
      final hasName = lower.contains('name') ||
          lower.contains('employee') ||
          lower.contains('technician');
      final hasAmount =
          lower.contains('amount') || lower.contains('salary');
      if (hasName && hasAmount) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex == -1) return rows;

    // Parse header columns
    final headers = _splitPipe(lines[headerIndex]);
    int nameCol = -1, amountCol = -1, fromCol = -1, toCol = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();

      if (nameCol == -1 &&
          (h.contains('name') ||
              h.contains('employee') ||
              h.contains('technician')) &&
          !h.contains('no') &&
          !h.contains('no.')) {
        nameCol = i;
      } else if (amountCol == -1 &&
          (h.contains('amount') || h.contains('salary'))) {
        amountCol = i;
      } else if (fromCol == -1 &&
          (h == 'from' ||
              h == 'fr.' ||
              h == 'fr' ||
              h.startsWith('from') ||
              h == 'date from')) {
        fromCol = i;
      } else if (toCol == -1 &&
          (h == 'to' ||
              h.contains('upto') ||
              h.contains('up to') ||
              (h.contains('to') &&
                  !h.contains('total') &&
                  !h.contains('technician')))) {
        toCol = i;
      }
    }

    // Fallback: look for any column whose header contains "date"
    // for fromCol if still -1.
    if (fromCol == -1) {
      for (int i = 0; i < headers.length; i++) {
        if (i == toCol) continue;
        if (headers[i].toLowerCase().contains('date')) {
          fromCol = i;
          break;
        }
      }
    }

    if (nameCol == -1 || amountCol == -1) return rows;

    // Skip separator line (---...)
    int dataStart = headerIndex + 1;
    if (dataStart < lines.length) {
      final sep = lines[dataStart];
      if (sep.contains('---') || sep.contains('===')) {
        dataStart++;
      }
    }

    // Parse data rows
    for (int i = dataStart; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('|')) break; // end of table

      final cells = _splitPipe(line);

      // Need at least up to the amount column
      if (cells.length <= amountCol) continue;

      final rawName = nameCol < cells.length ? cells[nameCol] : '';

      // Skip empty or "total" rows
      if (rawName.isEmpty) continue;
      final nl = rawName.toLowerCase();
      if (nl == 'total' ||
          nl.startsWith('total') ||
          nl == 'grand total' ||
          nl.startsWith('grand total')) continue;

      final rawAmount =
          amountCol < cells.length ? cells[amountCol] : '';
      final rawFrom =
          (fromCol >= 0 && fromCol < cells.length) ? cells[fromCol] : '';
      final rawTo =
          (toCol >= 0 && toCol < cells.length) ? cells[toCol] : rawFrom;

      final amount = _parseAmount(rawAmount);
      if (amount == null || amount <= 0) continue;

      rows.add(StructuredVoucherRow(
        rawName: rawName,
        amount: amount,
        fromDate: _convertDate(rawFrom) ?? '',
        toDate: _convertDate(rawTo) ?? _convertDate(rawFrom) ?? '',
      ));
    }

    return rows;
  }

  /// Splits a markdown pipe row, trims each cell, drops empty edge cells.
  static List<String> _splitPipe(String line) {
    return line
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  /// Parses an amount string like "19,055" or "₹19055" → 19055.0.
  static double? _parseAmount(String raw) {
    if (raw.isEmpty) return null;
    final cleaned = raw
        .replaceAll(RegExp(r'[^\d.]'), '')
        .trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Converts DD/MM/YYYY, DD.MM.YYYY, DD/MM/YY, DD-MM-YYYY → YYYY-MM-DD.
  /// Returns null if the format is not recognised.
  static String? _convertDate(String raw) {
    if (raw.isEmpty || raw == '-' || raw == '–') return null;
    raw = raw.trim();

    // Already ISO YYYY-MM-DD
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;

    // DD/MM/YYYY  or  DD.MM.YYYY  or  DD/MM/YY
    final dmy = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})$');
    var m = dmy.firstMatch(raw);
    if (m != null) {
      final d = m.group(1)!.padLeft(2, '0');
      final mo = m.group(2)!.padLeft(2, '0');
      var y = m.group(3)!;
      if (y.length == 2) y = '20$y';
      return '$y-$mo-$d';
    }

    // DD-MM-YYYY
    final dmyDash = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{2,4})$');
    m = dmyDash.firstMatch(raw);
    if (m != null) {
      final d = m.group(1)!.padLeft(2, '0');
      final mo = m.group(2)!.padLeft(2, '0');
      var y = m.group(3)!;
      if (y.length == 2) y = '20$y';
      return '$y-$mo-$d';
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata extractors
  // ─────────────────────────────────────────────────────────────────────────

  /// Extracts voucher title from prompt text.
  /// Handles: named "X", name "X", title "X", voucher named X, etc.
  static String? _extractTitle(String text) {
    final patterns = [
      // named "X" or named 'X'
      RegExp(r'''named?\s+["']([^"']+)["']''', caseSensitive: false),
      // title "X" or title 'X'
      RegExp(r'''title\s+["']([^"']+)["']''', caseSensitive: false),
      // voucher named/title/called X (quoted or bare word group)
      RegExp(
        r'''voucher\s+(?:named?|title|called)\s+["']?([A-Za-z0-9\s/&\-_.]{2,40}?)["']?(?:\s+and\b|\s+with\b|\s+bill\b|,|\.|\s*$)''',
        caseSensitive: false,
      ),
      // named X (bare, stop at common delimiters)
      RegExp(
        r'''named?\s+([A-Za-z0-9/&\-_.]{2,30})(?:\s+and\b|\s+with\b|\s+bill\b|,|\.|\s*$)''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final title = match.group(1)?.trim();
        if (title != null && title.isNotEmpty) return title;
      }
    }
    return null;
  }

  /// Extracts bill number from prompt.
  /// If the prompt contains "same bill no", returns [title] (same value as
  /// the voucher title), which is a common convention in this use-case.
  static String? _extractBillNo(String text, {String? title}) {
    // "same bill no" → use title
    if (title != null &&
        RegExp(r'\bsame\s+bill', caseSensitive: false).hasMatch(text)) {
      return title;
    }

    final patterns = [
      RegExp(
        r'''bill\s+no\.?\s*[:\-]?\s*[""]?([A-Za-z0-9/\-\.]{2,25})[""]?''',
        caseSensitive: false,
      ),
      RegExp(
        r'''bill\s+number\s*[:\-]?\s*[""]?([A-Za-z0-9/\-\.]{2,25})[""]?''',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final billNo = match.group(1)?.trim();
        if (billNo != null && billNo.isNotEmpty) return billNo;
      }
    }
    return null;
  }

  /// Extracts PO number from prompt or table heading.
  /// Handles: (PO 700042550), PO 700042550, po no. 700042550.
  static String? _extractPoNo(String text) {
    final patterns = [
      // (PO 700042550) — common in table headings
      RegExp(r'\(PO\s*([A-Za-z0-9\-]{5,20})\)', caseSensitive: false),
      // PO: 700042550  or  PO 700042550  or  PO#700042550
      RegExp(r'\bPO\s*[:\#]?\s*([A-Za-z0-9\-]{5,20})\b', caseSensitive: false),
      // po no. 700042550
      RegExp(r'po\s*no\.?\s*[:\-]?\s*([A-Za-z0-9\-]{5,20})',
          caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final poNo = match.group(1)?.trim();
        if (poNo != null && poNo.isNotEmpty) return poNo;
      }
    }
    return null;
  }
}