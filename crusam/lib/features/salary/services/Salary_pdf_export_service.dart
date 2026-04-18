// lib/features/salary/services/Salary_pdf_export_service.dart
//
// CHANGE: _outputDir() now checks ExportPreferencesNotifier.pdfPath first.
// All other logic is unchanged.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../notifier/salary_data_notifier.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _black   = PdfColor.fromInt(0xFF000000);
const _green   = PdfColor.fromInt(0xFF1A6B2F);
const _hdrBg   = PdfColor.fromInt(0xFFE3E8F4);
const _netBg   = PdfColor.fromInt(0xFFD6DCF5);
const _altBg   = PdfColor.fromInt(0xFFF8FAFC);
const _red     = PdfColor.fromInt(0xFFDC2626);
const _slate   = PdfColor.fromInt(0xFF475569);
const _slateL  = PdfColor.fromInt(0xFF94A3B8);

class SalaryPdfExportService {
  SalaryPdfExportService._();

  // ── Asset cache ──────────────────────────────────────────────────────────────
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _signature;
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _loadAssets() async {
    _logo ??= await _tryLoad('assets/images/aarti_logo.png');
    _signature ??= await _tryLoad('assets/images/');
    _regularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    _boldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
  }

  static pw.Document _createDocument() => pw.Document(
    theme: pw.ThemeData.withFont(
      base: _regularFont!,
      bold: _boldFont!,
    ),
  );

  static String _sanitizePdfText(String text) => text.replaceAll('−', '-');

  static pw.TextStyle _style({
    double? fontSize,
    PdfColor? color,
    pw.FontWeight? fontWeight,
    pw.FontStyle? fontStyle,
    double? lineSpacing,
    double? letterSpacing,
    pw.TextDecoration? decoration,
  }) => pw.TextStyle(
    font: _regularFont,
    fontBold: _boldFont,
    fontFallback: [_regularFont!],
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    lineSpacing: lineSpacing,
    letterSpacing: letterSpacing,
    decoration: decoration,
  );

  static Future<pw.MemoryImage?> _tryLoad(String path) async {
    try {
      final d = await rootBundle.load(path);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC: Salary Slips — exactly 1 pw.Page per employee
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> exportSalarySlips({
    required CompanyConfigModel config,
    required List<EmployeeModel> employees,
    required String monthName,
    required int year,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) async {
    await _loadAssets();
    final n   = SalaryDataNotifier.instance;
    final doc = _createDocument();

    for (final emp in employees) {
      final calc = _calc(
        emp: emp, n: n, daysInMonth: daysInMonth, isMsw: isMsw, isFeb: isFeb,
      );

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => _slipPage(
          config:      config,
          emp:         emp,
          calc:        calc,
          monthName:   monthName,
          year:        year,
          daysInMonth: daysInMonth,
        ),
      ));
    }

    await _saveAndShare(doc, 'salary_slips_${monthName.toLowerCase()}_$year', 'Salary Slips');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC: Attachment A — Invoice for Manpower Supply
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> exportAttachmentA({
    required CompanyConfigModel config,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required double itemAmount,
    required double pfAmount,
    required double esicAmount,
    required double totalAfterTax,
    String? customerName,
    String? customerAddress,
    String? customerGst,
  }) async {
    await _loadAssets();
    final doc = _createDocument();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => _attachmentAPage(
        config:          config,
        billNo:          billNo,
        date:            date,
        poNo:            poNo,
        itemDescription: itemDescription,
        itemAmount:      itemAmount,
        pfAmount:        pfAmount,
        esicAmount:      esicAmount,
        totalAfterTax:   totalAfterTax,
        customerName:    customerName ?? config.companyName,
        customerAddress: customerAddress ?? config.address,
        customerGst:     customerGst ?? config.gstin,
      ),
    ));

    await _saveAndShare(doc, 'attachment_a_${_slugify(billNo)}', 'Attachment A');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC: Attachment B — always single page
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> exportAttachmentB({
    required CompanyConfigModel config,
    required int employeeCount,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    String customerName    = 'M/s Diversey India Hygiene Private Ltd.',
    String customerAddress = '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093',
    String customerGst     = '27AABCC1597Q1Z2',
  }) async {
    await _loadAssets();
    final doc = _createDocument();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => _attachmentBPage(
        config:          config,
        employeeCount:   employeeCount,
        billNo:          billNo,
        date:            date,
        poNo:            poNo,
        itemDescription: itemDescription,
        customerName:    customerName,
        customerAddress: customerAddress,
        customerGst:     customerGst,
      ),
    ));

