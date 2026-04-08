import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';

class VoucherPdfPreview extends StatelessWidget {
  final VoucherModel voucher;
  final CompanyConfigModel config;
  const VoucherPdfPreview({super.key, required this.voucher, required this.config});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 9, color: Colors.black, fontFamily: 'monospace'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            'AARTI ENTERPRISES : ${voucher.title.isEmpty ? "Expenses Statement" : voucher.title}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
          ),
          Text(voucher.deptCode, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const Divider(color: Colors.black),
        const SizedBox(height: 8),
        _buildTable(),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatCurrency(voucher.baseTotal), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            Text(numberToWords(voucher.baseTotal), style: const TextStyle(fontStyle: FontStyle.italic)),
          ]),
        ]),
      ]),
    ),
  );

  Widget _buildTable() {
    const headers = ['Sr.', 'Debit A/c', 'IFSC', 'Credit A/c', 'Code', 'Name', 'Place', 'Bank', 'Fr.', 'To', 'Amount'];
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {
        0: FixedColumnWidth(24),
        10: FixedColumnWidth(60),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
          children: headers.map((h) => Padding(
            padding: const EdgeInsets.all(3),
            child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 8)),
          )).toList(),
        ),
        ...voucher.rows.asMap().entries.map((e) {
          final i = e.key; final r = e.value;
          return TableRow(children: [
            _c('${i + 1}'), _c(config.accountNo, mono: true),
            _c(r.ifscCode, mono: true), _c(r.accountNumber, mono: true),
            _c(r.sbCode), _c(r.employeeName),
            _c(r.branch), _c(voucher.title),
            _c(r.fromDate), _c(r.toDate),
            _c(r.amount.toStringAsFixed(2), right: true),
          ]);
        }),
      ],
    );
  }

  static Widget _c(String t, {bool mono = false, bool right = false}) => Padding(
    padding: const EdgeInsets.all(2),
    child: Text(t,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: TextStyle(fontSize: 8, fontFamily: mono ? 'monospace' : null),
    ),
  );
}