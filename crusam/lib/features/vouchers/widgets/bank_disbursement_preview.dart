import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';


// ── Column width configuration ─────────────────────────────────────────────────
// Eleven columns matching the bank disbursement table header order.
// Default total ≈ 747 px, which fits inside A4 content width (~753 px at
// default 20 px margins, minus 12 px for TableBorder.all vertical lines).
class BankColWidths {
  final double amount;
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double beneficiary;
  final double place;
  final double bank;
  final double debitName;
  final double from;
  final double to;

  const BankColWidths({
    this.amount      = 52,
    this.debitAc     = 87,
    this.ifsc        = 72,
    this.creditAc    = 87,
    this.code        = 38,
    this.beneficiary = 100,
    this.place       = 68,
    this.bank        = 87,
    this.debitName   = 68,
    this.from        = 44,
    this.to          = 44,
  });

  BankColWidths copyWith({
    double? amount, double? debitAc, double? ifsc,  double? creditAc,
    double? code,   double? beneficiary, double? place,
    double? bank,   double? debitName,  double? from, double? to,
  }) => BankColWidths(
    amount:      amount      ?? this.amount,
    debitAc:     debitAc     ?? this.debitAc,
    ifsc:        ifsc        ?? this.ifsc,
    creditAc:    creditAc    ?? this.creditAc,
    code:        code        ?? this.code,
    beneficiary: beneficiary ?? this.beneficiary,
    place:       place       ?? this.place,
    bank:        bank        ?? this.bank,
    debitName:   debitName   ?? this.debitName,
    from:        from        ?? this.from,
    to:          to          ?? this.to,
  );

  /// Ordered (label, width) pairs — consumed by the settings panel.
  List<(String label, double width)> get entries => [
    ('Amount',      amount),
    ('Debit A/c',   debitAc),
    ('IFSC',        ifsc),
    ('Credit A/c',  creditAc),
    ('Code',        code),
    ('Beneficiary', beneficiary),
    ('Place',       place),
    ('Bank',        bank),
    ('Debit Name',  debitName),
    ('Fr.',         from),
    ('To',          to),
  ];

  /// Applies a new width by column index (0–10).
  BankColWidths withIndex(int index, double value) => copyWith(
    amount:      index == 0  ? value : null,
    debitAc:     index == 1  ? value : null,
    ifsc:        index == 2  ? value : null,
    creditAc:    index == 3  ? value : null,
    code:        index == 4  ? value : null,
    beneficiary: index == 5  ? value : null,
    place:       index == 6  ? value : null,
    bank:        index == 7  ? value : null,
    debitName:   index == 8  ? value : null,
    from:        index == 9  ? value : null,
    to:          index == 10 ? value : null,
  );

  double get totalWidth =>
      amount + debitAc + ifsc + creditAc + code + beneficiary + place + bank + debitName + from + to;

  /// Flutter [TableColumnWidth] map — plug directly into [Table.columnWidths].
  Map<int, TableColumnWidth> get tableColumnWidths => {
    0:  FixedColumnWidth(amount),
    1:  FixedColumnWidth(debitAc),
    2:  FixedColumnWidth(ifsc),
    3:  FixedColumnWidth(creditAc),
    4:  FixedColumnWidth(code),
    5:  FixedColumnWidth(beneficiary),
    6:  FixedColumnWidth(place),
    7:  FixedColumnWidth(bank),
    8:  FixedColumnWidth(debitName),
    9:  FixedColumnWidth(from),
    10: FixedColumnWidth(to),
  };
}

// ── Preview widget ─────────────────────────────────────────────────────────────
class BankDisbursementPreview extends StatelessWidget {
  static const double a4Width    = 793.7;
  static const double a4Height   = 1122.5;
  static const int    _rowsPerPage = 30;

  final VoucherModel       voucher;
  final CompanyConfigModel config;
  final EdgeInsets         margins;
  final BankColWidths      colWidths;

  const BankDisbursementPreview({
    super.key,
    required this.voucher,
    required this.config,
    this.margins   = const EdgeInsets.all(20),
    this.colWidths = const BankColWidths(),
  });

