// crusam/lib/core/ai/services/parsers/name_resolver.dart

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

class NameResolver {
  final List<EmployeeModel> employees;

  NameResolver(this.employees);

  NameMatchResult resolve(String rawName) {
    if (rawName.trim().isEmpty) {
      return const NameMatchResult(
        confidence: NameMatchConfidence.none,
        issue: 'Empty name',
      );
    }

    final normalized = _normalize(rawName);

    // 1. Exact match (normalized)
    final exact = employees.where(
      (e) => _normalize(e.name) == normalized,
    ).toList();
    if (exact.length == 1) {
      return NameMatchResult(
        employee: exact.first,
        confidence: NameMatchConfidence.exact,
      );
    }

    // 2. Contains match — all words in rawName appear in employee name
    final words = normalized.split(RegExp(r'\s+'))
        .where((w) => w.length > 2) // skip very short words
        .toList();
    
    final wordMatches = employees.where((e) {
      final empName = _normalize(e.name);
      return words.every((w) => empName.contains(w));
    }).toList();

    if (wordMatches.length == 1) {
      return NameMatchResult(
        employee: wordMatches.first,
        confidence: NameMatchConfidence.high,
      );
    }
    if (wordMatches.length > 1) {
      return NameMatchResult(
        confidence: NameMatchConfidence.none,
        candidates: wordMatches,
        issue: 'Multiple employees match "$rawName": '
            '${wordMatches.map((e) => e.name).join(", ")}. '
            'Please clarify.',
      );
    }

    // 3. Fuzzy: any word in rawName appears in employee name
    final fuzzyMatches = employees.where((e) {
      final empName = _normalize(e.name);
      return words.any((w) => empName.contains(w) && w.length >= 4);
    }).toList();

    if (fuzzyMatches.length == 1) {
      return NameMatchResult(
        employee: fuzzyMatches.first,
        confidence: NameMatchConfidence.low,
        issue: 'Fuzzy match: "$rawName" → "${fuzzyMatches.first.name}" '
            '(please verify)',
      );
    }
    if (fuzzyMatches.length > 1) {
      return NameMatchResult(
        confidence: NameMatchConfidence.none,
        candidates: fuzzyMatches,
        issue: 'Could not uniquely match "$rawName". '
            'Possible matches: ${fuzzyMatches.map((e) => e.name).join(", ")}',
      );
    }

    // 4. No match
    return NameMatchResult(
      confidence: NameMatchConfidence.none,
      issue: '"$rawName" not found in employee master data. '
          'Add this employee first or correct the name.',
    );
  }

  static String _normalize(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
