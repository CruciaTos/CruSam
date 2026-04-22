import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';

class AttachmentAPreview extends StatelessWidget {
  static const double a4Width  = 793.7;
  static const double a4Height = 1122.5;

  // Reduced from 140 to 120 to save vertical space.
  static const double headerHeight = 120.0;

  final CompanyConfigModel config;
  final EdgeInsets margins;

  final String customerName;
  final String customerAddress;
  final String customerGst;
  final String billNo;
  final String date;
  final String poNo;
  final String itemDescription;
  final String panNo;
  final String companyGst;
  final String hsnCode;
  final String bankName;
  final String bankBranch;
  final String accountNo;
  final String ifscCode;

  final double itemAmount;
  final double pfAmount;
  final double esicAmount;
  final double totalAfterTax; // kept for compatibility

  const AttachmentAPreview({
    super.key,
    required this.config,
    this.margins         = const EdgeInsets.all(24),
    this.customerName    = 'M/s Diversey India Hygiene Private Ltd.',
    this.customerAddress = '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093',
    this.customerGst     = '27AABCC1597Q1Z2',
    this.billNo          = 'AE/-/25-26',
    this.date            = '2026-04-11',
    this.poNo            = '-',
    this.itemDescription = 'Manpower Supply Charges',
    this.panNo           = 'AAQFA5248L',
    this.companyGst      = '27AAQFA5248L2ZW',
    this.hsnCode         = 'SAC99851',
    this.bankName        = 'IDBI Bank Ltd.',
    this.bankBranch      = 'Dahisar - East',
    this.accountNo       = '0680651100000338',
    this.ifscCode        = 'IBKL0000680',
    this.itemAmount      = 0,
    this.pfAmount        = 0,
    this.esicAmount      = 0,
    this.totalAfterTax   = 0,
  });

  double get _subtotal      => itemAmount + pfAmount + esicAmount;
  double get _roundedTotal  => _subtotal.roundToDouble();
  double get _roundOff      => _roundedTotal - _subtotal;

  String get _roundOffFormatted {
    final sign = _roundOff >= 0 ? '+' : '';
    return '$sign${_roundOff.round().toString()}';
  }

  static const _black   = Color(0xFF000000);
  static const _green   = Color(0xFF1A6B2F);
  static const _hdrBg   = Color(0xFFE3E8F4);
  static const _grandBg = Color(0xFFD6DCF5);
  static const _bSide   = BorderSide(color: _black, width: 0.75);
  static const _body    = TextStyle(fontSize: 11, color: _black, height: 1.45);

  static String _multiline(String text) =>
      text.replaceAll('//', '\n').replaceAll('/n', '\n');

  static List<Widget> buildPdfPages({
    required CompanyConfigModel config,
    EdgeInsets margins = const EdgeInsets.all(24),
    double itemAmount = 0,
    double pfAmount   = 0,
    double esicAmount = 0,
    double totalAfterTax = 0,
    required String billNo,
    required String date,
    required String poNo,
    required String itemDescription,
    required String customerName,
    required String customerAddress,
    required String customerGst,
  }) {
    final preview = AttachmentAPreview(
      config: config,
      margins: margins,
      itemAmount: itemAmount,
      pfAmount: pfAmount,
      esicAmount: esicAmount,
      totalAfterTax: totalAfterTax,
      billNo: billNo,
      date: date,
      poNo: poNo,
      itemDescription: itemDescription,
      customerName: customerName,
      customerAddress: customerAddress,
      customerGst: customerGst,
    );
    return [preview._buildPage(width: a4Width, height: a4Height)];
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: _buildPage(width: a4Width, height: a4Height));

