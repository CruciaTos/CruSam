// Fuzzy person/company name matching, tuned for names read from handwriting:
// initials ("P.V. Lokesh" → "Pacharla Venkata Lokesh"), abbreviations
// ("Mohd" → "Mohammed"), joined/split words ("Rajeshkumar" → "Rajesh Kumar")
// and small spelling slips ("Raulo" → "Rawlo").

class FuzzyName {
  FuzzyName._();

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9&]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _tokens(String s) =>
      normalize(s).split(' ').where((t) => t.isNotEmpty).toList();

  /// 1 - (edit distance / longer length).
  static double ratio(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final m = a.length, n = b.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0)..[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev = cur;
    }
    return 1 - prev[n] / (m > n ? m : n);
  }

  static bool _isSubsequence(String short, String long) {
    var i = 0;
    for (var j = 0; j < long.length && i < short.length; j++) {
      if (short.codeUnitAt(i) == long.codeUnitAt(j)) i++;
    }
    return i == short.length;
  }

  static double _tokenScore(String q, String c) {
    if (q == c) return 1;
    if (q.length == 1) {
      // An initial in the query matches a word with the same first letter.
      return q[0] == c[0] ? 0.9 : 0;
    }
    if (c.length == 1) {
      // A stored initial only weakly explains a spelled-out query word.
      return q[0] == c[0] ? 0.6 : 0;
    }
    var best = ratio(q, c);
    if (q.length >= 3 && c.length >= 3 && (c.startsWith(q) || q.startsWith(c))) {
      best = best < 0.85 ? 0.85 : best;
    }
    if (q[0] == c[0] && q.length >= 3) {
      final (s, l) = q.length <= c.length ? (q, c) : (c, q);
      if (_isSubsequence(s, l) && s.length / l.length >= 0.45) {
        best = best < 0.8 ? 0.8 : best;
      }
    }
    return best;
  }

  static double _coverage(List<String> from, List<String> to) {
    if (from.isEmpty) return 0;
    var sum = 0.0;
    for (final t in from) {
      var best = 0.0;
      for (final u in to) {
        final s = _tokenScore(t, u);
        if (s > best) best = s;
      }
      sum += best;
    }
    return sum / from.length;
  }

  /// Similarity in [0, 1] between a query (e.g. a handwritten name) and a
  /// stored name. Weighted towards "every word of the query is explained".
  static double score(String query, String candidate) {
    final q = _tokens(query), c = _tokens(candidate);
    if (q.isEmpty || c.isEmpty) return 0;
    final compact = ratio(q.join(), c.join());
    final tokenBased = 0.75 * _coverage(q, c) + 0.25 * _coverage(c, q);
    // Joined words: "rajeshkumar" vs "rajesh kumar ..." — compare the query's
    // compact form against the same-length prefix of the candidate's.
    final cj = c.join(), qj = q.join();
    final prefix = cj.length > qj.length ? cj.substring(0, qj.length) : cj;
    final prefixScore = ratio(qj, prefix) * (0.75 + 0.25 * qj.length / cj.length);
    var s = compact;
    if (tokenBased > s) s = tokenBased;
    if (prefixScore > s) s = prefixScore;
    return s > 1 ? 1 : s;
  }

  /// Ranks [candidates] against [query]; returns (index, score) pairs with
  /// score >= [minScore], best first, at most [limit].
  static List<(int, double)> rank(
    String query,
    List<String> candidates, {
    double minScore = 0.5,
    int limit = 5,
  }) {
    final scored = <(int, double)>[];
    for (var i = 0; i < candidates.length; i++) {
      final s = score(query, candidates[i]);
      if (s >= minScore) scored.add((i, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).toList();
  }
}
