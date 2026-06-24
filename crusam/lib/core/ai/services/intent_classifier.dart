// crusam/lib/core/ai/services/intent_classifier.dart
//
// Pure rule-based intent classifier.  Zero LLM calls, zero async — runs
// synchronously before every sendMessage() call.
//
// ARCHITECTURE
// ─────────────────────────────────────────────────────────────────────────
// Each ContextDomain has a scorer that accumulates weighted keyword hits.
// A domain is included in the result only when its score clears a minimum
// threshold.  Scoring is additive across keyword groups, but each group
// contributes at most once (boolean "any match" per group), preventing
// the same concept repeated in a query from inflating the score.
//
// Entity extraction runs on the original-case query for regex accuracy.
//
// INTEGRATION POINT (Phase 3)
// ─────────────────────────────────────────────────────────────────────────
// In AiChatNotifier.sendMessage():
//
//   final classification = IntentClassifier.instance.classify(trimmed);
//   await _refreshContext(classification);   // pass to AiContextBuilder
//
// AiContextBuilder.build() will consume [ClassificationResult.requiredDomains]
// to skip loading unrelated data sections entirely.

import 'package:flutter/foundation.dart';
import 'classification_result.dart';

class IntentClassifier {
  IntentClassifier._();
  static final IntentClassifier instance = IntentClassifier._();

  // ── Tuning constants ───────────────────────────────────────────────────────

  /// A domain is included only when its accumulated score reaches this value.
  static const double _domainThreshold = 2.0;

  /// Below this total data-score, treat the query as conversational (no context).
  static const double _dataSignalFloor = 1.5;

  // ══════════════════════════════════════════════════════════════════════════
  // Public API
  // ══════════════════════════════════════════════════════════════════════════

