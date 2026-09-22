// lib/features/pdf/service/widget_pdf_export_service.dart
//
// Voucher-module PDFs, all built on PdfHouseStyle:
//   • Tax Invoice (portrait invoice page) followed by the Expenses
//     Statement (landscape table pages) — one bundle, saved to disk or
//     returned as bytes for email / on-screen preview.
//   • Bank Disbursement (landscape table pages).

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../export/export_hooks.dart';
import '../models/company_config_model.dart';
import '../models/voucher_model.dart';
import '../models/voucher_row_model.dart';
import 'pdf_col_widths.dart';
import 'pdf_house_style.dart';

class WidgetPdfExportService {
  WidgetPdfExportService._();

  // ══════════════════════════════════════════════════════════════════════════
  // TAX INVOICE + EXPENSES STATEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Saves the bundle to the Tax Invoice folder. Named after the bill
  /// number unless [fileName] is given.
  static Future<void> exportTaxInvoiceAndVoucher({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets? taxMargins,
    pw.EdgeInsets? voucherMargins,
    VoucherColWidths? colWidths,
    String? fileName,
  }) async {
    final bytes = await buildInvoiceBundleBytes(
      voucher: voucher,
      config: config,
      taxMargins: taxMargins,
      voucherMargins: voucherMargins,
      colWidths: colWidths,
    );
    await ExportHooks.savePdf(
      bytes,
      fileName: fileName ??
          (voucher.billNo.isEmpty
              ? 'tax_invoice_voucher_${ExportHooks.slug('')}'
              : ExportHooks.slug(voucher.billNo)),
      target: ExportPathTarget.taxInvoice,
    );
  }

  /// Tax invoice page + expenses statement pages. Margins and column widths
  /// default to the saved settings.
  static Future<Uint8List> buildInvoiceBundleBytes({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets? taxMargins,
    pw.EdgeInsets? voucherMargins,
    VoucherColWidths? colWidths,
  }) async {
    await PdfHouseStyle.ensureLoaded();
    final saved = (taxMargins == null || voucherMargins == null)
        ? await PdfHouseStyle.savedMargins()
        : PdfHouseStyle.defaultMargins;
    final widths = colWidths ?? await _savedVoucherColWidths();

    final doc = PdfHouseStyle.newDocument(title: 'Tax Invoice ${voucher.billNo}');
    PdfHouseStyle.addInvoicePage(
      doc,
      config: config,
      margins: taxMargins ?? saved,
      spec: _taxInvoiceSpec(voucher),
    );
    doc.addPage(_expensesStatement(voucher, config, voucherMargins ?? saved, widths));
    return _encode(doc);
  }

  static PdfInvoiceSpec _taxInvoiceSpec(VoucherModel v) {
    final sorted = _sortRows(v.rows);
    final money = PdfHouseStyle.money;
    return PdfInvoiceSpec(
      title: 'Tax Invoice',
      clientName: v.clientName,
      clientAddress: v.clientAddress,
      clientGstin: v.clientGstin,
      billNo: v.billNo.isEmpty ? 'AE/-/25-26' : v.billNo,
      date: PdfHouseStyle.displayDate(v.date),
      poNo: v.poNo,
      deptCode: v.deptCode,
      subject:
          'Travel expenses for the month of ${PdfHouseStyle.monthYear(v.date)}',
      showDateColumns: true,
      dateFrom: sorted.isNotEmpty
          ? PdfHouseStyle.displayDate(sorted.first.fromDate)
          : '-',
      dateTo: sorted.isNotEmpty
          ? PdfHouseStyle.displayDate(sorted.last.toDate)
          : '-',
      description: v.itemDescription,
      descriptionNote: '( Vouchers attached with this original bill )',
      amount: money(v.baseTotal),
      totals: [
        PdfInvoiceTotal('Total amount before Tax', money(v.baseTotal)),
        PdfInvoiceTotal('Add : CGST 9%', money(v.cgst)),
        PdfInvoiceTotal('Add : SGST 9%', money(v.sgst)),
        PdfInvoiceTotal('Total Tax Amount', money(v.totalTax), bold: true),
        PdfInvoiceTotal('Round Up',
            '${v.roundOff >= 0 ? '+' : ''}${money(v.roundOff)}'),
      ],
      grandTotal:
          PdfInvoiceTotal('Total amount after Tax', '₹ ${money(v.finalTotal)}'),
      amountInWords: v.finalTotal,
    );
  }

