import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';

/// Excel-style Tax Invoice Preview – A4 print ready.
class TaxInvoicePreview extends StatelessWidget {
  static const double a4Width = 793.7;
  static const double a4Height = 1122.5;

  final VoucherModel voucher;
  final CompanyConfigModel config;
  final EdgeInsets margins;

  const TaxInvoicePreview({
    super.key,
    required this.voucher,
    required this.config,
    this.margins = const EdgeInsets.all(24),
  });

  // ── Palette ────────────────────────────────────────────────────────────────
  static const _black = Color(0xFF000000);
  static const _green = Color(0xFF1A6B2F);
  static const _hdrBg = Color(0xFFE3E8F4);
  static const _grandBg = Color(0xFFD6DCF5);

  static const _bSide = BorderSide(color: _black, width: 0.75);
  static const _bSideThin = BorderSide(color: _black, width: 0.5);

  // ── Typography ─────────────────────────────────────────────────────────────
  static const _body = TextStyle(fontSize: 9, color: _black, height: 1.45);

  // ── Fixed column widths ────────────────────────────────────────────────────
  static const _wSr = 28.0;
  static const _wDateFr = 58.0;
  static const _wDateTo = 58.0;
  static const _wQty = 36.0;
  static const _wRate = 50.0;
  static const _wAmt = 90.0;

  static List<Widget> buildPdfPages({
    required VoucherModel voucher,
    required CompanyConfigModel config,
    EdgeInsets margins = const EdgeInsets.all(24),
  }) {
    final preview = TaxInvoicePreview(
      voucher: voucher,
      config: config,
      margins: margins,
    );

    return [
      preview._buildPage(width: a4Width, height: a4Height),
    ];
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: _buildPage(width: a4Width, height: a4Height));

