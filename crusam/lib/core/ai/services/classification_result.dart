// crusam/lib/core/ai/services/classification_result.dart
//
// Data model produced by IntentClassifier for every user query.
// Consumed by AiContextBuilder (Phase 3) to assemble minimal context.

/// App context domains — each maps to a distinct data section in AiContextBuilder.
enum ContextDomain {
  employees,
  salary,
  currentVoucher,
  savedVouchers,
  companyConfig,
}

/// How precisely the query targets data — drives retrieval strategy in Phase 2.
enum QueryGranularity {
  /// Query needs a broad view (e.g. "list all employees", "show salary summary").
  full,

  /// Query targets a specific record or subset
  /// (e.g. "salary of Rajesh April 2025", "invoice #INV-042").
  specific,
}

/// Output of [IntentClassifier.classify].
///
/// Three key things consumers care about:
///   1. [requiredDomains] — which data sections to load (empty = send no context)
///   2. [granularity]    — full load vs. targeted retrieval (Phase 2 hook)
///   3. entity hints     — names / IDs / dates that narrow retrieval
class ClassificationResult {
  const ClassificationResult({
    required this.requiredDomains,
    required this.granularity,
    this.extractedEntityNames = const [],
    this.extractedEntityIds = const [],
    this.monthHint,
    this.yearHint,
    this.billNoHint,
    this.domainScores = const {},
  });

  // ── Core output ────────────────────────────────────────────────────────────

  /// Which context domains are required to answer this query.
  /// Empty → no app data needed; skip context injection entirely.
  final Set<ContextDomain> requiredDomains;

  /// Whether the query is broad or targets a specific record.
  /// Used by the semantic index (Phase 2) to decide retrieval strategy.
  final QueryGranularity granularity;

  // ── Entity hints (Phase 2 retrieval keys) ─────────────────────────────────

  /// Employee or entity names mentioned in the original query.
  /// e.g. "salary of Rajesh Kumar" → ["Rajesh Kumar"]
  final List<String> extractedEntityNames;

  /// Numeric employee / record IDs mentioned in the query.
  /// e.g. "update employee id 42" → [42]
  final List<int> extractedEntityIds;

  /// Month name (lowercase) extracted from the query, if present.
  /// e.g. "april 2025 salary" → "april"
  final String? monthHint;

  /// 4-digit year extracted from the query, if present.
  final int? yearHint;

  /// Bill / invoice number extracted from the query, if present.
  /// e.g. "find invoice INV-042" → "INV-042"
  final String? billNoHint;

  // ── Debug / logging ────────────────────────────────────────────────────────

  /// Raw per-domain scores. Not used at runtime; exposed for logging only.
  final Map<ContextDomain, double> domainScores;

  // ── Convenience accessors ──────────────────────────────────────────────────

  bool get requiresNoContext => requiredDomains.isEmpty;
  bool get requiresContext   => requiredDomains.isNotEmpty;
  bool get isSpecificQuery   => granularity == QueryGranularity.specific;

  bool requires(ContextDomain domain) => requiredDomains.contains(domain);

  bool get hasEntityHints =>
      extractedEntityNames.isNotEmpty ||
      extractedEntityIds.isNotEmpty ||
      monthHint != null ||
      billNoHint != null;

  @override
  String toString() {
    if (requiresNoContext) return 'ClassificationResult(noContext)';
    return 'ClassificationResult('
        'domains=[${requiredDomains.map((d) => d.name).join(",")}], '
        'granularity=${granularity.name}, '
        'entities=$extractedEntityNames, '
        'ids=$extractedEntityIds, '
        'month=$monthHint, year=$yearHint, bill=$billNoHint'
        ')';
  }
}
