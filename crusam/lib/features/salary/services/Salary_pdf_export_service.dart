import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_state_controller.dart';
import '../widgets/salary_slip_preview.dart';
import '../widgets/salary_bill_preview.dart';
import '../widgets/attachment_a_preview.dart';
import '../widgets/attachment_b_preview.dart';
import 'package:crusam/features/vouchers/services/pdf_export_service.dart';

class SalaryPdfExportService {
  // ──────────────────────────────────────────────────────────────────────────
  // ✅ All exports now delegate to PdfExportService.exportWidgets()
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> exportSalarySlips({
    required BuildContext context,
    required CompanyConfigModel config,
    required List<EmployeeModel> employees,
    required String monthName,
    required int year,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) async {
    final n = SalaryDataNotifier.instance;
    final pages = <Widget>[];

    for (final emp in employees) {
      final days     = n.getDays(emp.id ?? 0);
      final total    = daysInMonth;
      final eBasic   = total == 0 ? 0.0 : emp.basicCharges * days / total;
      final eOther   = total == 0 ? 0.0 : emp.otherCharges * days / total;
      final eGross   = eBasic + eOther;
      final pf       = (eBasic * 0.12).round().toDouble();
      final esicApplicable = emp.grossSalary >= 21000;
      final esic     = esicApplicable ? (eGross * 0.0075).ceil().toDouble() : 0.0;
      final msw      = isMsw ? 6.0 : 0.0;
      final isFemale = emp.gender.toUpperCase() == 'F';
      double pt;
      if (isFemale) {
        pt = eGross < 25000 ? 0 : (isFeb ? 300 : 200);
      } else {
        if (eGross < 7500) pt = 0;
        else if (eGross < 10000) pt = 175;
        else pt = isFeb ? 300 : 200;
      }

      final dept = _codeToDept(emp.code);
      pages.add(SalarySlipPreview(
        config:           config,
        employeeName:     emp.name,
        employeeCode:     emp.code,
        designation:      'Technician',
        department:       dept,
        pfNo:             emp.pfNo,
        uanNo:            emp.uanNo,
        bankName:         emp.bankDetails,
        accountNo:        emp.accountNumber,
        ifscCode:         emp.ifscCode,
        month:            monthName,
        year:             year.toString(),
        daysInMonth:      daysInMonth,
        daysPresent:      days,
        basicSalary:      emp.basicCharges,
        otherAllowances:  emp.otherCharges,
        pfDeduction:      pf,
        esicDeduction:    esic,
        mswDeduction:     msw,
        ptDeduction:      pt,
      ));
    }

    if (pages.isEmpty) throw Exception('No employees to export');

    final slug = '${monthName.toLowerCase()}_$year';
    await PdfExportService.exportWidgets(
      context: context,
      pages: pages,
      fileNameSlug: slug,
      filePrefix: 'salary_slips',
      shareSubject: 'Salary Slips',
      assetPathsToPrecache: [
        'assets/images/aarti_logo.png',
        'assets/images/aarti_signature.png',
      ],
    );
  }

  static Future<void> exportSalaryInvoice({
    required BuildContext context,
    required CompanyConfigModel config,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required String customerName,
    required String customerAddress,
    required String customerGst,
    required double invoiceBaseAmount,
  }) async {
    final sc = SalaryStateController.instance;
    final n  = SalaryDataNotifier.instance;

    final pages = <Widget>[];

    // 1. Salary Invoice page
    pages.add(SalaryBillPreview(
      config:            config,
      customerName:      customerName,
      customerAddress:   customerAddress,
      customerGst:       customerGst,
      billNo:            billNo,
      date:              date,
      poNo:              poNo,
      itemDescription:   itemDescription,
      invoiceBaseAmount: invoiceBaseAmount,
    ));

    // 2. One salary slip per filtered employee
    final employees   = sc.filteredEmployees;
    final daysInMonth = n.totalDays;
    final isMsw       = n.isMsw;
    final isFeb       = n.isFeb;

    for (final emp in employees) {
      final days   = n.getDays(emp.id ?? 0);
      final total  = daysInMonth;
      final eBasic = total == 0 ? 0.0 : emp.basicCharges * days / total;
      final eGross = eBasic + (total == 0 ? 0.0 : emp.otherCharges * days / total);
      final pf     = (eBasic * 0.12).round().toDouble();
      final esicApplicable = emp.grossSalary >= 21000;
      final esic   = esicApplicable ? (eGross * 0.0075).ceil().toDouble() : 0.0;
      final msw    = isMsw ? 6.0 : 0.0;
      final isFemale = emp.gender.toUpperCase() == 'F';
      double pt;
      if (isFemale) {
        pt = eGross < 25000 ? 0 : (isFeb ? 300 : 200);
      } else {
        if (eGross < 7500) pt = 0;
        else if (eGross < 10000) pt = 175;
        else pt = isFeb ? 300 : 200;
      }

      pages.add(SalarySlipPreview(
        config:           config,
        employeeName:     emp.name,
        employeeCode:     emp.code,
        designation:      'Technician',
        department:       _codeToDept(emp.code),
        pfNo:             emp.pfNo,
        uanNo:            emp.uanNo,
        bankName:         emp.bankDetails,
        accountNo:        emp.accountNumber,
        ifscCode:         emp.ifscCode,
        month:            n.monthName,
        year:             n.year.toString(),
        daysInMonth:      daysInMonth,
        daysPresent:      days,
        basicSalary:      emp.basicCharges,
        otherAllowances:  emp.otherCharges,
        pfDeduction:      pf,
        esicDeduction:    esic,
        mswDeduction:     msw,
        ptDeduction:      pt,
      ));
    }

    await PdfExportService.exportWidgets(
      context: context,
      pages: pages,
      fileNameSlug: _slugify(billNo),
      filePrefix: 'salary_invoice',
      shareSubject: 'Salary Invoice',
      assetPathsToPrecache: [
        'assets/images/aarti_logo.png',
        'assets/images/aarti_signature.png',
      ],
    );
  }

  static Future<void> exportAttachmentA({
    required BuildContext context,
    required CompanyConfigModel config,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required double itemAmount,
    required double pfAmount,
    required double esicAmount,
    required double totalAfterTax,
    required String customerName,
    required String customerAddress,
    required String customerGst,
  }) async {
    final pages = AttachmentAPreview.buildPdfPages(
      config: config,
      itemAmount: itemAmount,
      pfAmount: pfAmount,
      esicAmount: esicAmount,
      totalAfterTax: totalAfterTax,
      // The preview's buildPdfPages already uses the default customer fields.
      // If you need to override, pass them into AttachmentAPreview constructor.
    );

    // Note: AttachmentAPreview uses hardcoded customer fields by default.
    // To pass custom values, modify buildPdfPages to accept them or create
    // the preview instance directly with your parameters.
    // For now, we assume the preview already receives the correct data via config.

    await PdfExportService.exportWidgets(
      context: context,
      pages: pages,
      fileNameSlug: _slugify(billNo),
      filePrefix: 'attachment_a',
      shareSubject: 'Attachment A',
      assetPathsToPrecache: [
        'assets/images/aarti_logo.png',
        'assets/images/aarti_signature.png',
      ],
    );
  }

  static Future<void> exportAttachmentB({
    required BuildContext context,
    required CompanyConfigModel config,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required int employeeCount,
    required String customerName,
    required String customerAddress,
    required String customerGst,
  }) async {
    final pages = AttachmentBPreview.buildPdfPages(
      config: config,
      employeeCount: employeeCount,
      // Similar note: pass customer details if needed.
    );

    await PdfExportService.exportWidgets(
      context: context,
      pages: pages,
      fileNameSlug: _slugify(billNo),
      filePrefix: 'attachment_b',
      shareSubject: 'Attachment B',
      assetPathsToPrecache: [
        'assets/images/aarti_logo.png',
        'assets/images/aarti_signature.png',
      ],
    );
  }

  // ── Helper ────────────────────────────────────────────────────────────────
  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
    'F&B' => 'Food & Beverage',
    'I&L' => 'Infrastructure & Logistics',
    'P&S' => 'Projects & Services',
    'A&P' => 'Administration & Projects',
    _     => code,
  };
}