// lib/features/pdf/service/pdf_house_style.dart
//
// The one house style every PDF in the app is built from: Tax Invoice,
// Expenses Statement (voucher), Bank Disbursement, Salary Invoice,
// Attachment A, Attachment B, Salary Statement and Salary Slips.
//
// Documents differ in content, page count and calculations — never in
// format. Two page kinds, matching the client's own documents:
//
//   • PdfPageKind.invoice — A4 portrait. Full letterhead, bill-to box, one
//     item table with a bank panel + totals panel, amount in words,
//     declaration and signature. (Salary slips use the same portrait page,
//     two slips per sheet.)
//   • PdfPageKind.table   — A4 landscape. Compact letterhead and a title
//     repeated on every page, one data table that flows over as many pages
//     as it needs, signature after the last row.
//
// Every page, of either kind, uses the same fonts, rules, type sizes,
// margins (the single saved margin setting), letterhead, title style,
// signature and "Page x of y" footer — all defined here, nowhere else.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company_config_model.dart';
import '../models/margin_settings_model.dart';
import '../export/export_hooks.dart';
import '../util/format_utils.dart';

enum PdfPageKind { invoice, table }

// ── Invoice layout inputs ────────────────────────────────────────────────────

/// One row of the totals panel on an invoice page.
class PdfInvoiceTotal {
  final String label;

  /// Optional smaller second line under [label], e.g. "(Total Basic Salary)".
  final String? note;
  final String value;
  final bool bold;

  const PdfInvoiceTotal(this.label, this.value, {this.note, this.bold = false});
}

/// Everything that varies between the invoice-format documents (Tax
/// Invoice, Salary Invoice, Attachment A, Attachment B). The layout itself
/// is fixed by [PdfHouseStyle.invoicePage].
class PdfInvoiceSpec {
  final String title;
  final String clientName;
  final String clientAddress;
  final String clientGstin;
  final String billNo;
  final String date;
  final String poNo;
  final String deptCode;

  /// Boxed line between the bill-to box and the item table.
  final String subject;

  /// Tax invoices carry a service period; salary documents don't.
  final bool showDateColumns;
  final String dateFrom;
  final String dateTo;

  final String description;

  /// Small line pinned to the bottom of the description cell.
  final String? descriptionNote;
  final String qty;
  final String rate;
  final String amount;

  /// Totals panel rows, top to bottom, above [grandTotal].
  final List<PdfInvoiceTotal> totals;
  final PdfInvoiceTotal grandTotal;
  final double amountInWords;

  const PdfInvoiceSpec({
    required this.title,
    required this.clientName,
    required this.clientAddress,
    required this.clientGstin,
    required this.billNo,
    required this.date,
    required this.poNo,
    this.deptCode = '',
    required this.subject,
    this.showDateColumns = false,
    this.dateFrom = '',
    this.dateTo = '',
    required this.description,
    this.descriptionNote,
    this.qty = '',
    this.rate = '',
    required this.amount,
    required this.totals,
    required this.grandTotal,
    required this.amountInWords,
  });
}

// ── Table layout inputs ──────────────────────────────────────────────────────

/// One column of a landscape data table. [weight] is relative — columns are
/// scaled to fill the usable page width exactly.
class PdfTableColumn {
  final String label;
  final double weight;
  final pw.TextAlign align;

  const PdfTableColumn(this.label, this.weight,
      {this.align = pw.TextAlign.left});
}

class PdfHouseStyle {
  PdfHouseStyle._();

  // ══════════════════════════════════════════════════════════════════════════
  // ASSETS
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.MemoryImage? _logo;
  static pw.MemoryImage? _letterhead;
  static pw.MemoryImage? _signature;

