import 'dart:convert';

import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

/// Outcome of one tool execution.
sealed class AiToolResult {}

class AiToolSuccess extends AiToolResult {
  final String confirmation; // Human-readable success message shown in chat.
  AiToolSuccess(this.confirmation);
}

class AiToolFailure extends AiToolResult {
  final String reason;
  AiToolFailure(this.reason);
}

/// Returned when no ACTION block is found in the LLM text.
class AiToolNotPresent extends AiToolResult {
  AiToolNotPresent();
}

// ─────────────────────────────────────────────────────────────────────────────
// Supported actions
// ─────────────────────────────────────────────────────────────────────────────
//
// The LLM embeds one of these JSON blocks anywhere in its reply:
//
//   [ACTION]{"action":"update_employee","name":"Rajesh Kumar","field":"basicCharges","value":15000}[/ACTION]
//   [ACTION]{"action":"delete_employee","name":"Rajesh Kumar"}[/ACTION]
//   [ACTION]{"action":"add_employee","srNo":42,"name":"New Person","code":"F&B",
//            "gender":"M","zone":"North","basicCharges":12000,"otherCharges":500,
//            "pfNo":"","uanNo":"","ifscCode":"","accountNumber":"",
//            "bankDetails":"","branch":"","dateOfJoining":""}[/ACTION]
//
// Updatable fields for update_employee:
//   basicCharges, otherCharges, zone, code, gender, bankDetails,
//   branch, pfNo, uanNo, ifscCode, accountNumber, dateOfJoining,
//   aartiAcNo, sbCode, name
// ─────────────────────────────────────────────────────────────────────────────

class AiToolExecutor {
  AiToolExecutor._();
  static final AiToolExecutor instance = AiToolExecutor._();

  static const _openTag = '[ACTION]';
  static const _closeTag = '[/ACTION]';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Scans [llmText] for an `[ACTION]...[/ACTION]` block.
  ///
  /// If found, executes the action and returns [AiToolSuccess] or
  /// [AiToolFailure].  If not found, returns [AiToolNotPresent].
  ///
  /// Pass the live [employeeNotifier] so it can be reloaded after mutations.
  Future<AiToolResult> tryExecute({
    required String llmText,
    required EmployeeNotifier employeeNotifier,
  }) async {
    final json = _extractJson(llmText);
    if (json == null) return AiToolNotPresent();

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return AiToolFailure('Could not parse ACTION block JSON.');
    }

