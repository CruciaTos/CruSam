// lib/features/pdf/services/widget_pdf_export_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../shared/utils/format_utils.dart';

// ── Column width configuration – matches the preview's VoucherColWidths ──────
class _VoucherColWidths {
  final double amount;    // 55
  final double debitAc;   // 82
  final double ifsc;      // 68
  final double creditAc;  // 86
  final double code;      // 30
  final double name;      // 95
  final double place;     // 65
  final double expenses;  // 82
  final double aarti;     // 46
  final double from;      // 42
  final double to;        // 42

  const _VoucherColWidths({
    this.amount   = 55,
    this.debitAc  = 82,
    this.ifsc     = 68,
    this.creditAc = 86,
    this.code     = 30,
    this.name     = 95,
    this.place    = 65,
    this.expenses = 82,
    this.aarti    = 46,
    this.from     = 42,
    this.to       = 42,
  });

  _VoucherColWidths copyWith({
    double? amount,
    double? debitAc,
    double? ifsc,
    double? creditAc,
    double? code,
    double? name,
    double? place,
    double? expenses,
    double? aarti,
    double? from,
    double? to,
  }) =>
      _VoucherColWidths(
        amount:   amount   ?? this.amount,
        debitAc:  debitAc  ?? this.debitAc,
        ifsc:     ifsc     ?? this.ifsc,
        creditAc: creditAc ?? this.creditAc,
        code:     code     ?? this.code,
        name:     name     ?? this.name,
        place:    place    ?? this.place,
        expenses: expenses ?? this.expenses,
        aarti:    aarti    ?? this.aarti,
        from:     from     ?? this.from,
        to:       to       ?? this.to,
      );

  double get totalWidth =>
      amount + debitAc + ifsc + creditAc + code + name + place +
      expenses + aarti + from + to;

  _VoucherColWidths scaleToFit(double targetWidth) {
    if (totalWidth == 0) return this;
    final scale = targetWidth / totalWidth;
    return _VoucherColWidths(
      amount:   amount   * scale,
      debitAc:  debitAc  * scale,
      ifsc:     ifsc     * scale,
      creditAc: creditAc * scale,
      code:     code     * scale,
      name:     name     * scale,
      place:    place    * scale,
      expenses: expenses * scale,
      aarti:    aarti    * scale,
      from:     from     * scale,
      to:       to       * scale,
    );
  }

  Map<int, pw.TableColumnWidth> get tableColumnWidths => {
    0:  pw.FixedColumnWidth(amount),
    1:  pw.FixedColumnWidth(debitAc),
    2:  pw.FixedColumnWidth(ifsc),
    3:  pw.FixedColumnWidth(creditAc),
    4:  pw.FixedColumnWidth(code),
    5:  pw.FixedColumnWidth(name),
    6:  pw.FixedColumnWidth(place),
    7:  pw.FixedColumnWidth(expenses),
    8:  pw.FixedColumnWidth(aarti),
    9:  pw.FixedColumnWidth(from),
    10: pw.FixedColumnWidth(to),
  };
}

class _TaxColumns {
  final double sr, fr, to, desc, qty, rate, amt;
  final double bank, tax, taxLbl;
  const _TaxColumns({
    required this.sr,
    required this.fr,
    required this.to,
    required this.desc,
    required this.qty,
    required this.rate,
    required this.amt,
    required this.bank,
    required this.tax,
    required this.taxLbl,
  });
}

class WidgetPdfExportService {
  WidgetPdfExportService._();

  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _sig;
  static pw.MemoryImage? _letterhead;

  static const _black   = PdfColor.fromInt(0xFF000000);
  static const _green   = PdfColor.fromInt(0xFF1A6B2F);

  static const _bSide   = pw.BorderSide(color: _black, width: 1.25);
  static const _thinSide = pw.BorderSide(color: _black, width: 1.25);
  static const double _outerBorderWidth = 1.25;
  static const double _headerHeightPt = 97.0;

  static Future<void> _init() async {
    _regular ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _bold ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    _logo       ??= await _tryImg('assets/images/aarti_logo.png');
    _sig        ??= await _tryImg('assets/images/aarti_signature.png');
    _letterhead ??= await _tryImg('assets/images/letterhead.png');
  }

