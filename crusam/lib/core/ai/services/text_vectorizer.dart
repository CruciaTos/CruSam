// crusam/lib/core/ai/services/text_vectorizer.dart
//
// Pure-Dart TF-IDF + cosine similarity. No I/O, no Flutter imports — easy to
// unit test in isolation and safe to call from any isolate.
//
// This is the local "semantic-ish" retrieval primitive used by
// SemanticIndexBuilder (to build per-domain term vectors) and
// SemanticIndexService (to score a query against those vectors). It is
// intentionally NOT a neural embedding — see Phase 2 brief §3 for why a
// classic bag-of-words TF-IDF + cosine ranking is the right scope for this
// app's data size (tens–hundreds of employees, hundreds–low-thousands of
// vouchers/salary rows).
library;

import 'dart:math' as math;

/// Lowercases, strips non-alphanumeric characters, and splits on whitespace.
/// Tokens of length 1 are dropped (mostly punctuation remnants / noise).
List<String> tokenize(String text) {
  final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1)
      .toList(growable: false);
}

/// Log-normalized term frequency for a single document's tokens.
/// Using `1 + ln(count)` instead of a raw count keeps very long documents
/// (e.g. a voucher with many rows) from dominating purely on length.
Map<String, double> termFrequency(List<String> tokens) {
  final counts = <String, int>{};
  for (final t in tokens) {
    counts[t] = (counts[t] ?? 0) + 1;
  }
  final tf = <String, double>{};
  counts.forEach((term, count) {
    tf[term] = 1 + _ln(count);
  });
  return tf;
}

/// Smoothed IDF: idf(term) = ln(N / (1 + docFrequency)) + 1.
///
/// [allDocTermFreqs] should be the term-frequency map for every document in
/// the domain's corpus (i.e. the output of [termFrequency] called once per
/// document). This is computed once per domain rebuild, not per query.
Map<String, double> computeIdf(List<Map<String, double>> allDocTermFreqs) {
  final df = <String, int>{};
  for (final doc in allDocTermFreqs) {
    for (final term in doc.keys) {
      df[term] = (df[term] ?? 0) + 1;
    }
  }
  final n = allDocTermFreqs.length;
  return df.map((term, count) => MapEntry(term, _ln(n / (1 + count)) + 1));
}

/// Multiplies a document's term-frequency map by the domain's IDF weights,
/// producing the final TF-IDF vector for that document (or for a query,
/// when [idf] is the already-persisted domain IDF).
///
/// Terms with no IDF entry (i.e. never seen when the domain index was built
/// — typically only possible for a *query*, never for an indexed document)
/// fall back to a neutral weight of 1.0 rather than being dropped, so a
/// brand-new query term still contributes a little to the dot product.
Map<String, double> applyTfIdf(Map<String, double> tf, Map<String, double> idf) {
  final out = <String, double>{};
  tf.forEach((term, freq) {
    final weight = idf[term] ?? 1.0;
    out[term] = freq * weight;
  });
  return out;
}

/// Cosine similarity between two sparse TF-IDF vectors, in [0, 1] for
/// non-negative weights (which all weights here are).
double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0.0;

  double dot = 0, magA = 0, magB = 0;
  a.forEach((term, weight) {
    magA += weight * weight;
    final bw = b[term];
    if (bw != null) dot += weight * bw;
  });
  b.forEach((_, weight) => magB += weight * weight);

  if (magA == 0 || magB == 0) return 0.0;
  return dot / (_sqrt(magA) * _sqrt(magB));
}

/// Convenience: tokenize + term-frequency + apply a domain's stored IDF, in
/// one call. Used by SemanticIndexService to build a query vector against
/// the already-persisted IDF for a domain (we never recompute IDF at query
/// time — only at rebuild time).
Map<String, double> buildQueryVector(String rawQuery, Map<String, double> domainIdf) {
  final tf = termFrequency(tokenize(rawQuery));
  return applyTfIdf(tf, domainIdf);
}

// ── dart:math wrappers kept local so call sites above read standalone ──────
double _ln(num x) {
  if (x <= 0) return 0;
  if (x == 1) return 0;
  return math.log(x);
}

double _sqrt(num x) => math.sqrt(x);