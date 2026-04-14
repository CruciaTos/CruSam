import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/db/database_helper.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_state_controller.dart';
import '../widgets/salary_slip_preview.dart';
import '../widgets/salary_bill_preview.dart';
import '../widgets/attachment_a_preview.dart';
import '../widgets/attachment_b_preview.dart';
import 'package:crusam/features/salary/widgets/attachment_a_preview.dart';
import 'package:crusam/features/salary/widgets/attachment_b_preview.dart';


class SalaryPdfExportService {
  static const Duration _captureDelay = Duration(milliseconds: 200);
  static const double _capturePixelRatio = 3.0;

  // ── Salary Slips (all filtered employees) ─────────────────────────────────
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

    if (pages.isEmpty) {
      throw Exception('No employees to export');
    }

    final prefix = 'salary_slips_${monthName.toLowerCase()}_$year';
    await _captureAndSave(context: context, pages: pages, prefix: prefix, subject: 'Salary Slips');
  }

  // ── Salary Invoice (invoice page + all employee slips) ────────────────────
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
    final employees  = sc.filteredEmployees;
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

    final prefix = 'salary_invoice_${n.monthName.toLowerCase()}_${n.year}';
    await _captureAndSave(context: context, pages: pages, prefix: prefix, subject: 'Salary Invoice');
  }

  // ── Attachment A ──────────────────────────────────────────────────────────
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
    final pages = <Widget>[
      AttachmentAPreview(
        config:          config,
        customerName:    customerName,
        customerAddress: customerAddress,
        customerGst:     customerGst,
        billNo:          billNo,
        date:            date,
        poNo:            poNo,
        itemDescription: itemDescription,
        itemAmount:      itemAmount,
        pfAmount:        pfAmount,
        esicAmount:      esicAmount,
        totalAfterTax:   totalAfterTax,
      ),
    ];
    await _captureAndSave(context: context, pages: pages, prefix: 'attachment_a', subject: 'Attachment A');
  }

  // ── Attachment B ──────────────────────────────────────────────────────────
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
    final pages = <Widget>[
      AttachmentBPreview(
        config:          config,
        customerName:    customerName,
        customerAddress: customerAddress,
        customerGst:     customerGst,
        billNo:          billNo,
        date:            date,
        poNo:            poNo,
        itemDescription: itemDescription,
        employeeCount:   employeeCount,
      ),
    ];
    await _captureAndSave(context: context, pages: pages, prefix: 'attachment_b', subject: 'Attachment B');
  }

  // ── Core capture + PDF + share ────────────────────────────────────────────
  static Future<void> _captureAndSave({
    required BuildContext context,
    required List<Widget> pages,
    required String prefix,
    required String subject,
  }) async {
    await WidgetsBinding.instance.endOfFrame;

    final captured = <Uint8List>[];
    for (final page in pages) {
      captured.add(await _capturePage(context, page));
    }

    final pdf = pw.Document();
    for (final bytes in captured) {
      final img = pw.MemoryImage(bytes);
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.SizedBox.expand(child: pw.Image(img, fit: pw.BoxFit.contain)),
      ));
    }

    final pdfBytes = await pdf.save();
    if (pdfBytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final dir    = await _resolveOutputDir();
    final now    = DateTime.now();
    final stamp  = '${now.year}${_p(now.month)}${_p(now.day)}';
    final path   = '${dir.path}${Platform.pathSeparator}${prefix}_$stamp.pdf';
    final file   = File(path);
    await file.writeAsBytes(pdfBytes, flush: true);

    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: File(path).uri.pathSegments.last)],
      subject: subject,
    );
  }

  static Future<Uint8List> _capturePage(BuildContext context, Widget page) async {
    final ctrl = ScreenshotController();
    final td   = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final mq   = MediaQuery.maybeOf(context) ?? const MediaQueryData(size: Size(800, 1200));

    final widget = InheritedTheme.captureAll(context, MediaQuery(
      data: mq,
      child: Directionality(
        textDirection: td,
        child: Material(color: Colors.white, child: ClipRect(child: page)),
      ),
    ));

    return ctrl.captureFromWidget(widget,
        context: context, delay: _captureDelay, pixelRatio: _capturePixelRatio);
  }

  static Future<Directory> _resolveOutputDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final downloads = Directory(Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await downloads.exists()) return downloads;
    return getApplicationDocumentsDirectory();
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
    'F&B' => 'Food & Beverage',
    'I&L' => 'Infrastructure & Logistics',
    'P&S' => 'Projects & Services',
    'A&P'  => 'Administration & Projects',
    _     => code,
  };
}