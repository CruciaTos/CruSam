import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';

import 'db.dart';

/// All problems found in one call's arguments, reported together so Claude
/// can fix them in a single retry.
class ValidationError implements Exception {
  final List<String> problems;
  const ValidationError(this.problems);
  @override
  String toString() => 'Invalid arguments:\n- ${problems.join('\n- ')}';
}

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Strict reader over a tool call's arguments. Every getter records a
/// precise, actionable message instead of throwing; call [check] at the end.
class Args {
  final Map<String, Object?> raw;
  final String prefix;
  final List<String> errors;

  Args(Map<String, Object?>? raw, {this.prefix = '', List<String>? errors})
      : raw = raw ?? const {},
        errors = errors ?? [];

  /// Reader for a nested object that reports into the same error list.
  Args nested(Map<String, Object?> m, String path) =>
      Args(m, prefix: path, errors: errors);

  String _p(String key) => prefix.isEmpty ? key : '$prefix.$key';

  bool has(String key) => raw.containsKey(key) && raw[key] != null;

  void rejectUnknown(Iterable<String> allowed) {
    final extra = raw.keys.where((k) => !allowed.contains(k)).toList();
    if (extra.isNotEmpty) {
      errors.add('${prefix.isEmpty ? 'arguments' : prefix}: unknown field(s) '
          '${extra.join(', ')}. Allowed: ${allowed.join(', ')}.');
    }
  }

  String? str(String key, {bool required = false, bool allowEmpty = false, int maxLength = 1000}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (string).');
      return null;
    }
    // Identifiers like PO / bill numbers often arrive as JSON numbers.
    final s = (v is num && v == v.roundToDouble()) ? v.toInt().toString() : v;
    if (s is! String) {
      errors.add('${_p(key)}: must be a string, got ${_type(v)}.');
      return null;
    }
    final t = s.trim();
    if (t.isEmpty && !allowEmpty) {
      if (required) errors.add('${_p(key)}: must not be empty.');
      return required ? null : '';
    }
    if (t.length > maxLength) {
      errors.add('${_p(key)}: longer than $maxLength characters.');
      return null;
    }
    return t;
  }

  /// Strict ISO 8601 calendar date (YYYY-MM-DD). Anything else, including
  /// day/month formats like 03/04/2026, is rejected as ambiguous.
  String? date(String key, {bool required = false}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required, format YYYY-MM-DD.');
      return null;
    }
    if (v is! String) {
      errors.add('${_p(key)}: must be a YYYY-MM-DD string, got ${_type(v)}.');
      return null;
    }
    final m = _isoDate.firstMatch(v.trim());
    if (m == null) {
      errors.add('${_p(key)}: "$v" is not an ISO 8601 date. Use YYYY-MM-DD '
          '(e.g. 2026-05-01). Formats like 03/04/2026 or 1.5.26 are rejected '
          'because day and month are ambiguous; resolve them first.');
      return null;
    }
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    final dt = DateTime.utc(y, mo, d);
    if (dt.year != y || dt.month != mo || dt.day != d) {
      errors.add('${_p(key)}: $v is not a real calendar date.');
      return null;
    }
    if (y < 2000 || y > 2100) {
      errors.add('${_p(key)}: year $y is out of range (2000-2100).');
      return null;
    }
    return v.trim();
  }

  /// A JSON number (not a numeric string), finite, at most 2 decimals.
  double? money(String key,
      {bool required = false, bool allowZero = false, double max = 100000000}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (number).');
      return null;
    }
    if (v is! num) {
      errors.add('${_p(key)}: must be a JSON number, got ${_type(v)}'
          '${v is String ? ' "$v" (remove quotes, commas and currency symbols)' : ''}.');
      return null;
    }
    final d = v.toDouble();
    if (!d.isFinite) {
      errors.add('${_p(key)}: must be a finite number.');
      return null;
    }
    if (d < 0 || (!allowZero && d == 0)) {
      errors.add('${_p(key)}: must be ${allowZero ? '>= 0' : '> 0'}, got $d.');
      return null;
    }
    if (d > max) {
      errors.add('${_p(key)}: $d exceeds the maximum of $max.');
      return null;
    }
    if (((d * 100).round() - d * 100).abs() > 1e-6) {
      errors.add('${_p(key)}: at most 2 decimal places, got $d.');
      return null;
    }
    return d;
  }

  /// A JSON number used as a rate/threshold (no decimal-place limit).
  double? number(String key, {bool required = false, double min = 0, double max = 1e9}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (number).');
      return null;
    }
    if (v is! num || !v.toDouble().isFinite) {
      errors.add('${_p(key)}: must be a JSON number, got ${_type(v)}.');
      return null;
    }
    final d = v.toDouble();
    if (d < min || d > max) {
      errors.add('${_p(key)}: must be between $min and $max, got $d.');
      return null;
    }
    return d;
  }

  int? integer(String key, {bool required = false, int min = -1 << 31, int max = 1 << 31}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (integer).');
      return null;
    }
    if (v is! num || v != v.roundToDouble()) {
      errors.add('${_p(key)}: must be an integer, got ${_type(v)} ${jsonEncode(v)}.');
      return null;
    }
    final i = v.toInt();
    if (i < min || i > max) {
      errors.add('${_p(key)}: must be between $min and $max, got $i.');
      return null;
    }
    return i;
  }

  bool boolean(String key, {bool? defaultValue, bool required = false}) {
    final v = raw[key];
    if (v == null) {
      if (required) {
        errors.add('${_p(key)}: required (true or false).');
      }
      return defaultValue ?? false;
    }
    if (v is! bool) {
      errors.add('${_p(key)}: must be true or false, got ${_type(v)}.');
      return defaultValue ?? false;
    }
    return v;
  }

  String? oneOf(String key, List<String> allowed, {bool required = false}) {
    final s = str(key, required: required);
    if (s == null || s.isEmpty) return s == null ? null : (required ? null : s);
    final match = allowed.where((a) => a.toLowerCase() == s.toLowerCase());
    if (match.isEmpty) {
      errors.add('${_p(key)}: "$s" is not allowed. Use one of: ${allowed.join(', ')}.');
      return null;
    }
    return match.first;
  }

  List<Map<String, Object?>>? objects(String key,
      {bool required = false, int minItems = 0, int maxItems = 500}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (array of objects).');
      return null;
    }
    if (v is! List) {
      errors.add('${_p(key)}: must be an array, got ${_type(v)}.');
      return null;
    }
    if (v.length < minItems) {
      errors.add('${_p(key)}: needs at least $minItems item(s).');
      return null;
    }
    if (v.length > maxItems) {
      errors.add('${_p(key)}: at most $maxItems items per call.');
      return null;
    }
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < v.length; i++) {
      final item = v[i];
      if (item is! Map) {
        errors.add('${_p(key)}[$i]: must be an object, got ${_type(item)}.');
        continue;
      }
      out.add(item.cast<String, Object?>());
    }
    return out;
  }

  List<String>? strings(String key,
      {bool required = false, int minItems = 0, int maxItems = 500}) {
    final v = raw[key];
    if (v == null) {
      if (required) errors.add('${_p(key)}: required (array of strings).');
      return null;
    }
    if (v is! List || v.any((e) => e is! String)) {
      errors.add('${_p(key)}: must be an array of strings.');
      return null;
    }
    if (v.length < minItems || v.length > maxItems) {
      errors.add('${_p(key)}: must have $minItems-$maxItems items, got ${v.length}.');
      return null;
    }
    return v.cast<String>().map((s) => s.trim()).toList();
  }

  void check() {
    if (errors.isNotEmpty) throw ValidationError(List.of(errors));
  }

  static String _type(Object? v) => switch (v) {
        null => 'null',
        String() => 'string',
        bool() => 'boolean',
        num() => 'number',
        List() => 'array',
        Map() => 'object',
        _ => v.runtimeType.toString(),
      };
}