  static Future<pw.MemoryImage?> _tryImg(String path) async {
    try {
      final d = await rootBundle.load(path);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.Document _newDoc() => pw.Document(
        theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
      );

  static pw.TextStyle _ts({
    double size = 8,
    PdfColor? color,
    bool bold = false,
    bool italic = false,
    pw.TextDecoration? decoration,
    double? letterSpacing,
  }) =>
      pw.TextStyle(
        font: bold ? _bold : _regular,
        fontBold: _bold,
        fontFallback: [_regular!],
        fontSize: size,
        color: color ?? _black,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        decoration: decoration,
        letterSpacing: letterSpacing,
      );

  static String _multiline(String text) =>
      text.replaceAll('//', '\n').replaceAll('/n', '\n');

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportTaxInvoiceAndVoucher({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets? taxMargins,
    pw.EdgeInsets? voucherMargins,
  }) async {
    await _init();

    final resolvedTax     = taxMargins     ?? await _loadSavedTaxMargins();
    final resolvedVoucher = voucherMargins ?? await _loadSavedVoucherMargins();

    final doc = _newDoc();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: resolvedTax,
      build: (ctx) => _taxInvoicePage(voucher, config, resolvedTax),
    ));

    final sorted = _sortRows(voucher.rows);
    const rowsPerPage = 20;

    if (sorted.isEmpty) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: resolvedVoucher,
        build: (ctx) =>
            _voucherPageContent(voucher, config, const [], 0, margins: resolvedVoucher, showTotal: true),
      ));
    } else {
      for (var i = 0; i < sorted.length; i += rowsPerPage) {
        final end   = (i + rowsPerPage).clamp(0, sorted.length);
        final slice = sorted.sublist(i, end);
        final isLast = end >= sorted.length;
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: resolvedVoucher,
          build: (ctx) => _voucherPageContent(
            voucher, config, slice, i,
            margins: resolvedVoucher,
            showTotal: isLast,
          ),
        ));
      }
    }

    await _saveFile(doc, voucher.billNo, 'tax_invoice_voucher',
        pathType: ExportPathTarget.taxInvoice);
  }

  static Future<pw.EdgeInsets> _loadSavedTaxMargins() async {
    try {
      final s = await DatabaseHelper.instance.getMarginSettings();
      return pw.EdgeInsets.fromLTRB(s.left, s.top, s.right, s.bottom);
    } catch (_) {
      return const pw.EdgeInsets.fromLTRB(52, 24, 24, 24);
    }
  }

  static Future<pw.EdgeInsets> _loadSavedVoucherMargins() async {
    try {
      final s = await DatabaseHelper.instance.getMarginSettings();
      return pw.EdgeInsets.fromLTRB(s.left, s.top, s.right, s.bottom);
    } catch (_) {
      return const pw.EdgeInsets.all(24);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAX INVOICE PAGE
  // ══════════════════════════════════════════════════════════════════════════

  static const double _a4PtWidth = 595.28;
  static const double _a4PxWidth = 793.7;
  static const double _pxToPt = _a4PtWidth / _a4PxWidth;

  static const double _pxColSr   = 28.0;
  static const double _pxColFr   = 80.0;
  static const double _pxColTo   = 80.0;
  static const double _pxColQty  = 36.0;
  static const double _pxColRate = 50.0;
  static const double _pxColAmt  = 90.0;

  static _TaxColumns _columnLayout(double usableW) {
    final sr   = _pxColSr   * _pxToPt;
    final fr   = _pxColFr   * _pxToPt;
    final to   = _pxColTo   * _pxToPt;
    final qty  = _pxColQty  * _pxToPt;
    final rate = _pxColRate * _pxToPt;
    final amt  = _pxColAmt  * _pxToPt;

    final fixedSum = sr + fr + to + qty + rate + amt;
    final desc     = usableW - fixedSum;
    final bank     = sr + fr + to + desc;
    final tax      = qty + rate + amt;
    final taxLbl   = tax - amt;

    return _TaxColumns(
      sr: sr, fr: fr, to: to, desc: desc,
      qty: qty, rate: rate, amt: amt,
      bank: bank, tax: tax, taxLbl: taxLbl,
    );
  }

  static pw.Widget _taxInvoicePage(
      VoucherModel voucher, CompanyConfigModel config, pw.EdgeInsets margins) {
    final sorted   = _sortRows(voucher.rows);
    final fromDate = sorted.isNotEmpty ? _fmtDate(sorted.first.fromDate) : '-';
    final toDate   = sorted.isNotEmpty ? _fmtDate(sorted.last.toDate)   : '-';

    final usableW = _a4PtWidth - margins.left - margins.right - 2 * _outerBorderWidth;
    final cols = _columnLayout(usableW);

  
    final taxInvoiceHeading = 'TAX INVOICE';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _invoiceHeader(config),
        pw.SizedBox(height: 4),
        pw.Divider(color: _black, thickness: 1.3),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            taxInvoiceHeading,
            style: _ts(
                size: 12,
                bold: true,
                decoration: pw.TextDecoration.underline,
                letterSpacing: 1.2),
          ),
        ),
        pw.SizedBox(height: 6),
        _billToSection(voucher),

        // ── EMPTY BOX moved here: between Bill To section and Tax Invoice table ──
        pw.SizedBox(height: 5),
        pw.Container(
          height: 18,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _black, width: 1.25),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            'TRAVEL EXPENSES FOR THE MONTH OF ${_monthYearFromIso(voucher.date)}',
            style: _ts(size: 8, bold: true),
          ),
        ),

        pw.SizedBox(height: 5),
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _black, width: _outerBorderWidth)),
          child: pw.Column(children: [
            pw.Table(
              border: pw.TableBorder(bottom: _bSide, verticalInside: _bSide),
              columnWidths: {
                0: pw.FixedColumnWidth(cols.sr),
                1: pw.FixedColumnWidth(cols.fr),
                2: pw.FixedColumnWidth(cols.to),
                3: pw.FixedColumnWidth(cols.desc),
                4: pw.FixedColumnWidth(cols.qty),
                5: pw.FixedColumnWidth(cols.rate),
                6: pw.FixedColumnWidth(cols.amt),
              },
              children: [
                pw.TableRow(
                  children: [
                    _tblHdrCell('Sr. No', centered: true),
                    _tblHdrCell('Date Fr.', centered: true),
                    _tblHdrCell('Date upto', centered: true),
                    _tblHdrCell('Item Description'),
                    _tblHdrCell('QTY', centered: true),
                    _tblHdrCell('RATE', centered: true),
                    _tblHdrCell('AMOUNT', centered: true),
                  ],
                ),
              ],
            ),
            pw.Table(
              border: pw.TableBorder(bottom: _bSide, verticalInside: _bSide),
              columnWidths: {
                0: pw.FixedColumnWidth(cols.sr),
                1: pw.FixedColumnWidth(cols.fr),
                2: pw.FixedColumnWidth(cols.to),
                3: pw.FixedColumnWidth(cols.desc),
                4: pw.FixedColumnWidth(cols.qty),
                5: pw.FixedColumnWidth(cols.rate),
                6: pw.FixedColumnWidth(cols.amt),
              },
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
              children: [
                pw.TableRow(children: [
                  _tblDataCell('1', centered: true),
                  _tblDataCell(fromDate, centered: true, size: 8, maxLines: 1),
                  _tblDataCell(toDate, centered: true, size: 8, maxLines: 1),
                  _tblDescCell(voucher.itemDescription),
                  _tblDataCell('', centered: true),
                  _tblDataCell('', centered: true),
                  _tblDataCell(
                    voucher.baseTotal == 0
                        ? '0.00'
                        : voucher.baseTotal.toStringAsFixed(2),
                    centered: true,
                    bold: true,
                  ),
                ]),
              ],
            ),
            pw.Table(
              border: pw.TableBorder(bottom: _bSide, verticalInside: _bSide),
              columnWidths: {
                0: pw.FixedColumnWidth(cols.bank),
                1: pw.FixedColumnWidth(cols.tax),
              },
              children: [
                pw.TableRow(children: [
                  _bankInfoPanel(config, voucher.deptCode),
                  _taxSummaryPanel(voucher, cols.taxLbl, cols.amt),
                ]),
              ],
            ),
            _buildAmountInWordsRow(voucher.finalTotal),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(config.declarationText,
                      style: _ts(size: 8, italic: true)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'Subject to ${config.jurisdiction} jurisdiction.',
                      style: _ts(size: 8)),
                ],
              ),
            ),

            pw.Container(
              margin: const pw.EdgeInsets.only(top: 15),
              child: _sig != null
                  ? pw.SizedBox(
                      width: 170,
                      height: 60,
                      child: pw.Image(_sig!, fit: pw.BoxFit.contain))
                  : pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('For AARTI ENTERPRISES',
                            style: _ts(size: 8, bold: true)),
                        pw.SizedBox(height: 4),
                        pw.Text('Authorised Signatory', style: _ts(size: 7)),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildAmountInWordsRow(double finalTotal) {
    final words = _convertAmountToWords(finalTotal);
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: _bSide),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(words, style: _ts(size: 9, bold: true)),
    );
  }

  static String _convertAmountToWords(double amount) {
    if (amount == 0) return 'Rupees Zero Only';
    int rupees = amount.toInt();
    int paise = ((amount - rupees) * 100).round();
    String words = 'Rupees ' + _numberToWordsIndian(rupees);
    if (paise > 0) {
      words += ' and ' + _numberToWordsIndian(paise) + ' Paise';
    }
    words += ' Only';
    return words;
  }

  static String _numberToWordsIndian(int n) {
    if (n == 0) return 'Zero';
    const ones = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen'
    ];
    const tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    ];
    String convertLessThanThousand(int num) {
      if (num == 0) return '';
      if (num < 20) return ones[num];
      if (num < 100) {
        return tens[num ~/ 10] + (num % 10 != 0 ? ' ' + ones[num % 10] : '');
      }
      return ones[num ~/ 100] + ' Hundred' + (num % 100 != 0 ? ' ' + convertLessThanThousand(num % 100) : '');
    }
    if (n < 1000) return convertLessThanThousand(n);
    List<String> parts = [];
    if (n >= 10000000) {
      parts.add(convertLessThanThousand(n ~/ 10000000) + ' Crore');
      n %= 10000000;
    }
    if (n >= 100000) {
      parts.add(convertLessThanThousand(n ~/ 100000) + ' Lakh');
      n %= 100000;
    }
    if (n >= 1000) {
      parts.add(convertLessThanThousand(n ~/ 1000) + ' Thousand');
      n %= 1000;
    }
    if (n > 0) parts.add(convertLessThanThousand(n));
    return parts.join(' ');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HEADER & BILL-TO
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _invoiceHeader(CompanyConfigModel config) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (_logo != null)
          pw.SizedBox(
              width: 100,
              height: _headerHeightPt,
              child: pw.Image(_logo!, fit: pw.BoxFit.contain))
        else
          pw.SizedBox(width: 100, height: _headerHeightPt),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.SizedBox(
            height: _headerHeightPt,
            child: _letterhead != null
                ? pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Image(_letterhead!,
                        fit: pw.BoxFit.contain,
                        width: double.infinity,
                        height: _headerHeightPt))
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(config.companyName.toUpperCase(),
                          textAlign: pw.TextAlign.right,
                          style: _ts(size: 15, color: _green, bold: true)),
                      pw.SizedBox(height: 3),
                      pw.Text(config.address,
                          textAlign: pw.TextAlign.right,
                          style: _ts(size: 8)),
                      pw.SizedBox(height: 2),
                      pw.Text('Tel.  Office  :  ${config.phone}',
                          textAlign: pw.TextAlign.right,
                          style: _ts(size: 8, bold: true)),
                    ]),
          ),
        ),
      ],
    );
  }

  // ── Bill To section — now includes Dept. Code row at the bottom ──────────
  static pw.Widget _billToSection(VoucherModel voucher) => pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _black, width: _bSide.width)),
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('BILL To,', style: _ts(size: 8, bold: true)),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(_multiline(voucher.clientName),
                      style: _ts(size: 9, bold: true)),
                ),
                _kvRight('Bill No :-',
                    voucher.billNo.isEmpty ? 'AE/-/25-26' : voucher.billNo),
              ],
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(_multiline(voucher.clientAddress),
                      style: _ts(size: 8)),
                ),
                _kvRight('Date :-', _fmtDate(voucher.date)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text('GST No. ${voucher.clientGstin}',
                      style: _ts(size: 8, bold: true)),
                ),
                _kvRight(
                    'PO.No. :-', voucher.poNo.isEmpty ? '-' : voucher.poNo),
              ],
            ),
            // ── Dept. Code row — only rendered when a code is selected ──
            if (voucher.deptCode.trim().isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                'DEPT. CODE : ${voucher.deptCode.trim()}',
                style: _ts(size: 8, bold: true),
              ),
            ],
          ],
        ),
      );

  static pw.Widget _kvRight(String label, String value) =>
      pw.Row(children: [
        pw.Text('$label  ', style: _ts(size: 8.5, bold: true)),
        pw.Text(value, style: _ts(size: 8.5)),
      ]);

  // ══════════════════════════════════════════════════════════════════════════
  // TABLE CELLS (tax invoice)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _tblHdrCell(String text, {bool centered = false}) =>
      pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Align(
          alignment:
              centered ? pw.Alignment.center : pw.Alignment.centerLeft,
          child: pw.Text(text, style: _ts(size: 7.5, bold: true)),
        ),
      );

  static pw.Widget _tblDataCell(String text,
          {bool centered = false,
          bool right = false,
          bool bold = false,
          double size = 8.0,
          int? maxLines}) =>
      pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Align(
          alignment: centered
              ? pw.Alignment.center
              : right
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft,
          child: pw.Text(text,
              style: _ts(size: size, bold: bold), maxLines: maxLines),
        ),
      );

  static pw.Widget _tblDescCell(String description) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_multiline(description), style: _ts(size: 8.5)),
            pw.SizedBox(height: 58),
            pw.Text('( Vouchers attached with this original bill )',
                style: _ts(size: 7, italic: true)),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // BANK INFO & TAX SUMMARY (tax invoice)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _bankInfoPanel(CompanyConfigModel config, String deptCode) =>
      pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PAN NO :-  ${config.pan}',
                style: _ts(size: 8, bold: true)),
            pw.SizedBox(height: 2),
            pw.Text(
                'GSTIN  :  ${config.gstin}          HSN: SAC99851',
                style: _ts(size: 8, bold: true)),
            pw.SizedBox(height: 2),
            if (deptCode.isNotEmpty)
              pw.Text(
                'Code  :  ($deptCode)',
                style: _ts(size: 8, bold: true),
              ),
            pw.SizedBox(height: deptCode.isNotEmpty ? 6 : 8),
            pw.Text('Bank Details for   :  RTGS / NEFT',
                style: _ts(size: 9, bold: true)),
            pw.SizedBox(height: 4),
            _bankRow('Bank Name',   config.bankName),
            _bankRow('Branch',      config.branch),
            _bankRow('Account No.', config.accountNo),
            _bankRow('IFSC Code',   config.ifscCode),
          ],
        ),
      );

  static pw.Widget _bankRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 72,
              child: pw.Text(label, style: _ts(size: 8, bold: true))),
          pw.Text(':  $value', style: _ts(size: 8)),
        ]),
      );

  static pw.Widget _taxSummaryPanel(
      VoucherModel voucher, double labelW, double amtW) {
    return pw.Column(children: [
      _taxRow('Total amount before Tax',
          voucher.baseTotal.toStringAsFixed(2), labelW, amtW, showTop: false),
      _taxRow(
          'Add : CGST 9%', voucher.cgst.toStringAsFixed(2), labelW, amtW),
      _taxRow(
          'Add : SGST 9%', voucher.sgst.toStringAsFixed(2), labelW, amtW),
      _taxRow('Total Tax Amount', voucher.totalTax.toStringAsFixed(2),
          labelW, amtW,
          bold: true),
      _taxRow(
          'Round Up',
          '${voucher.roundOff >= 0 ? '+' : ''}${voucher.roundOff.toStringAsFixed(2)}',
          labelW,
          amtW),
      _grandTaxRow(
          'Total amount after Tax',
          '₹ ${voucher.finalTotal.toStringAsFixed(2)}',
          labelW,
          amtW),
    ]);
  }

  static pw.Widget _taxRow(String label, String value, double labelW, double amtW,
      {bool bold = false, bool showTop = true}) {
    return pw.Container(
      decoration: showTop
          ? pw.BoxDecoration(border: pw.Border(top: _thinSide))
          : null,
      child: pw.Row(children: [
        pw.Container(
          width: labelW,
          decoration: pw.BoxDecoration(border: pw.Border(right: _bSide)),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(label,
              textAlign: pw.TextAlign.right,
              style: _ts(size: 7.5, bold: bold)),
        ),
        pw.Expanded(
          child: pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            alignment: pw.Alignment.center,
            child: pw.Text(value,
                textAlign: pw.TextAlign.center,
                style: _ts(size: 8, bold: true)),
          ),
        ),
      ]),
    );
  }

  static pw.Widget _grandTaxRow(
      String label, String value, double labelW, double amtW) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(top: _bSide),
      ),
      child: pw.Row(children: [
        pw.Container(
          width: labelW,
          decoration: pw.BoxDecoration(border: pw.Border(right: _bSide)),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(label,
              textAlign: pw.TextAlign.right,
              style: _ts(size: 7.5, bold: true)),
        ),
        pw.Expanded(
          child: pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            alignment: pw.Alignment.center,
            child: pw.Text(value,
                textAlign: pw.TextAlign.center,
                style: _ts(size: 8, bold: true)),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VOUCHER PAGE (LANDSCAPE)
  // ══════════════════════════════════════════════════════════════════════════

  static const double _voucherBorderWidth = 0.5;
  static const _voucherHeaders = [
    'Amount',
    'Debit A/c',
    'IFSC',
    'Credit A/c',
    'Code',
    'Name',
    'Place',
    'Expenses',
    'Aarti',
    'Fr.',
    'To',
  ];

  static double _measureDateWidth(String date) {
    if (date.isEmpty) return 0;
    const double charWidthFactor = 0.55;
    return date.length * 7.5 * charWidthFactor + 4;
  }

  static pw.Widget _voucherPageContent(
    VoucherModel voucher,
    CompanyConfigModel config,
    List<VoucherRowModel> rows,
    int startIndex, {
    required pw.EdgeInsets margins,
    required bool showTotal,
  }) {
    final landscape = PdfPageFormat.a4.landscape;
    final availableWidth = landscape.width - margins.left - margins.right;

    final baseColWidths = const _VoucherColWidths().scaleToFit(availableWidth);

    double maxDateWidth = 0;
    for (final row in rows) {
      final fromDate = _fmtDate(row.fromDate);
      final toDate   = _fmtDate(row.toDate);
      final fromW = _measureDateWidth(fromDate);
      final toW   = _measureDateWidth(toDate);
      if (fromW > maxDateWidth) maxDateWidth = fromW;
      if (toW   > maxDateWidth) maxDateWidth = toW;
    }
    final colWidths = baseColWidths.copyWith(
      from: maxDateWidth > baseColWidths.from ? maxDateWidth : baseColWidths.from,
      to:   maxDateWidth > baseColWidths.to   ? maxDateWidth : baseColWidths.to,
    );

    final monthLabel = _monthFromIso(voucher.date);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Metadata row ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'AARTI ENTERPRISES : ${voucher.title.isEmpty ? "Expenses Statement" : voucher.title}',
                style: _ts(size: 10, bold: true),
              ),
            ),
            pw.Text(voucher.deptCode, style: _ts(size: 10, bold: true)),
          ],
        ),
        pw.Divider(color: _black, thickness: 1.0),

        pw.Table(
          border: pw.TableBorder.all(
              color: _black, width: _voucherBorderWidth),
          columnWidths: colWidths.tableColumnWidths,
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            // Header row
            pw.TableRow(
              children: _voucherHeaders.map((h) {
                final center = h == 'Aarti';
                return _voucherHeaderCell(h, center: center);
              }).toList(),
            ),
            // Data rows
            ...rows.map((r) {
              return pw.TableRow(
                children: [
                  _voucherCell(r.amount.toStringAsFixed(2)),
                  _voucherCell(config.accountNo, mono: true),
                  _voucherCell(r.ifscCode, mono: true),
                  _voucherCell(r.accountNumber, mono: true),
                  _voucherCell(r.sbCode, center: true),
                  _voucherCell(r.employeeName),
                  _voucherCell(r.branch),
                  _voucherCell('Exp. for month of $monthLabel'),
                  _voucherCell('Aarti', center: true),
                  _voucherCell(_fmtDate(r.fromDate)),
                  _voucherCell(_fmtDate(r.toDate)),
                ],
              );
            }),
            // Grand total row
            if (showTotal)
              pw.TableRow(
                children: [
                  _voucherCell(voucher.baseTotal.toStringAsFixed(2), bold: true),
                  ...List.generate(10, (_) => _voucherCell('')),
                ],
              ),
          ],
        ),
        if (showTotal) ...[
          pw.SizedBox(height: 12),
          pw.Row(children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(formatCurrency(voucher.baseTotal),
                    style: _ts(size: 11, bold: true)),
                pw.Text(numberToWords(voucher.baseTotal),
                    style: _ts(size: 9, italic: true)),
              ],
            ),
          ]),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(child: pw.SizedBox()),
              pw.SizedBox(width: 20),
              if (_sig != null)
                pw.SizedBox(
                    width: 170,
                    height: 60,
                    child: pw.Image(_sig!, fit: pw.BoxFit.contain))
              else
                pw.SizedBox(width: 170, height: 60),
            ],
          ),
        ],
      ],
    );
  }

  static pw.Widget _voucherHeaderCell(String text, {bool center = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment:
              center ? pw.Alignment.center : pw.Alignment.centerLeft,
          child: pw.Text(text,
              style: _ts(size: 7.5, bold: true),
              maxLines: 1,
              overflow: pw.TextOverflow.clip),
        ),
      );

  static pw.Widget _voucherCell(String text,
        {bool mono = false,
        bool right = false,
        bool center = false,
        bool bold = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      child: pw.Align(
        alignment: center ? pw.Alignment.center
            : right ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
        child: pw.Text(text,
            style: _ts(size: 7.5, bold: bold),
            ),
      ),
    );

  // ══════════════════════════════════════════════════════════════════════════
  // FILE SAVING & HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Directory> _outputDirFor(ExportPathTarget type) async {
    final prefs = ExportPreferencesNotifier.instance;

    String specific = '';
    switch (type) {
      case ExportPathTarget.taxInvoice:
        specific = prefs.taxInvoicePdfPath;
        break;
      case ExportPathTarget.salary:
        specific = prefs.salaryPdfPath;
        break;
      case ExportPathTarget.general:
        break;
      default:
        break;
    }
    if (specific.isNotEmpty) {
      final dir = Directory(specific);
      if (await dir.exists()) return dir;
    }

    if (prefs.pdfPath.isNotEmpty) {
      final dir = Directory(prefs.pdfPath);
      if (await dir.exists()) return dir;
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

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

  static Future<void> _saveFile(
    pw.Document doc,
    String billNo,
    String prefix, {
    required ExportPathTarget pathType,
  }) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final slug = billNo.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}'
        : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final dir      = await _outputDirFor(pathType);
    final basePath =
        '${dir.path}${Platform.pathSeparator}${prefix}_$slug.pdf';
    final path = await _uniquePath(basePath);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  static List<VoucherRowModel> _sortRows(List<VoucherRowModel> rows) {
    final copy = [...rows];
    copy.sort((a, b) {
      if (a.fromDate.isEmpty && b.fromDate.isEmpty) return 0;
      if (a.fromDate.isEmpty) return 1;
      if (b.fromDate.isEmpty) return -1;
      return a.fromDate.compareTo(b.fromDate);
    });
    return copy;
  }

  static String _monthFromIso(String iso) {
    if (iso.isEmpty) return '';
    try {
      final parts = iso.split('-');
      if (parts.length != 3) return '';
      final month = int.parse(parts[1]);
      const months = [
        'January', 'February', 'March',     'April',
        'May',      'June',     'July',      'August',
        'September','October',  'November',  'December',
      ];
      return months[month - 1];
    } catch (_) {
      return '';
    }
  }

  static String _monthYearFromIso(String iso) {
    if (iso.isEmpty) return '';
    try {
      final parts = iso.split('-');
      if (parts.length != 3) return '';
      final year = parts[0];
      final month = int.parse(parts[1]);
      const months = [
        'JANUARY', 'FEBRUARY', 'MARCH',     'APRIL',
        'MAY',      'JUNE',     'JULY',      'AUGUST',
        'SEPTEMBER','OCTOBER',  'NOVEMBER',  'DECEMBER',
      ];
      return '${months[month - 1]} $year';
    } catch (_) {
      return '';
    }
  }

  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }
}