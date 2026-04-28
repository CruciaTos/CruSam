import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';


// ---------------------------------------------------------------------------
// Replace these imports with your actual notifier paths.
// The build() method below shows the pattern – adapt field names to match
// whatever your SalaryStateController / VoucherNotifier / DashboardNotifier
// actually expose.
// ---------------------------------------------------------------------------
//
// import '../../features/salary/salary_state_controller.dart';
// import '../../features/voucher/voucher_notifier.dart';
// import '../../features/dashboard/dashboard_notifier.dart';
// import '../../features/employee/employee_notifier.dart';

/// Stateless helper that reads live data from your existing notifiers and
/// produces an [AppContext] ready to inject into [AiChatNotifier].
///
/// Usage (call this right before or inside your send-message handler):
///
/// ```dart
/// final ctx = AiContextBuilder.build(
///   salaryController: SalaryStateController.instance,
///   voucherNotifier: VoucherNotifier.instance,
///   dashboardNotifier: DashboardNotifier.instance,
///   employeeNotifier: EmployeeNotifier.instance,
/// );
/// AiChatNotifier.instance.updateContext(ctx);
/// AiChatNotifier.instance.sendMessage(text);
/// ```
class AiContextBuilder {
  AiContextBuilder._();

  /// Builds an [AppContext] from your live notifier instances.
  ///
  /// All parameters are optional – pass only the notifiers you actually have.
  /// Any null parameter is silently skipped.
  static AppContext build({
    // Uncomment and type-annotate once you wire up real imports:
    // SalaryStateController? salaryController,
    // VoucherNotifier? voucherNotifier,
    // DashboardNotifier? dashboardNotifier,
    // EmployeeNotifier? employeeNotifier,

    // Generic escape-hatch: pass arbitrary key→value pairs.
    Map<String, String>? extras,
  }) {
    // ---- Employee data ----
    int? employeeCount;
    // if (employeeNotifier != null) {
    //   employeeCount = employeeNotifier.employees.length;
    // }

    // ---- Salary data ----
    double? totalSalary;
    // if (salaryController != null) {
    //   totalSalary = salaryController.totalDisbursed;   // ← your field name
    // }

    // ---- Voucher data ----
    int? pendingVouchers;
    // if (voucherNotifier != null) {
    //   pendingVouchers = voucherNotifier.pendingCount;  // ← your field name
    // }

    // ---- Dashboard summary ----
    String? dashboardSummary;
    // if (dashboardNotifier != null) {
    //   dashboardSummary = _buildDashboardLines(dashboardNotifier);
    // }

    return AppContext(
      employeeCount: employeeCount,
      totalSalary: totalSalary,
      pendingVouchers: pendingVouchers,
      dashboardSummary: dashboardSummary,
      extra: extras,
    );
  }

  // ---- Private helpers (expand as needed) ----------------------------------

  // static String _buildDashboardLines(DashboardNotifier n) {
  //   final lines = <String>[];
  //   if (n.currentMonthRevenue != null) {
  //     lines.add('Current month revenue: ₹${n.currentMonthRevenue}');
  //   }
  //   if (n.openTickets != null) {
  //     lines.add('Open support tickets: ${n.openTickets}');
  //   }
  //   return lines.join('\n');
  // }
}