  static List<Widget> buildPdfPages({
    required VoucherModel       voucher,
    required CompanyConfigModel config,
    EdgeInsets                  margins   = const EdgeInsets.all(20),
    BankColWidths               colWidths = const BankColWidths(),
  }) {
    final preview    = BankDisbursementPreview(
      voucher: voucher, config: config, margins: margins, colWidths: colWidths,
    );
    final sortedRows = _sorted(voucher.rows);
    final rowPages   = _chunkRows(sortedRows);

    final idbiOther = sortedRows
        .where((r) => !r.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, r) => a + r.amount);
    final idbiIdbi = sortedRows
        .where((r) => r.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, r) => a + r.amount);

    return List<Widget>.generate(
      rowPages.length,
      (i) => preview._buildPage(
        width:       a4Width,
        height:      a4Height,
        rows:        rowPages[i],
        showSummary: i == rowPages.length - 1,
        idbiOther:   idbiOther,
        idbiIdbi:    idbiIdbi,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = buildPdfPages(
      voucher: voucher, config: config, margins: margins, colWidths: colWidths,
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

  // ── Single A4 page ─────────────────────────────────────────────────────────
  Widget _buildPage({
    required double width,
    required double height,
    required List<VoucherRowModel> rows,
    required bool   showSummary,
    required double idbiOther,
    required double idbiIdbi,
  }) {
    return Container(
      width:  width,
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
          style: const TextStyle(fontSize: 10, color: Colors.black),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'AARTI ENTERPRISES : TRAVEL EXPENSES',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ✅ FIX: Center the table so margins appear symmetrical
              Center(
                child: _buildTable(rows, showTotal: showSummary),
              ),
              if (showSummary) ...[
                const SizedBox(height: 16),
                _buildSummary(idbiOther, idbiIdbi),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Table ──────────────────────────────────────────────────────────────────
  Widget _buildTable(List<VoucherRowModel> rows, {required bool showTotal}) {
    const headers = [
      'Amount', 'Debit A/c', 'IFSC', 'Credit A/c',
      'Code', 'Beneficiary', 'Place', 'Bank', 'Debit Name', 'Fr.', 'To',
    ];

    return Table(
      border:       TableBorder.all(color: Colors.black),
      columnWidths: colWidths.tableColumnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: headers
              .map((h) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(h,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ))
              .toList(),
        ),
        // Data rows
        ...rows.map((r) => TableRow(children: [
              _c(r.amount.toStringAsFixed(2), bold: true),
              _c(config.accountNo, mono: true),
              _c(r.ifscCode, mono: true),
              _c(r.accountNumber, mono: true),
              _c(r.sbCode),
              _c(r.employeeName),
              _c(r.branch),
              _c(r.bankDetails),
              _c(config.companyName),
              _c(_fmtDate(r.fromDate)),
              _c(_fmtDate(r.toDate)),
            ])),
        // Totals row
        if (showTotal)
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
            children: [
              _c(voucher.baseTotal.toStringAsFixed(2), bold: true),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  numberToWords(voucher.baseTotal),
                  style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              ...List.generate(9, (_) => _c('')),
            ],
          ),
      ],
    );
  }

  // ── Summary block ──────────────────────────────────────────────────────────
  Widget _buildSummary(double idbiOther, double idbiIdbi) => Container(
        width: 280,
        decoration: BoxDecoration(border: Border.all(color: Colors.black)),
        child: Column(children: [
          _summaryRow('1', 'From IDBI to Other Bank', idbiOther.toStringAsFixed(2)),
          _summaryRow('2', 'From IDBI to IDBI Bank',  idbiIdbi.toStringAsFixed(2)),
          Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.all(6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 9)),
              Text(voucher.baseTotal.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9)),
            ]),
          ),
        ]),
      );

  // ── Cell helpers ───────────────────────────────────────────────────────────
  static Widget _c(String t, {bool mono = false, bool bold = false}) => Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 9,
            fontFamily: mono ? 'monospace' : null,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );

  static Widget _summaryRow(String n, String label, String value) => Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black))),
        child: Row(children: [
          Text(n, style: const TextStyle(fontSize: 9)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 9))),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 9)),
        ]),
      );

  static String _fmtDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}';
    }
    return iso;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
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

  static List<List<VoucherRowModel>> _chunkRows(List<VoucherRowModel> rows) {
    if (rows.isEmpty) return const [[]];
    final chunks = <List<VoucherRowModel>>[];
    for (var i = 0; i < rows.length; i += _rowsPerPage) {
      final end = (i + _rowsPerPage).clamp(0, rows.length);
      chunks.add(rows.sublist(i, end));
    }
    return chunks;
  }
}