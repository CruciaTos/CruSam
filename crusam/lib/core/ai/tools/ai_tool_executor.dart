import 'dart:convert';

import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/voucher_row_model.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

/// Outcome of one tool execution.
sealed class AiToolResult {}

class AiToolSuccess extends AiToolResult {
  final String confirmation; // Human‑readable success message shown in chat.
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
//   [ACTION]{"action":"update_employee","employeeId":84,"field":"basicCharges","value":15000}[/ACTION]
//   [ACTION]{"action":"delete_employee","employeeId":84}[/ACTION]
//   [ACTION]{"action":"add_employee","srNo":42,"name":"New Person","code":"F&B",
//            "gender":"M","zone":"North","basicCharges":12000,"otherCharges":500,
//            "pfNo":"","uanNo":"","ifscCode":"","accountNumber":"",
//            "bankDetails":"","branch":"","dateOfJoining":""}[/ACTION]
//   [ACTION]{"action":"add_voucher_row","employeeName":"Abhishek","amount":5000,
//            "fromDate":"2026-04-01","toDate":"2026-04-09"}[/ACTION]
//   [ACTION]{"action":"approve_voucher"}[/ACTION]
//   [ACTION]{"action":"set_company_config","field":"gstin","value":"27AAQFA5248L2ZW"}[/ACTION]
//
// Updatable fields for update_employee:
//   basicCharges, otherCharges, zone, code, gender, bankDetails,
//   branch, pfNo, uanNo, ifscCode, accountNumber, dateOfJoining,
//   aartiAcNo, sbCode, name

class AiToolExecutor {
  AiToolExecutor._();
  static final AiToolExecutor instance = AiToolExecutor._();

  static const _openTag = '[ACTION]';
  static const _closeTag = '[/ACTION]';

  // ── Guard Rail Configuration ───────────────────────────────────────────────
  static const maxVoucherAmount = 10000000.0; // ₹1 crore limit
  static const maxBasicCharges = 5000000.0;  // ₹50 lakh per employee
  static const maxOtherCharges = 1000000.0;  // ₹10 lakh other charges
  static const actionRateLimit = 10;         // max 10 actions per minute
  static const maxBatchSize = 100;           // max 100 items in bulk ops

  // ── Action tracking for rate limiting ──────────────────────────────────────
  final Map<String, List<DateTime>> _actionTimestamps = {};

  // ── Public helpers ─────────────────────────────────────────────────────────

  /// Extracts every `[ACTION]…[/ACTION]` block and returns their JSON strings.
  static List<String> extractAllActionJsons(String text) {
    final regex = RegExp(r'\[ACTION\]([\s\S]*?)\[/ACTION\]', caseSensitive: false);
    return regex.allMatches(text).map((m) => m.group(1)!.trim()).toList();
  }

  /// Strips all `[ACTION]…[/ACTION]` blocks from the text.
  static String stripActionBlock(String text) {
    return text.replaceAll(RegExp(r'\[ACTION\][\s\S]*?\[/ACTION\]', caseSensitive: false), '').trim();
  }

  // ── Execute a single action (original entry point, now delegates) ──────────

  Future<AiToolResult> tryExecute({
    required String llmText,
    required EmployeeNotifier employeeNotifier,
    SalaryStateController? salaryStateController,
    SalaryDataNotifier? salaryDataNotifier,
    VoucherNotifier? voucherNotifier,
  }) async {
    final json = _extractJson(llmText);
    if (json == null) return AiToolNotPresent();

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return AiToolFailure('Could not parse ACTION block JSON.');
    }

    return _executePayload(
      payload,
      employeeNotifier: employeeNotifier,
      salaryStateController: salaryStateController,
      salaryDataNotifier: salaryDataNotifier,
      voucherNotifier: voucherNotifier,
    );
  }

  // ── Execute a batch of action JSON strings ─────────────────────────────────

  Future<AiToolResult> executeBatch(
    List<String> actionJsons, {
    required EmployeeNotifier employeeNotifier,
    SalaryStateController? salaryStateController,
    SalaryDataNotifier? salaryDataNotifier,
    VoucherNotifier? voucherNotifier,
  }) async {
    final successes = <String>[];
    final failures = <String>[];

    for (final json in actionJsons) {
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(json) as Map<String, dynamic>;
      } catch (_) {
        failures.add('Invalid JSON: $json');
        continue;
      }

      final result = await _executePayload(
        payload,
        employeeNotifier: employeeNotifier,
        salaryStateController: salaryStateController,
        salaryDataNotifier: salaryDataNotifier,
        voucherNotifier: voucherNotifier,
      );

      if (result is AiToolSuccess) {
        successes.add(result.confirmation);
      } else if (result is AiToolFailure) {
        failures.add(result.reason);
      }
    }