  Widget _buildPage({required double width, required double height}) => Container(
        width: width,
        height: height,
        clipBehavior:
            Clip.hardEdge, // hard clip — nothing bleeds outside the page
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [
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
                _header(),
                const SizedBox(height: 2),   // reduced from 4
                _divider(0.8),
                const SizedBox(height: 8),   // reduced from 10
                _taxInvoiceLabel(),
                const SizedBox(height: 6),   // reduced from 8
                _billToSection(),
                const SizedBox(height: 10),  // reduced from 12
                _itemTable(),
                const SizedBox(height: 12),  // reduced from 16
                _belowTableSection(),
              ],
            ),
          ),
        ),
      );

  // ── HEADER ─────────────────────────────────────────────────────────────────
  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _logo(),
      const SizedBox(width: 20),
      Expanded(child: _companyInfo()),
    ],
  );

  Widget _logo() => SizedBox(
    width: 110,
    height: 75,   // reduced from 90
    child: Image.asset(
      'assets/images/aarti_logo.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const _FallbackLogo(),
    ),
  );

  Widget _companyInfo() => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        config.companyName.toUpperCase(),
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: _green,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        config.address,
        textAlign: TextAlign.right,
        style: _body.copyWith(fontSize: 10),
      ),
      const SizedBox(height: 2),
      Text(
        'Tel.  Office  :  ${config.phone}',
        textAlign: TextAlign.right,
        style: _body.copyWith(fontSize: 10, fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _divider(double t) => Divider(color: _black, thickness: t, height: 4);   // reduced from 6

  Widget _taxInvoiceLabel() => Center(
    child: Text(
      'TAX INVOICE',
      style: _body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        decoration: TextDecoration.underline,
        letterSpacing: 1.2,
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // BILL TO – full-width bordered box (reference image has outer border)
  // Layout: "BILL To," header, then address LEFT + Bill/Date/PO RIGHT,
  //         then GST line spanning full width at bottom.
  // ══════════════════════════════════════════════════════════════════════════
  Widget _billToSection() => Container(
    decoration: BoxDecoration(border: Border.all(color: _black, width: 0.75)),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),   // reduced from 6
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BILL To,', style: _body.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        // Client name (left) | Bill No (right)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                voucher.clientName,
                style: _body.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            _refRow(
              'Bill No',
              voucher.billNo.isEmpty ? 'AE/-/25-26' : voucher.billNo,
            ),
          ],
        ),
        // Address (left) | Date (right)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(voucher.clientAddress, style: _body)),
            _refRow('Date', voucher.date),
          ],
        ),
        const SizedBox(height: 2),
        // GST (left) | PO No (right)
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('(F & B)', style: _body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'GST No. ${voucher.clientGstin}',
                style: _body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _refRow('PO.No.', voucher.poNo.isEmpty ? '-' : voucher.poNo),
          ],
        ),
      ],
    ),
  );

  Widget _refRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Text('$label :-  ', style: _body.copyWith(fontWeight: FontWeight.w600)),
        Text(value, style: _body),
      ],
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // ITEM TABLE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _itemTable() => LayoutBuilder(
    builder: (ctx, bc) {
      final fixedWidth = _wSr + _wDateFr + _wDateTo + _wQty + _wRate + _wAmt;
      final descW = (bc.maxWidth - fixedWidth - 2.0).clamp(
        0.0,
        double.infinity,
      );

      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: _black, width: 0.9),
        ),
        child: Column(
          children: [
            _headerRow(descW),
            _dataRow(descW),
            _tableBottom(descW),
            _declarationRow(),
          ],
        ),
      );
    },
  );

  // ── Column headers (updated to match reference: "Sr. No", "Date upto") ─────
  Widget _headerRow(double descW) => Container(
    decoration: const BoxDecoration(
      color: _hdrBg,
      border: Border(bottom: _bSide),
    ),
    child: Row(
      children: [
        _hCell('Sr. No', _wSr, center: true),
        _hCell('Date Fr.', _wDateFr, center: true),
        _hCell('Date upto', _wDateTo, center: true),
        _hCell('Item Description', descW),
        _hCell('QTY', _wQty, center: true),
        _hCell('RATE', _wRate, center: true),
        _hCell('AMOUNT', _wAmt, center: true, isLast: true),
      ],
    ),
  );

  // ── Data row – QTY and RATE blank per reference image ──────────────────────
  Widget _dataRow(double descW) {
    final sorted = _sorted(voucher.rows);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: _bSide)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dCell('1', _wSr, center: true),
            _dCell(
              _fmtDate(sorted.isNotEmpty ? sorted.first.fromDate : ''),
              _wDateFr,
              center: true,
            ),
            _dCell(
              _fmtDate(sorted.isNotEmpty ? sorted.last.toDate : ''),
              _wDateTo,
              center: true,
            ),
            Container(
              width: descW,
              decoration: const BoxDecoration(border: Border(right: _bSide)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),   // reduced from 12
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(voucher.itemDescription, style: _body),
                  const SizedBox(height: 6),   // reduced from 12
                  const Text(
                    '( Vouchers attached with this original bill )',
                    style: TextStyle(
                      fontSize: 8,
                      fontStyle: FontStyle.italic,
                      color: _black,
                    ),
                  ),
                ],
              ),
            ),
            _dCell('', _wQty, center: true),
            _dCell('', _wRate, center: true),
            _dCell(
              voucher.baseTotal.toStringAsFixed(2),
              _wAmt,
              right: true,
              bold: true,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TABLE BOTTOM
  //
  // Column mapping (reference image):
  //  ┌─Sr─┬─DateFr─┬─DateTo─┬──────── descW ────────┐  ← bankInfoW
  //                                                    ├─QTY─┬─RATE─┤  ← taxLabelW
  //                                                                   ├──AMOUNT──┤
  //
  //  bankInfoW = wSr + wDateFr + wDateTo + descW
  //  taxLabelW = wQty + wRate
  //  valueW    = wAmt
  // ══════════════════════════════════════════════════════════════════════════
  Widget _tableBottom(double descW) {
    final bankInfoW = _wSr + _wDateFr + _wDateTo + descW;
    final taxLabelW = _wQty + _wRate;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── LEFT: PAN / GSTIN / HSN + bank details (full-height merged cell)
          Container(
            width: bankInfoW,
            decoration: const BoxDecoration(border: Border(right: _bSide)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),   // reduced from 6
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAN NO :-  ${config.pan}',
                  style: _body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'GSTIN  :  ${config.gstin}          HSN: SAC99851',
                  style: _body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'Bank Details for   :  RTGS / NEFT',
                  style: _body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                _bankLine('Bank Name', config.bankName),
                _bankLine('Branch', config.branch),
                _bankLine('Account No.', config.accountNo),
                _bankLine('IFSC Code', config.ifscCode),
              ],
            ),
          ),
          // ── RIGHT: individual tax rows (each has its own top divider line)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btaxRow(
                taxLabelW,
                'Total amount before Tax',
                voucher.baseTotal.toStringAsFixed(2),
              ),
              _btaxRow(
                taxLabelW,
                'Add : CGST 9%',
                voucher.cgst.toStringAsFixed(2),
              ),
              _btaxRow(
                taxLabelW,
                'Add : SGST 9%',
                voucher.sgst.toStringAsFixed(2),
              ),
              _btaxRow(
                taxLabelW,
                'Total Tax Amount',
                voucher.totalTax.toStringAsFixed(2),
                bold: true,
              ),
              _btaxRow(
                taxLabelW,
                'Round Up',
                '${voucher.roundOff >= 0 ? '+' : ''}${voucher.roundOff.toStringAsFixed(2)}',
              ),
              _btaxGrand(
                taxLabelW,
                'Total Amount after Tax',
                '₹ ${voucher.finalTotal.toStringAsFixed(2)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Single label:value row inside bank info left block.
  Widget _bankLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 1),   // reduced from 2
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: _body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        Flexible(
          child: Text(
            ':  $value',
            style: _body.copyWith(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  /// Tax summary row in right block with top separator.
  Widget _btaxRow(
    double labelW,
    String label,
    String value, {
    bool bold = false,
  }) => Container(
    decoration: const BoxDecoration(border: Border(top: _bSideThin)),
    child: Row(
      children: [
        Container(
          width: labelW,
          decoration: const BoxDecoration(border: Border(right: _bSide)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),   // reduced from 4
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: _body.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        SizedBox(
          width: _wAmt,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),   // reduced from 4
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: _body.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Grand total row – highlighted + bold.
  Widget _btaxGrand(double labelW, String label, String value) => Container(
    decoration: const BoxDecoration(
      color: _grandBg,
      border: Border(top: _bSide),
    ),
    child: Row(
      children: [
        Container(
          width: labelW,
          decoration: const BoxDecoration(border: Border(right: _bSide)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),   // reduced from 6
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: _body.copyWith(fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ),
        SizedBox(
          width: _wAmt,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),   // reduced from 6
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: _body.copyWith(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    ),
  );

  /// Full-width declaration row – last row inside the table outer border.
  Widget _declarationRow() => Container(
    decoration: const BoxDecoration(border: Border(top: _bSide)),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),   // reduced from 5
    child: Text(
      config.declarationText,
      style: _body.copyWith(fontStyle: FontStyle.italic, fontSize: 8.5),
    ),
  );

  // ── Table cell builders ────────────────────────────────────────────────────
  Widget _hCell(
    String t,
    double w, {
    bool center = false,
    bool isLast = false,
  }) => Container(
    width: w,
    decoration: BoxDecoration(
      border: Border(right: isLast ? BorderSide.none : _bSide),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    child: Text(
      t,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: _body.copyWith(fontSize: 9, fontWeight: FontWeight.w800),
    ),
  );

  Widget _dCell(
    String t,
    double w, {
    bool center = false,
    bool right = false,
    bool bold = false,
    bool isLast = false,
  }) => Container(
    width: w,
    decoration: BoxDecoration(
      border: Border(right: isLast ? BorderSide.none : _bSide),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    child: Text(
      t,
      textAlign:
          right
              ? TextAlign.right
              : center
              ? TextAlign.center
              : TextAlign.left,
      style: _body.copyWith(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // BELOW TABLE – certification text (left) + "For Company" + signature (right)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _belowTableSection() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      // Left: bold certification + jurisdiction line
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Certified that particulars given above are true and correct.',
              style: _body.copyWith(fontWeight: FontWeight.w700, fontSize: 9),
            ),
            const SizedBox(height: 2),
            Text(
              'Subject to Mumbai jurisdiction.',
              style: _body.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
      // Right: company name label + signature image
      Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          SizedBox(
            width: 200,
            height: 90,   // reduced from 130
            child: Image.asset(
              'assets/images/aarti_signature.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
        ],
      ),
    ],
  );

  // ── Helpers ────────────────────────────────────────────────────────────────
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

// ── Fallback logo (asset not found) ───────────────────────────────────────────
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) => Container(
    width: 110,
    height: 75,   // reduced from 90 to match _logo
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(52),
      border: Border.all(color: const Color(0xFF1A237E), width: 3),
      color: const Color(0xFF1A237E),
    ),
    alignment: Alignment.center,
    child: const Text(
      'Aarti\nEnterprises',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}