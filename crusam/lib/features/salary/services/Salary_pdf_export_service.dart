// lib/features/salary/services/Salary_pdf_export_service.dart
//
// • 2 salary slips per A4 page (zero outer margin)
// • Header: aarti_logo.png (left) + letterhead.png (right)
// • Signature always visible: image + "For AARTI ENTERPRISES / Authorised Signatory" below
// • All sizes/fonts/padding are ~20% smaller than the SalarySlipPreview widget values

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../notifier/salary_data_notifier.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _black = PdfColor.fromInt(0xFF000000);
const _green = PdfColor.fromInt(0xFF1A6B2F);
const _hdrBg = PdfColor.fromInt(0xFFE3E8F4);
const _netBg = PdfColor.fromInt(0xFFD6DCF5);
const _altBg = PdfColor.fromInt(0xFFF8FAFC);
const _red   = PdfColor.fromInt(0xFFDC2626);
const _slate = PdfColor.fromInt(0xFF475569);

// ── 20% reduction reference table ─────────────────────────────────────────────
//  Logo          120×72  → 96×58
//  Logo gap      20      → 16
//  Inner pad     h:24 v:10 → h:19 v:8
//  Title font    11      → 9.0
//  Sub-label     9       → 7.0
//  Spacing 8     → 6
//  Spacing 4     → 3
//  Spacing 2     → 2
//  Emp hdr pad   h:8 v:4  → h:6 v:2
//  Emp hdr font  9       → 7.0
//  Emp inner pad all(6)  → all(4)
//  Detail label  95      → 76
//  Detail font   9       → 7.0
//  Col hdr pad   h:8 v:4  → h:6 v:2
//  Col hdr font  8.0     → 6.5
//  Row pad       h:8 v:3  → h:6 v:2
//  Row font      9       → 7.0
//  Subtotal pad  h:8 v:4  → h:6 v:2
//  Net pad       h:10 v:6 → h:8 v:4
//  Net label     10      → 8.0
//  Net formula   7.5     → 6.0
//  Net amount    14      → 11.0
//  Sig height    48      → 40
//  Sig text      8.5/7.5 → 6.5/6.0

class SalaryPdfExportService {
  SalaryPdfExportService._();

  // ── Asset cache ───────────────────────────────────────────────────────────
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _letterhead;
  static pw.MemoryImage? _signature;
  static pw.Font?        _regularFont;
  static pw.Font?        _boldFont;

  static Future<void> _loadAssets() async {
    _logo        ??= await _tryLoad('assets/images/aarti_logo.png');
    _letterhead  ??= await _tryLoad('assets/images/letterhead.png');
    _signature   ??= await _tryLoad('assets/images/aarti_signature.png');
    _regularFont ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _boldFont    ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  }

