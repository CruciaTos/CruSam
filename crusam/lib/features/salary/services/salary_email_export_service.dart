// lib/features/salary/services/salary_email_export_service.dart
//
// Builds in-memory bytes for every salary document type that can be
// emailed from the Saved Salary screen — Salary Slips, Salary Bill
// (export + finalised), Salary Statement, and Disbursement — by reusing
// the exact generators each dedicated screen already uses, just routed
// to bytes instead of (or in addition to) disk.
//
// All of these read the live SalaryDataNotifier / SalaryStateController
// singletons, so the relevant saved salary period must already be the
// app's active context (see SalarySnapshotNotifier.loadMonth) before
// calling any of these.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../vouchers/services/pdf_export_service.dart';
import '../models/salary_disbursement_model.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_disbursement_notifier.dart';
import '../notifier/salary_state_controller.dart';
import '../widgets/attachment_a_preview.dart';
import '../widgets/attachment_b_preview.dart';
import '../widgets/salary_bill_preview.dart';
import '../widgets/salary_statement_preview.dart';
import 'salary_pdf_export_service.dart';
import 'salary_statement_pdf_service.dart';

/// Every document type the Saved Salary screen can send by email.
enum SalaryDocumentType {
  salarySlips,
  salaryBillExport,
  salaryBillFinal,
  salaryStatement,
  disbursement,
}

extension SalaryDocumentTypeX on SalaryDocumentType {
  String get label => switch (this) {
    SalaryDocumentType.salarySlips => 'Salary Slips',
    SalaryDocumentType.salaryBillExport => 'Salary Bill — Export',
    SalaryDocumentType.salaryBillFinal => 'Salary Bill — Finalised',
    SalaryDocumentType.salaryStatement => 'Salary Statement',
    SalaryDocumentType.disbursement => 'Disbursement (Excel)',
  };

  /// entity_type value stored on the email_log row for this document.
  String get entityType => switch (this) {
    SalaryDocumentType.salarySlips => 'salary_slip',
    SalaryDocumentType.salaryBillExport => 'salary_bill_export',
    SalaryDocumentType.salaryBillFinal => 'salary_bill_final',
    SalaryDocumentType.salaryStatement => 'salary_statement',
    SalaryDocumentType.disbursement => 'salary_disbursement',
  };

  /// Disbursement batches already carry their own fixed department/code —
  /// every other document type can be scoped to a department on demand.
  bool get usesDepartmentFilter => this != SalaryDocumentType.disbursement;
}

