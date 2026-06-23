// crusam/lib/core/ai/services/semantic_index_models.dart
//
// Core data contracts for the semantic search layer.
//
// ┌─────────────────────────────────────────────────────────────┐
// │  IndexDomain       – which table/feature area owns a record │
// │  IndexEntry        – one searchable record in the corpus    │
// │  MatchReason       – how a retrieved record was surfaced    │
// │  RetrievedRecord   – a scored hit returned by the index     │
// │  SemanticSearchResult – the full result bundle per domain   │
// └─────────────────────────────────────────────────────────────┘
//
// No I/O, no Flutter imports — safe to use from any isolate and
// straightforward to unit-test in isolation.
//
// Consumed by:
//   • SemanticIndexBuilder   – builds IndexEntry lists from raw DB rows
//   • SemanticIndexService   – queries entries and returns SemanticSearchResult
//   • IntentClassifier       – reads SemanticSearchResult to fill context slots
library;

// ── Domain ─────────────────────────────────────────────────────────────────

/// Identifies which feature area a corpus entry belongs to.
///
/// Used to:
///  - namespace the index so a rebuild of one domain never touches others
///  - let [SemanticIndexService] fan out only to the domains a query touches
///  - give [IntentClassifier] a typed signal when injecting context
enum IndexDomain { employees, vouchers, salarySnapshots }

// ── IndexEntry ─────────────────────────────────────────────────────────────

/// A single searchable record stored in the in-memory corpus.
///
/// [termVector] is pre-computed at index-build time (via [applyTfIdf] in
/// text_vectorizer.dart) so query time is just a dot-product + magnitude,
/// never a tokenize/IDF round-trip.
class IndexEntry {
  const IndexEntry({
    required this.domain,
    required this.recordId,
    this.secondaryId,
    required this.displayText,
    required this.searchText,
    required this.termVector,
  });

  /// Which corpus this entry belongs to.
  final IndexDomain domain;

  /// String form of the source primary key (employee.id, voucher.id, …).
  final String recordId;

  /// Optional secondary key for entries that live inside a parent record.
  ///
  /// Examples:
  ///  - [IndexDomain.salarySnapshots]: the snapshot_id when [recordId] is the
  ///    employee_id of the owning employee.
  ///  - [IndexDomain.vouchers]:        the voucher_id when [recordId] is an
  ///    entry/line-item id and you want fast parent lookup.
  final String? secondaryId;

  /// Compact one-line human-readable summary shown when this entry is returned
  /// as a hit (e.g. "Ali Hassan – Sr. Engineer · Dept: Engineering").
  final String displayText;

  /// Normalized text fed into [tokenize] when the term vector was built.
  /// Kept on the entry so the builder can be re-run deterministically and
  /// so debug tooling can inspect what the index actually "sees".
  final String searchText;

  /// Pre-computed sparse TF-IDF vector: `{ term: weight }`.
  ///
  /// All weights are non-negative, so cosine similarity is in [0, 1].
  final Map<String, double> termVector;
}

// ── MatchReason ────────────────────────────────────────────────────────────

/// How a [RetrievedRecord] was surfaced — drives score assignment and
/// lets callers decide how to label or rank results in the UI / context blob.
///
/// Hierarchy (highest to lowest confidence):
///  exactId   – query matched an ID field character-for-character
///  exactName – query matched a name/code field case-insensitively
///  exactCode – query matched a short code (department, payroll code, …)
///  fuzzyName – query matched a name after light normalization
///  filter    – record passed a structured filter (date range, status, …)
///  vector    – cosine similarity above the relevance threshold
enum MatchReason { exactId, exactName, fuzzyName, exactCode, vector, filter }

// ── RetrievedRecord ────────────────────────────────────────────────────────

/// A single scored hit returned by [SemanticIndexService].
class RetrievedRecord {
  const RetrievedRecord({
    required this.entry,
    required this.score,
    required this.reason,
  });

  final IndexEntry entry;

  /// Normalised relevance score.
  ///
  /// • Exact / structured matches ([MatchReason.exactId], [MatchReason.exactName],
  ///   [MatchReason.exactCode]): always **1.0**.
  /// • [MatchReason.fuzzyName] / [MatchReason.filter]:  typically **0.9**.
  /// • [MatchReason.vector]: raw cosine similarity in **(0, 1)**.
  final double score;

  final MatchReason reason;
}

// ── SemanticSearchResult ───────────────────────────────────────────────────

/// The complete result bundle for a single domain after a search.
///
/// [SemanticIndexService] produces one [SemanticSearchResult] per domain that
/// was queried. The [IntentClassifier] merges these into the context payload
/// it injects into the LLM prompt — only fields relevant to the intent are
/// included, keeping token usage low.
class SemanticSearchResult {
  const SemanticSearchResult({
    required this.domain,
    required this.matched,
    this.aggregateSummary,
    required this.totalCandidates,
  });

  final IndexDomain domain;

  /// Top-K hits, sorted by [RetrievedRecord.score] descending.
  ///
  /// Already capped by [SemanticIndexService] before this object is built —
  /// callers should not re-slice this list.
  final List<RetrievedRecord> matched;

  /// Cheap aggregate statistics computed from the full domain corpus, e.g.:
  ///   "32 employees · avg salary ₹87,400 · 3 on probation"
  ///
  /// Populated whenever the domain has at least one candidate, even when
  /// [matched] is empty (so the LLM always has a count / summary to reason
  /// from). `null` only when the domain index has never been built.
  final String? aggregateSummary;

  /// Total number of records in the domain *before* any score filtering.
  ///
  /// Lets the LLM distinguish "only 1 employee named Ali" from "top 1 of 38".
  final int totalCandidates;

  /// `true` when there are no hits AND no aggregate summary to offer.
  ///
  /// The index service uses this to skip injecting a domain blob entirely,
  /// saving tokens on queries that don't touch that domain.
  bool get isEmpty => matched.isEmpty && aggregateSummary == null;
}