/// One tool: its MCP definition plus the implementation.
class ToolDef {
  final Tool tool;
  final Future<Map<String, Object?>> Function(Args args) run;
  ToolDef(this.tool, this.run);
}

/// A module of related tools (invoices, employees, …). Add a new capability
/// by writing a new ToolGroup and listing it in server.dart.
abstract class ToolGroup {
  List<ToolDef> get tools;
}

ToolAnnotations readOnlyTool(String title) =>
    ToolAnnotations(title: title, readOnlyHint: true, openWorldHint: false);

ToolAnnotations writeTool(String title, {bool destructive = false, bool idempotent = false}) =>
    ToolAnnotations(
        title: title,
        readOnlyHint: false,
        destructiveHint: destructive,
        idempotentHint: idempotent,
        openWorldHint: false);

CallToolResult okResult(Map<String, Object?> body) =>
    CallToolResult(content: [TextContent(text: jsonEncode(_clean(body)))]);

CallToolResult errorResult(String message) =>
    CallToolResult(content: [TextContent(text: message)], isError: true);

/// Rounds doubles to 2 decimals for compact, human-friendly output.
Object? _clean(Object? v) => switch (v) {
      double d => double.parse(d.toStringAsFixed(2)),
      Map m => {for (final e in m.entries) e.key: _clean(e.value)},
      List l => [for (final x in l) _clean(x)],
      _ => v,
    };

Future<CallToolResult> runTool(ToolDef def, CallToolRequest request,
    void Function(String, Object, StackTrace) onCrash) async {
  try {
    final args = Args(request.arguments);
    return okResult(await def.run(args));
  } on ValidationError catch (e) {
    return errorResult(e.toString());
  } on ToolError catch (e) {
    return errorResult(e.message);
  } catch (e, st) {
    onCrash(def.tool.name, e, st);
    return errorResult('Internal error in ${def.tool.name}: $e. '
        'Nothing is guaranteed to have been written; check with a read tool.');
  }
}

/// Requires `confirm: true` for destructive tools.
void requireConfirm(Args a, String what) {
  if (a.raw['confirm'] != true) {
    a.errors.add('confirm: must be true to $what. Show the user exactly what '
        'will be removed and get their explicit approval first.');
  }
}

// ── Schema helpers ──────────────────────────────────────────────────────────

Schema isoDateSchema(String description) => Schema.string(
    description: '$description Format YYYY-MM-DD (ISO 8601).',
    pattern: r'^\d{4}-\d{2}-\d{2}$');

Schema confirmSchema() => Schema.bool(
    description: 'Must be true. Only set after the user explicitly approved '
        'this exact change.');
