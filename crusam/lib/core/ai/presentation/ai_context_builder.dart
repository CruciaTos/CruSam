import 'package:crusam/core/ai/models/app_context.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';

/// Builds a rich [AppContext] from live notifier state for injection into
/// [AiChatNotifier] before every message.
///
/// **Important**: This automatically loads ALL historical data (employees, invoices)
/// from the database before building context, ensuring Ollama sees all existing data.
///
/// Usage:
///
/// ```dart
/// final ctx = await AiContextBuilder.build(
///   employeeNotifier: EmployeeNotifier.instance,
///   voucherNotifier:  VoucherNotifier.instance,
///   currentVoucher:   VoucherNotifier.instance.current,
/// );
/// AiChatNotifier.instance.updateContext(ctx);
/// AiChatNotifier.instance.sendMessage(text);
/// ```
class AiContextBuilder {
  AiContextBuilder._();

  static Future<AppContext> build({
    EmployeeNotifier? employeeNotifier,
    SalaryStateController? salaryStateController,
    SalaryDataNotifier? salaryDataNotifier,
    VoucherNotifier? voucherNotifier,
    /// The voucher currently open in the Voucher Builder screen.
    /// Pass [VoucherNotifier.instance.current] for real-time draft data.
    VoucherModel? currentVoucher,
    Map<String, String>? extras,
  }) async {
    // **CRITICAL**: Load ALL historical data from database before building context.
    // This ensures Ollama receives the complete picture, not just in-memory state.
    if (employeeNotifier != null && employeeNotifier.employees.isEmpty) {
      await employeeNotifier.load();
    }
    if (voucherNotifier != null && voucherNotifier.savedVouchers.isEmpty) {
      await voucherNotifier.loadDependencies();
    }

    final employeeSection     = _buildEmployeeSection(employeeNotifier);
    final salarySection       = _buildSalarySection(salaryStateController, salaryDataNotifier);
    final currentDraftSection = _buildCurrentDraftSection(currentVoucher);
    final savedInvoiceSection = _buildSavedInvoiceSection(voucherNotifier);

    final combined = <String, String>{
      if (employeeSection     != null) 'employee_data':      employeeSection,
      if (salarySection       != null) 'salary_data':        salarySection,
      if (currentDraftSection != null) 'current_draft':      currentDraftSection,
      if (savedInvoiceSection != null) 'saved_invoices':     savedInvoiceSection,
      ...?extras,
    };

    if (employeeNotifier == null) {
      return AppContext(extra: combined.isEmpty ? null : combined);
    }

    final employees = employeeNotifier.employees;
    double totalBasic = 0, totalOther = 0;
    for (final e in employees) {
      totalBasic += e.basicCharges;
      totalOther += e.otherCharges;
    }

    return AppContext(
      employeeCount:   employees.length,
      totalSalary:     totalBasic + totalOther,
      pendingVouchers: voucherNotifier != null
          ? voucherNotifier.savedVouchers
              .where((v) => v.status == VoucherStatus.draft)
              .length
          : null,
      dashboardSummary: _fullDashboardSummary(
        employees,
        voucherNotifier,
        currentVoucher,
        salaryStateController,
        salaryDataNotifier,
      ),
      extra: combined.isEmpty ? null : combined,
    );
  }

  // ── Employee data ──────────────────────────────────────────────────────────

  static String? _buildEmployeeSection(EmployeeNotifier? notifier) {
    if (notifier == null) return null;
    final employees = notifier.employees;
    if (employees.isEmpty) return null;

    final Map<String, int> zoneMap = {};
    final Map<String, int> codeMap = {};
    double totalBasic = 0, totalOther = 0;

    for (final e in employees) {
      final z = e.zone.trim().isEmpty ? 'Unknown' : e.zone.trim();
      zoneMap[z] = (zoneMap[z] ?? 0) + 1;
      final c = e.code.trim().isEmpty ? 'Unknown' : e.code.trim();
      codeMap[c] = (codeMap[c] ?? 0) + 1;
      totalBasic += e.basicCharges;
      totalOther += e.otherCharges;
    }

    final zoneLines   = zoneMap.entries.map((e) => '  ${e.key}: ${e.value} employees').join('\n');
    final codeLines   = codeMap.entries.map((e) => '  ${e.key}: ${e.value} employees').join('\n');
    final rosterLines = employees.map(_employeeToLine).join('\n');

    return '''
--- Employee Count: ${employees.length} ---
--- Total Basic: ₹${totalBasic.toStringAsFixed(2)} | Total Other: ₹${totalOther.toStringAsFixed(2)} | Total Gross: ₹${(totalBasic + totalOther).toStringAsFixed(2)} ---

--- Zone Breakdown ---
$zoneLines

--- Department (Code) Breakdown ---
$codeLines

--- Full Employee Roster ---
$rosterLines
''';
  }

