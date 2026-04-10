import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';

class VoucherPdfPreview extends StatelessWidget {
  final VoucherModel voucher;
  final CompanyConfigModel config;
  final EdgeInsets margins;

  const VoucherPdfPreview({
    super.key,
    required this.voucher,
    required this.config,
    this.margins = const EdgeInsets.all(24),
  });

  static const _black = Color(0xFF000000);
  static const _green = Color(0xFF1A6B2F);
  static const _hdrBg = Color(0xFFE3E8F4);
  static const _body = TextStyle(fontSize: 9, color: _black, height: 1.45);

  @override
  Widget build(BuildContext context) {
    const double a4Width = 793.7;
    const double a4Height = 1122.5;

    return Center(
      child: Container(
        width: a4Width,
        height: a4Height,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
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
                    Text(
                      'AARTI ENTERPRISES : ${voucher.title.isEmpty ? "Expenses Statement" : voucher.title}',
                      style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                    ),
                    Text(
                      voucher.deptCode,
                      style: _body.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Divider(color: _black),
                const SizedBox(height: 8),
                _buildTable(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatCurrency(voucher.baseTotal),
                          style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                        Text(
                          numberToWords(voucher.baseTotal),
                          style: _body.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    final sorted = _sorted(voucher.rows);
    const headers = ['Sr.', 'Debit A/c', 'IFSC', 'Credit A/c', 'Code', 'Name', 'Place', 'Bank', 'Fr.', 'To', 'Amount'];
    return Table(
      border: TableBorder.all(color: _black),
      columnWidths: const {
        0: FixedColumnWidth(24),
        10: FixedColumnWidth(60),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _hdrBg),
          children: headers
              .map((h) => Padding(
                    padding: const EdgeInsets.all(3),
                    child: Text(
                      h,
                      style: _body.copyWith(fontWeight: FontWeight.w800, fontSize: 8),
                    ),
                  ))
              .toList(),
        ),
        ...sorted.asMap().entries.map((e) {
          final i = e.key;
          final r = e.value;
          return TableRow(children: [
            _c('${i + 1}'),
            _c(config.accountNo, mono: true),
            _c(r.ifscCode, mono: true),
            _c(r.accountNumber, mono: true),
            _c(r.sbCode),
            _c(r.employeeName),
            _c(r.branch),
            _c(voucher.title),
            _c(_fmtDate(r.fromDate)),
            _c(_fmtDate(r.toDate)),
            _c(r.amount.toStringAsFixed(2), right: true),
          ]);
        }),
      ],
    );
  }

  static Widget _c(String t, {bool mono = false, bool right = false}) => Padding(
        padding: const EdgeInsets.all(2),
        child: Text(
          t,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(fontSize: 8, fontFamily: mono ? 'monospace' : null),
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
