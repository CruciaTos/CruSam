import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';

class ExcelExportService {
  // ── Border helpers ────────────────────────────────────────────────────────
  static Border get _thin =>
      Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.black);
  static Border get _none => Border(borderStyle: BorderStyle.None);

  /// Builds a [CellStyle]. [bg] is a 6-char hex string without '#'.
  static CellStyle _s({
    bool bold = false,
    bool italic = false,
    bool underline = false,
    String? bg,
    HorizontalAlign halign = HorizontalAlign.Left,
    bool ab = false, // all-borders
    bool wrap = false,
  }) =>
      CellStyle(
        bold: bold,
        italic: italic,
        underline: underline ? Underline.Single : Underline.None,
        // Provide a default color (white) when bg is null to avoid nullable type error
        backgroundColorHex: bg != null
            ? (ExcelColor.fromHexString('#$bg') ?? ExcelColor.white)
            : ExcelColor.white,
        horizontalAlign: halign,
        verticalAlign: VerticalAlign.Top,
        // Use TextWrapping.None for compatibility with older excel package versions
        textWrapping: wrap ? TextWrapping.WrapText : TextWrapping.Clip,
        leftBorder: ab ? _thin : _none,
        rightBorder: ab ? _thin : _none,
        topBorder: ab ? _thin : _none,
        bottomBorder: ab ? _thin : _none,
      );

  // ── Cell writers ──────────────────────────────────────────────────────────
  static void _set(Sheet s, int c, int r, String v, {CellStyle? style}) {
    final cell =
        s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    cell.value = TextCellValue(v);
    if (style != null) cell.cellStyle = style;
  }

  static void _merge(Sheet s, int c1, int r1, int c2, int r2) => s.merge(
        CellIndex.indexByColumnRow(columnIndex: c1, rowIndex: r1),
        CellIndex.indexByColumnRow(columnIndex: c2, rowIndex: r2),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // BANK DISBURSEMENT
  // ══════════════════════════════════════════════════════════════════════════
  static Future<String> exportBankDisbursement(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final xls = Excel.createExcel();
    final sh = xls['Bank Disbursement'];
    xls.delete('Sheet1');

    const colWidths = [12.0, 18.0, 16.0, 18.0, 10.0, 24.0, 14.0, 18.0, 20.0];
    for (var i = 0; i < colWidths.length; i++) {
      sh.setColumnWidth(i, colWidths[i]);
    }

    int r = 0;

    // Title
    _merge(sh, 0, r, 8, r);
    _set(sh, 0, r, 'AARTI ENTERPRISES : TRAVEL EXPENSES',
        style: _s(bold: true, underline: true, halign: HorizontalAlign.Center));
    r += 2;

    // Headers
    const hdrs = [
      'Amount', 'Debit A/c', 'IFSC', 'Credit A/c',
      'Code', 'Beneficiary', 'Place', 'Bank', 'Debit Name'
    ];
    final hdrS = _s(bold: true, bg: 'F1F5F9', ab: true);
    for (var c = 0; c < hdrs.length; c++) _set(sh, c, r, hdrs[c], style: hdrS);
    r++;

    // Data rows
    for (final row in voucher.rows) {
      final dS = _s(ab: true);
      _set(sh, 0, r, row.amount.toStringAsFixed(2),
          style: _s(bold: true, ab: true));
      _set(sh, 1, r, config.accountNo, style: dS);
      _set(sh, 2, r, row.ifscCode, style: dS);
      _set(sh, 3, r, row.accountNumber, style: dS);
      _set(sh, 4, r, row.sbCode, style: dS);
      _set(sh, 5, r, row.employeeName, style: dS);
      _set(sh, 6, r, row.branch, style: dS);
      _set(sh, 7, r, row.bankDetails, style: dS);
      _set(sh, 8, r, config.companyName, style: dS);
      r++;
    }

    // Total row
    _set(sh, 0, r, voucher.baseTotal.toStringAsFixed(2),
        style: _s(bold: true, bg: 'F8FAFC', ab: true));
    _merge(sh, 1, r, 8, r);
    _set(sh, 1, r, numberToWords(voucher.baseTotal),
        style: _s(italic: true, bg: 'F8FAFC', ab: true, wrap: true));
    r += 2;

    // Summary box (fixed 6-col width)
    final idbiOther = voucher.rows
        .where((x) => !x.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, x) => a + x.amount);
    final idbiIdbi = voucher.rows
        .where((x) => x.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, x) => a + x.amount);

    void summRow(int sr, String num, String label, String val,
        {bool total = false}) {
      final bg = total ? 'F1F5F9' : null;
      _set(sh, 0, sr, num, style: _s(bold: total, bg: bg, ab: true));
      _merge(sh, 1, sr, 3, sr);
      _set(sh, 1, sr, label, style: _s(bold: total, bg: bg, ab: true));
      _merge(sh, 4, sr, 5, sr);
      _set(sh, 4, sr, val,
          style: _s(
              bold: true, bg: bg, ab: true, halign: HorizontalAlign.Right));
    }

    summRow(r,     '1', 'From IDBI to Other Bank', idbiOther.toStringAsFixed(2));
    summRow(r + 1, '2', 'From IDBI to IDBI Bank',  idbiIdbi.toStringAsFixed(2));
    summRow(r + 2, '',  'Total', voucher.baseTotal.toStringAsFixed(2),
        total: true);

    return _save(xls, 'bank_disbursement_${_slug(voucher.billNo)}.xlsx');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAX INVOICE
  // ══════════════════════════════════════════════════════════════════════════
  static Future<String> exportTaxInvoice(
    VoucherModel voucher,
    CompanyConfigModel config,
  ) async {
    final xls = Excel.createExcel();
    final sh = xls['Tax Invoice'];
    xls.delete('Sheet1');

    // Col widths mirror fixed widths in TaxInvoicePreview
    sh.setColumnWidth(0, 8.0);   // Sr
    sh.setColumnWidth(1, 14.0);  // Date Fr
    sh.setColumnWidth(2, 14.0);  // Date upto
    sh.setColumnWidth(3, 40.0);  // Item Description
    sh.setColumnWidth(4, 8.0);   // QTY
    sh.setColumnWidth(5, 12.0);  // RATE
    sh.setColumnWidth(6, 16.0);  // AMOUNT

    int r = 0;

    // ── Company header (right-aligned, full width) ─────────────────────────
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, config.companyName.toUpperCase(),
        style: _s(bold: true, halign: HorizontalAlign.Right));
    r++;
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, config.address,
        style: _s(halign: HorizontalAlign.Right));
    r++;
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, 'Tel.  Office  :  ${config.phone}',
        style: _s(bold: true, halign: HorizontalAlign.Right));
    r += 2;

    // ── TAX INVOICE label ─────────────────────────────────────────────────
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, 'TAX INVOICE',
        style: _s(
            bold: true, underline: true, halign: HorizontalAlign.Center));
    r += 2;

    // ── Bill To ───────────────────────────────────────────────────────────
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, 'BILL To,', style: _s(bold: true, ab: true));
    r++;

    _merge(sh, 0, r, 3, r);
    _set(sh, 0, r, voucher.clientName, style: _s(bold: true, ab: true));
    _merge(sh, 4, r, 6, r);
    _set(sh, 4, r,
        'Bill No :-  ${voucher.billNo.isEmpty ? "AE/-/25-26" : voucher.billNo}',
        style: _s(ab: true));
    r++;

    _merge(sh, 0, r, 3, r);
    _set(sh, 0, r, voucher.clientAddress, style: _s(ab: true));
    _merge(sh, 4, r, 6, r);
    _set(sh, 4, r, 'Date :-  ${voucher.date}', style: _s(ab: true));
    r++;

    _merge(sh, 0, r, 3, r);
    _set(sh, 0, r, 'GST No. ${voucher.clientGstin}',
        style: _s(bold: true, ab: true));
    _merge(sh, 4, r, 6, r);
    _set(sh, 4, r,
        'PO.No. :-  ${voucher.poNo.isEmpty ? "-" : voucher.poNo}',
        style: _s(ab: true));
    r += 2;

    // ── Item table header ─────────────────────────────────────────────────
    final thS =
        _s(bold: true, bg: 'E3E8F4', ab: true, halign: HorizontalAlign.Center);
    _set(sh, 0, r, 'Sr. No',          style: thS);
    _set(sh, 1, r, 'Date Fr.',         style: thS);
    _set(sh, 2, r, 'Date upto',        style: thS);
    _set(sh, 3, r, 'Item Description', style: _s(bold: true, bg: 'E3E8F4', ab: true));
    _set(sh, 4, r, 'QTY',              style: thS);
    _set(sh, 5, r, 'RATE',             style: thS);
    _set(sh, 6, r, 'AMOUNT',           style: thS);
    r++;

    // ── Data row ──────────────────────────────────────────────────────────
    final ctrS = _s(ab: true, halign: HorizontalAlign.Center);
    _set(sh, 0, r, '1', style: ctrS);
    _set(sh, 1, r,
        _fmtDate(voucher.rows.isNotEmpty ? voucher.rows.first.fromDate : ''),
        style: ctrS);
    _set(sh, 2, r,
        _fmtDate(voucher.rows.isNotEmpty ? voucher.rows.last.toDate : ''),
        style: ctrS);
    _set(sh, 3, r,
        '${voucher.itemDescription}\n\n( Vouchers attached with this original bill )',
        style: _s(ab: true, wrap: true));
    _set(sh, 4, r, '', style: ctrS);
    _set(sh, 5, r, '', style: ctrS);
    _set(sh, 6, r, voucher.baseTotal.toStringAsFixed(2),
        style: _s(bold: true, ab: true, halign: HorizontalAlign.Right));
    sh.setRowHeight(r, 50);
    r++;

    // ── Bottom: bank info left (merged rows) + tax breakdown right ─────────
    final bStart = r;

    // 6 tax rows matching _tableBottom in the preview
    final taxRows = [
      (
        'Total amount before Tax',
        voucher.baseTotal.toStringAsFixed(2),
        false,
        false
      ),
      ('Add : CGST 9%',    voucher.cgst.toStringAsFixed(2),     false, false),
      ('Add : SGST 9%',    voucher.sgst.toStringAsFixed(2),     false, false),
      ('Total Tax Amount', voucher.totalTax.toStringAsFixed(2), true,  false),
      (
        'Round Up',
        '${voucher.roundOff >= 0 ? "+" : ""}${voucher.roundOff.toStringAsFixed(2)}',
        false,
        false
      ),
      (
        'Total Amount after Tax',
        '₹ ${voucher.finalTotal.toStringAsFixed(2)}',
        true,
        true
      ),
    ];

    // Left bank info cell spans all tax rows
    _merge(sh, 0, bStart, 3, bStart + taxRows.length - 1);
    _set(
        sh,
        0,
        bStart,
        [
          'PAN NO :-  ${config.pan}',
          'GSTIN  :  ${config.gstin}          HSN: SAC99851',
          '',
          'Bank Details for   :  RTGS / NEFT',
          'Bank Name     :  ${config.bankName}',
          'Branch            :  ${config.branch}',
          'Account No.   :  ${config.accountNo}',
          'IFSC Code     :  ${config.ifscCode}',
        ].join('\n'),
        style: _s(ab: true, wrap: true));

    // Right tax rows
    for (var i = 0; i < taxRows.length; i++) {
      final (label, val, isBold, isGrand) = taxRows[i];
      final bg = isGrand ? 'D6DCF5' : null;
      final rowStyle = _s(
          bold: isBold || isGrand,
          bg: bg,
          ab: true,
          halign: HorizontalAlign.Right);
      _merge(sh, 4, bStart + i, 5, bStart + i);
      _set(sh, 4, bStart + i, label, style: rowStyle);
      _set(sh, 6, bStart + i, val, style: rowStyle);
    }

    r = bStart + taxRows.length;

    // ── Declaration ───────────────────────────────────────────────────────
    _merge(sh, 0, r, 6, r);
    _set(sh, 0, r, config.declarationText,
        style: _s(italic: true, ab: true, wrap: true));
    sh.setRowHeight(r, 40);
    r += 2;

    // ── Certification + For Company ───────────────────────────────────────
    _merge(sh, 0, r, 3, r);
    _set(sh, 0, r,
        'Certified that particulars given above are true and correct.',
        style: _s(bold: true));
    _merge(sh, 4, r, 6, r);
    _set(sh, 4, r, 'For ${config.companyName}',
        style: _s(halign: HorizontalAlign.Center));
    r++;
    _merge(sh, 0, r, 3, r);
    _set(sh, 0, r, 'Subject to Mumbai jurisdiction.');

    return _save(xls, 'tax_invoice_${_slug(voucher.billNo)}.xlsx');
  }

  // ── Save to disk ──────────────────────────────────────────────────────────
  static Future<String> _save(Excel xls, String filename) async {
    final bytes = xls.encode();
    if (bytes == null) throw Exception('Excel encode returned null');

    if (kIsWeb) {
      // Web is handled by the caller via bytes – not applicable here.
      throw UnsupportedError(
          'Web download not handled in this service. Use exportBytes() instead.');
    }

    late Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final downloads = Directory('$home/Downloads');
      dir = await downloads.exists()
          ? downloads
          : await getApplicationDocumentsDirectory();
    }

    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Returns raw bytes – useful for web or custom share flows.
  static List<int>? exportBankDisbursementBytes(
          VoucherModel v, CompanyConfigModel c) =>
      throw UnimplementedError('Call exportBankDisbursement and read the file.');

  // ── Helpers ───────────────────────────────────────────────────────────────
  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static String _slug(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
}