  /// Loads fonts and images once. Call before building any page.
  static Future<void> ensureLoaded() async {
    _regular ??= pw.Font.ttf(
        await ExportHooks.loadAsset('assets/fonts/NotoSans-Regular.ttf'));
    _bold ??=
        pw.Font.ttf(await ExportHooks.loadAsset('assets/fonts/NotoSans-Bold.ttf'));
    _logo ??= await _tryImage('assets/images/aarti_logo.png');
    _letterhead ??= await _tryImage('assets/images/letterhead.png');
    _signature ??= await _tryImage('assets/images/aarti_signature.png');
  }

  static Future<pw.MemoryImage?> _tryImage(String path) async {
    try {
      final d = await ExportHooks.loadAsset(path);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.Document newDocument({String? title}) => pw.Document(
        title: title,
        creator: 'CruSam',
        theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE SETUP
  // ══════════════════════════════════════════════════════════════════════════

  static PdfPageFormat formatFor(PdfPageKind kind) =>
      kind == PdfPageKind.invoice
          ? PdfPageFormat.a4
          : PdfPageFormat.a4.landscape;

  static const pw.EdgeInsets defaultMargins = pw.EdgeInsets.all(24);

  static pw.EdgeInsets marginsFrom(MarginSettings s) =>
      pw.EdgeInsets.fromLTRB(s.left, s.top, s.right, s.bottom);

  /// The single saved margin setting, applied to every document.
  static Future<pw.EdgeInsets> savedMargins() async {
    try {
      return marginsFrom(await ExportHooks.margins());
    } catch (_) {
      return defaultMargins;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PALETTE, RULES, TYPE
  // ══════════════════════════════════════════════════════════════════════════

  static const PdfColor ink = PdfColors.black;

  /// Box outlines, section dividers and the rule under the letterhead.
  static const double rule = 1.0;

  /// Grid lines inside data tables.
  static const double hairline = 0.5;

  static const pw.BorderSide ruleSide = pw.BorderSide(color: ink, width: rule);
  static const pw.BorderSide hairSide =
      pw.BorderSide(color: ink, width: hairline);

  static const double titleSize = 12;
  static const double subtitleSize = 8.5;
  static const double bodySize = 8;
  static const double tableSize = 7.5;
  static const double footerSize = 6.5;

  static pw.TextStyle text({
    double size = bodySize,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    double? letterSpacing,
  }) =>
      pw.TextStyle(
        font: bold ? _bold : _regular,
        fontNormal: _regular,
        fontBold: _bold,
        fontFallback: [_regular!],
        fontSize: size,
        color: ink,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        decoration: underline ? pw.TextDecoration.underline : null,
        letterSpacing: letterSpacing,
      );

  static String multiline(String text) =>
      text.replaceAll('//', '\n').replaceAll('/n', '\n');

  static String money(double v) => v.toStringAsFixed(2);

  /// ₹4,10,651.00 — Indian digit grouping.
  static String formatIndian(double v) => formatCurrency(v);

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED BLOCKS — identical on every document
  // ══════════════════════════════════════════════════════════════════════════

  /// Full letterhead height on invoice pages.
  static const double invoiceHeaderHeight = 97;

  /// Letterhead height on landscape tables and salary slips.
  static const double compactHeaderHeight = 56;

  static double headerHeightFor(PdfPageKind kind) =>
      kind == PdfPageKind.invoice ? invoiceHeaderHeight : compactHeaderHeight;

  /// Logo on the left, letterhead image on the right, same proportions at
  /// every size.
  static pw.Widget letterhead(CompanyConfigModel config, {required double height}) {
    final scale = height / invoiceHeaderHeight;
    final logoWidth = 135 * scale;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: logoWidth,
          height: height,
          child: _logo != null
              ? pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(_logo!, fit: pw.BoxFit.contain),
                )
              : null,
        ),
        pw.SizedBox(
          height: height,
          child: _letterhead != null
              ? pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Image(_letterhead!, fit: pw.BoxFit.contain),
                )
              : _letterheadFallback(config, scale),
        ),
      ],
    );
  }

