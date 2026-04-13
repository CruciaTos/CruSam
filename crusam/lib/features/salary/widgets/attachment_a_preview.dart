import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../features/master_data/notifiers/employee_notifier.dart';

class AttachmentAPreview extends StatelessWidget {
  static const double a4Width  = 793.7;
  static const double a4Height = 1122.5;

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

  // ── Live salary data (exact decimals) ─────────────────────────────────────
  final double itemAmount;       // Total Earned Gross
  final double pfAmount;         // 13.61% of Total Earned Basic
  final double esicAmount;       // 3.25% of Eligible Gross
  final double totalAfterTax;    // (ignored – kept for compatibility)

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

  // ─── Rounding helpers (only for final total & round‑off) ──────────────────
  double get _subtotal    => itemAmount + pfAmount + esicAmount;
  double get _roundedTotal => _subtotal.roundToDouble();
  double get _roundOff    => _roundedTotal - _subtotal;
  

  String get _roundOffFormatted {
    final sign = _roundOff >= 0 ? '+' : '';
    return '$sign${_roundOff.round().toString()}';   // whole rupees
  }

  static const _black   = Color(0xFF000000);
  static const _green   = Color(0xFF1A6B2F);
  static const _hdrBg   = Color(0xFFE3E8F4);
  static const _grandBg = Color(0xFFD6DCF5);
  static const _bSide   = BorderSide(color: _black, width: 0.75);
  static const _body    = TextStyle(fontSize: 9, color: _black, height: 1.45);

  static List<Widget> buildPdfPages({
    required CompanyConfigModel config,
    EdgeInsets margins = const EdgeInsets.all(24),
    double itemAmount = 0,
    double pfAmount   = 0,
    double esicAmount = 0,
    double totalAfterTax = 0, // ignored
  }) {
    final preview = AttachmentAPreview(
      config: config, margins: margins,
      itemAmount: itemAmount, pfAmount: pfAmount,
      esicAmount: esicAmount, totalAfterTax: totalAfterTax,
    );
    return [preview._buildPage(width: a4Width, height: a4Height)];
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: _buildPage(width: a4Width, height: a4Height));

  Widget _buildPage({required double width, required double height}) =>
      Container(
        width: width, height: height,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Padding(
          padding: margins,
          child: DefaultTextStyle(
            style: _body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 6),
                _divider(0.75),
                const SizedBox(height: 12),
                _centreLabel('Attachment A'),
                const SizedBox(height: 12),
                _billingInfo(),
                const SizedBox(height: 12),
                _mainTable(),
                const Spacer(),
                _footer(),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _logo(), const SizedBox(width: 20), Expanded(child: _companyInfo()),
    ],
  );

  Widget _logo() => SizedBox(
    width: 110, height: 75,
    child: Image.asset('assets/images/aarti_logo.png', fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const _FallbackLogo()),
  );

