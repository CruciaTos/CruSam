// crusam/lib/core/ai/services/semantic_index_formatter.dart
//
// §5.6 of Phase 2 Implementation Brief — turns a SemanticSearchResult into
// plain-text prompt content, completely decoupling formatting from retrieval.
//
// ── Design rationale ─────────────────────────────────────────────────────
//
//   AiContextBuilder never needs to know about TF-IDF, scoring, or the
//   IndexEntry schema.  It just calls `SemanticIndexFormatter.format(result)`
//   and gets back a trimmed UTF-8 string ready for injection into the prompt.
//
// ── Hard ceiling (safety net) ────────────────────────────────────────────
//
//   If the combined output for a single domain section exceeds
//   [_maxOutputChars] (~2 000 characters), individual record lines are
//   truncated (the aggregate summary is always kept, and as many top-
//   scoring records as fit are preserved).  A tail line is appended:
//
//     "...(N more matches not shown — ask for a specific name to see details)"
//
//   This guarantees Phase 2 can never regress to a full-table-dump even
//   if a future bug returns too many candidates upstream.
//
// ── No Flutter widget imports ────────────────────────────────────────────
//
//   Pure Dart, no I/O, no foundation import.  Safe anywhere.

library;

import 'package:crusam/core/ai/services/semantic_index_models.dart';

// ── Formatter ────────────────────────────────────────────────────────────────

class SemanticIndexFormatter {
  SemanticIndexFormatter._(); // Utility class — not instantiable.

  // ── Constants ──────────────────────────────────────────────────────────────

  /// Hard ceiling on the formatted output length (in characters) for a single
  /// domain section.  Roughly 2 000 chars ≈ ~500 LLM tokens — generous enough
  /// for most queries but short enough to prevent accidental full-table dumps.
  static const int _maxOutputChars = 2000;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Formats a [SemanticSearchResult] into a trimmed plain-text string suitable
  /// for direct injection into an LLM prompt.
  ///
  /// Structure of the output:
  /// ```
  /// <aggregateSummary>           ← always first, if present
  /// <matched[0].displayText>    ← top-scoring hit
  /// <matched[1].displayText>
  /// …
  /// ```
  ///
  /// If the combined text exceeds [_maxOutputChars], individual record lines
  /// are progressively dropped (lowest-scoring first) and a tail-line is
  /// appended indicating how many matches were omitted.
  static String format(SemanticSearchResult result) {
    // ── 1. Build the aggregate header (always kept) ──────────────────────

    final aggregateLine =
        result.aggregateSummary != null ? '${result.aggregateSummary}\n' : '';

    // Quick exit: nothing to format.
    if (result.matched.isEmpty) {
      return aggregateLine.trim();
    }

    // ── 2. Compute how many chars are left for record lines ─────────────

    final budgetForRecords = _maxOutputChars - aggregateLine.length;

    if (budgetForRecords <= 0) {
      // Degenerate case: the aggregate alone fills the budget.
      return aggregateLine.trim();
    }

    // ── 3. Greedily add top-scoring records until the budget runs out ────
    //
    //   matched[] is already sorted by score descending (SemanticIndexService
    //   guarantees this), so we iterate in order and keep as many as fit.

    final keptLines = <String>[];
    var usedChars = 0;
    var cutIndex = result.matched.length; // index of the first dropped record

    for (var i = 0; i < result.matched.length; i++) {
      final line = result.matched[i].entry.displayText;
      // +1 for the trailing newline we'll add between lines.
      final cost = line.length + 1;

      if (usedChars + cost > budgetForRecords) {
        cutIndex = i;
        break;
      }

      keptLines.add(line);
      usedChars += cost;
    }

    // ── 4. Assemble final output ─────────────────────────────────────────

    final sb = StringBuffer();

    if (aggregateLine.isNotEmpty) sb.write(aggregateLine);

    for (final line in keptLines) {
      sb.writeln(line);
    }

    final omitted = result.matched.length - keptLines.length;
    if (omitted > 0) {
      sb.writeln(
        '...($omitted more match${omitted == 1 ? '' : 'es'} not shown '
        '— ask for a specific name to see details)',
      );
    }

    return sb.toString().trim();
  }
}
