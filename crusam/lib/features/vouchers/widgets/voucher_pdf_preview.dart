import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';

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

  // Fixed heights of non-row sections.
  static const double _headerH   = 46.0;
  static const double _tblHdrH   = 22.0;
  static const double _rowH      = 18.0;
  static const double _totalH    = 48.0;
  static const double _signatureH = 60.0;  // Space for signature row

  static int _rowsPerPage(EdgeInsets margins, {bool isLastPage = false}) {
    double extra = _headerH + _tblHdrH;
    if (isLastPage) extra += _totalH + _signatureH;
    final available = a4Height - margins.vertical - extra - 8;
    return (available / _rowH).floor().clamp(1, 80);
  }

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
    int offset = 0;

    while (true) {
      final isLast  = offset + _rowsPerPage(margins, isLastPage: false) >= sortedRows.length;
      final perPage = _rowsPerPage(margins, isLastPage: isLast);
      final end     = (offset + perPage).clamp(0, sortedRows.length);

      pages.add(preview._buildPage(
        width: a4Width,
        height: a4Height,
        rows: sortedRows.sublist(offset, end),
        startIndex: offset,
        showTotal: isLast,
      ));

      offset = end;
      if (offset >= sortedRows.length) break;
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
    final availableWidth = width - margins.horizontal;

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
}