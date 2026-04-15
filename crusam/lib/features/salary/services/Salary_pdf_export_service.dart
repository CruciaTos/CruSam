import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
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
    _signature ??= await _tryLoad('assets/images/aarti_signature.png');
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

      // ✅ KEY: one addPage call per employee = guaranteed 1 page
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
    BuildContext? context,
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

    final cgst = invoiceBaseAmount * 0.09;
    final sgst = invoiceBaseAmount * 0.09;
    final totalTax = cgst + sgst;
    final rawTotal = invoiceBaseAmount + totalTax;
    final finalTotal = rawTotal.roundToDouble();
    final roundOff = finalTotal - rawTotal;

    const bSide = pw.BorderSide(color: _black, width: 0.75);
    final doc = _createDocument();
    final body = _style(fontSize: 9, color: _black, lineSpacing: 1.2);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(config),
            pw.SizedBox(height: 6),
            pw.Divider(color: _black, thickness: 0.75),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Text(
                'Salary Invoice',
                style: _style(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                  letterSpacing: 1.2,
                  color: _black,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(
                  flex: 70,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('BILL To,', style: body),
                      pw.SizedBox(height: 4),
                      pw.Text(_sanitizePdfText(customerName),
                          style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                      pw.SizedBox(height: 2),
                      pw.Text(_sanitizePdfText(customerAddress), style: body),
                      pw.SizedBox(height: 10),
                      pw.Text('GST No. $customerGst',
                          style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                    ]),
                  ),
                ),
                pw.Container(width: 0.75, color: _black),
                pw.Expanded(
                  flex: 30,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        _kvRight('Bill No :- ', billNo, body),
                        pw.SizedBox(height: 4),
                        _kvRight('Date :- ', date, body),
                        pw.SizedBox(height: 4),
                        _kvRight('PO.No. :- ', poNo, body),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
              child: pw.Column(children: [
                pw.Container(
                  color: _hdrBg,
                  child: pw.Row(children: [
                    _hcell('Sr.\nNo', 5, bSide),
                    _hcell('Item Description', 65, bSide),
                    _hcell('QTY', 6, bSide),
                    _hcell('RATE', 9, bSide),
                    _hcell('AMOUNT', 15, const pw.BorderSide(style: pw.BorderStyle.none)),
                  ]),
                ),
                pw.Divider(color: _black, height: 0.75, thickness: 0.75),
                pw.ConstrainedBox(
                  constraints: const pw.BoxConstraints(minHeight: 180),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    _dcell('1', 5, bSide, style: body.copyWith(fontSize: 10)),
                    pw.Expanded(
                      flex: 65,
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(border: pw.Border(right: bSide)),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: pw.Text(
                          _sanitizePdfText(itemDescription),
                          style: body.copyWith(fontSize: 10),
                        ),
                      ),
                    ),
                    _dcell('', 6, bSide, style: body.copyWith(fontSize: 10)),
                    _dcell('', 9, bSide, style: body.copyWith(fontSize: 10)),
                    pw.Expanded(
                      flex: 15,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: pw.Align(
                          alignment: pw.Alignment.topRight,
                          child: pw.Text(invoiceBaseAmount.toStringAsFixed(2),
                              style: body.copyWith(fontSize: 10)),
                        ),
                      ),
                    ),
                  ]),
                ),
                pw.Divider(color: _black, height: 0.75, thickness: 0.75),
                pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Expanded(
                    flex: 70,
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('PAN NO :-  ${config.pan}',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('GSTIN :  ${config.gstin}',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('HSN: SAC99851',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 12),
                        pw.Text('Bank Details for  :  RTGS / NEFT',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 6),
                        _bankRow('Bank Name', config.bankName, body),
                        _bankRow('Branch', config.branch, body),
                        _bankRow('Account No.', config.accountNo, body),
                        _bankRow('IFSC Code', config.ifscCode, body),
                      ]),
                    ),
                  ),
                  pw.Container(width: 0.75, color: _black),
                  pw.Expanded(
                    flex: 30,
                    child: pw.Column(children: [
                      _invoiceTotalRow('Total amount\nbefore Tax', invoiceBaseAmount.toStringAsFixed(2), body),
                      _invoiceTotalRow('Add : CGST 9%', cgst.toStringAsFixed(2), body),
                      _invoiceTotalRow('Add : SGST 9%', sgst.toStringAsFixed(2), body),
                      _invoiceTotalRow('Total Tax\nAmount', totalTax.toStringAsFixed(2), body,
                          bold: true),
                      _invoiceTotalRow(
                        'Round Up',
                        '${roundOff >= 0 ? '+' : ''}${roundOff.toStringAsFixed(2)}',
                        body,
                      ),
                      _invoiceTotalRow(
                        'Total Amount\nafter Tax',
                        '₹ ${finalTotal.toStringAsFixed(0)}',
                        body,
                        bold: true,
                        bgColor: _netBg,
                        isLast: true,
                      ),
                    ]),
                  ),
                ]),
                pw.Divider(color: _black, height: 0.75, thickness: 0.75),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: pw.Text('Certified that particulars given above are true and correct.',
                      style: body.copyWith(fontStyle: pw.FontStyle.italic, fontSize: 8)),
                ),
              ]),
            ),
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('Certified that particulars given above are true and correct.',
                        style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('Subject to Mumbai jurisdiction.', style: body),
                  ]),
                ),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                  pw.Text('For ${config.companyName.toUpperCase()}',
                      style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 45),
                  pw.Text('Partner', style: body.copyWith(fontSize: 8.5)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );

    await _saveAndShare(doc, 'salary_invoice_${_slugify(billNo)}', 'Salary Invoice');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SALARY SLIP PAGE BUILDER
  // ════════════════════════════════════════════════════════════════════════════
  static pw.Widget _slipPage({
    required CompanyConfigModel config,
    required EmployeeModel emp,
    required _SlipCalc calc,
    required String monthName,
    required int year,
    required int daysInMonth,
  }) {
    final dept = _codeToDept(emp.code);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _header(config),
        pw.Divider(color: _black, thickness: 1),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('SALARY SLIP',
            style: _style(fontSize: 14, fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline, letterSpacing: 1.4, color: _black))),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('For the Month of $monthName $year',
            style: _style(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green))),
        pw.SizedBox(height: 10),
        _empDetails(emp, dept, daysInMonth, calc.days),
        pw.SizedBox(height: 10),
        _earningsDeductions(emp, calc),
        pw.SizedBox(height: 10),
        _netPayBlock(calc),
        pw.Spacer(),
        _footer(config),
      ],
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  static pw.Widget _header(CompanyConfigModel config) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (_logo != null)
        pw.SizedBox(width: 110, height: 70, child: pw.Image(_logo!))
      else
        _fallbackLogo(),
      pw.SizedBox(width: 16),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(config.companyName.toUpperCase(),
                textAlign: pw.TextAlign.right,
                style: _style(fontSize: 17, fontWeight: pw.FontWeight.bold,
                    color: _green, letterSpacing: 0.6)),
            pw.SizedBox(height: 4),
            pw.Text(config.address, textAlign: pw.TextAlign.right,
                style: _style(fontSize: 9, color: _black)),
            pw.SizedBox(height: 2),
            pw.Text('Tel. Office : ${config.phone}', textAlign: pw.TextAlign.right,
                style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _black)),
          ],
        ),
      ),
    ],
  );

  static pw.Widget _fallbackLogo() => pw.Container(
    width: 110, height: 70,
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFF1A237E),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    alignment: pw.Alignment.center,
    child: pw.Text('Aarti\nEnterprises', textAlign: pw.TextAlign.center,
        style: _style(fontSize: 10, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
  );

  // ── Employee details block ───────────────────────────────────────────────────
  static pw.Widget _empDetails(
      EmployeeModel emp, String dept, int daysInMonth, int daysPresent) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
      child: pw.Column(children: [
        pw.Container(
          color: _hdrBg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          width: double.infinity,
          child: pw.Text('Employee Details',
              style: _style(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _black)),
        ),
        pw.Divider(color: _black, height: 0.75, thickness: 0.75),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _dr('Employee Name', emp.name),
                _dr('Department / Code', '$dept (${emp.code})'),
                _dr('Designation', 'Technician'),
                _dr('PF No.', emp.pfNo),
                _dr('UAN No.', emp.uanNo),
              ]),
            ),
          ),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _dr('Bank Name', emp.bankDetails),
                _dr('Account No.', emp.accountNumber),
                _dr('IFSC Code', emp.ifscCode),
                _dr('Days in Month', daysInMonth.toString()),
                _dr('Days Present', daysPresent.toString()),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  static pw.Widget _dr(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 100,
          child: pw.Text(label, style: _style(fontSize: 9, color: _slate))),
      pw.Text(':  ', style: _style(fontSize: 9, color: _black)),
      pw.Expanded(child: pw.Text(value,
          style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _black))),
    ]),
  );

  // ── Earnings & Deductions table ──────────────────────────────────────────────
  static pw.Widget _earningsDeductions(EmployeeModel emp, _SlipCalc calc) {
    final earnings = [
      ('Basic Salary (Full)',     _fmt(emp.basicCharges)),
      ('Other Allowances (Full)', _fmt(emp.otherCharges)),
      ('Earned Basic',            _fmt(calc.eBasic)),
      ('Earned Allowances',       _fmt(calc.eOther)),
    ];
    final deductions = [
      ('Provident Fund (12%)', _fmt(calc.pf)),
      ('ESIC (0.75%)',         _fmt(calc.esic)),
      ('MSW',                  _fmt(calc.msw)),
      ('Professional Tax',     _fmt(calc.pt)),
    ];
    final rows = earnings.length;

    final cellStyle = _style(fontSize: 9);
    final boldStyle = _style(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final hdrStyle = _style(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

    // header
    final headerRow = pw.Container(
      color: _hdrBg,
      child: pw.Row(children: [
        pw.Expanded(flex: 60, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('EARNINGS', style: hdrStyle.copyWith(color: _black)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 20, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('AMOUNT (₹)', textAlign: pw.TextAlign.center, style: hdrStyle.copyWith(color: _black)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 60, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('DEDUCTIONS', style: hdrStyle.copyWith(color: _black)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 20, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('AMOUNT (₹)', textAlign: pw.TextAlign.center, style: hdrStyle.copyWith(color: _black)))),
      ]),
    );

    // data rows
    final dataRows = List.generate(rows, (i) {
      final bg = i.isOdd ? _altBg : PdfColors.white;
      return pw.Container(
        color: bg,
        child: pw.Row(children: [
          pw.Expanded(flex: 60, child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text(earnings[i].$1, style: cellStyle.copyWith(color: _black)))),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(flex: 20, child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text(earnings[i].$2, textAlign: pw.TextAlign.right,
                  style: boldStyle.copyWith(color: _black)))),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(flex: 60, child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text(deductions[i].$1, style: cellStyle.copyWith(color: _black)))),
          pw.Container(width: 0.75, color: _black),
          pw.Expanded(flex: 20, child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text(deductions[i].$2, textAlign: pw.TextAlign.right,
                  style: boldStyle.copyWith(color: _red)))),
        ]),
      );
    });

    // subtotals
    final totalRow = pw.Container(
      color: _hdrBg,
      child: pw.Row(children: [
        pw.Expanded(flex: 60, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('Gross Salary (Earned)', style: boldStyle.copyWith(color: _black)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 20, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(_fmt(calc.eGross), textAlign: pw.TextAlign.right,
                style: boldStyle.copyWith(color: _green)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 60, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text('Total Deductions', style: boldStyle.copyWith(color: _black)))),
        pw.Container(width: 0.75, color: _black),
        pw.Expanded(flex: 20, child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(_fmt(calc.totalDeductions), textAlign: pw.TextAlign.right,
                style: boldStyle.copyWith(color: _red)))),
      ]),
    );

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
      child: pw.Column(children: [
        headerRow,
        pw.Divider(color: _black, height: 0.75, thickness: 0.75),
        ...dataRows,
        pw.Divider(color: _black, height: 0.75, thickness: 0.75),
        totalRow,
      ]),
    );
  }

  // ── Net Pay block ─────────────────────────────────────────────────────────────
  static pw.Widget _netPayBlock(_SlipCalc calc) => pw.Container(
    decoration: pw.BoxDecoration(
      color: _netBg,
      border: pw.Border.all(color: _black, width: 0.75),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: pw.Row(children: [
      pw.Expanded(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NET SALARY PAYABLE',
              style: _style(fontSize: 12, fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.8, color: _black)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Gross Earned (${_fmt(calc.eGross)}) - Total Deductions (${_fmt(calc.totalDeductions)})',
            style: _style(fontSize: 8, color: _slate),
          ),
        ],
      )),
      pw.Text('₹ ${_fmt(calc.netPay)}',
          style: _style(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _green)),
    ]),
  );

  // ── Footer ────────────────────────────────────────────────────────────────────
  static pw.Widget _footer(CompanyConfigModel config) => pw.Column(children: [
    pw.Divider(color: _black, thickness: 0.5),
    pw.SizedBox(height: 6),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(child: pw.SizedBox()),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (_signature != null)
              pw.SizedBox(width: 160, height: 50, child: pw.Image(_signature!))
            else
              pw.SizedBox(height: 50),
            pw.Text('For ${config.companyName}',
                style: _style(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _black)),
            pw.SizedBox(height: 4),
            pw.Text('Authorised Signatory',
                style: _style(fontSize: 8.5, color: _black)),
          ],
        ),
      ],
    ),
  ]);

  // ════════════════════════════════════════════════════════════════════════════
  // ATTACHMENT A PAGE BUILDER
  // ════════════════════════════════════════════════════════════════════════════
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
    const bSide = pw.BorderSide(color: _black, width: 0.75);
    final body  = _style(fontSize: 9, color: _black);

    // Calculate round-off amount
    final subTotal = itemAmount + pfAmount + esicAmount;
    final roundOff = totalAfterTax - subTotal;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _header(config),
        pw.SizedBox(height: 6),
        pw.Divider(color: _black, thickness: 0.75),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text('TAX INVOICE',
            style: _style(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
              letterSpacing: 1.4,
              color: _black,
            ),
          ),
        ),
        pw.SizedBox(height: 12),

        // Bill-To block
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 70,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL To,', style: body),
                      pw.SizedBox(height: 4),
                      pw.Text(_sanitizePdfText(customerName),
                          style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                      pw.SizedBox(height: 2),
                      pw.Text(_sanitizePdfText(customerAddress), style: body),
                      pw.SizedBox(height: 10),
                      pw.Text('GST No. $customerGst',
                          style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              pw.Container(width: 0.75, color: _black),
              pw.Expanded(
                flex: 30,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      _kvRight('Bill No :- ', billNo, body),
                      pw.SizedBox(height: 4),
                      _kvRight('Date :- ', date, body),
                      pw.SizedBox(height: 4),
                      _kvRight('PO.No. :- ', poNo, body),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // Main table
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
          child: pw.Column(children: [
            // Header row
            pw.Container(
              color: _hdrBg,
              child: pw.Row(children: [
                _hcell('Sr.\nNo', 5, bSide),
                _hcell('Description', 55, bSide),
                _hcell('HSN/SAC', 12, bSide),
                _hcell('Qty', 6, bSide),
                _hcell('Rate (₹)', 10, bSide),
                _hcell('Amount (₹)', 12, const pw.BorderSide(style: pw.BorderStyle.none)),
              ]),
            ),
            pw.Divider(color: _black, height: 0.75, thickness: 0.75),

            // Data rows
            pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(minHeight: 120),
              child: pw.Column(children: [
                // Row 1: Manpower Supply Charges
                _invoiceRow(
                  sr: '1',
                  desc: _sanitizePdfText(itemDescription),
                  hsn: '998511', // SAC for manpower supply
                  qty: '1',
                  rate: itemAmount.toStringAsFixed(2),
                  amount: itemAmount.toStringAsFixed(2),
                  bSide: bSide,
                ),
                // Row 2: PF Contribution (if >0)
                if (pfAmount > 0)
                  _invoiceRow(
                    sr: '2',
                    desc: 'Add: Provident Fund Contribution (Employer Share)',
                    hsn: '',
                    qty: '',
                    rate: '',
                    amount: pfAmount.toStringAsFixed(2),
                    bSide: bSide,
                  ),
                // Row 3: ESIC Contribution (if >0)
                if (esicAmount > 0)
                  _invoiceRow(
                    sr: pfAmount > 0 ? '3' : '2',
                    desc: 'Add: ESIC Contribution (Employer Share)',
                    hsn: '',
                    qty: '',
                    rate: '',
                    amount: esicAmount.toStringAsFixed(2),
                    bSide: bSide,
                  ),
                // Row 4: Round Off (if non-zero)
                if (roundOff.abs() > 0.001)
                  _invoiceRow(
                    sr: _getNextSr(pfAmount > 0, esicAmount > 0),
                    desc: roundOff > 0 ? 'Add: Round Off' : 'Less: Round Off',
                    hsn: '',
                    qty: '',
                    rate: '',
                    amount: roundOff.toStringAsFixed(2),
                    bSide: bSide,
                    isRoundOff: true,
                  ),
              ]),
            ),
            pw.Divider(color: _black, height: 0.5, thickness: 0.5),

            // PAN / GSTIN / Bank + Total
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 70,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PAN NO :-  ${config.pan}',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text('GSTIN : ${config.gstin}    HSN: SAC998511',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 10),
                        pw.Text('Bank Details for  :  RTGS / NEFT',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 6),
                        _bankRow('Bank Name', config.bankName, body),
                        _bankRow('Branch', config.branch, body),
                        _bankRow('Account No.', config.accountNo, body),
                        _bankRow('IFSC Code', config.ifscCode, body),
                      ],
                    ),
                  ),
                ),
                pw.Container(width: 0.75, color: _black),
                pw.Expanded(
                  flex: 30,
                  child: pw.Column(children: [
                    pw.Spacer(),
                    pw.Container(
                      decoration: const pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFD6DCF5),
                        border: pw.Border(top: bSide),
                      ),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Total Amount:',
                              style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.Text(
                            '₹ ${totalAfterTax.toStringAsFixed(2)}',
                            style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ],
            ),
            pw.Divider(color: _black, height: 0.75, thickness: 0.75),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text('Certified that particulars given above are true and correct.',
                  style: body.copyWith(fontStyle: pw.FontStyle.italic, fontSize: 8)),
            ),
          ]),
        ),

        pw.Spacer(),
        // Footer
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Certified that particulars given above are true and correct.',
                      style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Subject to Mumbai jurisdiction.', style: body),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('For AARTI ENTERPRISES',
                    style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 45),
                pw.Text('Partner', style: body.copyWith(fontSize: 8.5)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Helper for invoice data rows
  static pw.Widget _invoiceRow({
    required String sr,
    required String desc,
    required String hsn,
    required String qty,
    required String rate,
    required String amount,
    required pw.BorderSide bSide,
    bool isRoundOff = false,
  }) {
    final textStyle = _style(
      fontSize: 9,
      color: isRoundOff ? _red : _black,
    );
    return pw.Row(
      children: [
        _dcell(sr, 5, bSide, style: textStyle),
        pw.Expanded(
          flex: 55,
          child: pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border(right: bSide)),
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Text(desc, style: textStyle),
          ),
        ),
        _dcell(hsn, 12, bSide, style: textStyle),
        _dcell(qty, 6, bSide, style: textStyle),
        _dcell(rate, 10, bSide, style: textStyle),
        pw.Expanded(
          flex: 12,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(amount, style: textStyle),
            ),
          ),
        ),
      ],
    );
  }

  static String _getNextSr(bool hasPf, bool hasEsic) {
    int sr = 1;
    if (hasPf) sr++;
    if (hasEsic) sr++;
    return (sr + 1).toString();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ATTACHMENT B PAGE BUILDER
  // ════════════════════════════════════════════════════════════════════════════
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
    const ratePerEmp = 1753.0;
    final totalAmount = employeeCount * ratePerEmp;
    const bSide = pw.BorderSide(color: _black, width: 0.75);
    final body  = _style(fontSize: 9, color: _black);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _header(config),
        pw.SizedBox(height: 6),
        pw.Divider(color: _black, thickness: 0.75),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Text('Attachment B',
            style: _style(fontSize: 13, fontWeight: pw.FontWeight.bold,
                decoration: pw.TextDecoration.underline, letterSpacing: 1.2, color: _black))),
        pw.SizedBox(height: 12),

        // Bill-To block
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(flex: 70, child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('BILL To,', style: body),
                pw.SizedBox(height: 4),
                pw.Text(_sanitizePdfText(customerName),
                    style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                pw.SizedBox(height: 2),
                pw.Text(_sanitizePdfText(customerAddress), style: body),
                pw.SizedBox(height: 10),
                pw.Text('GST No. $customerGst',
                    style: body.copyWith(fontWeight: pw.FontWeight.bold)),
              ]),
            )),
            pw.Container(width: 0.75, color: _black),
            pw.Expanded(flex: 30, child: pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  _kvRight('Bill No :- ', billNo, body),
                  pw.SizedBox(height: 4),
                  _kvRight('Date :- ', date, body),
                  pw.SizedBox(height: 4),
                  _kvRight('PO.No. :- ', poNo, body),
                ],
              ),
            )),
          ]),
        ),
        pw.SizedBox(height: 12),

        // Main table
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.75)),
          child: pw.Column(children: [
            // Header row
            pw.Container(
              color: _hdrBg,
              child: pw.Row(children: [
                _hcell('Sr.\nNo', 5, bSide),
                _hcell('Item Description', 65, bSide),
                _hcell('QTY', 6, bSide),
                _hcell('RATE', 9, bSide),
                _hcell('AMOUNT', 15, const pw.BorderSide(style: pw.BorderStyle.none)),
              ]),
            ),
            pw.Divider(color: _black, height: 0.75, thickness: 0.75),

            // Data row
            pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(minHeight: 160),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _dcell('1', 5, bSide),
                pw.Expanded(flex: 65, child: pw.Container(
                  decoration: const pw.BoxDecoration(border: pw.Border(right: bSide)),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: pw.Text(
                    _sanitizePdfText(itemDescription),
                    style: body.copyWith(fontSize: 10),
                  ),
                )),
                _dcell(employeeCount > 0 ? '$employeeCount' : '-', 6, bSide),
                _dcell(ratePerEmp.toStringAsFixed(2), 9, bSide),
                pw.Expanded(flex: 15, child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: pw.Align(
                    alignment: pw.Alignment.topRight,
                    child: pw.Text(
                      employeeCount > 0 ? totalAmount.toStringAsFixed(2) : '0.00',
                      style: body.copyWith(fontSize: 10),
                    ),
                  ),
                )),
              ]),
            ),
            pw.Divider(color: _black, height: 0.5, thickness: 0.5),

            // PAN / GSTIN / Bank + Total
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(flex: 70, child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('PAN NO :-  ${config.pan}',
                      style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('GSTIN : ${config.gstin}    HSN: SAC99851',
                      style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 10),
                  pw.Text('Bank Details for  :  RTGS / NEFT',
                      style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 6),
                  _bankRow('Bank Name', config.bankName, body),
                  _bankRow('Branch', config.branch, body),
                  _bankRow('Account No.', config.accountNo, body),
                  _bankRow('IFSC Code', config.ifscCode, body),
                ]),
              )),
              pw.Container(width: 0.75, color: _black),
              pw.Expanded(flex: 30, child: pw.Column(children: [
                pw.Spacer(),
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFD6DCF5),
                    border: pw.Border(top: bSide),
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Amount:',
                          style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text(
                        employeeCount > 0 ? '₹ ${totalAmount.toStringAsFixed(0)}' : '₹ 0',
                        style: body.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ])),
            ]),
            pw.Divider(color: _black, height: 0.75, thickness: 0.75),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text('Certified that particulars given above are true and correct.',
                  style: body.copyWith(fontStyle: pw.FontStyle.italic, fontSize: 8)),
            ),
          ]),
        ),

        pw.Spacer(),
        // Footer
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Certified that particulars given above are true and correct.',
                    style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Subject to Mumbai jurisdiction.', style: body),
              ],
            )),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('For AARTI ENTERPRISES',
                    style: body.copyWith(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 45),
                pw.Text('Partner', style: body.copyWith(fontSize: 8.5)),
              ],
            ),
          ],
        ),
      ],
    );
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
      if (eG < 7500)      pt = 0;
      else if (eG < 10000) pt = 175;
      else                  pt = isFeb ? 300 : 200;
    }
    return _SlipCalc(days: days, eBasic: eB, eOther: eO, pf: pf, esic: esic, msw: msw, pt: pt);
  }

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

  static Future<Directory> _outputDir() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
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

  double get eGross         => eBasic + eOther;
  double get totalDeductions => pf + esic + msw + pt;
  double get netPay          => eGross - totalDeductions;
}