    final action = payload['action'] as String?;
    switch (action) {
      case 'update_employee':
        return _updateEmployee(payload, employeeNotifier);
      case 'delete_employee':
        return _deleteEmployee(payload, employeeNotifier);
      case 'add_employee':
        return _addEmployee(payload, employeeNotifier);
      default:
        return AiToolFailure('Unknown action: "$action".');
    }
  }

  /// Strips the `[ACTION]...[/ACTION]` block from LLM text so it is not
  /// rendered verbatim in the chat bubble.
  static String stripActionBlock(String text) {
    final start = text.indexOf(_openTag);
    final end = text.indexOf(_closeTag);
    if (start == -1 || end == -1 || end < start) return text;
    return (text.substring(0, start) +
            text.substring(end + _closeTag.length))
        .trim();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String? _extractJson(String text) {
    final start = text.indexOf(_openTag);
    final end = text.indexOf(_closeTag);
    if (start == -1 || end == -1 || end < start) return null;
    return text.substring(start + _openTag.length, end).trim();
  }

  Future<AiToolResult> _updateEmployee(
    Map<String, dynamic> p,
    EmployeeNotifier notifier,
  ) async {
    final name = (p['name'] as String?)?.trim();
    final field = p['field'] as String?;
    final value = p['value'];

    if (name == null || field == null || value == null) {
      return AiToolFailure(
          'update_employee requires "name", "field", and "value".');
    }

    // Find the employee by name (case-insensitive).
    final all = await DatabaseHelper.instance.getAllEmployees();
    final match = all.cast<Map<String, dynamic>?>().firstWhere(
          (e) => (e!['name'] as String?)
                  ?.toLowerCase()
                  .contains(name.toLowerCase()) ==
              true,
          orElse: () => null,
        );

    if (match == null) {
      return AiToolFailure('No employee found matching "$name".');
    }

    final id = match['id'] as int;

    // Validate field name against allowed list.
    const updatable = {
      'name', 'basicCharges', 'otherCharges', 'zone', 'code', 'gender',
      'bankDetails', 'branch', 'pfNo', 'uanNo', 'ifscCode', 'accountNumber',
      'dateOfJoining', 'aartiAcNo', 'sbCode',
    };
    if (!updatable.contains(field)) {
      return AiToolFailure('"$field" is not an updatable field.');
    }

    // Build updated map.
    final updated = Map<String, dynamic>.from(match);
    updated.remove('id');

    // Coerce numeric fields.
    if (field == 'basicCharges' || field == 'otherCharges') {
      final num? parsed = num.tryParse(value.toString());
      if (parsed == null) {
        return AiToolFailure('"$field" must be a number, got "$value".');
      }
      updated[field] = parsed.toDouble();
    } else {
      updated[field] = value.toString();
    }

    await DatabaseHelper.instance.updateEmployee(id, updated);
    await notifier.load();

    final empName = match['name'] as String? ?? name;
    return AiToolSuccess(
        '✅ Updated **$empName** — $field set to $value.');
  }

  Future<AiToolResult> _deleteEmployee(
    Map<String, dynamic> p,
    EmployeeNotifier notifier,
  ) async {
    final name = (p['name'] as String?)?.trim();
    if (name == null) {
      return AiToolFailure('delete_employee requires "name".');
    }

    final all = await DatabaseHelper.instance.getAllEmployees();
    final match = all.cast<Map<String, dynamic>?>().firstWhere(
          (e) => (e!['name'] as String?)
                  ?.toLowerCase()
                  .contains(name.toLowerCase()) ==
              true,
          orElse: () => null,
        );

    if (match == null) {
      return AiToolFailure('No employee found matching "$name".');
    }

    final id = match['id'] as int;
    final empName = match['name'] as String? ?? name;

    await DatabaseHelper.instance.deleteEmployee(id);
    await notifier.load();

    return AiToolSuccess('🗑️ Employee **$empName** has been deleted.');
  }

  Future<AiToolResult> _addEmployee(
    Map<String, dynamic> p,
    EmployeeNotifier notifier,
  ) async {
    try {
      final emp = EmployeeModel(
        srNo: (p['srNo'] as num?)?.toInt() ?? 0,
        name: (p['name'] as String?)?.trim() ?? '',
        pfNo: (p['pfNo'] as String?) ?? '',
        uanNo: (p['uanNo'] as String?) ?? '',
        code: (p['code'] as String?) ?? '',
        ifscCode: (p['ifscCode'] as String?) ?? '',
        accountNumber: (p['accountNumber'] as String?) ?? '',
        aartiAcNo: (p['aartiAcNo'] as String?) ?? '',
        sbCode: (p['sbCode'] as String?) ?? '',
        bankDetails: (p['bankDetails'] as String?) ?? '',
        branch: (p['branch'] as String?) ?? '',
        zone: (p['zone'] as String?) ?? '',
        dateOfJoining: (p['dateOfJoining'] as String?) ?? '',
        basicCharges:
            (p['basicCharges'] as num?)?.toDouble() ?? 0,
        otherCharges:
            (p['otherCharges'] as num?)?.toDouble() ?? 0,
        gender: (p['gender'] as String?) ?? 'M',
      );

      if (emp.name.isEmpty) {
        return AiToolFailure('add_employee requires at least "name".');
      }

      await DatabaseHelper.instance.insertEmployee(emp.toMap());
      await notifier.load();

      return AiToolSuccess('✅ Employee **${emp.name}** has been added.');
    } catch (e) {
      return AiToolFailure('Failed to add employee: $e');
    }
  }
}