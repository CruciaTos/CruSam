// lib/core/ai/services/employee_matcher.dart
import 'package:crusam/data/models/employee_model.dart';

enum NameMatchConfidence { exact, high, low, none }

class NameMatchResult {
  final EmployeeModel? employee;
  final NameMatchConfidence confidence;
  final String? issue;
  final List<EmployeeModel> candidates; // if multiple matches

  const NameMatchResult({
    this.employee,
    required this.confidence,
    this.issue,
    this.candidates = const [],
  });
}

class EmployeeMatcher {
  final List<EmployeeModel> _employees;

  EmployeeMatcher(this._employees);

  // ── Public API ─────────────────────────────────────────────────────────

  /// Full resolution returning confidence & candidates.
  NameMatchResult resolve(String rawName) {
    if (rawName.trim().isEmpty) {
      return const NameMatchResult(
        confidence: NameMatchConfidence.none,
        issue: 'Empty name',
      );
    }

    final normalized = _norm(rawName);
    final words = normalized
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();

    // 1. Exact normalised match
    final exact = _employees.where((e) => _norm(e.name) == normalized).toList();
    if (exact.length == 1) {
      return NameMatchResult(
        employee: exact.first,
        confidence: NameMatchConfidence.exact,
      );
    }
    if (exact.length > 1) {
      return _ambiguous('Exact match', rawName, exact);
    }

    // 2. All significant words appear in employee name
    if (words.isNotEmpty) {
      final allWords = _employees.where((e) {
        final en = _norm(e.name);
        return words.every((w) => en.contains(w));
      }).toList();
      if (allWords.length == 1) {
        return NameMatchResult(
          employee: allWords.first,
          confidence: NameMatchConfidence.high,
        );
      }
      if (allWords.length > 1) {
        return _ambiguous('All words contained', rawName, allWords);
      }
    }

    // 3. Spaceless comparison
    final noSpace = normalized.replaceAll(' ', '');
    if (noSpace.isNotEmpty) {
      final candidates = <EmployeeModel>[];
      for (final emp in _employees) {
        final ens = _norm(emp.name).replaceAll(' ', '');
        if (ens == noSpace) {
          candidates.add(emp);
        } else if (ens.isNotEmpty &&
            (ens.contains(noSpace) || noSpace.contains(ens))) {
          final shorter = ens.length < noSpace.length ? ens : noSpace;
          final longer = ens.length >= noSpace.length ? ens : noSpace;
          if (shorter.length / longer.length >= 0.55) {
            candidates.add(emp);
          }
        }
      }
      if (candidates.length == 1) {
        return _fuzzyLow(rawName, candidates.first, 'Spaceless/initials match');
      }
      if (candidates.length > 1) {
        return _ambiguous('Spaceless match', rawName, candidates);
      }
    }

    // 4. Word-prefix / infix match
    if (words.isNotEmpty) {
      final candidates = <EmployeeModel>[];
      for (final emp in _employees) {
        final ew = _norm(emp.name)
            .split(' ')
            .where((w) => w.length > 1)
            .toList();
        final ej = ew.join('');
        final allMatch = words.every((qw) =>
            ej.contains(qw) ||
            ew.any((e) =>
                e.startsWith(qw) || qw.startsWith(e) ||
                e.contains(qw) || qw.contains(e)));
        if (allMatch) candidates.add(emp);
      }
      if (candidates.length == 1) {
        return _fuzzyLow(rawName, candidates.first, 'Word prefix/infix match');
      }
      if (candidates.length > 1) {
        return _ambiguous('Word prefix/infix', rawName, candidates);
      }

      // Reverse check: query joined vs employee words
      final qj = words.join('');
      final revCandidates = <EmployeeModel>[];
      for (final emp in _employees) {
        final ew = _norm(emp.name)
            .split(' ')
            .where((w) => w.length > 2)
            .toList();
        if (ew.isEmpty) continue;
        final allEmpMatch = ew.every((e) =>
            qj.contains(e) ||
            words.any((qw) =>
                qw.startsWith(e) || e.startsWith(qw) ||
                qw.contains(e) || e.contains(qw)));
        if (allEmpMatch) revCandidates.add(emp);
      }
      if (revCandidates.length == 1) {
        return _fuzzyLow(
            rawName, revCandidates.first, 'Reverse word prefix/infix');
      }
      if (revCandidates.length > 1) {
        return _ambiguous('Reverse word prefix/infix', rawName, revCandidates);
      }
    }

    // 5. Token‑set overlap ≥ 60 %
    if (words.length >= 2) {
      final qs = words.toSet();
      final overlapCandidates = <EmployeeModel>[];
      for (final emp in _employees) {
        final es = _norm(emp.name)
            .split(' ')
            .where((w) => w.length > 2)
            .toSet();
        if (es.isEmpty) continue;
        final inter = qs.intersection(es).length.toDouble();
        final union = qs.union(es).length.toDouble();
        if (union > 0 && inter / union >= 0.60) {
          overlapCandidates.add(emp);
        }
      }
      if (overlapCandidates.length == 1) {
        return _fuzzyLow(rawName, overlapCandidates.first,
            'Token-set overlap ≥60%');
      }
      if (overlapCandidates.length > 1) {
        return _ambiguous(
            'Token-set overlap', rawName, overlapCandidates);
      }
    }

    // 6. First significant word contained in employee name (fallback)
    if (words.isNotEmpty) {
      final fallback = _employees
          .where((e) => _norm(e.name).contains(words.first))
          .toList();
      if (fallback.length == 1) {
        return _fuzzyLow(
            rawName, fallback.first, 'First word partial match');
      }
      if (fallback.length > 1) {
        return _ambiguous('First word fallback', rawName, fallback);
      }
    }

    // 7. Edit‑distance (Levenshtein) fuzzy match
    if (words.isNotEmpty) {
      const multiThreshold = 0.75;
      const singleThreshold = 0.85;
      final threshold =
          words.length == 1 ? singleThreshold : multiThreshold;
      final fuzzyCandidates = <EmployeeModel>[];
      for (final emp in _employees) {
        final ew = _norm(emp.name)
            .split(' ')
            .where((w) => w.length > 1)
            .toList();
        if (ew.isEmpty) continue;
        if (words.every((qw) => ew.any(
            (e) => _stringSimilarity(qw, e) >= threshold))) {
          fuzzyCandidates.add(emp);
        }
      }
      if (fuzzyCandidates.length == 1) {
        return _fuzzyLow(
            rawName, fuzzyCandidates.first, 'Edit‑distance fuzzy match');
      }
      if (fuzzyCandidates.length > 1) {
        return _ambiguous(
            'Edit‑distance fuzzy', rawName, fuzzyCandidates);
      }
    }

    // 8. No match
    return NameMatchResult(
      confidence: NameMatchConfidence.none,
      issue:
          '"$rawName" not found in employee master data. '
          'Add this employee first or correct the name.',
    );
  }