    await _saveAndShare(doc, 'attachment_b_${_slugify(billNo)}', 'Attachment B');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC: Salary Invoice
  // ════════════════════════════════════════════════════════════════════════════
  static Future<void> exportSalaryInvoice({
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
    await _loadAssets();

    final cgst      = invoiceBaseAmount * 0.09;
    final sgst      = invoiceBaseAmount * 0.09;
    final totalTax  = cgst + sgst;
    final rawTotal  = invoiceBaseAmount + totalTax;
    final finalTotal = rawTotal.roundToDouble();
    final roundOff  = finalTotal - rawTotal;

    final doc = _createDocument();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => _salaryInvoicePage(
        config:          config,
        billNo:          billNo,
        date:            date,
        poNo:            poNo,
        itemDescription: itemDescription,
        customerName:    customerName,
        customerAddress: customerAddress,
        customerGst:     customerGst,
        baseAmount:      invoiceBaseAmount,
        cgst:            cgst,
        sgst:            sgst,
        totalTax:        totalTax,
        finalTotal:      finalTotal,
        roundOff:        roundOff,
      ),
    ));

    await _saveAndShare(doc, 'salary_invoice_${_slugify(billNo)}', 'Salary Invoice');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static _SlipCalc _calc({
    required EmployeeModel emp,
    required SalaryDataNotifier n,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
  }) {
    final days  = n.getDays(emp.id ?? 0);
    final eB    = daysInMonth == 0 ? 0.0 : emp.basicCharges * days / daysInMonth;
    final eO    = daysInMonth == 0 ? 0.0 : emp.otherCharges * days / daysInMonth;
    final eG    = eB + eO;
    final pf    = (eB * 0.12).round().toDouble();
    final esic  = emp.grossSalary >= 21000 ? (eG * 0.0075).ceil().toDouble() : 0.0;
    final msw   = isMsw ? 6.0 : 0.0;
    final female = emp.gender.toUpperCase() == 'F';
    double pt;
    if (female) {
      pt = eG < 25000 ? 0 : (isFeb ? 300 : 200);
    } else {
      if (eG < 7500)       pt = 0;
      else if (eG < 10000) pt = 175;
      else                  pt = isFeb ? 300 : 200;
    }
    return _SlipCalc(days: days, eBasic: eB, eOther: eO, pf: pf, esic: esic, msw: msw, pt: pt);
  }

  // ── Page builders ─────────────────────────────────────────────────────────

