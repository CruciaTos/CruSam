// Builds voucher rows and the final "ready to persist" voucher exactly the
// way the Voucher Builder screen does. Shared by VoucherNotifier (app) and
// the MCP server so invoices created from either place are identical.

import '../models/company_config_model.dart';
import '../models/employee_model.dart';
import '../models/voucher_model.dart';
import '../models/voucher_row_model.dart';
import 'invoice_totals.dart';

class VoucherFactory {
  VoucherFactory._();

  /// A blank row, as created by the "Add employee" button.
  static VoucherRowModel blankRow({
    required String rowId,
    required String deptCode,
    required CompanyConfigModel config,
  }) =>
      VoucherRowModel(
        id: rowId,
        deptCode: deptCode,
        debitAccountNumber: config.accountNo,
        debitAccountName: config.companyName,
      );

  /// Copies an employee's bank details onto a row, as selecting an employee
  /// in the row dropdown does.
  static VoucherRowModel applyEmployee(VoucherRowModel row, EmployeeModel emp) =>
      row.copyWith(
        employeeId: emp.id?.toString() ?? '',
        employeeName: emp.name,
        ifscCode: emp.ifscCode,
        accountNumber: emp.accountNumber,
        bankDetails: emp.bankDetails,
        branch: emp.branch,
        sbCode: emp.sbCode,
      );

  /// Invoice date → `created_at`. The app reads an invoice's date back from
  /// `created_at` (see VoucherModel.fromDbMap), so persisting the chosen
  /// date there is what makes it survive a reload. If the existing
  /// timestamp already falls on that date it is kept unchanged.
  static String createdAtFor({
    required String date,
    required String existingCreatedAt,
    required String nowUtcIso,
  }) {
    final d = date.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) {
      return existingCreatedAt.trim().isNotEmpty ? existingCreatedAt : nowUtcIso;
    }
    final existing = existingCreatedAt.trim();
    if (existing.startsWith(d)) return existing;
    if (existing.isEmpty && nowUtcIso.startsWith(d)) return nowUtcIso;
    return '${d}T00:00:00.000Z';
  }

  /// Applies computed totals and the save-time metadata (status, cloud id,
  /// audit fields). Mirrors the original VoucherNotifier._persistCurrentVoucher.
  static VoucherModel prepareForSave(
    VoucherModel current, {
    required String nowUtcIso,
    required String userEmail,
    required String Function() newCloudId,
  }) {
    final totals = InvoiceTotals.fromAmounts(current.rows.map((r) => r.amount));
    final cloudId =
        current.cloudId.trim().isNotEmpty ? current.cloudId : newCloudId();
    final createdBy =
        current.createdBy.trim().isNotEmpty ? current.createdBy : userEmail;
    return current.copyWith(
      baseTotal: totals.baseTotal,
      cgst: totals.cgst,
      sgst: totals.sgst,
      totalTax: totals.totalTax,
      roundOff: totals.roundOff,
      finalTotal: totals.finalTotal,
      status: VoucherStatus.saved,
      cloudId: cloudId,
      createdBy: createdBy,
      updatedBy: userEmail,
      createdAt: createdAtFor(
        date: current.date,
        existingCreatedAt: current.createdAt,
        nowUtcIso: nowUtcIso,
      ),
      updatedAt: nowUtcIso,
      isDeleted: false,
      deletedAt: null,
    );
  }
}