  static pw.Document _createDocument() => pw.Document(
        theme: pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont!),
      );

  static String _sanitize(String t) => t.replaceAll('−', '-');

  static pw.TextStyle _style({
    double?            fontSize,
    PdfColor?          color,
    pw.FontWeight?     fontWeight,
    double?            letterSpacing,
    pw.TextDecoration? decoration,
  }) =>
      pw.TextStyle(
        font:          _regularFont,
        fontBold:      _boldFont,
        fontFallback:  [_regularFont!],
        fontSize:      fontSize,
        color:         color,
        fontWeight:    fontWeight,
        letterSpacing: letterSpacing,
        decoration:    decoration,
      );

  static Future<pw.MemoryImage?> _tryLoad(String path) async {
    try {
      final d = await rootBundle.load(path);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC: Salary Slips — 2 per A4 page
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> exportSalarySlips({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required int                 daysInMonth,
    required bool                isMsw,
    required bool                isFeb,
  }) async {
    await _loadAssets();
    final n   = SalaryDataNotifier.instance;
    final doc = _createDocument();

    for (int i = 0; i < employees.length; i += 2) {
      final emp1  = employees[i];
      final emp2  = (i + 1 < employees.length) ? employees[i + 1] : null;
      final calc1 = _calc(emp: emp1, n: n, daysInMonth: daysInMonth, isMsw: isMsw, isFeb: isFeb);
      final calc2 = emp2 != null
          ? _calc(emp: emp2, n: n, daysInMonth: daysInMonth, isMsw: isMsw, isFeb: isFeb)
          : null;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin:     pw.EdgeInsets.zero,
        build: (ctx) => pw.Column(children: [
          pw.Expanded(
            child: _singleSlip(
              config: config, emp: emp1, calc: calc1,
              monthName: monthName, year: year, daysInMonth: daysInMonth,
            ),
          ),
          if (calc2 != null)
            pw.Expanded(
              child: _singleSlip(
                config: config, emp: emp2!, calc: calc2,
                monthName: monthName, year: year, daysInMonth: daysInMonth,
              ),
            )
          else
            pw.Spacer(),
        ]),
      ));
    }

    await _saveAndShare(
      doc,
      'salary_slips_${monthName.toLowerCase()}_$year',
      'Salary Slips',
      ExportPathTarget.salarySlipsPdf,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC: Attachment A
  // ══════════════════════════════════════════════════════════════════════════
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
      margin:     const pw.EdgeInsets.all(24),
      build: (ctx) => _attachmentAPage(
        config: config, billNo: billNo, date: date, poNo: poNo,
        itemDescription: itemDescription, itemAmount: itemAmount,
        pfAmount: pfAmount, esicAmount: esicAmount, totalAfterTax: totalAfterTax,
        customerName:    customerName    ?? config.companyName,
        customerAddress: customerAddress ?? config.address,
        customerGst:     customerGst     ?? config.gstin,
      ),
    ));
    await _saveAndShare(
      doc,
      'attachment_a_${_slugify(billNo)}',
      'Attachment A',
      ExportPathTarget.attachmentAPdf,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC: Attachment B
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> exportAttachmentB({
    required CompanyConfigModel config,
    required int    employeeCount,
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
      margin:     const pw.EdgeInsets.all(24),
      build: (ctx) => _attachmentBPage(
        config: config, employeeCount: employeeCount,
        billNo: billNo, date: date, poNo: poNo,
        itemDescription: itemDescription,
        customerName: customerName, customerAddress: customerAddress,
        customerGst: customerGst,
      ),
    ));
    await _saveAndShare(
      doc,
      'attachment_b_${_slugify(billNo)}',
      'Attachment B',
      ExportPathTarget.attachmentBPdf,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC: Salary Invoice
  // ══════════════════════════════════════════════════════════════════════════
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
    final cgst       = invoiceBaseAmount * 0.09;
    final sgst       = invoiceBaseAmount * 0.09;
    final totalTax   = cgst + sgst;
    final rawTotal   = invoiceBaseAmount + totalTax;
    final finalTotal = rawTotal.roundToDouble();
    final roundOff   = finalTotal - rawTotal;

    final doc = _createDocument();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin:     const pw.EdgeInsets.all(24),
      build: (ctx) => _salaryInvoicePage(
        config: config, billNo: billNo, date: date, poNo: poNo,
        itemDescription: itemDescription,
        customerName: customerName, customerAddress: customerAddress,
        customerGst: customerGst,
        baseAmount: invoiceBaseAmount, cgst: cgst, sgst: sgst,
        totalTax: totalTax, finalTotal: finalTotal, roundOff: roundOff,
      ),
    ));
    await _saveAndShare(
      doc,
      'salary_invoice_${_slugify(billNo)}',
      'Salary Invoice',
      ExportPathTarget.salaryInvoicePdf,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SINGLE SLIP  (half A4 height, all values ×0.80 vs widget)
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _singleSlip({
    required CompanyConfigModel config,
    required EmployeeModel      emp,
    required _SlipCalc          calc,
    required String             monthName,
    required int                year,
    required int                daysInMonth,
  }) {
    const bs   = pw.BorderSide(color: _black, width: 0.75);
    final bAll = pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75));

    final earnings = <(String, String)>[
      ('Basic Salary (Full)',     _fmt(emp.basicCharges)),
      ('Other Allowances (Full)', _fmt(emp.otherCharges)),
      ('Earned Basic',            _fmt(calc.eBasic)),
      ('Earned Allowances',       _fmt(calc.eOther)),
    ];
    final deductions = <(String, String)>[
      ('Provident Fund (12%)', _fmt(calc.pf)),
      ('ESIC (0.75%)',         _fmt(calc.esic)),
      ('MSW',                  _fmt(calc.msw)),
      ('Professional Tax',     _fmt(calc.pt)),
    ];

    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: double.infinity),
      padding: const pw.EdgeInsets.symmetric(horizontal: 19, vertical: 8),
      color: PdfColors.white,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [

          // ── Header ────────────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (_logo != null)
                pw.SizedBox(
                  width: 96, height: 58,
                  child: pw.Image(_logo!, fit: pw.BoxFit.contain),
                )
              else
                _fallbackLogo(),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Container(
                  height: 58,
                  alignment: pw.Alignment.centerRight,
                  child: _letterhead != null
                      ? pw.Image(_letterhead!,
                          fit:       pw.BoxFit.contain,
                          alignment: pw.Alignment.centerRight)
                      : pw.SizedBox(),
                ),
              ),
            ],
          ),

          pw.Divider(color: _black, thickness: 1),
          pw.SizedBox(height: 3),

          // ── Title ─────────────────────────────────────────────────────────
          pw.Center(
            child: pw.Text(
              'SALARY SLIP',
              style: _style(
                fontSize:      9.0,
                fontWeight:    pw.FontWeight.bold,
                decoration:    pw.TextDecoration.underline,
                letterSpacing: 1.0,
              ),
            ),
          ),
          pw.SizedBox(height: 2),

          pw.Center(
            child: pw.Text(
              'For the Month of $monthName $year',
              style: _style(
                fontSize:   7.0,
                fontWeight: pw.FontWeight.bold,
                color:      _green,
              ),
            ),
          ),
          pw.SizedBox(height: 6),

          // ── Employee Details ───────────────────────────────────────────────
          pw.Container(
            decoration: bAll,
            child: pw.Column(children: [
              pw.Container(
                color:   _hdrBg,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                width:   double.infinity,
                child:   pw.Text(
                  'Employee Details',
                  style: _style(fontWeight: pw.FontWeight.bold, fontSize: 7.0),
                ),
              ),
              pw.Table(
                border: const pw.TableBorder(
                  top:            bs,
                  verticalInside: bs,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(),
                  1: pw.FlexColumnWidth(),
                },
                children: [
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _detailRow('Employee Name', _sanitize(emp.name)),
                          _detailRow('Dept / Code',   '${_codeToDept(emp.code)} (${emp.code})'),
                          _detailRow('Designation',   'Technician'),
                          _detailRow('PF No.',        emp.pfNo.isEmpty  ? '-' : emp.pfNo),
                          _detailRow('UAN No.',       emp.uanNo.isEmpty ? '-' : emp.uanNo),
                        ],
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _detailRow('Bank Name',     _sanitize(emp.bankDetails.isEmpty   ? '-' : emp.bankDetails)),
                          _detailRow('Account No.',   emp.accountNumber.isEmpty ? '-' : emp.accountNumber),
                          _detailRow('IFSC Code',     emp.ifscCode.isEmpty      ? '-' : emp.ifscCode),
                          _detailRow('Days in Month', daysInMonth.toString()),
                          _detailRow('Days Present',  calc.days.toString()),
                        ],
                      ),
                    ),
                  ]),
                ],
              ),
            ]),
          ),
          pw.SizedBox(height: 6),

          // ── Earnings & Deductions ──────────────────────────────────────────
          pw.Table(
            border: const pw.TableBorder(
              top: bs, bottom: bs, left: bs, right: bs,
              horizontalInside: bs, verticalInside: bs,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(60),
              1: pw.FlexColumnWidth(20),
              2: pw.FlexColumnWidth(60),
              3: pw.FlexColumnWidth(20),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [

              // Column headers
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _hdrBg),
                children: [
                  _colHdr('EARNINGS',   center: false),
                  _colHdr('AMOUNT (₹)', center: true),
                  _colHdr('DEDUCTIONS', center: false),
                  _colHdr('AMOUNT (₹)', center: true),
                ],
              ),

              // Data rows
              ...List.generate(4, (i) {
                final bg = i.isOdd ? _altBg : PdfColors.white;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    _dataCell(earnings[i].$1),
                    _dataCellR(earnings[i].$2),
                    _dataCell(deductions[i].$1),
                    _dataCellR(deductions[i].$2, color: _red),
                  ],
                );
              }),

              // Sub-totals
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _hdrBg),
                children: [
                  _subTotalCell('Gross Salary (Earned)'),
                  _subTotalCellR(_fmt(calc.eGross),          color: _green),
                  _subTotalCell('Total Deductions'),
                  _subTotalCellR(_fmt(calc.totalDeductions), color: _red),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 6),

          // ── Net Pay Block ──────────────────────────────────────────────────
          pw.Container(
            decoration: pw.BoxDecoration(
                color: _netBg, border: pw.Border.all(color: _black, width: 0.75)),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NET SALARY PAYABLE',
                      style: _style(
                        fontSize:      8.0,
                        fontWeight:    pw.FontWeight.bold,
                        letterSpacing: 0.7,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Gross Earned (${_fmt(calc.eGross)}) - Deductions (${_fmt(calc.totalDeductions)})',
                      style: _style(fontSize: 6.0, color: _slate),
                    ),
                  ],
                ),
                pw.Text(
                  '₹ ${_fmt(calc.netPay)}',
                  style: _style(
                    fontSize:   11,
                    fontWeight: pw.FontWeight.bold,
                    color:      _green,
                  ),
                ),
              ],
            ),
          ),

          pw.Divider(color: _black, thickness: 0.5),

          // ═══════════════════════════════════════════════════════════════
          // SIGNATURE – guaranteed visibility (no Spacer, anchored bottom)
          // ═══════════════════════════════════════════════════════════════
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 100,
                      height: 40,
                      child: _signature != null
                          ? pw.Image(
                              _signature!,
                              fit: pw.BoxFit.contain,
                              alignment: pw.Alignment.bottomCenter,
                            )
                          : pw.Text(
                              '(Signature)',
                              style: _style(fontSize: 6.5, color: _slate),
                              textAlign: pw.TextAlign.center,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          pw.Divider(color: _black, thickness: 3),
        ],
      ),
    );
  }

  // ── Attachment / Invoice stubs ────────────────────────────────────────────

  static pw.Widget _attachmentAPage({
    required CompanyConfigModel config,
    required String billNo, required String date, required String poNo,
    required String itemDescription,
    required double itemAmount, required double pfAmount,
    required double esicAmount, required double totalAfterTax,
    required String customerName, required String customerAddress,
    required String customerGst,
  }) {
    // Replace with your original _attachmentAPage implementation
    throw UnimplementedError('Replace with original _attachmentAPage implementation');
  }

  static pw.Widget _attachmentBPage({
    required CompanyConfigModel config, required int employeeCount,
    required String billNo, required String date, required String poNo,
    required String itemDescription,
    required String customerName, required String customerAddress,
    required String customerGst,
  }) {
    // Replace with your original _attachmentBPage implementation
    throw UnimplementedError('Replace with original _attachmentBPage implementation');
  }

  static pw.Widget _salaryInvoicePage({
    required CompanyConfigModel config,
    required String billNo, required String date, required String poNo,
    required String itemDescription,
    required String customerName, required String customerAddress,
    required String customerGst,
    required double baseAmount, required double cgst, required double sgst,
    required double totalTax, required double finalTotal, required double roundOff,
  }) {
    // Replace with your original _salaryInvoicePage implementation
    throw UnimplementedError('Replace with original _salaryInvoicePage implementation');
  }

  // ── Shared cell builders ──────────────────────────────────────────────────

  static pw.Widget _fallbackLogo() => pw.Container(
        width: 80, height: 58,
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFF1A237E),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(40)),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFF1A237E), width: 3),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'Aarti\nEnterprises',
          textAlign: pw.TextAlign.center,
          style: _style(fontSize: 7.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _colHdr(String text, {required bool center}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(
          text,
          textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
          style: _style(fontWeight: pw.FontWeight.bold, fontSize: 6.5),
        ),
      );

  static pw.Widget _dataCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(text, style: _style(fontSize: 7.0)),
      );

  static pw.Widget _dataCellR(String text, {PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(text,
            textAlign: pw.TextAlign.right,
            style: _style(
                fontSize:   7.0,
                fontWeight: pw.FontWeight.bold,
                color:      color)),
      );

  static pw.Widget _subTotalCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(text,
            style: _style(fontWeight: pw.FontWeight.bold, fontSize: 7.0)),
      );

  static pw.Widget _subTotalCellR(String text, {required PdfColor color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(text,
            textAlign: pw.TextAlign.right,
            style: _style(
                fontWeight: pw.FontWeight.bold,
                fontSize:   7.0,
                color:      color)),
      );

  static pw.Widget _detailRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 76,
              child: pw.Text(label, style: _style(color: _slate, fontSize: 7.0)),
            ),
            pw.Text(':  ', style: _style(fontSize: 7.0)),
            pw.Expanded(
              child: pw.Text(value,
                  style: _style(fontWeight: pw.FontWeight.bold, fontSize: 7.0)),
            ),
          ],
        ),
      );

  // Kept for attachment/invoice builders
  static pw.Widget _hcell(String t, int flex, pw.BorderSide rb) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(right: rb)),
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: pw.Text(t,
              textAlign: pw.TextAlign.center,
              style: _style(fontWeight: pw.FontWeight.bold, fontSize: 8, color: _black)),
        ),
      );

  static pw.Widget _dcell(String t, int flex, pw.BorderSide rb,
          {pw.TextStyle? style}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border(right: rb)),
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: pw.Text(t, style: style ?? _style(fontSize: 9, color: _black)),
        ),
      );

  static pw.Widget _kvRight(String k, String v, pw.TextStyle s) =>
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text(k, style: s.copyWith(fontSize: 12)),
        pw.Text(v, style: s.copyWith(fontSize: 12)),
      ]);

  static pw.Widget _bankRow(String label, String value, pw.TextStyle s) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: s.copyWith(fontSize: 13))),
          pw.Text(':   $value', style: s.copyWith(fontSize: 13)),
        ]),
      );

  static pw.Widget _invoiceTotalRow(
    String label, String value, pw.TextStyle style, {
    bool bold = false, PdfColor? bgColor, bool isLast = false,
  }) =>
      pw.Container(
        decoration: pw.BoxDecoration(
          color:  bgColor,
          border: isLast
              ? null
              : const pw.Border(bottom: pw.BorderSide(color: _black, width: 0.75)),
        ),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              padding:   const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(label,
                  textAlign: pw.TextAlign.right,
                  style: style.copyWith(
                      fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null)),
            ),
          ),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(
            child: pw.Container(
              padding:   const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(value,
                  style: style.copyWith(
                      fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null)),
            ),
          ),
        ]),
      );

  // ── Calculation helper ────────────────────────────────────────────────────

  static _SlipCalc _calc({
    required EmployeeModel      emp,
    required SalaryDataNotifier n,
    required int                daysInMonth,
    required bool               isMsw,
    required bool               isFeb,
  }) {
    final days   = n.getDays(emp.id ?? 0);
    final eB     = daysInMonth == 0 ? 0.0 : emp.basicCharges * days / daysInMonth;
    final eO     = daysInMonth == 0 ? 0.0 : emp.otherCharges * days / daysInMonth;
    final eG     = eB + eO;
    final pf     = (eB * 0.12).round().toDouble();
    final esic   = emp.grossSalary >= 21000 ? (eG * 0.0075).ceil().toDouble() : 0.0;
    final msw    = isMsw ? 6.0 : 0.0;
    final female = emp.gender.toUpperCase() == 'F';
    double pt;
    if (female) {
      pt = eG < 25000 ? 0 : (isFeb ? 300 : 200);
    } else {
      if (eG < 7500) {
        pt = 0;
      } else if (eG < 10000) pt = 175;
      else                  pt = isFeb ? 300 : 200;
    }
    return _SlipCalc(
        days: days, eBasic: eB, eOther: eO, pf: pf, esic: esic, msw: msw, pt: pt);
  }

  // ── String utilities ──────────────────────────────────────────────────────

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

  // ── Respects user-chosen PDF path ─────────────────────────────────────────
  static Future<Directory> _outputDir([ExportPathTarget? target]) async {
    final savedPath = target != null
        ? ExportPreferencesNotifier.instance.resolvedPathForTarget(target)
        : ExportPreferencesNotifier.instance.pdfPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  // ── Save + Share (with unique file name to avoid overwrites) ───────────────
  static Future<String> _uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;
    final dot  = basePath.lastIndexOf('.');
    final base = dot == -1 ? basePath : basePath.substring(0, dot);
    final ext  = dot == -1 ? '' : basePath.substring(dot);
    var counter = 1;
    while (true) {
      final candidate = '$base($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }

  static Future<void> _saveAndShare(
      pw.Document doc, String slug, String subject, ExportPathTarget target) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final dir      = await _outputDir(target);
    final basePath = '${dir.path}${Platform.pathSeparator}$slug.pdf';
    final path     = await _uniquePath(basePath);
    await File(path).writeAsBytes(bytes, flush: true);
  }
}

// ── Calculation value object ───────────────────────────────────────────────────
class _SlipCalc {
  final int    days;
  final double eBasic, eOther, pf, esic, msw, pt;

  _SlipCalc({
    required this.days,   required this.eBasic, required this.eOther,
    required this.pf,     required this.esic,   required this.msw,
    required this.pt,
  });

  double get eGross          => eBasic + eOther;
  double get totalDeductions => pf + esic + msw + pt;
  double get netPay          => eGross - totalDeductions;
}