  static pw.MultiPage _expensesStatement(
    VoucherModel v,
    CompanyConfigModel config,
    pw.EdgeInsets margins,
    VoucherColWidths w,
  ) {
    final month = PdfHouseStyle.monthName(v.date);
    final date = PdfHouseStyle.displayDate;
    return PdfHouseStyle.tablePages(
      config: config,
      margins: margins,
      title: v.title.isEmpty ? 'Expenses Statement' : v.title,
      referencesRight: [
        if (v.deptCode.trim().isNotEmpty) ('Dept. Code', v.deptCode.trim()),
      ],
      columns: [
        PdfTableColumn('Amount', w.amount, align: pw.TextAlign.right),
        PdfTableColumn('Debit A/c', w.debitAc),
        PdfTableColumn('IFSC', w.ifsc),
        PdfTableColumn('Credit A/c', w.creditAc),
        PdfTableColumn('Code', w.code, align: pw.TextAlign.center),
        PdfTableColumn('Name', w.name),
        PdfTableColumn('Place', w.place),
        PdfTableColumn('Expenses', w.expenses),
        PdfTableColumn('Aarti', w.aarti, align: pw.TextAlign.center),
        PdfTableColumn('Fr.', w.from, align: pw.TextAlign.center),
        PdfTableColumn('To', w.to, align: pw.TextAlign.center),
      ],
      rows: [
        for (final r in _sortRows(v.rows))
          [
            PdfHouseStyle.money(r.amount),
            config.accountNo,
            r.ifscCode,
            r.accountNumber,
            r.sbCode,
            r.employeeName,
            r.branch,
            'Exp. for month of $month',
            'Aarti',
            date(r.fromDate),
            date(r.toDate),
          ],
      ],
      totalRow: [PdfHouseStyle.money(v.baseTotal)],
      closing: PdfHouseStyle.tableClosing(config, total: v.baseTotal),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BANK DISBURSEMENT
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportBankDisbursement({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets? margins,
    BankColWidths? colWidths,
  }) async {
    final bytes = await buildBankDisbursementBytes(
      voucher: voucher,
      config: config,
      margins: margins,
      colWidths: colWidths,
    );
    await ExportHooks.savePdf(
      bytes,
      fileName: 'bank_disbursement_${ExportHooks.slug(voucher.billNo)}',
      target: ExportPathTarget.general,
    );
  }

  static Future<Uint8List> buildBankDisbursementBytes({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    pw.EdgeInsets? margins,
    BankColWidths? colWidths,
  }) async {
    await PdfHouseStyle.ensureLoaded();
    final m = margins ?? await PdfHouseStyle.savedMargins();
    final w = colWidths ?? await _savedBankColWidths();
    final rows = _sortRows(voucher.rows);

    final toIdbi = rows
        .where((r) => _isCompanyBankTransfer(r, config))
        .fold(0.0, (a, r) => a + r.amount);
    final toOther = rows
        .where((r) => !_isCompanyBankTransfer(r, config))
        .fold(0.0, (a, r) => a + r.amount);

    String dayMonth(String iso) {
      if (iso.isEmpty) return '-';
      if (iso.contains('-') && iso.length == 10) {
        final p = iso.split('-');
        return '${p[2]}/${p[1]}';
      }
      return iso;
    }

    final money = PdfHouseStyle.money;
    final doc = PdfHouseStyle.newDocument(
        title: 'Bank Disbursement ${voucher.billNo}');
    doc.addPage(PdfHouseStyle.tablePages(
      config: config,
      margins: m,
      title: 'Bank Disbursement : '
          '${voucher.title.isEmpty ? 'Travel Expenses' : voucher.title}',
      referencesRight: [
        if (voucher.deptCode.trim().isNotEmpty)
          ('Dept. Code', voucher.deptCode.trim()),
      ],
      columns: [
        PdfTableColumn('Amount', w.amount, align: pw.TextAlign.right),
        PdfTableColumn('Debit A/c', w.debitAc),
        PdfTableColumn('IFSC', w.ifsc),
        PdfTableColumn('Credit A/c', w.creditAc),
        PdfTableColumn('Code', w.code, align: pw.TextAlign.center),
        PdfTableColumn('Beneficiary', w.beneficiary),
        PdfTableColumn('Place', w.place),
        PdfTableColumn('Bank', w.bank),
        PdfTableColumn('Debit Name', w.debitName),
        PdfTableColumn('Fr.', w.from, align: pw.TextAlign.center),
        PdfTableColumn('To', w.to, align: pw.TextAlign.center),
      ],
      rows: [
        for (final r in rows)
          [
            money(r.amount),
            config.accountNo,
            r.ifscCode,
            r.accountNumber,
            r.sbCode,
            r.employeeName,
            r.branch,
            r.bankDetails,
            config.companyName,
            dayMonth(r.fromDate),
            dayMonth(r.toDate),
          ],
      ],
      totalRow: [money(voucher.baseTotal)],
      closing: PdfHouseStyle.tableClosing(
        config,
        total: voucher.baseTotal,
        summary: PdfHouseStyle.summaryBox(
          title: 'BANK TRANSFER SPLIT',
          rows: [
            ('From IDBI to Other Bank', money(toOther)),
            ('From IDBI to IDBI Bank', money(toIdbi)),
          ],
          total: ('Total Base Amount', money(voucher.baseTotal)),
        ),
      ),
    ));
    return _encode(doc);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _encode(pw.Document doc) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    return bytes;
  }

  /// Same mapping the preview dialog's Column Widths panel uses.
  static Future<VoucherColWidths> _savedVoucherColWidths() async {
    try {
      final s = await ExportHooks.voucherColumnWidths();
      return VoucherColWidths(
        debitAc: s.debitAc,
        ifsc: s.ifsc,
        creditAc: s.creditAc,
        code: s.code,
        name: s.name,
        place: s.place,
        from: s.from,
        to: s.to,
        amount: s.amount,
      );
    } catch (_) {
      return const VoucherColWidths();
    }
  }

  static Future<BankColWidths> _savedBankColWidths() async {
    try {
      final s = await ExportHooks.bankColumnWidths();
      return BankColWidths(
        amount: s.amount,
        debitAc: s.debitAc,
        ifsc: s.ifsc,
        creditAc: s.creditAc,
        code: s.code,
        beneficiary: s.beneficiary,
        place: s.place,
        bank: s.bank,
        debitName: s.debitName,
      );
    } catch (_) {
      return const BankColWidths();
    }
  }

  static bool _isCompanyBankTransfer(
      VoucherRowModel row, CompanyConfigModel config) {
    final ifsc = config.ifscCode.trim().toUpperCase();
    final prefix = ifsc.length >= 4
        ? ifsc.substring(0, 4)
        : (config.bankName.toLowerCase().contains('idbi') ? 'IBKL' : ifsc);
    return (prefix.isNotEmpty &&
            row.ifscCode.trim().toUpperCase().startsWith(prefix)) ||
        row.bankDetails.trim().toLowerCase().contains('idbi');
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
}