  /// Classify [rawQuery] and return the minimal set of context domains needed.
  ///
  /// This is the only public method. Call it synchronously before assembling
  /// any context for the LLM.
  ClassificationResult classify(String rawQuery) {
    final raw   = rawQuery.trim();
    final query = raw.toLowerCase();

    if (query.isEmpty) {
      return const ClassificationResult(
        requiredDomains: {},
        granularity: QueryGranularity.full,
      );
    }

    // ── Score all domains ────────────────────────────────────────────────────
    final scores = <ContextDomain, double>{
      ContextDomain.employees:     _scoreEmployees(query),
      ContextDomain.salary:        _scoreSalary(query),
      ContextDomain.currentVoucher: _scoreCurrentVoucher(query),
      ContextDomain.savedVouchers: _scoreSavedVouchers(query),
      ContextDomain.companyConfig:  _scoreCompanyConfig(query),
    };
    final noneScore    = _scoreNone(query);
    final maxDataScore = scores.values.fold(0.0, (a, b) => a > b ? a : b);

    // ── Early exit: conversational query ────────────────────────────────────
    // Strong "none" signal AND no domain exceeds the data-signal floor.
    if (noneScore >= 4.0 && maxDataScore < _dataSignalFloor) {
      _log(rawQuery, {}, scores, noneScore);
      return ClassificationResult(
        requiredDomains: const {},
        granularity: QueryGranularity.full,
        domainScores: scores,
      );
    }

    // ── Build required domain set ────────────────────────────────────────────
    final required = <ContextDomain>{};
    for (final entry in scores.entries) {
      if (entry.value >= _domainThreshold) required.add(entry.key);
    }

    // If no domain cleared the threshold but there is some data signal,
    // pick the single highest-scoring domain rather than returning nothing.
    if (required.isEmpty && maxDataScore >= _dataSignalFloor) {
      final top = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
      required.add(top.key);
    }

    // If still empty after fallback → genuinely no context needed.
    if (required.isEmpty) {
      _log(rawQuery, {}, scores, noneScore);
      return ClassificationResult(
        requiredDomains: const {},
        granularity: QueryGranularity.full,
        domainScores: scores,
      );
    }

    // ── Extract entity hints ─────────────────────────────────────────────────
    final entityNames = _extractEntityNames(raw);   // original case for regex
    final entityIds   = _extractEntityIds(query);
    final monthHint   = _extractMonth(query);
    final yearHint    = _extractYear(query);
    final billNoHint  = _extractBillNo(raw);

    final isSpecific = entityNames.isNotEmpty ||
        entityIds.isNotEmpty ||
        monthHint != null ||
        yearHint != null ||
        billNoHint != null;

    _log(rawQuery, required, scores, noneScore);

    return ClassificationResult(
      requiredDomains:      required,
      granularity:          isSpecific ? QueryGranularity.specific : QueryGranularity.full,
      extractedEntityNames: entityNames,
      extractedEntityIds:   entityIds,
      monthHint:            monthHint,
      yearHint:             yearHint,
      billNoHint:           billNoHint,
      domainScores:         scores,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Domain scorers
  // Each scorer returns an accumulated score.
  // Each _kw() call adds `weight` AT MOST ONCE (first keyword match wins),
  // so repeated synonyms in the query don't multiply the score.
  // ══════════════════════════════════════════════════════════════════════════

  double _scoreEmployees(String q) {
    double s = 0;

    // Core concept
    s += _kw(q, ['employee', 'staff', 'worker', 'technician', 'manpower'], 3.0);

    // CRUD actions
    s += _kw(q, [
      'add employee', 'new employee', 'create employee',
      'delete employee', 'remove employee',
      'update employee', 'edit employee',
    ], 4.0);

    // Statutory identifiers
    s += _kw(q, ['pf no', 'pf number', 'provident fund', 'uan no', 'uan number', 'uan'], 4.0);

    // Banking fields
    s += _kw(q, ['bank details', 'account number', 'ifsc', 'ifsc code'], 3.0);

    // Employment fields
    s += _kw(q, ['date of joining', 'joining date', 'doj', 'designation', 'zone'], 2.5);

    // Charge fields — be specific to avoid collision with salary scorer
    s += _kw(q, ['basic charges', 'other charges', 'gross salary'], 2.5);

    // List / count queries
    s += _kw(q, [
      'roster', 'all employees', 'employee list', 'employee count',
      'how many employees', 'who works', 'staff list', 'head count',
    ], 3.5);

    // Hiring / onboarding
    s += _kw(q, ['hire', 'onboard', 'recruit'], 2.0);

    return s;
  }

  double _scoreSalary(String q) {
    double s = 0;

    // Core concept
    s += _kw(q, ['salary', 'wage', 'payroll', 'compensation', 'pay slip', 'payslip'], 4.0);

    // Pay-action synonyms — covers "how much was Rajesh paid", "Rajesh's earnings",
    // "show payout for April".  Weight 3.0: strong signal but one step below
    // the unambiguous "salary"/"payroll" terms.
    s += _kw(q, ['paid', 'payout', 'earnings', 'earning', 'total pay', 'payment for'], 3.0);

    // Attendance
    s += _kw(q, ['days present', 'days worked', 'days attended', 'attendance'], 4.0);

    // Computed salary fields
    s += _kw(q, ['earned basic', 'earned gross', 'earned salary', 'prorated', 'net salary'], 4.0);

    // Statutory deductions
    s += _kw(q, ['pf deduction', 'esic', 'msw', 'professional tax', 'pt deduction',
                 'total deduction', 'deduction'], 3.5);

    // Outputs / statements
    s += _kw(q, ['disbursement', 'salary statement', 'salary report',
                 'invoice total', 'salary total', 'total earned',
                 'attachment a', 'attachment b'], 3.5);

    // Salary meta fields
    s += _kw(q, ['set days', 'set month', 'set year', 'salary month',
                 'set salary', 'salary data', 'total basic full',
                 'total gross full', 'invoice total'], 3.5);

    // Summary totals
    s += _kw(q, ['total basic', 'total gross'], 2.5);

    // Month mentioned alongside salary context already contributes via month
    // extraction; give a mild boost if present to help the fallback path.
    if (_monthNames.any((m) => q.contains(m))) s += 1.0;

    return s;
  }

  double _scoreCurrentVoucher(String q) {
    double s = 0;

    // Unambiguous current-draft phrases
    s += _kw(q, ['current voucher', 'voucher draft', 'active voucher',
                 'open voucher', 'this voucher'], 5.0);

    // Row operations
    s += _kw(q, ['add row', 'delete row', 'remove row', 'update row',
                 'voucher row', 'add to voucher', 'insert row',
                 'add entry', 'new row'], 4.5);

    // Voucher lifecycle
    s += _kw(q, ['approve voucher', 'save voucher', 'discard voucher',
                 'discard draft', 'approve current'], 4.5);

    // Field setters
    s += _kw(q, ['set voucher field', 'set title', 'voucher title',
                 'set dept code', 'set bill no', 'set po no',
                 'set client', 'item description'], 3.5);

    // "Draft" alone is a strong current-voucher signal
    s += _kw(q, ['draft'], 3.0);

    // Date range (usually for a row being added)
    s += _kw(q, ['from date', 'to date', 'from_date', 'to_date'], 2.0);

    // Totals of the current voucher
    s += _kw(q, ['base total', 'grand total', 'voucher total',
                 'voucher amount', 'current total'], 2.5);

    // Generic "voucher" — below threshold alone but combines with others.
    // Scores 2.5 so that "voucher" alone clears the 2.0 threshold and
    // defaults to the active draft (most common intent).
    s += _kw(q, ['voucher'], 2.5);

    return s;
  }

  double _scoreSavedVouchers(String q) {
    double s = 0;

    // Unambiguous saved-invoice phrases
    s += _kw(q, ['saved voucher', 'saved invoice', 'all invoices',
                 'invoice list', 'all vouchers', 'voucher list',
                 'past voucher', 'previous voucher', 'historical voucher',
                 'old voucher', 'old invoice'], 5.0);

    // "Invoice" alone strongly implies saved records (no draft invoice concept)
    s += _kw(q, ['invoice', 'invoiced', 'total invoiced'], 3.5);

    // Lookup by identifier
    s += _kw(q, ['bill number', 'bill no', 'invoice number', 'find invoice',
                 'invoice #', 'search invoice'], 3.5);

    // Status queries
    s += _kw(q, ['approved voucher', 'approved invoice'], 3.0);

    // GST breakdown (only relevant for saved/finalized vouchers)
    s += _kw(q, ['cgst', 'sgst', 'tax breakdown', 'final total'], 2.5);

    // Client info query against saved records
    s += _kw(q, ['client name', 'client address', 'client gstin'], 2.0);

    // Generic "voucher" — weak; combined with other signals only.
    s += _kw(q, ['voucher'], 1.5);

    // Bare "bill" — covers "show bill INV-042", "bill INV-003".
    // 2.0 clears the domain threshold alone, which is intentional: "bill" in
    // this app almost always means a saved voucher, not a legislative bill.
    s += _kw(q, ['bill'], 2.0);

    return s;
  }

  double _scoreCompanyConfig(String q) {
    double s = 0;

    // Tax identifiers
    s += _kw(q, ['gstin', 'gst number', 'gst no', 'pan', 'pan number', 'pan card'], 5.0);

    // Config actions
    s += _kw(q, ['set company config', 'update config', 'company configuration',
                 'company settings', 'update company'], 5.0);

    // Specific config fields
    s += _kw(q, ['company name', 'company address', 'company phone',
                 'jurisdiction', 'declaration text', 'company declaration'], 4.0);

    // Company bank details (disambiguated from employee bank details by 'company')
    s += _kw(q, ['company bank', 'company account', 'company ifsc',
                 'company branch'], 4.0);

    // Weaker generic signals — only push over threshold when combined
    s += _kw(q, ['company'], 2.0);
    s += _kw(q, ['config', 'configuration', 'settings'], 2.0);

    return s;
  }

  /// Score for "this is conversational — no data needed".
  double _scoreNone(String q) {
    double s = 0;

    s += _kw(q, ['hello', 'hi', 'hey', 'greetings',
                 'good morning', 'good afternoon', 'good evening'], 5.0);
    s += _kw(q, ['how are you', 'how r u', "how's it going", 'how do you do'], 5.0);
    s += _kw(q, ['thank you', 'thanks', 'thank u', 'thx', 'cheers'], 5.0);
    s += _kw(q, ['what can you do', 'what can you help', 'who are you',
                 'what are you', 'tell me about yourself', 'introduce yourself'], 4.0);
    s += _kw(q, ['okay', 'ok', 'got it', 'understood', 'alright',
                 'sounds good', 'perfect', 'great'], 3.0);
    s += _kw(q, ['bye', 'goodbye', 'see you', 'later'], 4.0);

    return s;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Entity extractors
  // Run on the ORIGINAL-CASE query for accurate regex matching.
  // ══════════════════════════════════════════════════════════════════════════

  static const _monthNames = [
    'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
    'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static const _monthNumberMap = {
    'january': 1,  'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3,    'mar': 3,
    'april': 4,    'apr': 4,
    'may': 5,
    'june': 6,     'jun': 6,
    'july': 7,     'jul': 7,
    'august': 8,   'aug': 8,
    'september': 9,'sep': 9,
    'october': 10, 'oct': 10,
    'november': 11,'nov': 11,
    'december': 12,'dec': 12,
  };

  // Reverse map used when a numeric month (04, 4) is parsed from the query.
  static const _monthNumToName = {
    1: 'january',  2: 'february', 3: 'march',    4: 'april',
    5: 'may',      6: 'june',     7: 'july',      8: 'august',
    9: 'september',10: 'october', 11: 'november', 12: 'december',
  };

  /// Extract proper-noun names from the raw (original-case) query.
  ///
  /// Three patterns are tried:
  ///
  ///   Pattern 1 — preposition anchor:
  ///     "salary of Rajesh Kumar"  → ["Rajesh Kumar"]
  ///     "salary of rajesh"        → ["Rajesh"]  (via title-cased copy)
  ///
  ///   Pattern 2 — possessive / data-keyword suffix:
  ///     "Rajesh's salary"         → ["Rajesh"]
  ///     "Rajesh Kumar's details"  → ["Rajesh Kumar"]
  ///
  ///   Pattern 3 — domain keyword immediately before name, no preposition:
  ///     "salary Rajesh April 2026"  → ["Rajesh"]
  ///     "payroll Amit Kumar"        → ["Amit Kumar"]
  ///
  /// All three patterns are run on both the original query and a title-cased copy
  /// so that "salary of rajesh" and "salary of RAJESH" both extract correctly.
  /// The result set deduplicates automatically.
  List<String> _extractEntityNames(String raw) {
    final names = <String>{};

    // Build a title-cased copy so all-lowercase / ALL-CAPS inputs still fire.
    // Example: "salary of rajesh kumar" → "Salary Of Rajesh Kumar"
    final titleCased = raw.replaceAllMapped(
      RegExp(r'\b(\w)(\w*)'),
      (m) => m.group(1)!.toUpperCase() + (m.group(2) ?? '').toLowerCase(),
    );

    for (final source in <String>{raw, titleCased}) {
      // ── Pattern 1: preposition + title-cased name (1–4 words) ─────────────
      for (final m in RegExp(
        r'(?:of|for|by|about|named|called|employee)\s+'
        r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})',
      ).allMatches(source)) {
        final name = _trimTrailingStopWords(m.group(1)?.trim() ?? '');
        if (name.isNotEmpty && !_isNameStopWord(name)) names.add(name);
      }

      // ── Pattern 2: title-cased name followed by possessive/data keyword ───
      for (final m in RegExp(
        r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3})'
        r"(?:'s|\s+salary|\s+days|\s+attendance|\s+details|\s+info|\s+data|\s+account)",
      ).allMatches(source)) {
        final name = _trimTrailingStopWords(m.group(1)?.trim() ?? '');
        if (name.isNotEmpty && !_isNameStopWord(name)) names.add(name);
      }

      // ── Pattern 3: domain keyword directly before a name, no preposition ──
      // Handles "salary Rajesh April 2026", "payroll Amit Kumar", etc.
      // Captures at most 2 title-case words, then strips trailing stop-words
      // so month names ("April") don't bleed into the name.
      for (final m in RegExp(
        r'(?:salary|payroll|wage|wages|invoice|attendance)\s+'
        r'([A-Z][a-z]+)(?:\s+([A-Z][a-z]+))?',
        caseSensitive: false,
      ).allMatches(source)) {
        final part1 = m.group(1)?.trim() ?? '';
        final part2 = m.group(2)?.trim() ?? '';
        if (part1.isEmpty || _isNameStopWord(part1)) continue;
        // Accept second word only if it isn't a stop-word (month / domain term)
        final name = part2.isNotEmpty && !_isNameStopWord(part2)
            ? '$part1 $part2'
            : part1;
        names.add(name);
      }
    }