  static pw.Widget _letterheadFallback(CompanyConfigModel config, double scale) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(config.companyName.toUpperCase(),
              textAlign: pw.TextAlign.right,
              style: text(size: 15 * scale, bold: true)),
          pw.SizedBox(height: 3 * scale),
          pw.Text(config.address,
              textAlign: pw.TextAlign.right, style: text(size: 8 * scale)),
          pw.SizedBox(height: 2 * scale),
          pw.Text('Tel.  Office  :  ${config.phone}',
              textAlign: pw.TextAlign.right,
              style: text(size: 8 * scale, bold: true)),
        ],
      );

  static pw.Widget documentTitle(String title) => pw.Center(
        child: pw.Text(
          title.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: text(
              size: titleSize, bold: true, underline: true, letterSpacing: 1.2),
        ),
      );

  /// Letterhead, rule and document title — the top of every document.
  /// Continuation pages of a table document pass [withLetterhead] false and
  /// carry just the title.
  static pw.Widget heading(
    CompanyConfigModel config, {
    required double headerHeight,
    required String title,
    String? subtitle,
    bool withLetterhead = true,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (withLetterhead) ...[
            letterhead(config, height: headerHeight),
            pw.SizedBox(height: 4),
            pw.Container(height: rule, color: ink),
            pw.SizedBox(height: 6),
          ],
          documentTitle(title),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(subtitle.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: text(size: subtitleSize, bold: true)),
            ),
          ],
          pw.SizedBox(height: 6),
        ],
      );

  /// "Label :- value" pairs on the left and right under a table title.
  static pw.Widget referenceStrip({
    List<(String, String)> left = const [],
    List<(String, String)> right = const [],
  }) {
    pw.Widget pairs(List<(String, String)> items) => pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) pw.SizedBox(width: 18),
              pw.Text('${items[i].$1} :-  ', style: text(bold: true)),
              pw.Text(items[i].$2, style: text()),
            ],
          ],
        );
    if (left.isEmpty && right.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pairs(left), pairs(right)],
      ),
    );
  }

  static const double signatureWidth = 170;
  static const double signatureHeight = 60;

  static pw.Widget signature(CompanyConfigModel config) => pw.SizedBox(
        width: signatureWidth,
        height: signatureHeight,
        child: _signature != null
            ? pw.Image(_signature!,
                fit: pw.BoxFit.contain, alignment: pw.Alignment.bottomRight)
            : pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('For ${config.companyName}', style: text(bold: true)),
                  pw.Text('Authorised Signatory', style: text(size: 7)),
                ],
              ),
      );

  /// Signature on the right; on invoice pages the declaration and
  /// jurisdiction sit on the left.
  static pw.Widget signOff(CompanyConfigModel config,
          {bool withDeclaration = false}) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: withDeclaration
                ? pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (config.declarationText.trim().isNotEmpty) ...[
                        pw.Text(config.declarationText,
                            style: text(bold: true)),
                        pw.SizedBox(height: 2),
                      ],
                      pw.Text('Subject to ${config.jurisdiction} jurisdiction.',
                          style: text()),
                    ],
                  )
                : pw.SizedBox(),
          ),
          signature(config),
        ],
      );

  /// What follows the last row of every table document, kept together as
  /// one block: the total and its amount in words (money tables only) and
  /// an optional [summary] box on the left, the signature on the right.
  static pw.Widget tableClosing(
    CompanyConfigModel config, {
    double? total,
    pw.Widget? summary,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (total != null) ...[
                    pw.Text('Total :-  ${formatIndian(total)}',
                        style: text(size: 9, bold: true)),
                    pw.SizedBox(height: 2),
                    amountInWordsLine(total),
                  ],
                  if (summary != null) ...[
                    if (total != null) pw.SizedBox(height: 8),
                    summary,
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            signature(config),
          ],
        ),
      );

  static pw.Widget pageFooter(pw.Context context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: text(size: footerSize),
        ),
      );

  static pw.Widget amountInWordsLine(double amount) => pw.Text(
        amountInWords(amount),
        style: text(size: 9, bold: true),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE SCAFFOLDS
  // ══════════════════════════════════════════════════════════════════════════

  /// A single portrait page with the standard footer.
  static pw.Page portraitPage({
    required pw.EdgeInsets margins,
    required pw.Widget Function(pw.Context context) build,
  }) =>
      pw.Page(
        pageFormat: formatFor(PdfPageKind.invoice),
        margin: margins,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [pw.Expanded(child: build(ctx)), pageFooter(ctx)],
        ),
      );

  /// Landscape pages for one data table. Every page repeats the title,
  /// references and the table's header row. [withLetterhead] controls
  /// whether the first page shows the letterhead (default false — letterhead
  /// and logo are kept for invoice-style pages). [closing] (see [tableClosing])
  /// follows the last row.
  static pw.MultiPage tablePages({
    required CompanyConfigModel config,
    required pw.EdgeInsets margins,
    required String title,
    List<(String, String)> referencesLeft = const [],
    List<(String, String)> referencesRight = const [],
    required List<PdfTableColumn> columns,
    required List<List<String>> rows,
    List<String>? totalRow,
    pw.Widget? closing,
    bool withLetterhead = false,
  }) {
    final format = formatFor(PdfPageKind.table);
    final usableWidth = format.width - margins.left - margins.right;

    // Headers are built in page order, so the first call is this
    // document's first page (it may follow other documents in a bundle).
    int? firstPage;
    bool isFirstPage(pw.Context ctx) =>
        ctx.pageNumber == (firstPage ??= ctx.pageNumber);

    return pw.MultiPage(
      pageFormat: format,
      margin: margins,
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          heading(config,
              headerHeight: invoiceHeaderHeight,
              title: title,
              withLetterhead: withLetterhead && isFirstPage(ctx)),
          referenceStrip(left: referencesLeft, right: referencesRight),
        ],
      ),
      footer: pageFooter,
      build: (ctx) => [
        dataTable(
          columns: columns,
          rows: rows,
          totalRow: totalRow,
          width: usableWidth,
        ),
        if (closing != null) closing,
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATA TABLE (landscape documents)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget dataTable({
    required List<PdfTableColumn> columns,
    required List<List<String>> rows,
    List<String>? totalRow,
    required double width,
  }) {
    final totalWeight = columns.fold<double>(0, (s, c) => s + c.weight);
    final scale = totalWeight == 0 ? 1.0 : width / totalWeight;

    return pw.Table(
      border: const pw.TableBorder(
        left: ruleSide,
        right: ruleSide,
        top: ruleSide,
        bottom: ruleSide,
        horizontalInside: hairSide,
        verticalInside: hairSide,
      ),
      columnWidths: {
        for (var i = 0; i < columns.length; i++)
          i: pw.FixedColumnWidth(columns[i].weight * scale),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true,
          children: [
            for (final c in columns)
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3.5),
                // Labels shrink rather than break mid-word in narrow columns.
                // Align loosens the cell's tight width so FittedBox never
                // grows the row to preserve aspect ratio.
                child: pw.Align(
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    child: pw.Text(c.label,
                        textAlign: pw.TextAlign.center,
                        style: text(size: tableSize, bold: true)),
                  ),
                ),
              ),
          ],
        ),
        for (final r in rows)
          pw.TableRow(
            children: [
              for (var i = 0; i < columns.length; i++)
                _tableCell(i < r.length ? r[i] : '', align: columns[i].align),
            ],
          ),
        if (totalRow != null)
          pw.TableRow(
            children: [
              for (var i = 0; i < columns.length; i++)
                _tableCell(i < totalRow.length ? totalRow[i] : '',
                    align: columns[i].align, bold: true, vertical: 3.5),
            ],
          ),
      ],
    );
  }

  static pw.Widget _tableCell(
    String value, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    double vertical = 2.5,
  }) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: vertical),
        child: pw.Text(value,
            textAlign: align, style: text(size: tableSize, bold: bold)),
      );

  /// A small bordered label/value box — used for summaries under a table.
  static pw.Widget summaryBox({
    required String title,
    required List<(String, String)> rows,
    required (String, String) total,
    double width = 280,
  }) {
    pw.Widget line((String, String) row, {bool bold = false}) => pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(top: hairSide)),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: pw.Row(children: [
            pw.Expanded(
                child: pw.Text(row.$1,
                    style: text(size: tableSize, bold: bold))),
            pw.Text(row.$2, style: text(size: tableSize, bold: bold)),
          ]),
        );
    return pw.Container(
      width: width,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: ink, width: rule)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
            child: pw.Text(title, style: text(size: tableSize, bold: true)),
          ),
          for (final r in rows) line(r),
          line(total, bold: true),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INVOICE PAGE (portrait documents)
  // ══════════════════════════════════════════════════════════════════════════

  static const double _colSr = 30;
  static const double _colDate = 60;
  static const double _colQty = 30;
  static const double _colRate = 42;
  static const double _colAmount = 72;
  static const double _itemRowHeight = 110;

  /// Adds one invoice-format page to [doc].
  static void addInvoicePage(
    pw.Document doc, {
    required CompanyConfigModel config,
    required pw.EdgeInsets margins,
    required PdfInvoiceSpec spec,
  }) {
    doc.addPage(portraitPage(
      margins: margins,
      build: (ctx) => invoiceBody(config, spec,
          usableWidth:
              formatFor(PdfPageKind.invoice).width - margins.left - margins.right),
    ));
  }

  static pw.Widget invoiceBody(
    CompanyConfigModel config,
    PdfInvoiceSpec spec, {
    required double usableWidth,
  }) {
    // Inner width of the item box (outer border drawn by the container).
    final inner = usableWidth - 2 * rule;
    final dateCols = spec.showDateColumns ? 2 * _colDate : 0.0;
    final desc = inner - _colSr - dateCols - _colQty - _colRate - _colAmount;
    final bankW = _colSr + dateCols + desc;
    final taxW = _colQty + _colRate + _colAmount;
    final labelW = _colQty + _colRate;

    final itemWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(_colSr),
      if (spec.showDateColumns) ...{
        1: const pw.FixedColumnWidth(_colDate),
        2: const pw.FixedColumnWidth(_colDate),
      },
    };
    final d = spec.showDateColumns ? 3 : 1;
    itemWidths[d] = pw.FixedColumnWidth(desc);
    itemWidths[d + 1] = const pw.FixedColumnWidth(_colQty);
    itemWidths[d + 2] = const pw.FixedColumnWidth(_colRate);
    itemWidths[d + 3] = const pw.FixedColumnWidth(_colAmount);

    const rowBorder = pw.TableBorder(bottom: ruleSide, verticalInside: ruleSide);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        heading(config, headerHeight: invoiceHeaderHeight, title: spec.title),
        _billTo(spec),
        pw.SizedBox(height: 5),
        pw.Container(
          height: 18,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: ink, width: rule)),
          child: pw.Text(spec.subject.toUpperCase(),
              style: text(bold: true)),
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: ink, width: rule)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header row
              pw.Table(
                border: rowBorder,
                columnWidths: itemWidths,
                defaultVerticalAlignment:
                    pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(children: [
                    _invoiceHeaderCell('Sr. No'),
                    if (spec.showDateColumns) ...[
                      _invoiceHeaderCell('Date Fr.'),
                      _invoiceHeaderCell('Date upto'),
                    ],
                    _invoiceHeaderCell('Item Description'),
                    _invoiceHeaderCell('QTY'),
                    _invoiceHeaderCell('RATE'),
                    _invoiceHeaderCell('AMOUNT'),
                  ]),
                ],
              ),
              // Item row
              pw.Table(
                border: rowBorder,
                columnWidths: itemWidths,
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                children: [
                  pw.TableRow(children: [
                    _invoiceCell('1', align: pw.TextAlign.center),
                    if (spec.showDateColumns) ...[
                      _invoiceCell(spec.dateFrom, align: pw.TextAlign.center),
                      _invoiceCell(spec.dateTo, align: pw.TextAlign.center),
                    ],
                    _descriptionCell(spec.description, spec.descriptionNote),
                    _invoiceCell(spec.qty, align: pw.TextAlign.center),
                    _invoiceCell(spec.rate, align: pw.TextAlign.center),
                    _invoiceCell(spec.amount,
                        align: pw.TextAlign.right, bold: true),
                  ]),
                ],
              ),
              // Bank panel | totals panel
              pw.Table(
                border: rowBorder,
                columnWidths: {
                  0: pw.FixedColumnWidth(bankW),
                  1: pw.FixedColumnWidth(taxW),
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
                children: [
                  pw.TableRow(children: [
                    _bankPanel(config, spec.deptCode),
                    _totalsPanel(spec, labelW),
                  ]),
                ],
              ),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: amountInWordsLine(spec.amountInWords),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        signOff(config, withDeclaration: true),
      ],
    );
  }

  static pw.Widget _billTo(PdfInvoiceSpec spec) {
    pw.Widget ref(String label, String value) => pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('$label  ', style: text(size: 8.5, bold: true)),
            pw.Text(value, style: text(size: 8.5)),
          ],
        );
    return pw.Container(
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: ink, width: rule)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('BILL To,', style: text(bold: true)),
          pw.SizedBox(height: 2),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
                child: pw.Text(multiline(spec.clientName),
                    style: text(size: 9, bold: true))),
            ref('Bill No :-', spec.billNo.isEmpty ? '-' : spec.billNo),
          ]),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
                child: pw.Text(multiline(spec.clientAddress), style: text())),
            ref('Date :-', spec.date.isEmpty ? '-' : spec.date),
          ]),
          pw.SizedBox(height: 2),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Expanded(
                child: pw.Text('GST No. ${spec.clientGstin}',
                    style: text(bold: true))),
            ref('PO.No. :-', spec.poNo.isEmpty ? '-' : spec.poNo),
          ]),
          if (spec.deptCode.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text('DEPT. CODE : ${spec.deptCode.trim()}',
                style: text(bold: true)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _invoiceHeaderCell(String label) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(label,
            textAlign: pw.TextAlign.center,
            style: text(size: tableSize, bold: true)),
      );

  static pw.Widget _invoiceCell(
    String value, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: pw.Text(value,
            textAlign: align, style: text(size: 8.5, bold: bold)),
      );

  static pw.Widget _descriptionCell(String description, String? note) =>
      pw.Container(
        constraints: const pw.BoxConstraints(minHeight: _itemRowHeight),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(multiline(description), style: text(size: 8.5)),
            if (note != null && note.isNotEmpty) ...[
              // Grows to fill the row so the note sits at the bottom.
              pw.Flexible(child: pw.Container()),
              pw.SizedBox(height: 6),
              pw.Text(note, style: text(size: 7, italic: true)),
            ],
          ],
        ),
      );

  static pw.Widget _bankPanel(CompanyConfigModel config, String deptCode) {
    pw.Widget bankRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 72, child: pw.Text(label, style: text(bold: true))),
            pw.Text(':  $value', style: text()),
          ]),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PAN NO :-  ${config.pan}', style: text(bold: true)),
          pw.SizedBox(height: 2),
          pw.Text('GSTIN  :  ${config.gstin}          HSN: SAC99851',
              style: text(bold: true)),
          if (deptCode.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text('Code  :  (${deptCode.trim()})', style: text(bold: true)),
          ],
          pw.SizedBox(height: 7),
          pw.Text('Bank Details for   :  RTGS / NEFT',
              style: text(size: 9, bold: true)),
          pw.SizedBox(height: 4),
          bankRow('Bank Name', config.bankName),
          bankRow('Branch', config.branch),
          bankRow('Account No.', config.accountNo),
          bankRow('IFSC Code', config.ifscCode),
        ],
      ),
    );
  }

  static pw.Widget _totalsPanel(PdfInvoiceSpec spec, double labelW) {
    pw.Widget row(PdfInvoiceTotal t, {required bool top, bool grand = false}) =>
        pw.Container(
          decoration: top
              ? const pw.BoxDecoration(border: pw.Border(top: ruleSide))
              : null,
          child: pw.Row(children: [
            pw.Container(
              width: labelW,
              decoration:
                  const pw.BoxDecoration(border: pw.Border(right: ruleSide)),
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(t.label,
                      textAlign: pw.TextAlign.right,
                      style: text(size: tableSize, bold: grand || t.bold)),
                  if (t.note != null)
                    pw.Text(t.note!,
                        textAlign: pw.TextAlign.right,
                        style: text(size: 6.5, italic: true)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: pw.Text(t.value,
                    textAlign: pw.TextAlign.right,
                    style: text(size: grand ? 9 : bodySize, bold: true)),
              ),
            ),
          ]),
        );

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < spec.totals.length; i++)
          row(spec.totals[i], top: i > 0),
        // Carries the label/value divider down to the grand total, which is
        // always pinned to the bottom of the panel.
        pw.Flexible(
          child: pw.Container(
            width: labelW,
            decoration:
                const pw.BoxDecoration(border: pw.Border(right: ruleSide)),
          ),
        ),
        row(spec.grandTotal, top: spec.totals.isNotEmpty, grand: true),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FORMATTING HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// dd/MM/yyyy from an ISO yyyy-MM-dd date; anything else is returned as-is.
  static String displayDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  /// "March 2026" from an ISO yyyy-MM-dd date.
  static String monthYear(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return '';
    final m = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12) return '';
    return '${_months[m - 1]} ${parts[0]}';
  }

  /// "March" from an ISO yyyy-MM-dd date.
  static String monthName(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return '';
    final m = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12) return '';
    return _months[m - 1];
  }

  /// "Rupees Four Lakh Ten Thousand Six Hundred Fifty One Only" — with
  /// "and N Paise" when there are paise.
  static String amountInWords(double amount) {
    if (amount == 0) return 'Rupees Zero Only';
    final negative = amount < 0;
    final abs = amount.abs();
    var rupees = abs.truncate();
    var paise = ((abs - rupees) * 100).round();
    if (paise == 100) {
      rupees += 1;
      paise = 0;
    }
    final words = StringBuffer(negative ? 'Minus Rupees ' : 'Rupees ')
      ..write(_indianWords(rupees));
    if (paise > 0) words.write(' and ${_indianWords(paise)} Paise');
    words.write(' Only');
    return words.toString();
  }

  static String _indianWords(int n) {
    if (n == 0) return 'Zero';
    const ones = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
      'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
      'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
    ];
    const tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy',
      'Eighty', 'Ninety',
    ];
    String below1000(int x) {
      if (x == 0) return '';
      if (x < 20) return ones[x];
      if (x < 100) return tens[x ~/ 10] + (x % 10 != 0 ? ' ${ones[x % 10]}' : '');
      return '${ones[x ~/ 100]} Hundred'
          '${x % 100 != 0 ? ' ${below1000(x % 100)}' : ''}';
    }

    final parts = <String>[];
    if (n >= 10000000) {
      parts.add('${_indianWords(n ~/ 10000000)} Crore');
      n %= 10000000;
    }
    if (n >= 100000) {
      parts.add('${below1000(n ~/ 100000)} Lakh');
      n %= 100000;
    }
    if (n >= 1000) {
      parts.add('${below1000(n ~/ 1000)} Thousand');
      n %= 1000;
    }
    if (n > 0) parts.add(below1000(n));
    return parts.join(' ');
  }
}
