import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../core/preferences/export_preferences_notifier.dart';

// ── Column width configuration ─────────────────────────────────────────────────
class VoucherColWidths {
  final double amount;    // moved to first column
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double name;
  final double place;
  final double blank;     // new column (empty)
  final double aarti;     // new column (filled with 'Aarti')
  final double from;
  final double to;

  const VoucherColWidths({
    this.amount   = 58,
    this.debitAc  = 88,
    this.ifsc     = 72,
    this.creditAc = 90,
    this.code     = 34,
    this.name     = 105,
    this.place    = 72,
    this.blank    = 40,   // reasonable default for empty column
    this.aarti    = 50,   // reasonable default for 'Aarti' column
    this.from     = 44,
    this.to       = 44,
  });

  VoucherColWidths copyWith({
    double? amount,   double? debitAc, double? ifsc,   double? creditAc,
    double? code,     double? name,    double? place,  double? blank,
    double? aarti,    double? from,    double? to,
  }) => VoucherColWidths(
    amount:   amount   ?? this.amount,
    debitAc:  debitAc  ?? this.debitAc,
    ifsc:     ifsc     ?? this.ifsc,
    creditAc: creditAc ?? this.creditAc,
    code:     code     ?? this.code,
    name:     name     ?? this.name,
    place:    place    ?? this.place,
    blank:    blank    ?? this.blank,
    aarti:    aarti    ?? this.aarti,
    from:     from     ?? this.from,
    to:       to       ?? this.to,
  );

  List<(String label, double width)> get entries => [
    ('Amount',     amount),
    ('Debit A/c',  debitAc),
    ('IFSC',       ifsc),
    ('Credit A/c', creditAc),
    ('Code',       code),
    ('Name',       name),
    ('Place',      place),
    ('',           blank),   // blank column header empty
    ('Aarti',      aarti),
    ('Fr.',        from),
    ('To',         to),
  ];

  VoucherColWidths withIndex(int index, double value) {
    return copyWith(
      amount:   index == 0 ? value : null,
      debitAc:  index == 1 ? value : null,
      ifsc:     index == 2 ? value : null,
      creditAc: index == 3 ? value : null,
      code:     index == 4 ? value : null,
      name:     index == 5 ? value : null,
      place:    index == 6 ? value : null,
      blank:    index == 7 ? value : null,
      aarti:    index == 8 ? value : null,
      from:     index == 9 ? value : null,
      to:       index == 10 ? value : null,
    );
  }

  double get totalWidth =>
      amount + debitAc + ifsc + creditAc + code + name + place +
      blank + aarti + from + to;

  VoucherColWidths scaleToFit(double targetWidth) {
    if (totalWidth == 0) return this;
    final scale = targetWidth / totalWidth;
    return VoucherColWidths(
      amount:   amount   * scale,
      debitAc:  debitAc  * scale,
      ifsc:     ifsc     * scale,
      creditAc: creditAc * scale,
      code:     code     * scale,
      name:     name     * scale,
      place:    place    * scale,
      blank:    blank    * scale,
      aarti:    aarti    * scale,
      from:     from     * scale,
      to:       to       * scale,
    );
  }

  Map<int, TableColumnWidth> get tableColumnWidths => {
    0:  FixedColumnWidth(amount),
    1:  FixedColumnWidth(debitAc),
    2:  FixedColumnWidth(ifsc),
    3:  FixedColumnWidth(creditAc),
    4:  FixedColumnWidth(code),
    5:  FixedColumnWidth(name),
    6:  FixedColumnWidth(place),
    7:  FixedColumnWidth(blank),
    8:  FixedColumnWidth(aarti),
    9:  FixedColumnWidth(from),
    10: FixedColumnWidth(to),
  };
}

// ── Preview widget ─────────────────────────────────────────────────────────────
class VoucherPdfPreview extends StatelessWidget {
  static const double a4Width  = 793.7;
  static const double a4Height = 1122.5;

  // Fixed limit of 24 employee rows per page
  static const int maxRowsPerPage = 24;

  final VoucherModel       voucher;
  final CompanyConfigModel config;
  final EdgeInsets         margins;
  final VoucherColWidths   colWidths;
  final bool               autoFitColumns;

  const VoucherPdfPreview({
    super.key,
    required this.voucher,
    required this.config,
    this.margins         = const EdgeInsets.all(24),
    this.colWidths       = const VoucherColWidths(),
    this.autoFitColumns  = true,
  });

  static const _black = Color(0xFF000000);
  static const _hdrBg = Color(0xFFE3E8F4);
  static const _body  = TextStyle(fontSize: 9, color: _black, height: 1.45);

