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
  // ✅ Matches pdf_export_service.dart exactly
  static const Duration _captureDelay = Duration(milliseconds: 150);
  static const double _capturePixelRatio = 4.0;

  // ── Asset precaching (mirrors pdf_export_service) ─────────────────────────
  static Future<void> _precacheSalaryAssets(BuildContext context) async {
    await Future.wait([
      _safePrecache(context, 'assets/images/aarti_logo.png'),
      _safePrecache(context, 'assets/images/aarti_signature.png'),
    ]);
  }

  static Future<void> _safePrecache(BuildContext context, String assetPath) async {
    try {
      await precacheImage(AssetImage(assetPath), context);
    } catch (_) {
      // Fall back to the preview widget errorBuilder if the asset is unavailable.
    }
  }

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
    await _precacheSalaryAssets(context);

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
    await _exportPages(
      context:    context,
      pages:      pages,
      slug:       slug,
      filePrefix: 'salary_slips',
      subject:    'Salary Slips',
    );
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
    await _precacheSalaryAssets(context);

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

    await _exportPages(
      context:    context,
      pages:      pages,
      slug:       _slugify(billNo),
      filePrefix: 'salary_invoice',
      subject:    'Salary Invoice',
    );
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
    await _precacheSalaryAssets(context);

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

    await _exportPages(
      context:    context,
      pages:      pages,
      slug:       _slugify(billNo),
      filePrefix: 'attachment_a',
      subject:    'Attachment A',
    );
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
    await _precacheSalaryAssets(context);

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

    await _exportPages(
      context:    context,
      pages:      pages,
      slug:       _slugify(billNo),
      filePrefix: 'attachment_b',
      subject:    'Attachment B',
    );
  }

  // ── Core export: capture → PDF → write → share ────────────────────────────
  // ✅ Mirrors _exportPages from pdf_export_service.dart exactly
  static Future<void> _exportPages({
    required BuildContext context,
    required List<Widget> pages,
    required String slug,
    required String filePrefix,
    required String subject,
  }) async {
    await WidgetsBinding.instance.endOfFrame;

    final capturedPages = <Uint8List>[];
    for (final page in pages) {
      capturedPages.add(await _capturePage(context, page));
    }

    final pdf = pw.Document();
    for (final pageBytes in capturedPages) {
      final pdfImage = pw.MemoryImage(pageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.SizedBox.expand(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final fileName = '${filePrefix}_$slug.pdf';
    final dir  = await _resolveOutputDir();
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    // ✅ File-size guard (from pdf_export_service)
    final written = await file.length();
    if (written == 0) throw Exception('File written but is empty: $path');

    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: fileName)],
      subject: subject,
    );
  }

  // ✅ Mirrors _capturePage from pdf_export_service.dart exactly
  static Future<Uint8List> _capturePage(BuildContext context, Widget page) async {
    final controller    = ScreenshotController();
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final mediaQuery    = MediaQuery.maybeOf(context) ??
        const MediaQueryData(size: Size(800, 1200));

    final widget = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: mediaQuery,
        child: Directionality(
          textDirection: textDirection,
          child: Material(
            color: Colors.white,
            child: ClipRect(child: page),
          ),
        ),
      ),
    );

    return controller.captureFromWidget(
      widget,
      context: context,
      delay: _captureDelay,
      pixelRatio: _capturePixelRatio,
    );
  }

  // ✅ Slugify bill number for filename (from pdf_export_service)
  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  // ✅ Mirrors _resolveOutputDir from pdf_export_service.dart exactly
  static Future<Directory> _resolveOutputDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final downloads = Directory(
      Platform.isWindows ? '$home\\Downloads' : '$home/Downloads',
    );
    if (await downloads.exists()) return downloads;
    return getApplicationDocumentsDirectory();
  }

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
    'F&B' => 'Food & Beverage',
    'I&L' => 'Infrastructure & Logistics',
    'P&S' => 'Projects & Services',
    'A&P' => 'Administration & Projects',
    _     => code,
  };
}