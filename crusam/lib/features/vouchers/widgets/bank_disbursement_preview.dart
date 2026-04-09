import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/format_utils.dart';

class BankDisbursementPreview extends StatelessWidget {
  final VoucherModel voucher;
  final CompanyConfigModel config;
  const BankDisbursementPreview({super.key, required this.voucher, required this.config});

  @override
  Widget build(BuildContext context) {
    const double a4Width = 793.7;
    const double a4Height = 1122.5; // 297mm at 96 PPI

    final idbiOther = voucher.rows
        .where((r) => !r.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, r) => a + r.amount);
    final idbiIdbi = voucher.rows
        .where((r) => r.ifscCode.startsWith('IDIB'))
        .fold(0.0, (a, r) => a + r.amount);

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
          padding: const EdgeInsets.all(20),
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
                        fontSize: 12,
                        decoration: TextDecoration.underline),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTable(),
                const SizedBox(height: 16),
                _buildSummary(idbiOther, idbiIdbi),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    const headers = [
      'Amount',
      'Debit A/c',
      'IFSC',
      'Credit A/c',
      'Code',
      'Beneficiary',
      'Place',
      'Bank',
      'Debit Name'
    ];
    return Table(
      border: TableBorder.all(color: Colors.black),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
          children: headers
              .map((h) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(h,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 9)),
                  ))
              .toList(),
        ),
        ...voucher.rows.map((r) => TableRow(children: [
              _c(r.amount.toStringAsFixed(2), bold: true),
              _c(config.accountNo, mono: true),
              _c(r.ifscCode, mono: true),
              _c(r.accountNumber, mono: true),
              _c(r.sbCode),
              _c(r.employeeName),
              _c(r.branch),
              _c(r.bankDetails),
              _c(config.companyName),
            ])),
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
          children: [
            _c(voucher.baseTotal.toStringAsFixed(2), bold: true),
            Padding(
              padding: const EdgeInsets.all(4),
              child: TableCell(
                child: Text(numberToWords(voucher.baseTotal),
                    style:
                        const TextStyle(fontStyle: FontStyle.italic, fontSize: 9)),
              ),
            ),
            ...List.generate(7, (_) => _c('')),
          ],
        ),
      ],
    );
  }

  static Widget _c(String t, {bool mono = false, bool bold = false}) => Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 9,
            fontFamily: mono ? 'monospace' : null,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );

  Widget _buildSummary(double idbiOther, double idbiIdbi) => Container(
        width: 280,
        decoration: BoxDecoration(border: Border.all(color: Colors.black)),
        child: Column(children: [
          _summaryRow('1', 'From IDBI to Other Bank', idbiOther.toStringAsFixed(2)),
          _summaryRow('2', 'From IDBI to IDBI Bank', idbiIdbi.toStringAsFixed(2)),
          Container(
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.all(6),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 9)),
                  Text(voucher.baseTotal.toStringAsFixed(2),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 9)),
                ]),
          ),
        ]),
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
}