  static String _employeeToLine(EmployeeModel e) {
    final gross = (e.basicCharges + e.otherCharges).toStringAsFixed(2);
    return '[${e.srNo}] ${e.name} | Code:${e.code} | Zone:${e.zone} '
        '| Gender:${e.gender} | Basic:₹${e.basicCharges.toStringAsFixed(2)} '
        '| Other:₹${e.otherCharges.toStringAsFixed(2)} | Gross:₹$gross '
        '| Bank:${e.bankDetails} | Branch:${e.branch} '
        '| PF:${e.pfNo} | UAN:${e.uanNo} | DOJ:${e.dateOfJoining}';
  }

  // ── Current Voucher Builder draft (REAL-TIME) ──────────────────────────────

  /// Builds a detailed section for the voucher currently open in the builder.
  /// Includes every row so the AI can answer questions about the live draft.
  static String? _buildCurrentDraftSection(VoucherModel? v) {
    if (v == null) return null;
    // Treat an empty draft (no rows, no title) as "nothing open"
    if (v.rows.isEmpty && v.title.trim().isEmpty) return null;

    final sb = StringBuffer();
    sb.writeln('=== VOUCHER BUILDER — CURRENT DRAFT ===');
    sb.writeln('Title       : ${v.title.isEmpty ? "(Untitled)" : v.title}');
    sb.writeln('Bill No     : ${v.billNo.isEmpty ? "(not set)" : v.billNo}');
    sb.writeln('Date        : ${v.date}');
    sb.writeln('Client      : ${v.clientName.isEmpty ? "(not set)" : v.clientName}');
    sb.writeln('Dept Code   : ${v.deptCode}');
    sb.writeln('Status      : ${v.status.name.toUpperCase()}');
    sb.writeln('Base Total  : ₹${v.baseTotal.toStringAsFixed(2)}');
    sb.writeln('CGST (9%)   : ₹${v.cgst.toStringAsFixed(2)}');
    sb.writeln('SGST (9%)   : ₹${v.sgst.toStringAsFixed(2)}');
    sb.writeln('Grand Total : ₹${v.finalTotal.toStringAsFixed(2)}');
    sb.writeln('Row Count   : ${v.rows.length}');

    if (v.rows.isNotEmpty) {
      sb.writeln('\n--- Draft Rows ---');
      for (var i = 0; i < v.rows.length; i++) {
        sb.writeln(_rowToLine(i + 1, v.rows[i]));
      }
    }

    sb.writeln('=== END CURRENT DRAFT ===');
    return sb.toString();
  }

  // ── Saved Invoices (ALL rows, real-time) ───────────────────────────────────

  /// Builds a full invoice list from [VoucherNotifier.savedVouchers].
  /// Each invoice includes every disbursement row so the AI has complete data.
  static String? _buildSavedInvoiceSection(VoucherNotifier? notifier) {
    if (notifier == null) return null;
    final vouchers = notifier.savedVouchers;
    if (vouchers.isEmpty) return null;

    final saved  = vouchers.where((v) => v.status == VoucherStatus.saved).toList();
    final drafts = vouchers.where((v) => v.status == VoucherStatus.draft).toList();

    double totalInvoiced = 0;
    for (final v in saved) {
      totalInvoiced += v.finalTotal;
    }

    final sb = StringBuffer();
    sb.writeln('=== ALL INVOICES ===');
    sb.writeln('Total : ${vouchers.length}  (${saved.length} saved, ${drafts.length} drafts)');
    sb.writeln('Total Invoiced Amount : ₹${totalInvoiced.toStringAsFixed(2)}');
    sb.writeln();

    for (final v in vouchers) {
      sb.writeln('--- Invoice: ${v.billNo.isEmpty ? "(no bill no)" : v.billNo} ---');
      sb.writeln('  Title       : ${v.title.isEmpty ? "(Untitled)" : v.title}');
      sb.writeln('  Date        : ${v.date}');
      sb.writeln('  Client      : ${v.clientName.isEmpty ? "(not set)" : v.clientName}');
      sb.writeln('  Dept Code   : ${v.deptCode}');
      sb.writeln('  Status      : ${v.status.name.toUpperCase()}');
      sb.writeln('  Base Total  : ₹${v.baseTotal.toStringAsFixed(2)}');
      sb.writeln('  CGST (9%)   : ₹${v.cgst.toStringAsFixed(2)}');
      sb.writeln('  SGST (9%)   : ₹${v.sgst.toStringAsFixed(2)}');
      sb.writeln('  Grand Total : ₹${v.finalTotal.toStringAsFixed(2)}');
      sb.writeln('  Row Count   : ${v.rows.length}');

      if (v.rows.isNotEmpty) {
        sb.writeln('  Rows:');
        for (var i = 0; i < v.rows.length; i++) {
          sb.writeln('    ${_rowToLine(i + 1, v.rows[i])}');
        }
      }
      sb.writeln();
    }

    sb.writeln('=== END INVOICES ===');
    return sb.toString();
  }

  // ── Row formatter ──────────────────────────────────────────────────────────

  static String _rowToLine(int index, VoucherRowModel r) =>
      '[$index] ${r.employeeName} | Amt:₹${r.amount.toStringAsFixed(2)} '
      '| IFSC:${r.ifscCode} | A/c:${r.accountNumber} '
      '| Bank:${r.bankDetails} | Branch:${r.branch} '
      '| Code:${r.sbCode} '
      '| From:${r.fromDate.isEmpty ? "-" : r.fromDate} '
      '| To:${r.toDate.isEmpty ? "-" : r.toDate}';