/// A generated document ready to attach to an email.
class SalaryDocumentBytes {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const SalaryDocumentBytes({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

class SalaryEmailExportService {
  SalaryEmailExportService._();

  static const String pdfMimeType = 'application/pdf';
  static const String xlsxMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static const String _defaultItemDescription = 'Manpower Supply Charges';

  // ── Salary Slips ───────────────────────────────────────────────────────
  static Future<SalaryDocumentBytes> buildSalarySlips({
    required CompanyConfigModel config,
    required String deptCode,
  }) async {
    final n = SalaryDataNotifier.instance;
    final sc = SalaryStateController.instance;
    final employees = _filterByDept(sc.employees, deptCode);

    final bytes = await SalaryPdfExportService.buildSalarySlipsBytes(
      config: config,
      employees: employees,
      monthName: n.monthName,
      year: n.year,
      daysInMonth: n.totalDays,
      isMsw: n.isMsw,
      isFeb: n.isFeb,
    );

    return SalaryDocumentBytes(
      bytes: bytes,
      filename: 'salary_slips_${n.monthName.toLowerCase()}_${n.year}.pdf',
      mimeType: pdfMimeType,
    );
  }

  // ── Salary Statement ───────────────────────────────────────────────────
  static Future<SalaryDocumentBytes> buildSalaryStatement({
    required CompanyConfigModel config,
    required String deptCode,
  }) async {
    final n = SalaryDataNotifier.instance;
    final sc = SalaryStateController.instance;
    final employees = _filterByDept(sc.employees, deptCode);
    final daysMap = _daysMapFor(employees, n);

    final bytes = await SalaryStatementPdfService.buildSalaryStatementBytes(
      config: config,
      employees: employees,
      monthName: n.monthName,
      year: n.year,
      isMsw: n.isMsw,
      isFeb: n.isFeb,
      daysMap: daysMap,
      daysInMonth: n.totalDays,
    );

    return SalaryDocumentBytes(
      bytes: bytes,
      filename: 'salary_statement_${n.monthName.toLowerCase()}_${n.year}.pdf',
      mimeType: pdfMimeType,
    );
  }

  // ── Salary Bill — export version, or finalised bundle ─────────────────
  //
  // Temporarily switches SalaryStateController's company-code filter to
  // [deptCode] so every computed total (invoice / Attachment A / Attachment
  // B) reflects that department only — exactly what happens when a user
  // picks that chip themselves on the Salary Bills screen — then restores
  // whatever was selected before, so this never leaves global state changed
  // behind the scenes.
  static Future<SalaryDocumentBytes> buildSalaryBill({
    required BuildContext context,
    required CompanyConfigModel config,
    required EdgeInsets margins,
    required String deptCode,
    required bool finalised,
  }) async {
    final n = SalaryDataNotifier.instance;
    final sc = SalaryStateController.instance;
    final originalCode = sc.selectedCompanyCode;

    try {
      sc.setCompanyCode(deptCode);

      final pages = <Widget>[
        ...SalaryBillPreview.buildPdfPages(
          config: config,
          margins: margins,
          invoiceBaseAmount: sc.invoiceTotal,
          billNo: n.billNo,
          date: n.dateDisplay,
          poNo: n.poNo,
          itemDescription: _defaultItemDescription,
          customerName: n.clientName,
          customerAddress: n.clientAddr,
          customerGst: n.clientGstin,
        ),
        if (finalised) ...[
          ...AttachmentAPreview.buildPdfPages(
            config: config,
            margins: margins,
            itemAmount: sc.totalGrossFull,
            pfAmount: sc.attachmentAPf,
            esicAmount: sc.attachmentAEsic,
            totalAfterTax: sc.attachmentATotal,
            billNo: n.billNo,
            date: n.dateDisplay,
            poNo: n.poNo,
            itemDescription: _defaultItemDescription,
            customerName: n.clientName,
            customerAddress: n.clientAddr,
            customerGst: n.clientGstin,
          ),
          ...AttachmentBPreview.buildPdfPages(
            config: config,
            margins: margins,
            employeeCount: sc.employeeCount,
            billNo: n.billNo,
            date: n.dateDisplay,
            poNo: n.poNo,
            itemDescription: _defaultItemDescription,
            customerName: n.clientName,
            customerAddress: n.clientAddr,
            customerGst: n.clientGstin,
          ),
          ...SalaryStatementPreview.buildPdfPages(
            config: config,
            margins: margins,
            employees: sc.filteredEmployees,
            monthName: n.monthName,
            year: n.year,
            isMsw: n.isMsw,
            isFeb: n.isFeb,
            daysMap: _daysMapFor(sc.filteredEmployees, n),
            daysInMonth: n.totalDays,
          ),
        ],
      ];

      final bytes = await PdfExportService.buildWidgetsBytes(
        context: context,
        pages: pages,
        assetPathsToPrecache: const [
          'assets/images/aarti_logo.png',
          'assets/images/aarti_signature.png',
          'assets/images/letterhead.png',
        ],
      );

      final slug =
          n.billNo.trim().isEmpty
              ? '${DateTime.now().millisecondsSinceEpoch}'
              : n.billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final prefix = finalised ? 'final_invoice' : 'salary_invoice';

      return SalaryDocumentBytes(
        bytes: bytes,
        filename: '${prefix}_$slug.pdf',
        mimeType: pdfMimeType,
      );
    } finally {
      sc.setCompanyCode(originalCode);
    }
  }

  // ── Disbursement — re-exports an already-generated batch's Excel ──────
  //
  // Disbursement batches carry real bank account/IFSC details and are
  // created through the dedicated Disbursements screen's own review-and-
  // select workflow. This never generates a new batch — it only re-exports
  // bytes for one that already exists, the same way that screen's own
  // "Export Excel" button does (including marking it exported).
  static Future<SalaryDocumentBytes?> buildDisbursementExcel(
    SalaryDisbursementModel disbursement,
  ) async {
    final path = await SalaryDisbursementNotifier.instance
        .exportDisbursementExcel(disbursement);
    if (path == null) return null;

    final bytes = await File(path).readAsBytes();
    final filename = path.split(Platform.pathSeparator).last;

    return SalaryDocumentBytes(
      bytes: bytes,
      filename: filename,
      mimeType: xlsxMimeType,
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────

  /// Mirrors SalaryStateController.filteredEmployees but for an explicit
  /// department code chosen in the send dialog (independent of whatever
  /// the live selectedCompanyCode happens to be elsewhere in the app).
  static List<EmployeeModel> _filterByDept(
    List<EmployeeModel> employees,
    String deptCode,
  ) {
    final list =
        deptCode == 'All'
            ? List<EmployeeModel>.from(employees)
            : employees.where((e) => e.code == deptCode).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static Map<int, int> _daysMapFor(
    List<EmployeeModel> employees,
    SalaryDataNotifier n,
  ) {
    final map = <int, int>{};
    for (final e in employees) {
      final id = e.id;
      if (id != null) map[id] = n.getDays(id);
    }
    return map;
  }
}