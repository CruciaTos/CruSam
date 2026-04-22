// lib/features/pdf/services/widget_pdf_export_service.dart
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../shared/utils/format_utils.dart';

class WidgetPdfExportService {
  WidgetPdfExportService._();

  // ── Asset / font cache ──────────────────────────────────────────────────────
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _sig;
  static pw.MemoryImage? _letterhead; // ← NEW: mirrors TaxInvoicePreview

  // ── Palette ─────────────────────────────────────────────────────────────────
  static const _black   = PdfColor.fromInt(0xFF000000);
  static const _green   = PdfColor.fromInt(0xFF1A6B2F);
  static const _hdrBg   = PdfColor.fromInt(0xFFE3E8F4);
  static const _grandBg = PdfColor.fromInt(0xFFD6DCF5);
  static const _altBg   = PdfColor.fromInt(0xFFF8FAFC);
  static const _slate   = PdfColor.fromInt(0xFF475569);
  static const _red     = PdfColor.fromInt(0xFFDC2626);

  static const _bSide = pw.BorderSide(color: _black, width: 0.75);

  // ── Header height — mirrors TaxInvoicePreview.headerHeight (140px logical)
  // Scaled to PDF pt: 140 × (547 / 793.7) ≈ 96.5pt. Round to 97.
  static const double _headerHeightPt = 97.0;

  // ── Init ────────────────────────────────────────────────────────────────────
  static Future<void> _init() async {
    _regular ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _bold ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    _logo        ??= await _tryImg('assets/images/aarti_logo.png');
    _sig         ??= await _tryImg('assets/images/aarti_signature.png');
    _letterhead  ??= await _tryImg('assets/images/letterhead.png'); // ← NEW
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

  // ── Text style helper ───────────────────────────────────────────────────────
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

  // ── Multiline helper (mirrors TaxInvoicePreview._multiline) ─────────────────
  static String _multiline(String text) =>
      text.replaceAll('//', '\n').replaceAll('/n', '\n');

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  /// Exports Tax Invoice (portrait) + Voucher (landscape) as a single PDF.
  static Future<void> exportTaxInvoiceAndVoucher({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets taxMargins   = const pw.EdgeInsets.all(24),
    pw.EdgeInsets voucherMargins = const pw.EdgeInsets.all(24),
  }) async {
    await _init();
    final doc = _newDoc();

    // ── Page 1: Tax Invoice (portrait) ────────────────────────────────────
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: taxMargins,
      build: (ctx) => _taxInvoicePage(voucher, config),
    ));

    // ── Page 2+: Voucher (landscape) ──────────────────────────────────────
    final sorted = _sortRows(voucher.rows);

    // FIX: Reduced from 24 → 20 rows per page so the table never overflows
    // the landscape page height even when Expenses text is long.
    const rowsPerPage = 20;