  Widget _buildPage({required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))
          ],
        ),
        child: Padding(
          padding: margins,
          child: DefaultTextStyle(
            style: _body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 4),   // reduced from 6
                _divider(0.75),
                const SizedBox(height: 8),   // reduced from 12
                _centreLabel('Attachment A'),
                const SizedBox(height: 8),   // reduced from 12
                _billingInfo(),
                const SizedBox(height: 8),   // reduced from 12
                _mainTable(),
                const SizedBox(height: 4),   // reduced from 12
                _footer(),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _logo(),
      const SizedBox(width: 20),
      Expanded(child: _letterheadImage()),
    ],
  );

  Widget _logo() => SizedBox(
    width: 140,
    height: headerHeight,
    child: Image.asset(
      'assets/images/aarti_logo.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const _FallbackLogo(),
    ),
  );

  Widget _letterheadImage() => SizedBox(
    height: headerHeight,
    child: Image.asset(
      'assets/images/letterhead.png',
      fit: BoxFit.contain,
      alignment: Alignment.centerRight,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    ),
  );

  Widget _divider(double t) => Divider(color: _black, thickness: t, height: 4);

  Widget _centreLabel(String text) => Center(
    child: Text(
      text,
      style: _body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w900,
        decoration: TextDecoration.underline,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _billingInfo() => IntrinsicHeight(
    child: Container(
      decoration: BoxDecoration(border: Border.all(color: _black, width: 0.75)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 70,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // reduced
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BILL To,', style: _body),
                  const SizedBox(height: 4),
                  Text(_multiline(customerName),
                      style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(_multiline(customerAddress), style: _body),
                  const SizedBox(height: 8), // reduced from 10
                  Text('GST No. $customerGst', style: _body.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          Container(width: 0.75, color: _black),
          Expanded(
            flex: 30,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _kvRight('Bill No :- ', billNo),
                  const SizedBox(height: 4),
                  _kvRight('Date :- ', date),
                  const SizedBox(height: 4),
                  _kvRight('PO.No. :- ', poNo),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _kvRight(String k, String v) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text(k, style: _body.copyWith(fontSize: 12)),
      Text(v, style: _body.copyWith(fontSize: 12)),
    ],
  );

  Widget _mainTable() => Container(
    decoration: BoxDecoration(border: Border.all(color: _black, width: 0.75)),
    child: Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerCell('Sr.\nNo', 5),
              _headerCell('Item Description', 80),
              _headerCell('AMOUNT', 15, rightBorder: false),
            ],
          ),
        ),
        _divider(0.75),

        IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 130), // reduced from 180
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _itemCell('1', 5),
                _itemCellDesc(itemDescription, 80, align: Alignment.topLeft),
                _itemCell(
                  itemAmount == 0 ? '0.00' : itemAmount.toStringAsFixed(2),
                  15,
                  rightBorder: false,
                  align: Alignment.topRight,
                ),
              ],
            ),
          ),
        ),
        _divider(0.75),

        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 70,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // reduced from 6
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PAN NO :-  $panNo', style: _body.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('GSTIN :  $companyGst', style: _body.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 40),
                          Text('HSN: $hsnCode', style: _body.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8), // reduced from 12
                      Text(
                        'Bank Details for  :  RTGS / NEFT',
                        style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const SizedBox(height: 4), // reduced from 6
                      _bankRow('Bank Name', bankName),
                      _bankRow('Branch', bankBranch),
                      _bankRow('Account No.', accountNo),
                      _bankRow('IFSC Code', ifscCode),
                    ],
                  ),
                ),
              ),
              Container(width: 0.75, color: _black),
              Expanded(
                flex: 30,
                child: Column(
                  children: [
                    _multilineTotalRow(
                      firstLine: 'P.F : 13.61 %',
                      secondLine: '(Total Basic Salary)',
                      value: pfAmount.toStringAsFixed(2),
                    ),
                    _multilineTotalRow(
                      firstLine: 'ESIC : 3.25 %',
                      secondLine: '(Total Gross Salary of Eligibles)',
                      value: esicAmount.toStringAsFixed(2),
                    ),
                    _roundUpRow('Round Up', _roundOffFormatted),
                    _totalRow(
                      'Total Amount',
                      '₹ ${_roundedTotal.round().toString()}',
                      isBold: true,
                      bgColor: _grandBg,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _divider(0.75),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), // reduced from 4
          child: Text(
            '',
            style: _body.copyWith(fontStyle: FontStyle.italic, fontSize: 10),
          ),
        ),
      ],
    ),
  );

  Widget _headerCell(String text, int flex, {bool rightBorder = true}) => Expanded(
    flex: flex,
    child: Container(
      decoration: BoxDecoration(
        color: _hdrBg,
        border: rightBorder ? const Border(right: _bSide) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), // reduced from 8
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _body.copyWith(fontWeight: FontWeight.w800, fontSize: 10),
      ),
    ),
  );

  Widget _itemCell(String text, int flex,
      {bool rightBorder = true, Alignment align = Alignment.topCenter}) =>
      Expanded(
        flex: flex,
        child: Container(
          decoration: BoxDecoration(border: rightBorder ? const Border(right: _bSide) : null),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), // reduced from 8
          alignment: align,
          child: Text(text, style: _body.copyWith(fontSize: 12)),
        ),
      );

  Widget _itemCellDesc(String text, int flex,
      {bool rightBorder = true, Alignment align = Alignment.topCenter}) {
    final normalized = _multiline(text);
    final parts = normalized.split('(Vouchers');
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(border: rightBorder ? const Border(right: _bSide) : null),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), // reduced from 8
        alignment: align,
        child: parts.length > 1
            ? RichText(
                text: TextSpan(
                  style: _body.copyWith(fontSize: 12),
                  children: [
                    TextSpan(text: parts[0]),
                    TextSpan(
                      text: '(Vouchers${parts[1]}',
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
                    ),
                  ],
                ),
              )
            : Text(normalized, style: _body.copyWith(fontSize: 12)),
      ),
    );
  }

  Widget _bankRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: _body)),
        Text(':   $value', style: _body),
      ],
    ),
  );

  Widget _totalRow(String label, String value,
      {bool isBold = false, Color? bgColor, bool isLast = false}) =>
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: isLast ? null : const Border(bottom: _bSide),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
                  alignment: Alignment.centerRight,
                  child: Text(
                    label,
                    textAlign: TextAlign.right,
                    style: _body.copyWith(
                      fontSize: 10,
                      fontWeight: isBold ? FontWeight.w800 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              Container(width: 0.75, color: _black),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: _body.copyWith(
                      fontSize: 11,
                      fontWeight: isBold ? FontWeight.w800 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _multilineTotalRow({
    required String firstLine,
    required String secondLine,
    required String value,
  }) => Expanded(
    child: Container(
      decoration: const BoxDecoration(border: Border(bottom: _bSide)),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(firstLine, textAlign: TextAlign.right, style: _body.copyWith(fontSize: 10)),
                  Text(secondLine, textAlign: TextAlign.right, style: _body.copyWith(fontSize: 9, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ),
          Container(width: 0.75, color: _black),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
              alignment: Alignment.centerRight,
              child: Text(value, style: _body.copyWith(fontSize: 11)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _roundUpRow(String label, String value) => Expanded(
    child: Container(
      decoration: const BoxDecoration(border: Border(bottom: _bSide)),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
              alignment: Alignment.centerRight,
              child: Text(label, textAlign: TextAlign.right, style: _body.copyWith(fontSize: 10)),
            ),
          ),
          Container(width: 0.75, color: _black),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3), // reduced from 4
              alignment: Alignment.centerRight,
              child: Text(value, style: _body.copyWith(fontSize: 11)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _footer() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      const Divider(color: _black, thickness: 0.5),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '',
              style: _body.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('', style: _body),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/aarti_signature.png',
            height: 60,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('For AARTI ENTERPRISES',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text('Partner', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();
  @override
  Widget build(BuildContext context) => Container(
    width: 110,
    height: AttachmentAPreview.headerHeight,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(52),
      border: Border.all(color: const Color(0xFF1A237E), width: 3),
      color: const Color(0xFF1A237E),
    ),
    alignment: Alignment.center,
    child: const Text(
      'Aarti\nEnterprises',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
    ),
  );
}