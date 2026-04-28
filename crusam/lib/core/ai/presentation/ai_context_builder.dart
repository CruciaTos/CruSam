import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import '../../../data/models/employee_model.dart';

/// Builds a rich [AppContext] from live notifier state for injection into
/// [AiChatNotifier] before every message.
///
/// Usage — call right before sending a message:
///
/// ```dart
/// final ctx = AiContextBuilder.build(
///   employeeNotifier: EmployeeNotifier.instance,
/// );
/// AiChatNotifier.instance.updateContext(ctx);
/// AiChatNotifier.instance.sendMessage(text);
/// ```
class AiContextBuilder {
  AiContextBuilder._();

  /// Serialises all live employee data into an [AppContext].
  ///
  /// [employeeNotifier] is optional. When omitted the context will still
  /// contain any [extras] but no employee roster or salary aggregates.
  static AppContext build({
    EmployeeNotifier? employeeNotifier,
    Map<String, String>? extras,
  }) {
    if (employeeNotifier == null) {
      return AppContext(extra: extras);
    }

    final employees = employeeNotifier.employees;

    // ── Aggregates ────────────────────────────────────────────────────────────
    final int employeeCount = employees.length;

    double totalBasic = 0;
    double totalOther = 0;
    for (final e in employees) {
      totalBasic += e.basicCharges;
      totalOther += e.otherCharges;
    }
    final double totalSalary = totalBasic + totalOther;

    // ── Zone breakdown ────────────────────────────────────────────────────────
    final Map<String, int> zoneMap = {};
    for (final e in employees) {
      final z = e.zone.trim().isEmpty ? 'Unknown' : e.zone.trim();
      zoneMap[z] = (zoneMap[z] ?? 0) + 1;
    }
    final zoneLines = zoneMap.entries
        .map((en) => '  ${en.key}: ${en.value} employees')
        .join('\n');

    // ── Code (department) breakdown ───────────────────────────────────────────
    final Map<String, int> codeMap = {};
    for (final e in employees) {
      final c = e.code.trim().isEmpty ? 'Unknown' : e.code.trim();
      codeMap[c] = (codeMap[c] ?? 0) + 1;
    }
    final codeLines = codeMap.entries
        .map((en) => '  ${en.key}: ${en.value} employees')
        .join('\n');

    // ── Full employee roster ──────────────────────────────────────────────────
    // Serialise every employee so the LLM can answer detailed per-person queries
    // and generate precise ACTION blocks for mutations.
    final rosterLines = employees.map((e) => _employeeToLine(e)).join('\n');

    final dashboardSummary = '''
--- Zone Breakdown ---
$zoneLines

--- Department (Code) Breakdown ---
$codeLines

--- Total Basic: ₹${totalBasic.toStringAsFixed(2)} | Total Other: ₹${totalOther.toStringAsFixed(2)} ---

--- Employee Roster ---
$rosterLines
''';

    return AppContext(
      employeeCount: employeeCount,
      totalSalary: totalSalary,
      dashboardSummary: dashboardSummary,
      extra: extras,
    );
  }

  /// Compact single-line representation of one employee for the prompt.
  static String _employeeToLine(EmployeeModel e) {
    final gross = (e.basicCharges + e.otherCharges).toStringAsFixed(2);
    return '[${e.srNo}] ${e.name} | Code:${e.code} | Zone:${e.zone} '
        '| Gender:${e.gender} | Basic:₹${e.basicCharges.toStringAsFixed(2)} '
        '| Other:₹${e.otherCharges.toStringAsFixed(2)} | Gross:₹$gross '
        '| Bank:${e.bankDetails} | Branch:${e.branch} '
        '| PF:${e.pfNo} | UAN:${e.uanNo} | DOJ:${e.dateOfJoining}';
  }
}