    if (sorted.isEmpty) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: voucherMargins,
        build: (ctx) =>
            _voucherPageContent(voucher, config, const [], 0, showTotal: true),
      ));
    } else {
      for (var i = 0; i < sorted.length; i += rowsPerPage) {
        final end    = (i + rowsPerPage).clamp(0, sorted.length);
        final slice  = sorted.sublist(i, end);
        final isLast = end >= sorted.length;
        final start  = i;
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: voucherMargins,
          build: (ctx) => _voucherPageContent(
            voucher, config, slice, start,
            showTotal: isLast,
          ),
        ));
      }
    }

    await _saveAndShare(
        doc, voucher.billNo, 'tax_invoice_voucher', 'Tax Invoice & Voucher');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAX INVOICE PAGE
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _taxInvoicePage(
      VoucherModel voucher, CompanyConfigModel config) {
    final sorted   = _sortRows(voucher.rows);
    final fromDate = sorted.isNotEmpty ? _fmtDate(sorted.first.fromDate) : '-';
    final toDate   = sorted.isNotEmpty ? _fmtDate(sorted.last.toDate)   : '-';

    const outerBorder = 0.9;
    const usableW = 547.28 - 2 * outerBorder; // 545.48

    const srW   = 20.0;
    const frW   = 47.0;
    const toW   = 47.0;
    const qtyW  = 26.0;
    const rateW = 60.0;
    const amtW  = 66.0;
    const fixedSum = srW + frW + toW + qtyW + rateW + amtW; // 258
    const descW = usableW - fixedSum;                        // ~287.48

    const bankW   = srW + frW + toW + descW;  // ~401.48
    const taxW    = qtyW + rateW + amtW;       // 144
    const taxLblW = taxW - amtW;               //  78

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _invoiceHeader(config),
        pw.SizedBox(height: 4),
        pw.Divider(color: _black, thickness: 0.8),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            'TAX INVOICE',
            style: _ts(
              size: 12,
              bold: true,
              decoration: pw.TextDecoration.underline,
              letterSpacing: 1.2,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        _billToSection(voucher),
        pw.SizedBox(height: 8),

        // ── Main table container ─────────────────────────────────────────
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _black, width: 0.9)),
          child: pw.Column(
            children: [

              // ── 1. Header row ────────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  bottom: _bSide,
                  verticalInside: _bSide,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(srW),
                  1: pw.FixedColumnWidth(frW),
                  2: pw.FixedColumnWidth(toW),
                  3: pw.FixedColumnWidth(descW),
                  4: pw.FixedColumnWidth(qtyW),
                  5: pw.FixedColumnWidth(rateW),
                  6: pw.FixedColumnWidth(amtW),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _hdrBg),
                    children: [
                      _tblHdrCell('Sr. No',         centered: true),
                      _tblHdrCell('Date Fr.',        centered: true),
                      _tblHdrCell('Date upto',       centered: true),
                      _tblHdrCell('Item Description'),
                      _tblHdrCell('QTY',             centered: true),
                      _tblHdrCell('RATE',            centered: true),
                      _tblHdrCell('AMOUNT',          centered: true),
                    ],
                  ),
                ],
              ),

              // ── 2. Data row ──────────────────────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  bottom: _bSide,
                  verticalInside: _bSide,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(srW),
                  1: pw.FixedColumnWidth(frW),
                  2: pw.FixedColumnWidth(toW),
                  3: pw.FixedColumnWidth(descW),
                  4: pw.FixedColumnWidth(qtyW),
                  5: pw.FixedColumnWidth(rateW),
                  6: pw.FixedColumnWidth(amtW),
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
                children: [
                  pw.TableRow(
                    children: [
                      _tblDataCell('1',        centered: true),
                      _tblDataCell(fromDate,   centered: true, size: 8),
                      _tblDataCell(toDate,     centered: true, size: 8),
                      _tblDescCell(voucher.itemDescription),
                      _tblDataCell('',         centered: true),
                      _tblDataCell('',         centered: true),
                      _tblDataCell(
                        voucher.baseTotal == 0
                            ? '0.00'
                            : voucher.baseTotal.toStringAsFixed(2),
                        right: true,
                        bold: true,
                      ),
                    ],
                  ),
                ],
              ),

              // ── 3. Bank info + Tax summary ───────────────────────────────
              pw.Table(
                border: pw.TableBorder(
                  bottom: _bSide,
                  verticalInside: _bSide,
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(bankW),
                  1: pw.FixedColumnWidth(taxW),
                },
                children: [
                  pw.TableRow(
                    children: [
                      _bankInfoPanel(config),
                      _taxSummaryPanel(voucher, taxLblW, amtW),
                    ],
                  ),
                ],
              ),

              // ── 4. Declaration ────────────────────────────────────────────
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                child: pw.Text(
                  config.declarationText,
                  style: _ts(size: 7.5, italic: true),
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 8),

        // ── Jurisdiction + Signature ─────────────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Subject to ${config.jurisdiction} jurisdiction.',
                    style: _ts(size: 8),
                  ),
                ],
              ),
            ),
            if (_sig != null)
              pw.SizedBox(
                width: 150,
                height: 66,
                child: pw.Image(_sig!, fit: pw.BoxFit.contain),
              )
            else
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('For AARTI ENTERPRISES',
                      style: _ts(size: 8, bold: true)),
                  pw.SizedBox(height: 4),
                  pw.Text('Authorised Signatory', style: _ts(size: 7)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── Invoice header ─────────────────────────────────────────────────────────
  static pw.Widget _invoiceHeader(CompanyConfigModel config) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (_logo != null)
          pw.SizedBox(
            width: 100,
            height: _headerHeightPt,
            child: pw.Image(_logo!, fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(width: 100, height: _headerHeightPt),

        pw.SizedBox(width: 12),

        pw.Expanded(
          child: pw.SizedBox(
            height: _headerHeightPt,
            child: _letterhead != null
                ? pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Image(
                      _letterhead!,
                      fit: pw.BoxFit.contain,
                      width: double.infinity,
                      height: _headerHeightPt,
                    ),
                  )
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        config.companyName.toUpperCase(),
                        textAlign: pw.TextAlign.right,
                        style: _ts(size: 15, color: _green, bold: true),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(config.address,
                          textAlign: pw.TextAlign.right,
                          style: _ts(size: 8)),
                      pw.SizedBox(height: 2),
                      pw.Text('Tel.  Office  :  ${config.phone}',
                          textAlign: pw.TextAlign.right,
                          style: _ts(size: 8, bold: true)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Bill To ──────────────────────────────────────────────────────────────
  static pw.Widget _billToSection(VoucherModel voucher) => pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _black, width: 0.75)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('BILL To,', style: _ts(size: 8, bold: true)),
            pw.SizedBox(height: 2),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    _multiline(voucher.clientName),
                    style: _ts(size: 9, bold: true),
                  ),
                ),
                _kvRight('Bill No :-',
                    voucher.billNo.isEmpty ? 'AE/-/25-26' : voucher.billNo),
              ],
            ),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    _multiline(voucher.clientAddress),
                    style: _ts(size: 8),
                  ),
                ),
                _kvRight('Date :-', voucher.date),
              ],
            ),

            pw.SizedBox(height: 2),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'GST No. ${voucher.clientGstin}',
                    style: _ts(size: 8, bold: true),
                  ),
                ),
                _kvRight('PO.No. :-',
                    voucher.poNo.isEmpty ? '-' : voucher.poNo),
              ],
            ),
          ],
        ),
      );

  static pw.Widget _kvRight(String label, String value) =>
      pw.Row(children: [
        pw.Text('$label  ', style: _ts(size: 8.5, bold: true)),
        pw.Text(value, style: _ts(size: 8.5)),
      ]);

  // ── Table cell helpers ─────────────────────────────────────────────────────

  static pw.Widget _tblHdrCell(String text, {bool centered = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Align(
          alignment:
              centered ? pw.Alignment.center : pw.Alignment.centerLeft,
          child: pw.Text(text, style: _ts(size: 7.5, bold: true)),
        ),
      );

  static pw.Widget _tblDataCell(
    String text, {
    bool centered = false,
    bool right    = false,
    bool bold     = false,
    double size   = 8.0,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Align(
          alignment: centered
              ? pw.Alignment.center
              : right
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft,
          child: pw.Text(text, style: _ts(size: size, bold: bold)),
        ),
      );

  static pw.Widget _tblDescCell(String description) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_multiline(description), style: _ts(size: 8.5)),
            pw.SizedBox(height: 58),
            pw.Text(
              '( Vouchers attached with this original bill )',
              style: _ts(size: 7, italic: true),
            ),
          ],
        ),
      );

  // ── Bank info panel ────────────────────────────────────────────────────────
  static pw.Widget _bankInfoPanel(CompanyConfigModel config) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('PAN NO :-  ${config.pan}',
                style: _ts(size: 8, bold: true)),
            pw.SizedBox(height: 2),
            pw.Text(
              'GSTIN  :  ${config.gstin}          HSN: SAC99851',
              style: _ts(size: 8, bold: true),
            ),
            pw.SizedBox(height: 8),
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
            child: pw.Text(label, style: _ts(size: 8, bold: true)),
          ),
          pw.Text(':  $value', style: _ts(size: 8)),
        ]),
      );

  // ── Tax summary panel ──────────────────────────────────────────────────────
  static pw.Widget _taxSummaryPanel(
      VoucherModel voucher, double labelW, double amtW) {
    return pw.Column(
      children: [
        _taxRow('Total amount before Tax',
            voucher.baseTotal.toStringAsFixed(2), labelW, amtW),
        _taxRow('Add : CGST 9%',
            voucher.cgst.toStringAsFixed(2), labelW, amtW),
        _taxRow('Add : SGST 9%',
            voucher.sgst.toStringAsFixed(2), labelW, amtW),
        _taxRow('Total Tax Amount',
            voucher.totalTax.toStringAsFixed(2), labelW, amtW,
            bold: true),
        _taxRow(
          'Round Up',
          '${voucher.roundOff >= 0 ? '+' : ''}${voucher.roundOff.toStringAsFixed(2)}',
          labelW, amtW,
        ),
        _taxRow(
          'Total Amount after Tax',
          '₹ ${voucher.finalTotal.toStringAsFixed(0)}',
          labelW, amtW,
          bold: true,
          bg: _grandBg,
          last: true,
        ),
      ],
    );
  }

  static pw.Widget _taxRow(
    String label,
    String value,
    double labelW,
    double amtW, {
    bool bold     = false,
    PdfColor? bg,
    bool last     = false,
  }) {
    const borderThickness = 0.75;
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: bg,
        border: last ? null : const pw.Border(bottom: _bSide),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: labelW - borderThickness,
            decoration:
                const pw.BoxDecoration(border: pw.Border(right: _bSide)),
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              label,
              textAlign: pw.TextAlign.right,
              style: _ts(size: 7.5, bold: bold),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: _ts(size: 8, bold: bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VOUCHER PAGE (LANDSCAPE)
  // ══════════════════════════════════════════════════════════════════════════

  static const double _defaultTotalPx = 693.0;
  static const double _targetWidthPt  = 794.0;

  static List<double> _getScaledColWidths() {
    const scale = _targetWidthPt / _defaultTotalPx;
    return [
      55 * scale,
      82 * scale,
      68 * scale,
      86 * scale,
      30 * scale,
      95 * scale,
      65 * scale,
      82 * scale,
      46 * scale,
      42 * scale,
      42 * scale,
    ];
  }

  static const _vHeaders = [
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

  static pw.Widget _voucherPageContent(
    VoucherModel voucher,
    CompanyConfigModel config,
    List<VoucherRowModel> rows,
    int startIndex, {
    required bool showTotal,
  }) {
    final colWidths  = _getScaledColWidths();
    final monthLabel = _monthFromIso(voucher.date);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
        pw.Divider(color: _black, thickness: 0.75),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: _black, width: 0.5),
          columnWidths: {
            for (var i = 0; i < colWidths.length; i++)
              i: pw.FixedColumnWidth(colWidths[i])
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _hdrBg),
              children: _vHeaders.map((h) {
                final center = h == 'Aarti';
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 3, vertical: 3),
                  child: pw.Align(
                    alignment: center
                        ? pw.Alignment.center
                        : pw.Alignment.centerLeft,
                    child: pw.Text(h, style: _ts(size: 7.5, bold: true)),
                  ),
                );
              }).toList(),
            ),
            ...rows.asMap().entries.map((e) {
              final i  = e.key;
              final r  = e.value;
              final bg = i.isOdd ? _altBg : PdfColors.white;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _vCell(r.amount.toStringAsFixed(2), right: true),
                  _vCell(config.accountNo, mono: true),
                  _vCell(r.ifscCode, mono: true),
                  _vCell(r.accountNumber, mono: true),
                  _vCell(r.sbCode),
                  _vCell(r.employeeName),
                  _vCell(r.branch),
                  _vCell('Exp. for month of $monthLabel'),
                  _vCell('Aarti', center: true),
                  _vCell(_fmtDate(r.fromDate)),
                  _vCell(_fmtDate(r.toDate)),
                ],
              );
            }),
            if (showTotal)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _grandBg),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(2),
                    child: pw.Align(
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        voucher.baseTotal.toStringAsFixed(2),
                        style: _ts(size: 8, bold: true),
                      ),
                    ),
                  ),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                  _vCell(''),
                ],
              ),
          ],
        ),
        if (showTotal) ...[
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    formatCurrency(voucher.baseTotal),
                    style: _ts(size: 11, bold: true),
                  ),
                  pw.Text(
                    numberToWords(voucher.baseTotal),
                    style: _ts(size: 9, italic: true),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Certified that the particulars given above are true and correct.',
                      style: _ts(size: 8, italic: true),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Subject to Mumbai jurisdiction.',
                      style: _ts(size: 8),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Column(
                children: [
                  pw.SizedBox(height: 4),
                  if (_sig != null)
                    pw.SizedBox(
                      width: 200,
                      height: 90,
                      child: pw.Image(_sig!, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.SizedBox(width: 200, height: 90),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  static pw.Widget _vCell(
    String text, {
    bool mono = false,
    bool right = false,
    bool center = false,
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      child: pw.Align(
        alignment: center
            ? pw.Alignment.center
            : right
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: _ts(size: 7.5, bold: bold),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
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
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return months[month - 1];
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

  static Future<Directory> _outputDir() async {
    final saved = ExportPreferencesNotifier.instance.pdfPath;
    if (saved.isNotEmpty) {
      final dir = Directory(saved);
      if (await dir.exists()) return dir;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIX 1 — unique path helper (prevents file overwriting)
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns [basePath] unchanged if the file does not yet exist.
  /// Otherwise appends an incrementing counter before the extension:
  ///   invoice.pdf → invoice(1).pdf → invoice(2).pdf …
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
      pw.Document doc, String billNo, String prefix, String subject) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final slug = billNo.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}'
        : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final dir      = await _outputDir();
    final basePath = '${dir.path}${Platform.pathSeparator}${prefix}_$slug.pdf';
    // FIX 1: never overwrite — auto-increment filename if file already exists
    final path     = await _uniquePath(basePath);
    final fileName = File(path).uri.pathSegments.last;
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: fileName)],
      subject: subject,
    );
  }
}