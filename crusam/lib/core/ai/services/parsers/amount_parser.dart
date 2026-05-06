// crusam/lib/core/ai/services/parsers/amount_parser.dart

class AmountParser {
  /// Parses strings like:
  /// "15438 X", "340+", "18747X", "9755x", "10828 +"
  /// Returns null if unparseable.
  static double? parse(String raw) {
    if (raw.isEmpty) return null;

    // Remove common suffixes: X, x, +, -, spaces, ×
    final cleaned = raw
        .replaceAll(RegExp(r'[Xx×+\-\s]'), '')
        .replaceAll(',', '') // handle "1,500"
        .trim();

    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
