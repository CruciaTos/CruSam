import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/company_config_model.dart';

class TaxInvoicePreview extends StatelessWidget {
  final VoucherModel voucher;
  final CompanyConfigModel config;
  const TaxInvoicePreview({super.key, required this.voucher, required this.config});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(24),
    child: DefaultTextStyle(
      style: const TextStyle(fontSize: 11, color: Colors.black, fontFamily: 'monospace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Divider(color: Colors.black, thickness: 2),
          const SizedBox(height: 12),
          _billInfo(),
          const SizedBox(height: 12),
          _table(),
          const SizedBox(height: 12),
          _footer(),
          const SizedBox(height: 24),
          _signature(),
        ],
      ),
    ),
  );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(border: Border.all(color: AppColors.slate300), borderRadius: BorderRadius.circular(28)),
        alignment: Alignment.center,
        child: const Text('Aarti\nEnterprises', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: AppColors.indigo600)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AARTI ENTERPRISES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
          Text(config.address, style: const TextStyle(fontSize: 9)),
          Text('Tel. Office: ${config.phone}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
      const Text('TAX INVOICE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ],
  );

  Widget _billInfo() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BILL To,', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(voucher.clientName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(voucher.clientAddress, style: const TextStyle(fontSize: 9)),
          Text('GST No. ${voucher.clientGstin}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Bill No: ${voucher.billNo.isEmpty ? 'AE/-/25-26' : voucher.billNo}'),
        Text('Date: ${voucher.date}'),
        Text('PO. No.: ${voucher.poNo.isEmpty ? '-' : voucher.poNo}'),
      ]),
    ],
  );

  Widget _table() => Table(
    border: TableBorder.all(color: Colors.black, width: 1.5),
    columnWidths: const {
      0: FixedColumnWidth(40),
      1: FixedColumnWidth(70),
      2: FixedColumnWidth(70),
      3: FlexColumnWidth(),
      4: FixedColumnWidth(50),
      5: FixedColumnWidth(60),
      6: FixedColumnWidth(80),
    },
    children: [
      _tableHeader(),
      TableRow(children: [
        _tc('1'),
        _tc(''),
        _tc(''),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(voucher.itemDescription),
            const SizedBox(height: 60),
            const Text('( Vouchers attached with this original bill )',
                textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, fontSize: 9)),
          ]),
        ),
        _tc(''),
        _tc(''),
        _tc(voucher.baseTotal.toStringAsFixed(2), align: TextAlign.right, bold: true),
      ]),
    ],
  );

  TableRow _tableHeader() => TableRow(children: [
    _tc('Sr.', bold: true), _tc('Date Fr.', bold: true), _tc('Date To', bold: true),
    _tc('Item Description', bold: true), _tc('QTY', bold: true),
    _tc('RATE', bold: true), _tc('AMOUNT', bold: true),
  ]);

  static Widget _tc(String t, {TextAlign align = TextAlign.center, bool bold = false}) => Padding(
    padding: const EdgeInsets.all(6),
    child: Text(t, textAlign: align,
        style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 10)),
  );

  Widget _footer() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PAN NO: ${config.pan}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('GSTIN: ${config.gstin}  HSN: SAC99851', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Bank Details for: RTGS / NEFT'),
          Text('Bank Name: ${config.bankName}'),
          Text('Branch: ${config.branch}'),
          Text('Account No.: ${config.accountNo}'),
          Text('IFSC Code: ${config.ifscCode}'),
        ]),
      ),
      const SizedBox(width: 16),
      Container(
        width: 260,
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Colors.black, width: 1.5))),
        child: Column(children: [
          _summaryRow('Total before Tax', voucher.baseTotal.toStringAsFixed(2)),
          _summaryRow('CGST 9%', voucher.cgst.toStringAsFixed(2)),
          _summaryRow('SGST 9%', voucher.sgst.toStringAsFixed(2)),
          const Divider(color: Colors.black),
          _summaryRow('Total Tax', voucher.totalTax.toStringAsFixed(2), bold: true),
          _summaryRow('Round Up', voucher.roundOff.toStringAsFixed(2)),
          const Divider(color: Colors.black, thickness: 2),
          _summaryRow('Total after Tax', voucher.finalTotal.toStringAsFixed(2), bold: true, big: true),
        ]),
      ),
    ],
  );

  static Widget _summaryRow(String l, String v, {bool bold = false, bool big = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: big ? 11 : 10, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      Text(v, style: TextStyle(fontSize: big ? 13 : 10, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    ]),
  );

  Widget _signature() => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
    Column(children: [
      Text(config.declarationText, style: const TextStyle(fontSize: 9)),
      const SizedBox(height: 32),
      const Text('For AARTI ENTERPRISES', style: TextStyle(fontWeight: FontWeight.w700)),
      const Divider(color: Colors.black),
      const Text('Partner'),
    ]),
  ]);
}