    if (failures.isEmpty) {
      return AiToolSuccess(successes.join('\n'));
    } else if (successes.isEmpty) {
      return AiToolFailure(failures.join('\n'));
    } else {
      return AiToolSuccess(
        '${successes.length} action(s) succeeded, ${failures.length} failed:\n'
        '${successes.join('\n')}\nFailures:\n${failures.join('\n')}',
      );
    }
  }

  // ── Private: execute a single parsed payload ───────────────────────────────

  Future<AiToolResult> _executePayload(
    Map<String, dynamic> payload, {
    required EmployeeNotifier employeeNotifier,
    SalaryStateController? salaryStateController,
    SalaryDataNotifier? salaryDataNotifier,
    VoucherNotifier? voucherNotifier,
  }) async {
    final action = payload['action'] as String?;
    final salaryController = salaryStateController ?? SalaryStateController.instance;
    final salaryNotifier = salaryDataNotifier ?? SalaryDataNotifier.instance;
    final voucher = voucherNotifier ?? VoucherNotifier.instance;

    switch (action) {
      case 'update_employee':
        return _updateEmployee(payload, employeeNotifier);
      case 'delete_employee':
        return _deleteEmployee(payload, employeeNotifier);
      case 'add_employee':
        return _addEmployee(payload, employeeNotifier);
      case 'add_voucher_row':
        return _addVoucherRow(payload, voucher, employeeNotifier);
      case 'update_voucher_row':
        return _updateVoucherRow(payload, voucher, employeeNotifier);
      case 'delete_voucher_row':
        return _deleteVoucherRow(payload, voucher);
      case 'save_voucher':
        return _saveVoucher(payload, voucher);
      case 'discard_voucher':
        return _discardVoucher(payload, voucher);
      case 'approve_voucher':
        return await _approveVoucher(payload, voucher);
      case 'set_company_config':
        return await _setCompanyConfig(payload, voucher);
      case 'set_voucher_metadata':
        return _setVoucherField(payload, voucher);
      case 'set_company_filter':
        return _setCompanyFilter(payload, salaryController);
      case 'set_month_year':
        return _setMonthYear(payload, salaryNotifier);
      case 'set_days_present':
        return _setDaysPresent(payload, salaryNotifier);
      case 'set_salary_meta':
        return _setSalaryMeta(payload, salaryNotifier);
      case 'set_voucher_field':
        return _setVoucherField(payload, voucher);
      default:
        return AiToolFailure('Unknown action: "$action".');
    }
  }

  // ── Private: JSON extraction (single block, used by tryExecute) ────────────

  String? _extractJson(String text) {
    final start = text.indexOf(_openTag);
    final end = text.indexOf(_closeTag);
    if (start == -1 || end == -1 || end < start) return null;
    return text.substring(start + _openTag.length, end).trim();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Existing tool implementations (all unchanged)
  // ═══════════════════════════════════════════════════════════════════════════

  int? _parseEmployeeId(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int? _getEmployeeIdFromPayload(Map<String, dynamic> p) {
    return _parseEmployeeId(p['employeeId']) ??
        _parseEmployeeId(p['employeeid']) ??
        _parseEmployeeId(p['id']);
  }

  // ── GUARD RAILS: Input Validation ──────────────────────────────────────────

  /// Check rate limit for actions (10 per minute).
  AiToolResult? _checkRateLimit(String action) {
    final now = DateTime.now();
    final key = 'action_$action';
    final timestamps = _actionTimestamps[key] ?? [];

    // Remove timestamps older than 1 minute
    final recent = timestamps
        .where((t) => now.difference(t).inSeconds < 60)
        .toList();

    if (recent.length >= actionRateLimit) {
      return AiToolFailure(
        'Too many "$action" requests. Max $actionRateLimit per minute. Please wait.',
      );
    }

    recent.add(now);
    _actionTimestamps[key] = recent;
    return null; // pass
  }

  /// Validate GSTIN format (15 alphanumeric chars).
  bool _isValidGstin(String gstin) {
    final clean = gstin.replaceAll(RegExp(r'\s'), '').toUpperCase();
    return RegExp(r'^[0-9A-Z]{15}$').hasMatch(clean);
  }

  /// Validate PAN format (10 alphanumeric chars).
  bool _isValidPan(String pan) {
    final clean = pan.replaceAll(RegExp(r'\s'), '').toUpperCase();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(clean);
  }

  /// Validate phone format (10 digits, optional country code).
  bool _isValidPhone(String phone) {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    return clean.length == 10 || clean.length == 12; // 10 digit or +91+10
  }

  /// Validate IFSC code (11 alphanumeric, first 4 letters).
  bool _isValidIfsc(String ifsc) {
    final clean = ifsc.replaceAll(RegExp(r'\s'), '').toUpperCase();
    return RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(clean);
  }

  /// Validate account number (8-17 digits).
  bool _isValidAccountNumber(String accNo) {
    final clean = accNo.replaceAll(RegExp(r'\s'), '');
    return RegExp(r'^\d{8,17}$').hasMatch(clean);
  }

  /// Validate date in YYYY-MM-DD format, not in future.
  bool _isValidDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return !date.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Validate date range: fromDate <= toDate.
  bool _isValidDateRange(String fromDate, String toDate) {
    try {
      final from = DateTime.parse(fromDate);
      final to = DateTime.parse(toDate);
      return !from.isAfter(to);
    } catch (_) {
      return false;
    }
  }

  /// Check for duplicate employee by name.
  Future<bool> _employeeNameExists(String name) async {
    final all = await DatabaseHelper.instance.getAllEmployees();
    return all.any((e) =>
        (e['name'] as String?)?.toLowerCase() == name.toLowerCase());
  }

  /// Validate numeric range for charges.
  bool _isValidChargeAmount(double amount, {required double max}) {
    return amount >= 0 && amount <= max;
  }

  /// Validate voucher amount limit.
  bool _isValidVoucherAmount(double amount) {
    return amount > 0 && amount <= maxVoucherAmount;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Individual action handlers
  // ═══════════════════════════════════════════════════════════════════════════

  Future<AiToolResult> _updateEmployee(
    Map<String, dynamic> p,
    EmployeeNotifier notifier,
  ) async {
    final employeeId = _getEmployeeIdFromPayload(p);
    final name = (p['name'] as String?)?.trim();
    final field = p['field'] as String?;
    final value = p['value'];

    if ((employeeId == null && name == null) || field == null || value == null) {
      return AiToolFailure(
          'update_employee requires "employeeId" or "name", plus "field" and "value".');
    }

    final all = await DatabaseHelper.instance.getAllEmployees();
    Map<String, dynamic>? match;
    if (employeeId != null) {
      match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => e != null && e['id'] == employeeId,
            orElse: () => null,
          );
    }
    if (match == null && name != null) {
      match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => (e!['name'] as String?)
                    ?.toLowerCase()
                    .contains(name.toLowerCase()) ==
                true,
            orElse: () => null,
          );
    }

    if (match == null) {
      final idStr = employeeId != null ? 'id $employeeId' : 'name "$name"';
      return AiToolFailure('No employee found matching $idStr.');
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
    final employeeId = _getEmployeeIdFromPayload(p);
    final name = (p['name'] as String?)?.trim();
    if (employeeId == null && name == null) {
      return AiToolFailure('delete_employee requires "employeeId" or "name".');
    }

    final all = await DatabaseHelper.instance.getAllEmployees();
    Map<String, dynamic>? match;
    if (employeeId != null) {
      match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => e != null && e['id'] == employeeId,
            orElse: () => null,
          );
    }
    if (match == null && name != null) {
      match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => (e!['name'] as String?)
                    ?.toLowerCase()
                    .contains(name.toLowerCase()) ==
                true,
            orElse: () => null,
          );
    }

    if (match == null) {
      final idStr = employeeId != null ? 'id $employeeId' : 'name "$name"';
      return AiToolFailure('No employee found matching $idStr.');
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
    // Guard: Rate limit
    final rateLimitCheck = _checkRateLimit('add_employee');
    if (rateLimitCheck != null) return rateLimitCheck;

    try {
      final name = (p['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return AiToolFailure('add_employee requires at least "name".');
      }

      // Guard: Duplicate check
      if (await _employeeNameExists(name)) {
        return AiToolFailure('❌ Employee "$name" already exists. Skipped to prevent duplicates.');
      }

      final basicCharges = (p['basicCharges'] as num?)?.toDouble() ?? 0;
      final otherCharges = (p['otherCharges'] as num?)?.toDouble() ?? 0;

      // Guard: Validate charge amounts
      if (!_isValidChargeAmount(basicCharges, max: maxBasicCharges)) {
        return AiToolFailure(
          'Basic charges ₹$basicCharges exceeds max limit ₹$maxBasicCharges.',
        );
      }
      if (!_isValidChargeAmount(otherCharges, max: maxOtherCharges)) {
        return AiToolFailure(
          'Other charges ₹$otherCharges exceeds max limit ₹$maxOtherCharges.',
        );
      }

      // Guard: Validate bank details if provided
      final ifscCode = (p['ifscCode'] as String?)?.trim() ?? '';
      final accountNumber = (p['accountNumber'] as String?)?.trim() ?? '';
      if (ifscCode.isNotEmpty && !_isValidIfsc(ifscCode)) {
        return AiToolFailure('⚠️ Invalid IFSC code "$ifscCode". Expected format: 4 letters + "0" + 6 alphanumeric.');
      }
      if (accountNumber.isNotEmpty && !_isValidAccountNumber(accountNumber)) {
        return AiToolFailure('⚠️ Invalid account number "$accountNumber". Expected 8-17 digits.');
      }

      // Guard: Validate date if provided
      final doj = (p['dateOfJoining'] as String?)?.trim() ?? '';
      if (doj.isNotEmpty && !_isValidDate(doj)) {
        return AiToolFailure('⚠️ Invalid date of joining "$doj". Expected YYYY-MM-DD format, not in future.');
      }

      final emp = EmployeeModel(
        srNo: (p['srNo'] as num?)?.toInt() ?? 0,
        name: name,
        pfNo: (p['pfNo'] as String?) ?? '',
        uanNo: (p['uanNo'] as String?) ?? '',
        code: (p['code'] as String?) ?? '',
        ifscCode: ifscCode,
        accountNumber: accountNumber,
        aartiAcNo: (p['aartiAcNo'] as String?) ?? '',
        sbCode: (p['sbCode'] as String?) ?? '',
        bankDetails: (p['bankDetails'] as String?) ?? '',
        branch: (p['branch'] as String?) ?? '',
        zone: (p['zone'] as String?) ?? '',
        dateOfJoining: doj,
        basicCharges: basicCharges,
        otherCharges: otherCharges,
        gender: (p['gender'] as String?) ?? 'M',
      );

      await DatabaseHelper.instance.insertEmployee(emp.toMap());
      await notifier.load();

      return AiToolSuccess('✅ Employee **${emp.name}** has been added.');
    } catch (e) {
      return AiToolFailure('Failed to add employee: $e');
    }
  }

  Future<EmployeeModel?> _lookupEmployee(
    Map<String, dynamic> p,
  ) async {
    final employeeId = _getEmployeeIdFromPayload(p);
    final name = (p['employeeName'] as String?)?.trim() ??
        (p['name'] as String?)?.trim();

    final all = await DatabaseHelper.instance.getAllEmployees();
    if (employeeId != null) {
      final match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => e != null && e['id'] == employeeId,
            orElse: () => null,
          );
      if (match != null) return EmployeeModel.fromMap(match);
    }

    if (name != null && name.isNotEmpty) {
      final match = all.cast<Map<String, dynamic>?>().firstWhere(
            (e) => (e!['name'] as String?)
                    ?.toLowerCase()
                    .contains(name.toLowerCase()) ==
                true,
            orElse: () => null,
          );
      if (match != null) return EmployeeModel.fromMap(match);
    }

    return null;
  }

  double? _parseAmount(dynamic rawValue) {
    if (rawValue is num) return rawValue.toDouble();
    if (rawValue is String) {
      final normalized = rawValue
          .replaceAll(RegExp(r'[^0-9.]'), '')
          .trim();
      return double.tryParse(normalized);
    }
    return null;
  }

  Future<AiToolResult> _addVoucherRow(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
    EmployeeNotifier employeeNotifier,
  ) async {
    // Guard: Rate limit
    final rateLimitCheck = _checkRateLimit('add_voucher_row');
    if (rateLimitCheck != null) return rateLimitCheck;

    final employee = await _lookupEmployee(p);
    final amount = _parseAmount(p['amount'] ?? p['value']);
    final fromDate = (p['fromDate'] as String?)?.trim() ??
        (p['from_date'] as String?)?.trim() ??
        (p['from'] as String?)?.trim() ?? '';
    final toDate = (p['toDate'] as String?)?.trim() ??
        (p['to_date'] as String?)?.trim() ??
        (p['to'] as String?)?.trim() ?? '';

    if (amount == null || amount <= 0) {
      return AiToolFailure('add_voucher_row requires a valid numeric "amount".');
    }

    // Guard: Validate amount limit
    if (!_isValidVoucherAmount(amount)) {
      return AiToolFailure(
        '❌ Row amount ₹$amount exceeds voucher limit ₹$maxVoucherAmount.',
      );
    }

    if (fromDate.isEmpty || toDate.isEmpty) {
      return AiToolFailure(
        'add_voucher_row requires both "fromDate" and "toDate" in YYYY-MM-DD format.',
      );
    }

    // Guard: Validate date format and range
    if (!_isValidDate(fromDate)) {
      return AiToolFailure('❌ Invalid fromDate "$fromDate". Expected YYYY-MM-DD format, not in future.');
    }
    if (!_isValidDate(toDate)) {
      return AiToolFailure('❌ Invalid toDate "$toDate". Expected YYYY-MM-DD format, not in future.');
    }
    if (!_isValidDateRange(fromDate, toDate)) {
      return AiToolFailure('❌ Date range invalid: fromDate "$fromDate" must be ≤ toDate "$toDate".');
    }

    // Guard: Check if voucher will exceed amount limit
    final projectedTotal = notifier.baseTotal + amount;
    if (projectedTotal > maxVoucherAmount) {
      return AiToolFailure(
        '⚠️ Adding ₹${amount.toStringAsFixed(2)} would exceed voucher limit. '
        'Current: ₹${notifier.baseTotal.toStringAsFixed(2)}, Projected: ₹${projectedTotal.toStringAsFixed(2)}, '
        'Max: ₹$maxVoucherAmount.',
      );
    }

    final row = VoucherRowModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      employeeId: employee?.id?.toString() ??
          _getEmployeeIdFromPayload(p)?.toString() ??
          '',
      employeeName: employee?.name ??
          (p['employeeName'] as String?)?.trim() ??
          (p['name'] as String?)?.trim() ?? '',
      amount: amount,
      fromDate: fromDate,
      toDate: toDate,
      ifscCode: employee?.ifscCode ?? (p['ifscCode'] as String?) ?? '',
      accountNumber: employee?.accountNumber ??
          (p['accountNumber'] as String?) ?? '',
      sbCode: employee?.sbCode ?? (p['sbCode'] as String?) ?? '',
      bankDetails: employee?.bankDetails ??
          (p['bankDetails'] as String?) ?? '',
      branch: employee?.branch ?? (p['branch'] as String?) ?? '',
      deptCode: (p['deptCode'] as String?)?.trim() ?? notifier.current.deptCode,
      debitAccountNumber: notifier.config.accountNo,
      debitAccountName: notifier.config.companyName,
    );

    notifier.update((current) =>
        current.copyWith(rows: [...current.rows, row]));

    return AiToolSuccess(
      '✅ Added voucher row for ${row.employeeName.isNotEmpty ? row.employeeName : 'employee'} '
      'with ₹${amount.toStringAsFixed(2)} from $fromDate to $toDate.',
    );
  }

  Future<VoucherRowModel?> _findVoucherRow(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    final rowId = (p['rowId'] as String?)?.trim() ??
        (p['row_id'] as String?)?.trim() ??
        (p['id'] as String?)?.trim();
    if (rowId != null && rowId.isNotEmpty) {
      for (final row in notifier.current.rows) {
        if (row.id == rowId) return row;
      }
    }

    final rowIndex = (p['rowIndex'] as num?)?.toInt() ??
        int.tryParse((p['rowIndex'] as String?) ?? '');
    if (rowIndex != null && rowIndex >= 0 && rowIndex < notifier.current.rows.length) {
      return notifier.current.rows[rowIndex];
    }

    final employeeName = (p['employeeName'] as String?)?.trim() ??
        (p['name'] as String?)?.trim();
    final fromDate = (p['fromDate'] as String?)?.trim() ??
        (p['from_date'] as String?)?.trim() ?? '';
    final toDate = (p['toDate'] as String?)?.trim() ??
        (p['to_date'] as String?)?.trim() ?? '';
    final amount = _parseAmount(p['amount']);

    for (final row in notifier.current.rows) {
      if (employeeName != null && employeeName.isNotEmpty &&
          row.employeeName.toLowerCase() != employeeName.toLowerCase()) {
        continue;
      }
      if (fromDate.isNotEmpty && row.fromDate != fromDate) continue;
      if (toDate.isNotEmpty && row.toDate != toDate) continue;
      if (amount != null && row.amount != amount) continue;
      return row;
    }
    return null;
  }

  Future<AiToolResult> _updateVoucherRow(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
    EmployeeNotifier employeeNotifier,
  ) async {
    final row = await _findVoucherRow(p, notifier);
    if (row == null) {
      return AiToolFailure(
          'Could not find a voucher row matching the provided criteria.');
    }

    final employee = await _lookupEmployee(p);
    final amount = p.containsKey('amount') ? _parseAmount(p['amount']) : null;
    final fromDate = (p['fromDate'] as String?)?.trim() ??
        (p['from_date'] as String?)?.trim();
    final toDate = (p['toDate'] as String?)?.trim() ??
        (p['to_date'] as String?)?.trim();
    final deptCode = (p['deptCode'] as String?)?.trim();
    final ifscCode = (p['ifscCode'] as String?)?.trim();
    final accountNumber = (p['accountNumber'] as String?)?.trim();
    final sbCode = (p['sbCode'] as String?)?.trim();
    final bankDetails = (p['bankDetails'] as String?)?.trim();
    final branch = (p['branch'] as String?)?.trim();
    final employeeName = (p['employeeName'] as String?)?.trim();
    final employeeId = _getEmployeeIdFromPayload(p)?.toString();

    final updated = row.copyWith(
      amount: amount ?? row.amount,
      fromDate: fromDate ?? row.fromDate,
      toDate: toDate ?? row.toDate,
      deptCode: deptCode ?? row.deptCode,
      ifscCode: ifscCode ?? row.ifscCode,
      accountNumber: accountNumber ?? row.accountNumber,
      sbCode: sbCode ?? row.sbCode,
      bankDetails: bankDetails ?? row.bankDetails,
      branch: branch ?? row.branch,
      employeeId: employee?.id?.toString() ?? employeeId ?? row.employeeId,
      employeeName: employee?.name ?? employeeName ?? row.employeeName,
    );

    notifier.updateRow(row.id, (_) => updated);

    return AiToolSuccess(
      '✅ Updated voucher row for ${updated.employeeName.isNotEmpty ? updated.employeeName : 'employee'}.'
    );
  }

  Future<AiToolResult> _deleteVoucherRow(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    final row = await _findVoucherRow(p, notifier);
    if (row == null) {
      return AiToolFailure(
          'Could not find a voucher row matching the provided criteria.');
    }

    notifier.removeRow(row.id);
    return AiToolSuccess(
      '🗑️ Deleted voucher row for ${row.employeeName.isNotEmpty ? row.employeeName : 'employee'}.'
    );
  }

  Future<AiToolResult> _saveVoucher(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    final ok = await notifier.saveVoucher();
    if (!ok) {
      return AiToolFailure('Unable to save the current voucher. Check that the title and rows are valid.');
    }
    return AiToolSuccess('✅ Current voucher has been saved.');
  }

  Future<AiToolResult> _discardVoucher(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    await notifier.discardDraft();
    return AiToolSuccess('✅ Current voucher draft has been discarded.');
  }

  Future<AiToolResult> _approveVoucher(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    final ok = await notifier.saveVoucher();
    if (!ok) {
      return AiToolFailure(
        'Unable to approve the current voucher. Ensure the voucher has a title and at least one row.',
      );
    }
    return AiToolSuccess('✅ Current voucher has been approved and saved.');
  }

  Future<AiToolResult> _setCompanyConfig(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) async {
    // Guard: Rate limit
    final rateLimitCheck = _checkRateLimit('set_company_config');
    if (rateLimitCheck != null) return rateLimitCheck;

    final field = (p['field'] as String?)?.trim();
    final value = (p['value'] as String?)?.toString();

    final fieldMap = {
      'companyName': 'company_name',
      'address': 'address',
      'gstin': 'gstin',
      'pan': 'pan',
      'jurisdiction': 'jurisdiction',
      'declarationText': 'declaration_text',
      'bankName': 'bank_name',
      'branch': 'branch',
      'accountNo': 'account_no',
      'ifscCode': 'ifsc_code',
      'phone': 'phone',
    };

    final currentMap = await DatabaseHelper.instance.getCompanyConfig() ??
        const CompanyConfigModel().toMap();
    final updates = <String, dynamic>{};

    if (field != null && field.isNotEmpty && value != null) {
      final dbKey = fieldMap[field];
      if (dbKey == null) {
        return AiToolFailure('Unsupported company config field "$field".');
      }

      // Guard: Validate field-specific formats
      if (field == 'gstin' && value.isNotEmpty && !_isValidGstin(value)) {
        return AiToolFailure('❌ Invalid GSTIN "$value". Expected 15 alphanumeric characters.');
      }
      if (field == 'pan' && value.isNotEmpty && !_isValidPan(value)) {
        return AiToolFailure('❌ Invalid PAN "$value". Expected format: 5 letters + 4 digits + 1 letter.');
      }
      if (field == 'phone' && value.isNotEmpty && !_isValidPhone(value)) {
        return AiToolFailure('❌ Invalid phone "$value". Expected 10 digits.');
      }
      if (field == 'ifscCode' && value.isNotEmpty && !_isValidIfsc(value)) {
        return AiToolFailure('❌ Invalid IFSC code "$value". Expected format: 4 letters + "0" + 6 alphanumeric.');
      }
      if (field == 'accountNo' && value.isNotEmpty && !_isValidAccountNumber(value)) {
        return AiToolFailure('❌ Invalid account number "$value". Expected 8-17 digits.');
      }

      updates[dbKey] = value;
    } else {
      for (final entry in fieldMap.entries) {
        if (p.containsKey(entry.key)) {
          final fieldValue = p[entry.key]?.toString() ?? '';
          
          // Validate each field
          if (entry.key == 'gstin' && fieldValue.isNotEmpty && !_isValidGstin(fieldValue)) {
            return AiToolFailure('❌ Invalid GSTIN "$fieldValue". Expected 15 alphanumeric characters.');
          }
          if (entry.key == 'pan' && fieldValue.isNotEmpty && !_isValidPan(fieldValue)) {
            return AiToolFailure('❌ Invalid PAN "$fieldValue". Expected format: 5 letters + 4 digits + 1 letter.');
          }
          if (entry.key == 'phone' && fieldValue.isNotEmpty && !_isValidPhone(fieldValue)) {
            return AiToolFailure('❌ Invalid phone "$fieldValue". Expected 10 digits.');
          }
          
          updates[entry.value] = fieldValue;
        }
      }
      if (updates.isEmpty) {
        return AiToolFailure(
          'set_company_config requires at least one valid company config field.',
        );
      }
    }

    final merged = {...currentMap, ...updates};
    await DatabaseHelper.instance.saveCompanyConfig(merged);

    try {
      final updatedConfig = CompanyConfigModel.fromMap(merged);
      notifier.config = updatedConfig;
      notifier.update((current) => current);
    } catch (_) {
      // best-effort sync only
    }

    return AiToolSuccess('✅ Company configuration has been updated.');
  }

  AiToolResult _setCompanyFilter(
    Map<String, dynamic> p,
    SalaryStateController controller,
  ) {
    final code = (p['code'] as String?)?.trim();
    if (code == null || code.isEmpty) {
      return AiToolFailure('set_company_filter requires a non-empty "code".');
    }
    controller.setCompanyCode(code);
    return AiToolSuccess('✅ Salary company filter set to "$code".');
  }

  AiToolResult _setMonthYear(
    Map<String, dynamic> p,
    SalaryDataNotifier notifier,
  ) {
    final rawMonth = p['month'];
    final rawYear = p['year'];
    if (rawMonth == null || rawYear == null) {
      return AiToolFailure('set_month_year requires "month" and "year".');
    }

    final month = _parseMonth(rawMonth);
    final year = (rawYear as num?)?.toInt() ?? int.tryParse(rawYear.toString());
    if (month == null || year == null || year < 1900 || year > 2100) {
      return AiToolFailure('Invalid month or year values.');
    }

    notifier.setMonthYear(month, year);
    return AiToolSuccess('✅ Salary month/year set to ${notifier.monthName} $year.');
  }

  AiToolResult _setDaysPresent(
    Map<String, dynamic> p,
    SalaryDataNotifier notifier,
  ) {
    final rawValue = p['days'];
    final employeeId = _resolveEmployeeId(p);
    if (employeeId == null) {
      return AiToolFailure('set_days_present requires a valid employee id or name.');
    }

    final days = (rawValue as num?)?.toInt() ?? int.tryParse(rawValue?.toString() ?? '');
    if (days == null || days < 0) {
      return AiToolFailure('set_days_present requires a non-negative "days".');
    }

    notifier.setDays(employeeId, days);
    return AiToolSuccess('✅ Set $days days present for employee id $employeeId.');
  }

  AiToolResult _setSalaryMeta(
    Map<String, dynamic> p,
    SalaryDataNotifier notifier,
  ) {
    final field = (p['field'] as String?)?.trim();
    final value = (p['value'] as String?)?.trim();
    if (field == null || field.isEmpty || value == null) {
      return AiToolFailure('set_salary_meta requires "field" and "value".');
    }

    switch (field) {
      case 'billNo':
        notifier.setBillNo(value);
        break;
      case 'poNo':
        notifier.setPoNo(value);
        break;
      case 'clientName':
        notifier.setClientName(value);
        break;
      case 'clientAddr':
        notifier.setClientAddr(value);
        break;
      case 'clientGstin':
        notifier.setClientGstin(value);
        break;
      case 'deptCode':
        notifier.setDeptCode(value);
        break;
      default:
        return AiToolFailure('Unsupported salary field "$field".');
    }

    return AiToolSuccess('✅ Updated salary metadata field "$field".');
  }

  AiToolResult _setVoucherField(
    Map<String, dynamic> p,
    VoucherNotifier notifier,
  ) {
    final field = (p['field'] as String?)?.trim();
    final value = (p['value'] as String?)?.trim();
    if (field == null || field.isEmpty || value == null) {
      return AiToolFailure('set_voucher_field requires "field" and "value".');
    }

    final acceptedFields = {
      'title', 'deptCode', 'date', 'billNo', 'poNo',
      'itemDescription', 'clientName', 'clientAddress', 'clientGstin',
    };
    if (!acceptedFields.contains(field)) {
      return AiToolFailure('Unsupported voucher field "$field".');
    }

    notifier.update((current) => current.copyWith(
          title: field == 'title' ? value : null,
          deptCode: field == 'deptCode' ? value : null,
          date: field == 'date' ? value : null,
          billNo: field == 'billNo' ? value : null,
          poNo: field == 'poNo' ? value : null,
          itemDescription: field == 'itemDescription' ? value : null,
          clientName: field == 'clientName' ? value : null,
          clientAddress: field == 'clientAddress' ? value : null,
          clientGstin: field == 'clientGstin' ? value : null,
        ));

    return AiToolSuccess('✅ Updated voucher $field.');
  }

  int? _resolveEmployeeId(Map<String, dynamic> payload) {
    final byId = (payload['employeeId'] as num?)?.toInt();
    if (byId != null) return byId;
    return null;
  }

  int? _parseMonth(dynamic rawMonth) {
    if (rawMonth is num) {
      final month = rawMonth.toInt();
      return month >= 1 && month <= 12 ? month : null;
    }
    if (rawMonth is String) {
      final text = rawMonth.trim();
      final parsed = int.tryParse(text);
      if (parsed != null && parsed >= 1 && parsed <= 12) {
        return parsed;
      }
      final normalized = text.toLowerCase();
      const months = {
        'january': 1,
        'february': 2,
        'march': 3,
        'april': 4,
        'may': 5,
        'june': 6,
        'july': 7,
        'august': 8,
        'september': 9,
        'october': 10,
        'november': 11,
        'december': 12,
      };
      return months[normalized];
    }
    return null;
  }
}