    return names.toList();
  }

  /// Strips trailing title-cased words that are domain stop-words or month names.
  ///
  /// Prevents Pattern 1/2 captures like "Rajesh April" from leaking the month
  /// into the extracted name when a date follows immediately.
  String _trimTrailingStopWords(String name) {
    if (name.isEmpty) return name;
    final words = name.split(RegExp(r'\s+'));
    while (words.isNotEmpty && _isNameStopWord(words.last)) {
      words.removeLast();
    }
    return words.join(' ');
  }

  /// Extract explicit numeric employee IDs from the lowercased query.
  ///
  /// Patterns:  "id 42", "employee id 42", "employee #42", "#42"
  List<int> _extractEntityIds(String q) {
    final ids = <int>[];
    final pattern = RegExp(r'(?:employee\s*)?(?:id|#)\s*(\d+)');
    for (final m in pattern.allMatches(q)) {
      final id = int.tryParse(m.group(1) ?? '');
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Extract a month name from the lowercased query.
  ///
  /// Handles both text ("april", "apr") and numeric forms ("04/2026", "2026-04").
  /// Always returns a full lowercase month name (e.g. "april") so downstream
  /// callers have a single canonical form to match against searchText.
  String? _extractMonth(String q) {
    // ── Numeric formats: MM/YYYY · YYYY-MM · YYYY/MM ─────────────────────────
    // Tried first so "04/2026" doesn't accidentally hit a text-name false-positive.
    final numFmt = RegExp(
      r'(?:^|\D)(0?[1-9]|1[0-2])[/\-](20\d{2})'    // MM/YYYY or MM-YYYY
      r'|(20\d{2})[/\-](0?[1-9]|1[0-2])(?:\D|$)',   // YYYY/MM or YYYY-MM
    );
    final nm = numFmt.firstMatch(q);
    if (nm != null) {
      // group(1) = month from MM/YYYY form; group(4) = month from YYYY-MM form
      final raw = nm.group(1) ?? nm.group(4);
      final n   = int.tryParse(raw ?? '');
      if (n != null) return _monthNumToName[n];
    }

    // ── Text names ────────────────────────────────────────────────────────────
    // Iterate in insertion order (full name before abbreviation) so "march" is
    // matched before "mar" — prevents the "mar" substring false-positive.
    for (final name in _monthNumberMap.keys) {
      if (q.contains(name)) return name;
    }
    return null;
  }

  /// Extract a 4-digit year (2000–2099) from the lowercased query.
  int? _extractYear(String q) {
    final m = RegExp(r'\b(20\d{2})\b').firstMatch(q);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  /// Extract a bill / invoice number from the original-case query.
  ///
  /// Pattern A — explicit separator:
  ///   "bill no INV-042", "invoice number INV-042", "invoice #INV-042", "#042"
  ///
  /// Pattern B — bare keyword + code:
  ///   "invoice INV-042", "find voucher INV-042", "show bill INV-042"
  ///   Requires the code to look like a bill number: 2–5 letters, a dash, digits.
  String? _extractBillNo(String raw) {
    // Pattern A: explicit separator keyword
    final mA = RegExp(
      r'(?:bill\s*(?:no|number)|invoice\s*(?:no|number)|invoice\s*#|#)\s*([A-Za-z0-9/_-]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (mA != null) return mA.group(1)?.trim();

    // Pattern B: bare "<keyword> <CODE>" where CODE looks like INV-042 / PO-003
    final mB = RegExp(
      r'(?:invoice|voucher|bill)\s+([A-Za-z]{2,6}-\d+)',
      caseSensitive: false,
    ).firstMatch(raw);
    return mB?.group(1)?.trim();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns [weight] if ANY keyword in [keywords] is found in [query].
  /// Each call contributes at most [weight] once — prevents over-counting
  /// when several synonyms appear in the same query.
  double _kw(String query, List<String> keywords, double weight) {
    for (final kw in keywords) {
      if (query.contains(kw)) return weight;
    }
    return 0.0;
  }

  /// Words that look like proper nouns but are domain keywords, not names.
  /// Checked against both whole-string captures and individual trailing words
  /// (via _trimTrailingStopWords) to prevent month / domain terms leaking in.
  static const _nameStopWords = {
    // Month names (title-cased, as they appear after normalisation)
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
    // Domain nouns that appear in title-case near names
    'Salary', 'Employee', 'Voucher', 'Invoice', 'Company',
    'Statement', 'Report', 'Summary', 'Details', 'Data', 'Info',
    'Payroll', 'Attendance', 'Record', 'Records', 'List', 'All',
  };

  bool _isNameStopWord(String word) => _nameStopWords.contains(word);

  void _log(
    String query,
    Set<ContextDomain> required,
    Map<ContextDomain, double> scores,
    double noneScore,
  ) {
    if (!kDebugMode) return;
    final domainsStr = required.isEmpty
        ? 'NONE (no context)'
        : required.map((d) => d.name).join(', ');
    final scoresStr = scores.entries
        .map((e) => '${e.key.name}=${e.value.toStringAsFixed(1)}')
        .join(' | ');
    debugPrint(
      'IntentClassifier: "$query"\n'
      '  → domains: $domainsStr\n'
      '  → scores:  $scoresStr | none=$noneScore',
    );
  }
}