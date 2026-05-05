class AppContext {
  const AppContext({
    this.employeeCount,
    this.totalSalary,
    this.pendingVouchers,
    this.dashboardSummary,
    this.extra,
  });

  final int? employeeCount;
  final double? totalSalary;
  final int? pendingVouchers;
  final String? dashboardSummary;
  final Map<String, String>? extra;

  String toPromptSection() {
    final lines = <String>['=== Current App Data ==='];
    if (employeeCount != null) lines.add('Total employees: $employeeCount');
    if (totalSalary != null) {
      lines.add('Total salary disbursed: ₹${totalSalary!.toStringAsFixed(2)}');
    }
    if (pendingVouchers != null) lines.add('Pending vouchers: $pendingVouchers');
    if (dashboardSummary != null) lines.add(dashboardSummary!);
    extra?.forEach((k, v) => lines.add('$k: $v'));
    lines.add('========================');
    return lines.join('\n');
  }

  bool get isEmpty =>
      employeeCount == null &&
      totalSalary == null &&
      pendingVouchers == null &&
      dashboardSummary == null &&
      (extra == null || extra!.isEmpty);
}