  static String? _buildSalarySection(
    SalaryStateController? controller,
    SalaryDataNotifier? dataNotifier,
  ) {
    if (controller == null || dataNotifier == null) return null;

    final monthYear = '${dataNotifier.monthName} ${dataNotifier.year}';
    final employees = controller.filteredEmployees;
    final employeeLines = employees.map((e) {
      final days = dataNotifier.getDays(e.id ?? 0);
      final earnedBasic = dataNotifier.totalDays == 0
          ? 0
          : e.basicCharges * days / dataNotifier.totalDays;
      final earnedGross = dataNotifier.totalDays == 0
          ? 0
          : e.grossSalary * days / dataNotifier.totalDays;
      return '  [${e.srNo}] ${e.name} | Days:$days | Basic:₹${e.basicCharges.toStringAsFixed(2)} | Gross:₹${e.grossSalary.toStringAsFixed(2)} | Earned Basic:₹${earnedBasic.toStringAsFixed(2)} | Earned Gross:₹${earnedGross.toStringAsFixed(2)}';
    }).join('\n');

    return '''
--- Salary Context ---
Month/Year: $monthYear
Total days in month: ${dataNotifier.totalDays}
Company filter: ${controller.selectedCompanyCode}
Employees in scope: ${employees.length}
Total Basic Full: ₹${controller.totalBasicFull.toStringAsFixed(2)}
Total Gross Full: ₹${controller.totalGrossFull.toStringAsFixed(2)}
Total Earned Basic: ₹${controller.totalEarnedBasic.toStringAsFixed(2)}
Total Earned Gross: ₹${controller.totalEarnedGross.toStringAsFixed(2)}
Attachment A PF: ₹${controller.attachmentAPf.toStringAsFixed(2)}
Attachment A ESIC: ₹${controller.attachmentAEsic.toStringAsFixed(2)}
Attachment A Subtotal: ₹${controller.attachmentASubtotal.toStringAsFixed(2)}
Attachment A Total: ₹${controller.attachmentATotal.toStringAsFixed(2)}
Attachment B Total: ₹${controller.attachmentBTotal.toStringAsFixed(2)}
Invoice Total: ₹${controller.invoiceTotal.toStringAsFixed(2)}
Bill No: ${dataNotifier.billNo}
PO No: ${dataNotifier.poNo}
Client Name: ${dataNotifier.clientName}
Dept Code: ${dataNotifier.deptCode}

--- Days Present ---
$employeeLines
''';
  }

  // ── Combined dashboard summary ─────────────────────────────────────────────

  static String? _fullDashboardSummary(
    List<EmployeeModel> employees,
    VoucherNotifier? voucherNotifier,
    VoucherModel? currentVoucher,
    SalaryStateController? salaryStateController,
    SalaryDataNotifier? salaryDataNotifier,
  ) {
    final parts = <String>[];

    if (employees.isNotEmpty) {
      final Map<String, int> zoneMap = {};
      final Map<String, int> codeMap = {};
      for (final e in employees) {
        final z = e.zone.trim().isEmpty ? 'Unknown' : e.zone.trim();
        zoneMap[z] = (zoneMap[z] ?? 0) + 1;
        final c = e.code.trim().isEmpty ? 'Unknown' : e.code.trim();
        codeMap[c] = (codeMap[c] ?? 0) + 1;
      }
      parts.add(
        'Zone Breakdown: ${zoneMap.entries.map((e) => "${e.key}:${e.value}").join(", ")}',
      );
      parts.add(
        'Dept Breakdown: ${codeMap.entries.map((e) => "${e.key}:${e.value}").join(", ")}',
      );
      parts.add('\n--- Employee Roster ---\n${employees.map(_employeeToLine).join('\n')}');
    }

    final salarySection = _buildSalarySummary(salaryStateController, salaryDataNotifier);
    if (salarySection != null) parts.add(salarySection);

    final draftSection = _buildCurrentDraftSection(currentVoucher);
    if (draftSection != null) parts.add(draftSection);

    final invoiceSection = _buildSavedInvoiceSection(voucherNotifier);
    if (invoiceSection != null) parts.add(invoiceSection);

    return parts.isEmpty ? null : parts.join('\n');
  }

  static String? _buildSalarySummary(
    SalaryStateController? controller,
    SalaryDataNotifier? dataNotifier,
  ) {
    if (controller == null || dataNotifier == null) return null;
    return 'Salary Summary: Month ${dataNotifier.monthName} ${dataNotifier.year} | Company filter: ${controller.selectedCompanyCode} | Total Basic: ₹${controller.totalBasicFull.toStringAsFixed(2)} | Total Gross: ₹${controller.totalGrossFull.toStringAsFixed(2)} | Total Earned Gross: ₹${controller.totalEarnedGross.toStringAsFixed(2)} | Invoice Total: ₹${controller.invoiceTotal.toStringAsFixed(2)}';
  }
}