  Widget _companyInfo() => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(config.companyName.toUpperCase(), textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _green, letterSpacing: 0.6)),
      const SizedBox(height: 4),
      Text(config.address, textAlign: TextAlign.right, style: _body.copyWith(fontSize: 10)),
      const SizedBox(height: 2),
      Text('Tel.  Office  :  ${config.phone}', textAlign: TextAlign.right,
          style: _body.copyWith(fontSize: 10, fontWeight: FontWeight.w700)),
    ],
  );

  Widget _divider(double t) => Divider(color: _black, thickness: t, height: 4);

  Widget _centreLabel(String text) => Center(
    child: Text(text, style: _body.copyWith(
      fontSize: 13, fontWeight: FontWeight.w900,
      decoration: TextDecoration.underline, letterSpacing: 1.2,
    )),
  );

  Widget _billingInfo() => IntrinsicHeight(
    child: Container(
      decoration: BoxDecoration(border: Border.all(color: _black, width: 0.75)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 70,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BILL To,', style: _body),
              const SizedBox(height: 4),
              Text(customerName, style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 9.5)),
              const SizedBox(height: 2),
              Text(customerAddress, style: _body),
              const SizedBox(height: 10),
              Text('GST No. $customerGst', style: _body.copyWith(fontWeight: FontWeight.w700)),
            ]),
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
      ]),
    ),
  );

  Widget _kvRight(String k, String v) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [Text(k, style: _body), Text(v, style: _body)],
  );

  // ── Main Table — 3 columns only (Sr.No | Item Description | Amount) ────────
  Widget _mainTable() => Container(
    decoration: BoxDecoration(border: Border.all(color: _black, width: 0.75)),
    child: Column(children: [
      // Header — 3 columns
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _headerCell('Sr.\nNo', 5),
          _headerCell('Item Description', 80),
          _headerCell('AMOUNT', 15, rightBorder: false),
        ]),
      ),
      _divider(0.75),

      // Item row — 3 columns
      IntrinsicHeight(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 180),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _itemCell('1', 5),
            _itemCellDesc(itemDescription, 80, align: Alignment.topLeft),
            _itemCell(
              itemAmount == 0 ? '0.00' : itemAmount.toStringAsFixed(2),   // ← decimal
              15, rightBorder: false, align: Alignment.topRight,
            ),
          ]),
        ),
      ),
      _divider(0.75),

      // Totals area with rounding
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Left: bank details
          Expanded(
            flex: 70,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PAN NO :-  $panNo', style: _body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(children: [
                  Text('GSTIN :  $companyGst', style: _body.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 40),
                  Text('HSN: $hsnCode', style: _body.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 12),
                Text('Bank Details for  :  RTGS / NEFT', style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 10)),
                const SizedBox(height: 6),
                _bankRow('Bank Name', bankName),
                _bankRow('Branch', bankBranch),
                _bankRow('Account No.', accountNo),
                _bankRow('IFSC Code', ifscCode),
              ]),
            ),
          ),
          Container(width: 0.75, color: _black),
          // Right: live calculated totals with rounding
          Expanded(
            flex: 30,
            child: Column(children: [
              _multilineTotalRow(
                firstLine: 'P.F : 13.61 %',
                secondLine: '(Total Basic Salary)',
                value: pfAmount.toStringAsFixed(2),   // ← decimal
              ),
              _multilineTotalRow(
                firstLine: 'ESIC : 3.25 %',
                secondLine: '(Total Gross Salary of Eligibles)',
                value: esicAmount.toStringAsFixed(2), // ← decimal
              ),
              _roundUpRow('Round Up', _roundOffFormatted),
              _totalRow('Total Amount',
                '₹ ${_roundedTotal.round().toString()}',  // ← rounded whole rupees
                isBold: true, bgColor: _grandBg, isLast: true,
              ),
            ]),
          ),
        ]),
      ),
      _divider(0.75),

      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('Certified that particulars given above are true and correct.',
            style: _body.copyWith(fontStyle: FontStyle.italic, fontSize: 8)),
      ),
    ]),
  );

  Widget _headerCell(String text, int flex, {bool rightBorder = true}) => Expanded(
    flex: flex,
    child: Container(
      decoration: BoxDecoration(
        color: _hdrBg,
        border: rightBorder ? const Border(right: _bSide) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      alignment: Alignment.center,
      child: Text(text, textAlign: TextAlign.center,
          style: _body.copyWith(fontWeight: FontWeight.w800, fontSize: 8)),
    ),
  );

  Widget _itemCell(String text, int flex,
      {bool rightBorder = true, Alignment align = Alignment.topCenter}) =>
      Expanded(
        flex: flex,
        child: Container(
          decoration: BoxDecoration(border: rightBorder ? const Border(right: _bSide) : null),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: align,
          child: Text(text, style: _body.copyWith(fontSize: 8.5)),
        ),
      );

  Widget _itemCellDesc(String text, int flex,
      {bool rightBorder = true, Alignment align = Alignment.topCenter}) {
    final parts = text.split('(Vouchers');
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(border: rightBorder ? const Border(right: _bSide) : null),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        alignment: align,
        child: parts.length > 1
            ? RichText(text: TextSpan(style: _body.copyWith(fontSize: 8.5), children: [
                TextSpan(text: parts[0]),
                TextSpan(text: '(Vouchers${parts[1]}',
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 8)),
              ]))
            : Text(text, style: _body.copyWith(fontSize: 8.5)),
      ),
    );
  }

  Widget _bankRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: _body)),
      Text(':   $value', style: _body),
    ]),
  );

  Widget _totalRow(String label, String value,
      {bool isBold = false, Color? bgColor, bool isLast = false}) =>
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: isLast ? null : const Border(bottom: _bSide),
          ),
          child: Row(children: [
            Expanded(flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                alignment: Alignment.centerRight,
                child: Text(label, textAlign: TextAlign.right,
                    style: _body.copyWith(fontSize: 8, fontWeight: isBold ? FontWeight.w800 : FontWeight.normal)),
              ),
            ),
            Container(width: 0.75, color: _black),
            Expanded(flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                alignment: Alignment.centerRight,
                child: Text(value,
                    style: _body.copyWith(fontSize: 9, fontWeight: isBold ? FontWeight.w800 : FontWeight.normal)),
              ),
            ),
          ]),
        ),
      );

  Widget _multilineTotalRow({
    required String firstLine,
    required String secondLine,
    required String value,
  }) => Expanded(
    child: Container(
      decoration: const BoxDecoration(border: Border(bottom: _bSide)),
      child: Row(children: [
        Expanded(flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerRight,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(firstLine, textAlign: TextAlign.right,
                  style: AppTextStyles.bodyMedium.copyWith(fontSize: 8)),
              Text(secondLine, textAlign: TextAlign.right,
                  style: _body.copyWith(fontSize: 7, fontStyle: FontStyle.italic)),
            ]),
          ),
        ),
        Container(width: 0.75, color: _black),
        Expanded(flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerRight,
            child: Text(value, style: _body.copyWith(fontSize: 9)),
          ),
        ),
      ]),
    ),
  );

  Widget _roundUpRow(String label, String value) => Expanded(
    child: Container(
      decoration: const BoxDecoration(border: Border(bottom: _bSide)),
      child: Row(children: [
        Expanded(flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerRight,
            child: Text(label, textAlign: TextAlign.right,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 8)),
          ),
        ),
        Container(width: 0.75, color: _black),
        Expanded(flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerRight,
            child: Text(value, style: _body.copyWith(fontSize: 9)),
          ),
        ),
      ]),
    ),
  );

  Widget _footer() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Certified that particulars given above are true and correct.',
              style: _body.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Subject to Mumbai jurisdiction.', style: _body),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text('For AARTI ENTERPRISES',
            style: _body.copyWith(fontWeight: FontWeight.w800, color: _black.withOpacity(0.7))),
        const SizedBox(height: 45),
        Text('Partner', style: _body.copyWith(fontSize: 8.5)),
      ]),
    ],
  );

  
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();
  @override
  Widget build(BuildContext context) => Container(
    width: 110, height: 75,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(52),
      border: Border.all(color: const Color(0xFF1A237E), width: 3),
      color: const Color(0xFF1A237E),
    ),
    alignment: Alignment.center,
    child: const Text('Aarti\nEnterprises', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
  );
}