  /// Convenience: returns the best matching employee (or null).
  EmployeeModel? findBestEmployee(String rawName) {
    return resolve(rawName).employee;
  }

  /// Convenience: returns the department code (or null) of the best match.
  String? lookupDeptCode(String rawName) {
    final emp = resolve(rawName).employee;
    if (emp != null && emp.code.isNotEmpty) return emp.code;
    return null;
  }

  // ── Normalisation ──────────────────────────────────────────────────────

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ── Edit‑distance helpers ──────────────────────────────────────────────

  static double _stringSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - dist / maxLen;
  }

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

  // ── Result helpers ─────────────────────────────────────────────────────

  static NameMatchResult _fuzzyLow(
      String rawName, EmployeeModel emp, String reason) {
    return NameMatchResult(
      employee: emp,
      confidence: NameMatchConfidence.low,
      issue: 'Fuzzy match ($reason): "$rawName" → "${emp.name}" '
          '(please verify)',
    );
  }

  static NameMatchResult _ambiguous(
      String strategy, String rawName, List<EmployeeModel> candidates) {
    return NameMatchResult(
      confidence: NameMatchConfidence.none,
      candidates: candidates,
      issue: 'Multiple employees match "$rawName" ($strategy): '
          '${candidates.map((e) => e.name).join(", ")}. Please clarify.',
    );
  }
}