  static pw.Widget _slipPage({
    required CompanyConfigModel config,
    required EmployeeModel emp,
    required _SlipCalc calc,
    required String monthName,
    required int year,
    required int daysInMonth,
  }) {
    const borderSide = pw.BorderSide(color: _black, width: 0.75);
    final bAll   = pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75));

    final earnings = <(String, String)>[
      ('Basic Salary (Full)',      _fmt(emp.basicCharges)),
      ('Other Allowances (Full)',  _fmt(emp.otherCharges)),
      ('Earned Basic',             _fmt(calc.eBasic)),
      ('Earned Allowances',        _fmt(calc.eOther)),
    ];
    final deductions = <(String, String)>[
      ('Provident Fund (12%)', _fmt(calc.pf)),
      ('ESIC (0.75%)',         _fmt(calc.esic)),
      ('MSW',                  _fmt(calc.msw)),
      ('Professional Tax',     _fmt(calc.pt)),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (_logo != null)
            pw.SizedBox(width: 100, height: 65, child: pw.Image(_logo!))
          else
            pw.SizedBox(width: 100, height: 65),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(_sanitizePdfText(config.companyName.toUpperCase()),
                  textAlign: pw.TextAlign.right,
                  style: _style(fontSize: 16, fontWeight: pw.FontWeight.bold,
                      color: _green, letterSpacing: 0.6)),
              pw.SizedBox(height: 4),
              pw.Text(_sanitizePdfText(config.address),
                  textAlign: pw.TextAlign.right, style: _style(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text('Tel.  Office  :  ${config.phone}',
                  textAlign: pw.TextAlign.right,
                  style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          )),
        ]),
        pw.Divider(color: _black, thickness: 1),
        pw.SizedBox(height: 8),
        // Title
        pw.Center(child: pw.Text('SALARY SLIP',
            style: _style(fontSize: 13, fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline, letterSpacing: 1.4))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('For the Month of $monthName $year',
            style: _style(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green))),
        pw.SizedBox(height: 10),
        // Employee details
        pw.Container(
          decoration: bAll,
          child: pw.Column(children: [
            pw.Container(
              color: _hdrBg,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              width: double.infinity,
              child: pw.Text('Employee Details',
                  style: _style(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ),
            pw.Table(
              border: const pw.TableBorder(
                top: borderSide,
                verticalInside: borderSide,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _detailRow('Employee Name',  _sanitizePdfText(emp.name)),
                          _detailRow('Dept / Code',    '${_codeToDept(emp.code)} (${emp.code})'),
                          _detailRow('Designation',    'Technician'),
                          _detailRow('PF No.',         emp.pfNo.isEmpty     ? '-' : emp.pfNo),
                          _detailRow('UAN No.',        emp.uanNo.isEmpty    ? '-' : emp.uanNo),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _detailRow('Bank Name',    _sanitizePdfText(emp.bankDetails.isEmpty  ? '-' : emp.bankDetails)),
                          _detailRow('Account No.', emp.accountNumber.isEmpty ? '-' : emp.accountNumber),
                          _detailRow('IFSC Code',   emp.ifscCode.isEmpty      ? '-' : emp.ifscCode),
                          _detailRow('Days in Month', daysInMonth.toString()),
                          _detailRow('Days Present',  calc.days.toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ),
        pw.SizedBox(height: 10),
        // Earnings & Deductions
        pw.Table(
          border: const pw.TableBorder(
            top: borderSide,
            bottom: borderSide,
            left: borderSide,
            right: borderSide,
            horizontalInside: borderSide,
            verticalInside: borderSide,
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(60),
            1: pw.FlexColumnWidth(20),
            2: pw.FlexColumnWidth(60),
            3: pw.FlexColumnWidth(20),
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _hdrBg),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('EARNINGS',
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('AMOUNT (₹)',
                      textAlign: pw.TextAlign.center,
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('DEDUCTIONS',
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('AMOUNT (₹)',
                      textAlign: pw.TextAlign.center,
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                ),
              ],
            ),
            ...List.generate(4, (i) {
              final bg = i.isOdd ? _altBg : PdfColors.white;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(earnings[i].$1, style: _style(fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(earnings[i].$2,
                        textAlign: pw.TextAlign.right,
                        style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(deductions[i].$1, style: _style(fontSize: 9)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(deductions[i].$2,
                        textAlign: pw.TextAlign.right,
                        style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _red)),
                  ),
                ],
              );
            }),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _hdrBg),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('Gross Salary (Earned)',
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(_fmt(calc.eGross),
                      textAlign: pw.TextAlign.right,
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _green)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text('Total Deductions',
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(_fmt(calc.totalDeductions),
                      textAlign: pw.TextAlign.right,
                      style: _style(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _red)),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        // Net pay
        pw.Container(
          decoration: pw.BoxDecoration(
              color: _netBg, border: pw.Border.all(color: _black, width: 0.75)),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('NET SALARY PAYABLE',
                    style: _style(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Gross Earned (${_fmt(calc.eGross)}) - Deductions (${_fmt(calc.totalDeductions)})',
                  style: _style(fontSize: 7.5, color: _slate),
                ),
              ]),
              pw.Text('₹ ${_fmt(calc.netPay)}',
                  style: _style(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _green)),
            ],
          ),
        ),
        pw.Spacer(),
        // Footer
        pw.Divider(color: _black, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (_signature != null)
              pw.Image(_signature!, height: 50)
            else
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Text('For AARTI ENTERPRISES',
                    style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('Authorised Signatory', style: _style(fontSize: 8)),
              ]),
          ],
        ),
      ],
    );
  }

  static pw.Widget _attachmentAPage({
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
  }) {
    throw UnimplementedError('Replace with original _attachmentAPage implementation');
  }

  static pw.Widget _attachmentBPage({
    required CompanyConfigModel config,
    required int employeeCount,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required String customerName,
    required String customerAddress,
    required String customerGst,
  }) {
    throw UnimplementedError('Replace with original _attachmentBPage implementation');
  }

  static pw.Widget _salaryInvoicePage({
    required CompanyConfigModel config,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required String customerName,
    required String customerAddress,
    required String customerGst,
    required double baseAmount,
    required double cgst,
    required double sgst,
    required double totalTax,
    required double finalTotal,
    required double roundOff,
  }) {
    throw UnimplementedError('Replace with original _salaryInvoicePage implementation');
  }

  static pw.Widget _detailRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 90,
          child: pw.Text(label, style: _style(color: _slate, fontSize: 9))),
      pw.Text(':  ', style: _style(fontSize: 9)),
      pw.Expanded(child: pw.Text(value,
          style: _style(fontWeight: pw.FontWeight.bold, fontSize: 9))),
    ]),
  );

  static pw.Widget _hcell(String t, int flex, pw.BorderSide rightBorder) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(right: rightBorder)),
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: pw.Text(t, textAlign: pw.TextAlign.center,
              style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8, color: _black)),
        ),
      );

  static pw.Widget _dcell(String t, int flex, pw.BorderSide rightBorder, {pw.TextStyle? style}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(right: rightBorder)),
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: pw.Text(t, style: style ?? _style(fontSize: 9, color: _black)),
        ),
      );

  static pw.Widget _kvRight(String k, String v, pw.TextStyle style) =>
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text(k, style: style.copyWith(fontSize: 10)),
        pw.Text(v, style: style.copyWith(fontSize: 10)),
      ]);

  static pw.Widget _bankRow(String label, String value, pw.TextStyle style) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: style)),
          pw.Text(':   $value', style: style),
        ]),
      );

  static pw.Widget _invoiceTotalRow(
    String label,
    String value,
    pw.TextStyle style, {
    bool bold = false,
    PdfColor? bgColor,
    bool isLast = false,
  }) =>
      pw.Container(
        decoration: pw.BoxDecoration(
          color: bgColor,
          border: isLast ? null : const pw.Border(bottom: pw.BorderSide(color: _black, width: 0.75)),
        ),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                label,
                textAlign: pw.TextAlign.right,
                style: style.copyWith(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null),
              ),
            ),
          ),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                value,
                style: style.copyWith(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null),
              ),
            ),
          ),
        ]),
      );

  static String _fmt(double v) => v.toStringAsFixed(2);

  static String _slugify(String s) => s.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
    'F&B' => 'Food & Beverage',
    'I&L' => 'Infrastructure & Logistics',
    'P&S' => 'Projects & Services',
    'A&P' => 'Administration & Projects',
    _     => code,
  };

  // ── UPDATED: respects user-chosen PDF path ─────────────────────────────────
  static Future<Directory> _outputDir() async {
    // 1. User-chosen path (set via Profile → Export Paths).
    final savedPath = ExportPreferencesNotifier.instance.pdfPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir;
      // Path was saved but no longer exists — fall through to default.
    }

    // 2. Platform default: Downloads on desktop, app documents on mobile.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  static Future<void> _saveAndShare(
      pw.Document doc, String slug, String subject) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final dir  = await _outputDir();
    final path = '${dir.path}${Platform.pathSeparator}$slug.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: '$slug.pdf')],
      subject: subject,
    );
  }
}

// ── Calculation value object ───────────────────────────────────────────────────
class _SlipCalc {
  final int    days;
  final double eBasic, eOther, pf, esic, msw, pt;

  _SlipCalc({
    required this.days,
    required this.eBasic,
    required this.eOther,
    required this.pf,
    required this.esic,
    required this.msw,
    required this.pt,
  });

  double get eGross          => eBasic + eOther;
  double get totalDeductions => pf + esic + msw + pt;
  double get netPay          => eGross - totalDeductions;
}
