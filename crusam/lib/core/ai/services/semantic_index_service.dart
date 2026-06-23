// crusam/lib/core/ai/services/semantic_index_service.dart
//
// §5.5 of Phase 2 Implementation Brief — the one public entry point for
// semantic search across all IndexDomains.
//
// ── Responsibilities ─────────────────────────────────────────────────────
//
//   1. Ensure the domain index is fresh (delegates to SemanticIndexBuilder).
//   2. Stage-1: Try structured / exact resolution per §4's per-domain rules.
//      If unambiguous → return immediately, skip vector search.
//   3. Stage-2: Tokenize rawQuery, build TF-IDF query vector using the
//      domain's stored IDF, score every entry via cosineSimilarity, drop
//      scores below the noise floor, sort descending, take topK.
//   4. Always compute & attach the cheap aggregate summary (per §4)
//      regardless of match count.
//   5. Return SemanticSearchResult.
//
// ── Top-K defaults (per §4.1 / §4.2 / §4.3 token-reduction rule) ────────
//
//   • QueryGranularity.specific               → topK = 5
//   • QueryGranularity.full + filter hint      → topK = 15
//   • QueryGranularity.full + no filter hint   → topK = 0 (aggregate only)
//
// ── In-memory cache ──────────────────────────────────────────────────────
//
//   Domain entries and IDF weights are loaded from SemanticIndexRepository
//   once per session and cached.  SemanticIndexBuilder calls invalidate()
//   after a rebuild to force a reload on the next search.
//
// ── No Flutter widget imports ────────────────────────────────────────────
//
//   Only flutter/foundation is imported (for kDebugMode / debugPrint).
//   Safe to call from any context; no BuildContext dependency.

library;

import 'package:flutter/foundation.dart';

import 'package:crusam/core/ai/services/classification_result.dart';
import 'package:crusam/core/ai/services/employee_matcher.dart';
import 'package:crusam/core/ai/services/semantic_index_builder.dart';
import 'package:crusam/core/ai/services/semantic_index_models.dart';
import 'package:crusam/core/ai/services/semantic_index_repository.dart';
import 'package:crusam/core/ai/services/text_vectorizer.dart';
import 'package:crusam/data/db/database_helper.dart';
import 'package:crusam/data/models/employee_model.dart';

// ── Service ──────────────────────────────────────────────────────────────────

class SemanticIndexService {
  SemanticIndexService._();
  static final SemanticIndexService instance = SemanticIndexService._();

  // ── In-memory cache ────────────────────────────────────────────────────────
  //
  // Loaded lazily on first search per domain; invalidated by the builder after
  // a rebuild so the next search reloads fresh data from the repository.

  final _entries = <IndexDomain, List<IndexEntry>>{};
  final _idf = <IndexDomain, Map<String, double>>{};

  // ── Top-K and scoring constants ────────────────────────────────────────────

  /// Default topK for [QueryGranularity.specific] queries.
  static const int _topKSpecific = 5;

  /// Default topK for [QueryGranularity.full] queries that carry a filter
  /// hint (month, year, billNo, entity name).
  static const int _topKFullFiltered = 15;

  /// Cosine similarity below this threshold is treated as noise and dropped.
  static const double _noiseFloor = 0.05;

  /// Score assigned to exact-match / structured-match hits.
  static const double _exactScore = 1.0;

  /// Score assigned to fuzzy-name / filter-based hits.
  static const double _fuzzyScore = 0.9;

  // ── Cache invalidation (called by SemanticIndexBuilder) ────────────────────

