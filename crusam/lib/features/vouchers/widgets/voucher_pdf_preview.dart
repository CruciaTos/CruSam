import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../core/preferences/export_preferences_notifier.dart';

// ── Column width configuration – matches PDF export’s unscaled base widths ────
class VoucherColWidths {
  final double amount;    // 55  (amount)
  final double debitAc;   // 82  (Debit A/c)
  final double ifsc;      // 68  (IFSC)
  final double creditAc;  // 86  (Credit A/c)
  final double code;      // 30  (Code)
  final double name;      // 95  (Name)
  final double place;     // 65  (Place)
  final double expenses;  // 82  (Expenses) – was “blank”
  final double aarti;     // 46  (Aarti)
  final double from;      // 42  (Fr.)
  final double to;        // 42  (To)

  const VoucherColWidths({
    this.amount   = 55,
    this.debitAc  = 82,
    this.ifsc     = 68,
    this.creditAc = 86,
    this.code     = 30,
    this.name     = 95,
    this.place    = 65,
    this.expenses = 82,   // previously 40 as “blank”
    this.aarti    = 46,
    this.from     = 42,
    this.to       = 42,
  });

  VoucherColWidths copyWith({
    double? amount,   double? debitAc, double? ifsc,   double? creditAc,
    double? code,     double? name,    double? place,  double? expenses,
    double? aarti,    double? from,    double? to,
  }) => VoucherColWidths(
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

  List<(String label, double width)> get entries => [
    ('Amount',     amount),
    ('Debit A/c',  debitAc),
    ('IFSC',       ifsc),
    ('Credit A/c', creditAc),
    ('Code',       code),
    ('Name',       name),
    ('Place',      place),
    ('Expenses',   expenses),   // changed from blank
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
      expenses: index == 7 ? value : null,
      aarti:    index == 8 ? value : null,
      from:     index == 9 ? value : null,
      to:       index == 10 ? value : null,
    );
  }

  double get totalWidth =>
      amount + debitAc + ifsc + creditAc + code + name + place +
      expenses + aarti + from + to;   // now 693.0

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
      expenses: expenses * scale,
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
    7:  FixedColumnWidth(expenses),
    8:  FixedColumnWidth(aarti),
    9:  FixedColumnWidth(from),
    10: FixedColumnWidth(to),
  };
}

// ── Preview widget – now perfectly mirrors the PDF export voucher page ───────
class VoucherPdfPreview extends StatelessWidget {
  static const double a4Width  = 793.7;
  static const double a4Height = 1122.5;

  // Match export: 20 rows per page
  static const int maxRowsPerPage = 20;

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
  static const _grandBg = Color(0xFFD6DCF5);
  static const _altBg   = Color(0xFFF8FAFC);

  static const _body = TextStyle(fontSize: 9, color: _black, height: 1.45);

  // ── Dynamic date‑column width measurement (mirrors export) ──────────────
  static double _measureDateWidth(String date) {
    if (date.isEmpty) return 0;
    const double charWidthFactor = 0.55; // empirical for 7.5pt font
    return date.length * 7.5 * charWidthFactor + 4; // +4pt for padding
  }

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
    // Available width after rotation (portrait height becomes landscape width)
    final availableWidth = a4Height - margins.horizontal;

    // Base column widths scaled to fit the available width
    final baseColWidths = autoFitColumns
        ? colWidths.scaleToFit(availableWidth)
        : colWidths;

    // Ensure date columns are wide enough for the longest formatted date
    double maxDateWidth = 0;
    for (final row in rows) {
      final fromDate = _fmtDate(row.fromDate);
      final toDate   = _fmtDate(row.toDate);
      final fromW = _measureDateWidth(fromDate);
      final toW   = _measureDateWidth(toDate);
      if (fromW > maxDateWidth) maxDateWidth = fromW;
      if (toW   > maxDateWidth) maxDateWidth = toW;
    }
    final effectiveColWidths = baseColWidths.copyWith(
      from: maxDateWidth > baseColWidths.from ? maxDateWidth : baseColWidths.from,
      to:   maxDateWidth > baseColWidths.to   ? maxDateWidth : baseColWidths.to,
    );

    final monthLabel = _monthFromIso(voucher.date);

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
        quarterTurns: 3, // 90° CCW
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
                const SizedBox(height: 4),
                _buildTable(rows, startIndex, effectiveColWidths, showTotal, monthLabel),
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
      ),
    );
  }

  Widget _buildTable(
    List<VoucherRowModel> rows,
    int startIndex,
    VoucherColWidths colWidths,
    bool showTotal,
    String monthLabel,
  ) {
    const headers = [
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

    final border = TableBorder.all(color: _black, width: 0.5);

    return Table(
      border: border,
      columnWidths: colWidths.tableColumnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(color: _hdrBg),
          children: headers.map((header) {
            final center = header == 'Aarti' || header == 'Code';
            return _hCell(header, center: center);
          }).toList(),
        ),
        // Data rows with alternating background
        ...rows.asMap().entries.map((entry) {
          final r   = entry.value;
          final idx = entry.key;
          final bg  = idx.isOdd ? _altBg : Colors.white;
          return TableRow(
            decoration: BoxDecoration(color: bg),
            children: [
              _c(r.amount.toStringAsFixed(2)),                         // left‑aligned
              _c(config.accountNo,                mono: true),
              _c(r.ifscCode,                      mono: true),
              _c(r.accountNumber,                 mono: true),
              _c(r.sbCode,                        center: true),       // centered
              _c(r.employeeName),
              _c(r.branch),
              _c('Exp. for month of $monthLabel'),
              _c('Aarti',                         center: true),
              _c(_fmtDate(r.fromDate)),
              _c(_fmtDate(r.toDate)),
            ],
          );
        }),
        // Grand total row
        if (showTotal)
          TableRow(
            decoration: const BoxDecoration(color: _grandBg),
            children: [
              _c(voucher.baseTotal.toStringAsFixed(2), bold: true),   // left‑aligned, bold
              ...List.generate(10, (_) => _c('')),
            ],
          ),
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

  // ── Cell helpers – now fully consistent with the PDF export ─────────────
  static Widget _hCell(String t, {bool center = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Align(
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: Text(
            t,
            textAlign: center ? TextAlign.center : TextAlign.left,
            style: const TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.bold,
              color: _black,
            ),
            overflow: TextOverflow.clip,    // matches export's pw.TextOverflow.clip
            maxLines: 1,
          ),
        ),
      );

  static Widget _c(String t, {
    bool mono = false,
    bool right = false,
    bool center = false,
    bool bold = false,
  }) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        child: Align(
          alignment: center ? Alignment.center
              : right ? Alignment.centerRight
                      : Alignment.centerLeft,
          child: Text(
            t,
            textAlign: center ? TextAlign.center
                : right ? TextAlign.right
                        : TextAlign.left,
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: mono ? 'monospace' : null,
            ),
            // No maxLines or overflow – text wraps as needed
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
  // PDF EXPORT (unchanged, included for completeness)
  // ════════════════════════════════════════════════════════════════════════════
  // ... (the existing export method remains identical)
}