  static List<Widget> buildPdfPages({
    required VoucherModel       voucher,
    required CompanyConfigModel config,
    EdgeInsets                  margins   = const EdgeInsets.all(24),
    VoucherColWidths            colWidths = const VoucherColWidths(),
    bool                        autoFitColumns = true,
  }) {
    final preview = VoucherPdfPreview(
      voucher: voucher,
      config: config,
      margins: margins,
      colWidths: colWidths,
      autoFitColumns: autoFitColumns,
    );
    final sortedRows = _sorted(voucher.rows);
    final pages = <Widget>[];

    for (int i = 0; i < sortedRows.length; i += maxRowsPerPage) {
      final end = (i + maxRowsPerPage).clamp(0, sortedRows.length);
      final isLast = end == sortedRows.length;

      pages.add(preview._buildPage(
        width: a4Width,
        height: a4Height,
        rows: sortedRows.sublist(i, end),
        startIndex: i,
        showTotal: isLast,
      ));
    }

    if (pages.isEmpty) {
      pages.add(preview._buildPage(
        width: a4Width,
        height: a4Height,
        rows: const [],
        startIndex: 0,
        showTotal: true,
      ));
    }

    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final pages = buildPdfPages(
      voucher: voucher,
      config: config,
      margins: margins,
      colWidths: colWidths,
      autoFitColumns: autoFitColumns,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < pages.length; i++) ...[
          Align(alignment: Alignment.topCenter, child: pages[i]),
          if (i != pages.length - 1) const SizedBox(height: 32),
        ],
      ],
    );
  }

  Widget _buildPage({
    required double width,
    required double height,
    required List<VoucherRowModel> rows,
    required int startIndex,
    required bool showTotal,
  }) {
    // Content is rendered in landscape (a4Height wide, a4Width tall) and then
    // rotated 90° CCW so it fits inside the portrait A4 shell.
    final availableWidth = a4Height - margins.horizontal;

    final effectiveColWidths = autoFitColumns
        ? colWidths.scaleToFit(availableWidth)
        : colWidths;

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: RotatedBox(
        quarterTurns: 3, // 90° CCW — landscape content sits sideways in portrait shell
        child: Padding(
          padding: margins,
          child: DefaultTextStyle(
          style: _body,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'AARTI ENTERPRISES : ${voucher.title.isEmpty ? "Expenses Statement" : voucher.title}',
                      style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(voucher.deptCode,
                      style: _body.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const Divider(color: _black),
              const SizedBox(height: 8),
              _buildTable(rows, startIndex, effectiveColWidths),
              if (showTotal) ...[
                const SizedBox(height: 12),
                _buildTotalSection(),
                const SizedBox(height: 16),
                _buildSignatureSection(),
              ],
            ],
          ),
        ),
        ),
      ), // RotatedBox
    );
  }

  Widget _buildTable(
    List<VoucherRowModel> rows,
    int startIndex,
    VoucherColWidths colWidths,
  ) {
    // Header order: Amount, Debit A/c, IFSC, Credit A/c, Code, Name, Place, (blank), Aarti, Fr., To
    const headers = [
      'Amount',
      'Debit A/c',
      'IFSC',
      'Credit A/c',
      'Code',
      'Name',
      'Place',
      '',      // blank column header
      'Aarti',
      'Fr.',
      'To',
    ];

    return Table(
      border:       TableBorder.all(color: _black),
      columnWidths: colWidths.tableColumnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _hdrBg),
          children: headers
              .map((header) => _hCell(header, center: header == 'Aarti'))
              .toList(),
        ),
        ...rows.map((r) {
          return TableRow(children: [
            _c(r.amount.toStringAsFixed(2), right: true),          // Amount (first)
            _c(config.accountNo,                mono: true),       // Debit A/c
            _c(r.ifscCode,                      mono: true),       // IFSC
            _c(r.accountNumber,                 mono: true),       // Credit A/c
            _c(r.sbCode),                                           // Code
            _c(r.employeeName),                                     // Name
            _c(r.branch),                                           // Place
            _c(''),                                                 // Blank column
            _c('Aarti', center: true),                              // Aarti column
            _c(_fmtDate(r.fromDate)),                              // Fr.
            _c(_fmtDate(r.toDate)),                                // To.
          ]);
        }),
      ],
    );
  }

  Widget _buildTotalSection() => Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatCurrency(voucher.baseTotal),
                  style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 11)),
              Text(numberToWords(voucher.baseTotal),
                  style: _body.copyWith(fontStyle: FontStyle.italic)),
            ],
          ),
        ],
      );

   Widget _buildSignatureSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Certified that the particulars given above are true and correct.',
                style: _body.copyWith(fontSize: 8, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
              Text(
                'Subject to Mumbai jurisdiction.',
                style: _body.copyWith(fontSize: 8),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Column(
          children: [
            const SizedBox(height: 4),
            SizedBox(
              width: 200,
              height: 90,
              child: Image.asset(
                'assets/images/aarti_signature.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cell helpers ──────────────────────────────────────────────────────────
  static Widget _hCell(String t, {bool center = false}) => Padding(
        padding: const EdgeInsets.all(3),
        child: Align(
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: Text(
            t,
            textAlign: center ? TextAlign.center : TextAlign.left,
            style: _body.copyWith(fontWeight: FontWeight.w800, fontSize: 8),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );

  static Widget _c(
    String t, {
    bool mono = false,
    bool right = false,
    bool center = false,
  }) => Padding(
        padding: const EdgeInsets.all(2),
        child: Align(
          alignment: center
              ? Alignment.center
              : right
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
          child: Text(
            t,
            textAlign: center
                ? TextAlign.center
                : right
                    ? TextAlign.right
                    : TextAlign.left,
            style: TextStyle(fontSize: 8, fontFamily: mono ? 'monospace' : null),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      );

  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static List<VoucherRowModel> _sorted(List<VoucherRowModel> rows) {
    final copy = [...rows];
    copy.sort((a, b) {
      if (a.fromDate.isEmpty && b.fromDate.isEmpty) return 0;
      if (a.fromDate.isEmpty) return 1;
      if (b.fromDate.isEmpty) return -1;
      return a.fromDate.compareTo(b.fromDate);
    });
    return copy;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF EXPORT (using pdf/widgets library – no rotation issues)
  // ════════════════════════════════════════════════════════════════════════════

  static pw.Font? _pwRegularFont;
  static pw.Font? _pwBoldFont;
  static pw.MemoryImage? _pwSignatureImage;

  static Future<void> _loadPdfAssets() async {
    _pwRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    _pwBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    _pwSignatureImage ??= await _loadPdfImage('assets/images/aarti_signature.png');
  }

  static Future<pw.MemoryImage?> _loadPdfImage(String path) async {
    try {
      final data = await rootBundle.load(path);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static pw.TextStyle _pwStyle({
    double? fontSize,
    PdfColor? color = const PdfColor(0, 0, 0),
    pw.FontWeight? fontWeight,
    pw.FontStyle? fontStyle,
  }) => pw.TextStyle(
    font: _pwRegularFont,
    fontBold: _pwBoldFont,
    fontSize: fontSize,
    color: color,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
  );

  static const PdfColor _pwBlack = PdfColor(0, 0, 0);
  static const PdfColor _pwHeaderBg = PdfColor(0.89, 0.91, 0.96); // #E3E8F4

  /// Builds a list of pw.Page objects for the voucher (landscape).
  /// This allows embedding into a larger PDF document.
  static Future<List<pw.Page>> buildPdfPagesForExport({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    EdgeInsets margins = const EdgeInsets.all(24),
    VoucherColWidths colWidths = const VoucherColWidths(),
    bool autoFitColumns = true,
  }) async {
    await _loadPdfAssets();

    final sortedRows = _sorted(voucher.rows);

    // Split into pages using the fixed 24‑row limit
    final pagesData = <_PdfPageData>[];
    for (int i = 0; i < sortedRows.length; i += maxRowsPerPage) {
      final end = (i + maxRowsPerPage).clamp(0, sortedRows.length);
      final isLast = end == sortedRows.length;
      pagesData.add(_PdfPageData(
        rows: sortedRows.sublist(i, end),
        startIndex: i,
        showTotal: isLast,
      ));
    }

    if (pagesData.isEmpty) {
      pagesData.add(_PdfPageData(rows: const [], startIndex: 0, showTotal: true));
    }

    // Available width for table (landscape width minus margins)
    final availableWidth = a4Height - margins.horizontal;
    final effectiveColWidths = autoFitColumns
        ? colWidths.scaleToFit(availableWidth)
        : colWidths;

    final pages = <pw.Page>[];
    for (final pageData in pagesData) {
      pages.add(pw.Page(
        pageFormat: PdfPageFormat(a4Height, a4Width), // landscape
        margin: pw.EdgeInsets.fromLTRB(
          margins.left,
          margins.top,
          margins.right,
          margins.bottom,
        ),
        build: (context) => _buildPdfPage(
          voucher: voucher,
          config: config,
          pageData: pageData,
          colWidths: effectiveColWidths,
        ),
      ));
    }
    return pages;
  }

  /// Export the voucher as a standalone PDF file and share it.
  static Future<void> exportPdf({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    EdgeInsets margins = const EdgeInsets.all(24),
    VoucherColWidths colWidths = const VoucherColWidths(),
    bool autoFitColumns = true,
  }) async {
    await _loadPdfAssets();

    final doc = pw.Document();
    final pages = await buildPdfPagesForExport(
      voucher: voucher,
      config: config,
      margins: margins,
      colWidths: colWidths,
      autoFitColumns: autoFitColumns,
    );

    final bytes = await doc.save();
    final dir = await _outputDir();
    final fileName = 'voucher_${voucher.id ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    await File(path).writeAsBytes(bytes);
    await Share.shareXFiles([XFile(path)],
        subject: 'Voucher ${voucher.title}');
  }

  static pw.Widget _buildPdfPage({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    required _PdfPageData pageData,
    required VoucherColWidths colWidths,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header row
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'AARTI ENTERPRISES : ${voucher.title.isEmpty ? "Expenses Statement" : voucher.title}',
                style: _pwStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Text(
              voucher.deptCode,
              style: _pwStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.Divider(color: _pwBlack, thickness: 1),
        pw.SizedBox(height: 8),
        // Table
        _buildPdfTable(pageData.rows, config, colWidths),
        if (pageData.showTotal) ...[
          pw.SizedBox(height: 12),
          _buildPdfTotalSection(voucher),
          pw.SizedBox(height: 16),
          _buildPdfSignatureSection(),
        ],
      ],
    );
  }

  static pw.Widget _buildPdfTable(
    List<VoucherRowModel> rows,
    CompanyConfigModel config,
    VoucherColWidths colWidths,
  ) {
    const headers = [
      'Amount',
      'Debit A/c',
      'IFSC',
      'Credit A/c',
      'Code',
      'Name',
      'Place',
      '',      // blank column header
      'Aarti',
      'Fr.',
      'To',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _pwBlack, width: 0.75),
      columnWidths: {
        0: pw.FixedColumnWidth(colWidths.amount),
        1: pw.FixedColumnWidth(colWidths.debitAc),
        2: pw.FixedColumnWidth(colWidths.ifsc),
        3: pw.FixedColumnWidth(colWidths.creditAc),
        4: pw.FixedColumnWidth(colWidths.code),
        5: pw.FixedColumnWidth(colWidths.name),
        6: pw.FixedColumnWidth(colWidths.place),
        7: pw.FixedColumnWidth(colWidths.blank),
        8: pw.FixedColumnWidth(colWidths.aarti),
        9: pw.FixedColumnWidth(colWidths.from),
        10: pw.FixedColumnWidth(colWidths.to),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _pwHeaderBg),
          children: headers.map((h) => _pwHeaderCell(h, center: h == 'Aarti')).toList(),
        ),
        // Data rows
        ...rows.map((r) {
          return pw.TableRow(
            children: [
              _pwCell(r.amount.toStringAsFixed(2), right: true),
              _pwCell(config.accountNo, mono: true),
              _pwCell(r.ifscCode, mono: true),
              _pwCell(r.accountNumber, mono: true),
              _pwCell(r.sbCode),
              _pwCell(r.employeeName),
              _pwCell(r.branch),
              _pwCell(''),
              _pwCell('Aarti', center: true),
              _pwCell(_fmtDate(r.fromDate)),
              _pwCell(_fmtDate(r.toDate)),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildPdfTotalSection(VoucherModel voucher) {
    return pw.Row(
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              formatCurrency(voucher.baseTotal),
              style: _pwStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              numberToWords(voucher.baseTotal),
              style: _pwStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPdfSignatureSection() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Certified that the particulars given above are true and correct.',
                style: _pwStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Subject to Mumbai jurisdiction.',
                style: _pwStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Column(
          children: [
            pw.SizedBox(height: 4),
            if (_pwSignatureImage != null)
              pw.SizedBox(
                width: 200,
                height: 90,
                child: pw.Image(_pwSignatureImage!, fit: pw.BoxFit.contain),
              )
            else
              pw.SizedBox(width: 200, height: 90),
          ],
        ),
      ],
    );
  }

  static pw.Widget _pwHeaderCell(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Align(
        alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: _pwStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  static pw.Widget _pwCell(
    String text, {
    bool mono = false,
    bool right = false,
    bool center = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Align(
        alignment: center
            ? pw.Alignment.center
            : right
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: _pwStyle(fontSize: 8),
        ),
      ),
    );
  }

  static Future<Directory> _outputDir() async {
    // 1. User-chosen path (set via Profile → Export Paths).
    final savedPath = ExportPreferencesNotifier.instance.pdfPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir;
    }

    // 2. Platform default: Downloads on desktop, app documents on mobile.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }
}

// ── Helper class for PDF page data ────────────────────────────────────────────
class _PdfPageData {
  final List<VoucherRowModel> rows;
  final int startIndex;
  final bool showTotal;

  _PdfPageData({
    required this.rows,
    required this.startIndex,
    required this.showTotal,
  });
}