  /// Evicts the in-memory cache for [domain] so the next [search] call
  /// reloads entries + IDF from [SemanticIndexRepository].
  void invalidate(IndexDomain domain) {
    _entries.remove(domain);
    _idf.remove(domain);
    if (kDebugMode) {
      debugPrint('[SemanticIndexService] cache invalidated for $domain');
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Searches [domain] for records relevant to the classified [rawQuery].
  ///
  /// The [classification] drives granularity-aware topK selection and
  /// provides entity hints (names, IDs, month, year, billNo) for Stage-1
  /// structured resolution.
  ///
  /// Returns a [SemanticSearchResult] with scored hits and an aggregate
  /// summary — even when [matched] is empty.
  Future<SemanticSearchResult> search({
    required IndexDomain domain,
    required ClassificationResult classification,
    required String rawQuery,
    int? topK,
  }) async {
    // ── 0. Ensure the domain index is current ────────────────────────────
    await SemanticIndexBuilder.instance.ensureFresh(domain);

    // ── 0a. Load entries + IDF into memory if not cached ─────────────────
    await _ensureLoaded(domain);

    final entries = _entries[domain] ?? const [];
    final idf = _idf[domain] ?? const {};

    // ── 0b. Resolve effective topK ───────────────────────────────────────
    final effectiveTopK = topK ?? _resolveTopK(classification);

    if (kDebugMode) {
      debugPrint(
        '[SemanticIndexService] search($domain) — '
        '${entries.length} entries, topK=$effectiveTopK, '
        'granularity=${classification.granularity.name}',
      );
    }

    // ── 1. Stage-1: structured / exact resolution ────────────────────────
    final stage1 = await _stage1Resolve(domain, classification, entries);

    if (stage1 != null && stage1.length == 1) {
      // Unambiguous structured hit → return immediately, skip vector search.
      final aggregate = _computeAggregate(domain, entries);
      return SemanticSearchResult(
        domain: domain,
        matched: stage1,
        aggregateSummary: aggregate,
        totalCandidates: entries.length,
      );
    }

    // If Stage-1 returned multiple structured hits, they become candidates
    // for the final result (merged with vector hits below).
    final structuredHits = stage1 ?? const <RetrievedRecord>[];

    // ── 2. Stage-2: TF-IDF vector search ─────────────────────────────────
    List<RetrievedRecord> vectorHits = const [];

    if (effectiveTopK > 0 && rawQuery.trim().isNotEmpty && idf.isNotEmpty) {
      final queryVec = buildQueryVector(rawQuery, idf);

      if (queryVec.isNotEmpty) {
        final scored = <RetrievedRecord>[];

        // Track Stage-1 record IDs to avoid duplicates.
        final stage1Ids = structuredHits.map((r) => r.entry.recordId).toSet();

        for (final entry in entries) {
          if (stage1Ids.contains(entry.recordId)) continue;

          final sim = cosineSimilarity(queryVec, entry.termVector);
          if (sim >= _noiseFloor) {
            scored.add(
              RetrievedRecord(
                entry: entry,
                score: sim,
                reason: MatchReason.vector,
              ),
            );
          }
        }

        scored.sort((a, b) => b.score.compareTo(a.score));
        vectorHits = scored.take(effectiveTopK).toList();
      }
    }

    // ── 3. Merge Stage-1 + Stage-2, cap at topK ─────────────────────────
    final merged = <RetrievedRecord>[...structuredHits, ...vectorHits];

    // Sort by score descending, then cap if needed.
    merged.sort((a, b) => b.score.compareTo(a.score));

    final capped =
        effectiveTopK > 0 && merged.length > effectiveTopK
            ? merged.sublist(0, effectiveTopK)
            : merged;

    // ── 4. Always compute aggregate summary ─────────────────────────────
    final aggregate = _computeAggregate(domain, entries);

    if (kDebugMode) {
      debugPrint(
        '[SemanticIndexService] $domain result — '
        '${capped.length} hits (${structuredHits.length} stage-1, '
        '${vectorHits.length} stage-2)',
      );
    }

    return SemanticSearchResult(
      domain: domain,
      matched: capped,
      aggregateSummary: aggregate,
      totalCandidates: entries.length,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Stage-1: Structured / exact resolution
  // ══════════════════════════════════════════════════════════════════════════

  /// Attempts structured resolution for [domain] using entity hints from
  /// [classification].  Returns `null` if no structured path applies,
  /// or a list of [RetrievedRecord]s when structured matching finds hits.
  Future<List<RetrievedRecord>?> _stage1Resolve(
    IndexDomain domain,
    ClassificationResult classification,
    List<IndexEntry> entries,
  ) async {
    return switch (domain) {
      IndexDomain.employees => _stage1Employees(classification, entries),
      IndexDomain.vouchers => _stage1Vouchers(classification, entries),
      IndexDomain.salarySnapshots => _stage1SalarySnapshots(
        classification,
        entries,
      ),
    };
  }

  // ── §4.1 Employees ────────────────────────────────────────────────────────
  //
  // Stage-1 resolution order:
  //   1. extractedEntityIds → exact ID match against recordId
  //   2. extractedEntityNames → EmployeeMatcher (imported from employee_matcher.dart)
  //      • exact/high confidence → return single hit
  //      • low confidence → return single hit (fuzzyName reason)
  //      • none with candidates → return all candidates for disambiguation

  Future<List<RetrievedRecord>?> _stage1Employees(
    ClassificationResult classification,
    List<IndexEntry> entries,
  ) async {
    if (entries.isEmpty) return null;

    // ── 1a. Exact ID lookup ──────────────────────────────────────────────
    if (classification.extractedEntityIds.isNotEmpty) {
      final idSet =
          classification.extractedEntityIds.map((id) => id.toString()).toSet();

      final hits =
          entries
              .where((e) => idSet.contains(e.recordId))
              .map(
                (e) => RetrievedRecord(
                  entry: e,
                  score: _exactScore,
                  reason: MatchReason.exactId,
                ),
              )
              .toList();

      if (hits.isNotEmpty) return hits;
    }

    // ── 1b. EmployeeMatcher for name resolution ──────────────────────────
    if (classification.extractedEntityNames.isNotEmpty) {
      // Load employees from DB to construct the matcher.
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      final employees = empMaps.map((m) => EmployeeModel.fromMap(m)).toList();

      if (employees.isEmpty) return null;

      final matcher = EmployeeMatcher(employees);
      final allHits = <RetrievedRecord>[];

      for (final name in classification.extractedEntityNames) {
        final result = matcher.resolve(name);

        switch (result.confidence) {
          case NameMatchConfidence.exact:
          case NameMatchConfidence.high:
            if (result.employee != null) {
              final entry = _findEntryByRecordId(
                entries,
                result.employee!.id.toString(),
              );
              if (entry != null) {
                allHits.add(
                  RetrievedRecord(
                    entry: entry,
                    score: _exactScore,
                    reason:
                        result.confidence == NameMatchConfidence.exact
                            ? MatchReason.exactName
                            : MatchReason.exactName,
                  ),
                );
              }
            }

          case NameMatchConfidence.low:
            if (result.employee != null) {
              final entry = _findEntryByRecordId(
                entries,
                result.employee!.id.toString(),
              );
              if (entry != null) {
                allHits.add(
                  RetrievedRecord(
                    entry: entry,
                    score: _fuzzyScore,
                    reason: MatchReason.fuzzyName,
                  ),
                );
              }
            }

          case NameMatchConfidence.none:
            // Multiple ambiguous candidates — return them all so the LLM
            // can ask the user to disambiguate.
            if (result.candidates.isNotEmpty) {
              for (final candidate in result.candidates) {
                final entry = _findEntryByRecordId(
                  entries,
                  candidate.id.toString(),
                );
                if (entry != null) {
                  allHits.add(
                    RetrievedRecord(
                      entry: entry,
                      score: _fuzzyScore,
                      reason: MatchReason.fuzzyName,
                    ),
                  );
                }
              }
            }
        }
      }

      if (allHits.isNotEmpty) return allHits;
    }

    return null; // No structured path matched → fall through to Stage-2.
  }

  // ── §4.2 Vouchers ─────────────────────────────────────────────────────────
  //
  // Stage-1 resolution:
  //   1. billNoHint → exact match against displayText (bill_no is the first
  //      segment of displayText, e.g. "INV-042 · ABC Corp · ₹45,000 · …")
  //   2. extractedEntityIds → exact ID match against recordId

  Future<List<RetrievedRecord>?> _stage1Vouchers(
    ClassificationResult classification,
    List<IndexEntry> entries,
  ) async {
    if (entries.isEmpty) return null;

    // ── 1a. Bill number exact match ──────────────────────────────────────
    if (classification.billNoHint != null) {
      final billNo = classification.billNoHint!.toLowerCase();

      final hits =
          entries
              .where(
                (e) =>
                    e.displayText.toLowerCase().contains(billNo) ||
                    e.searchText.toLowerCase().contains(billNo),
              )
              .map(
                (e) => RetrievedRecord(
                  entry: e,
                  score: _exactScore,
                  reason: MatchReason.exactCode,
                ),
              )
              .toList();

      if (hits.isNotEmpty) return hits;
    }

    // ── 1b. Exact ID lookup ──────────────────────────────────────────────
    if (classification.extractedEntityIds.isNotEmpty) {
      final idSet =
          classification.extractedEntityIds.map((id) => id.toString()).toSet();

      final hits =
          entries
              .where((e) => idSet.contains(e.recordId))
              .map(
                (e) => RetrievedRecord(
                  entry: e,
                  score: _exactScore,
                  reason: MatchReason.exactId,
                ),
              )
              .toList();

      if (hits.isNotEmpty) return hits;
    }

    return null;
  }

  // ── §4.3 Salary Snapshots ──────────────────────────────────────────────────
  //
  // Stage-1 resolution:
  //   1. extractedEntityNames + monthHint/yearHint → filter by employee name
  //      AND time period (narrow intersection).
  //   2. extractedEntityNames alone → filter by employee name.
  //   3. monthHint / yearHint alone → filter by time period.
  //   4. extractedEntityIds → exact employee_id match.
  //
  // Salary snapshots use recordId = employee_id, secondaryId = snapshot_id,
  // and displayText contains "Name · MonthFull Year · ₹Amount".

  Future<List<RetrievedRecord>?> _stage1SalarySnapshots(
    ClassificationResult classification,
    List<IndexEntry> entries,
  ) async {
    if (entries.isEmpty) return null;

    final hasNames = classification.extractedEntityNames.isNotEmpty;
    final hasMonth = classification.monthHint != null;
    final hasYear = classification.yearHint != null;
    final hasIds = classification.extractedEntityIds.isNotEmpty;
    final hasFilter = hasNames || hasMonth || hasYear || hasIds;

    if (!hasFilter) return null;

    // Build a filter predicate combining all available hints.
    bool matchesEntry(IndexEntry e) {
      final display = e.displayText.toLowerCase();
      final search = e.searchText.toLowerCase();

      // Name filter: any extracted name must appear in displayText.
      if (hasNames) {
        final nameMatch = classification.extractedEntityNames.any(
          (n) => display.contains(n.toLowerCase()),
        );
        if (!nameMatch) return false;
      }

      // ID filter.
      if (hasIds) {
        final idSet =
            classification.extractedEntityIds
                .map((id) => id.toString())
                .toSet();
        if (!idSet.contains(e.recordId)) return false;
      }

      // Month filter: match against searchText which contains both short
      // and full month names, plus the zero-padded month number.
      if (hasMonth) {
        final monthLower = classification.monthHint!.toLowerCase();
        if (!search.contains(monthLower)) return false;
      }

      // Year filter.
      if (hasYear) {
        final yearStr = classification.yearHint!.toString();
        if (!search.contains(yearStr)) return false;
      }

      return true;
    }

    final hits =
        entries
            .where(matchesEntry)
            .map(
              (e) => RetrievedRecord(
                entry: e,
                score: _fuzzyScore,
                reason: MatchReason.filter,
              ),
            )
            .toList();

    return hits.isNotEmpty ? hits : null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Aggregate summary
  // ══════════════════════════════════════════════════════════════════════════

  /// Computes a cheap one-line aggregate summary for [domain] from the full
  /// corpus.  Always non-null when entries exist.
  String? _computeAggregate(IndexDomain domain, List<IndexEntry> entries) {
    if (entries.isEmpty) return null;

    return switch (domain) {
      IndexDomain.employees => _aggregateEmployees(entries),
      IndexDomain.vouchers => _aggregateVouchers(entries),
      IndexDomain.salarySnapshots => _aggregateSalarySnapshots(entries),
    };
  }

  /// "32 employees in index"
  String _aggregateEmployees(List<IndexEntry> entries) {
    return '${entries.length} employee${entries.length == 1 ? '' : 's'} '
        'in index';
  }

  /// "128 vouchers in index"
  String _aggregateVouchers(List<IndexEntry> entries) {
    return '${entries.length} voucher${entries.length == 1 ? '' : 's'} '
        'in index';
  }

  /// "245 salary snapshot records in index"
  String _aggregateSalarySnapshots(List<IndexEntry> entries) {
    // Count distinct employees (recordId = employee_id).
    final distinctEmployees = entries.map((e) => e.recordId).toSet().length;
    // Count distinct snapshots (secondaryId = snapshot_id).
    final distinctSnapshots =
        entries
            .where((e) => e.secondaryId != null)
            .map((e) => e.secondaryId)
            .toSet()
            .length;

    return '${entries.length} salary record${entries.length == 1 ? '' : 's'} '
        '· $distinctEmployees employee${distinctEmployees == 1 ? '' : 's'} '
        '· $distinctSnapshots snapshot${distinctSnapshots == 1 ? '' : 's'}';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// Loads entries + IDF for [domain] from the repository into the in-memory
  /// cache (no-op if already loaded).
  Future<void> _ensureLoaded(IndexDomain domain) async {
    if (_entries.containsKey(domain) && _idf.containsKey(domain)) return;

    final entries = await SemanticIndexRepository.instance.getDomainEntries(
      domain,
    );
    final idf = await SemanticIndexRepository.instance.getDomainIdf(domain);

    _entries[domain] = entries;
    _idf[domain] = idf;

    if (kDebugMode) {
      debugPrint(
        '[SemanticIndexService] loaded $domain — '
        '${entries.length} entries, ${idf.length} IDF terms',
      );
    }
  }

  /// Resolves the effective topK based on [classification] granularity and
  /// whether filter hints are present.
  ///
  /// • specific               → 5
  /// • full + has filter hints → 15
  /// • full + no filter hints  → 0 (aggregate only, no individual records)
  int _resolveTopK(ClassificationResult classification) {
    if (classification.granularity == QueryGranularity.specific) {
      return _topKSpecific;
    }

    // QueryGranularity.full — check for filter hints.
    if (classification.hasEntityHints) {
      return _topKFullFiltered;
    }

    // Pure "list all" / "how many" query → aggregate only.
    return 0;
  }

  /// Finds the first [IndexEntry] in [entries] whose [recordId] matches [id].
  IndexEntry? _findEntryByRecordId(List<IndexEntry> entries, String id) {
    for (final e in entries) {
      if (e.recordId == id) return e;
    }
    return null;
  }
}
