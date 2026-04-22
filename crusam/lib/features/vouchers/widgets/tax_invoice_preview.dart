import 'package:flutter/material.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../data/models/company_config_model.dart';

/// Excel-style Tax Invoice Preview – A4 print ready.
class TaxInvoicePreview extends StatelessWidget {
  static const double a4Width = 793.7;
  static const double a4Height = 1122.5;

  // ---------- Configurable Header Height ----------
  // Change this value to adjust both logo and letterhead image heights.
  // The divider and all content below will automatically shift.
  static const double headerHeight = 140.0;
  // ------------------------------------------------

  final VoucherModel voucher;
  final CompanyConfigModel config;
  final EdgeInsets margins;

  const TaxInvoicePreview({
    super.key,
    required this.voucher,
    required this.config,
    this.margins = const EdgeInsets.all(24),
  });

  // ── Design Constants ───────────────────────────────────────────────────────
  static const _black = Color(0xFF000000);
  static const _green = Color(0xFF1A6B2F);
  static const _headerBg = Color(0xFFE3E8F4);
  static const _grandTotalBg = Color(0xFFD6DCF5);
  static const _borderSide = BorderSide(color: _black, width: 0.75);
  static const _thinBorderSide = BorderSide(color: _black, width: 0.5);

  static const _bodyStyle = TextStyle(fontSize: 10, color: _black, height: 1.85);

  static const _colSr = 28.0;
  static const _colDateFrom = 65.0;
  static const _colDateTo = 65.0;
  static const _colQty = 36.0;
  static const _colRate = 50.0;
  static const _colAmount = 90.0;

  // ── Helper: // or legacy /n → newline for multi-line display in previews ───
  static String _multiline(String text) =>
      text.replaceAll('//', '\n').replaceAll('/n', '\n');

  // ── Static method for PDF generation ──────────────────────────────────────
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
    return [preview._buildPage(width: a4Width, height: a4Height)];
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: _buildPage(width: a4Width, height: a4Height));

  Widget _buildPage({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.hardEdge,
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
          style: _bodyStyle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 2),
              _buildDivider(0.8),
              const SizedBox(height: 8),
              _buildTaxInvoiceLabel(),
              const SizedBox(height: 6),
              _buildBillToSection(),
              const SizedBox(height: 10),
              _buildItemTable(),
              const SizedBox(height: 12),
              _buildBelowTableSection(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header Section ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLogo(),
        const SizedBox(width: 20),
        Expanded(child: _buildLetterheadImage()),
      ],
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 140,
      height: headerHeight,
      child: Image.asset(
        'assets/images/aarti_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const _FallbackLogo(),
      ),
    );
  }

  Widget _buildLetterheadImage() {
    return SizedBox(
      height: headerHeight,
      child: Image.asset(
        'assets/images/letterhead.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerRight,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildDivider(double thickness) {
    return Divider(color: _black, thickness: thickness, height: 4);
  }

  Widget _buildTaxInvoiceLabel() {
    return Center(
      child: Text(
        'TAX INVOICE',
        style: _bodyStyle.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          decoration: TextDecoration.underline,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // ── Bill To Section ────────────────────────────────────────────────────────
  Widget _buildBillToSection() {
    return Container(
      decoration: const BoxDecoration(border: Border.fromBorderSide(_borderSide)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BILL To,', style: _bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          _buildBillToRow1(),
          _buildBillToRow2(),
          const SizedBox(height: 2),
          _buildBillToRow3(),
        ],
      ),
    );
  }

  Widget _buildBillToRow1() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Client name — commas become newlines
        Expanded(
          child: Text(
            _multiline(voucher.clientName),
            style: _bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 10),
          ),
        ),
        _ReferenceRow(
          label: 'Bill No',
          value: voucher.billNo.isEmpty ? 'AE/-/25-26' : voucher.billNo,
        ),
      ],
    );
  }

  Widget _buildBillToRow2() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Client address — commas become newlines
        Expanded(
          child: Text(
            _multiline(voucher.clientAddress),
            style: _bodyStyle,
          ),
        ),
        _ReferenceRow(label: 'Date', value: _formatDate(voucher.date)),
      ],
    );
  }

  Widget _buildBillToRow3() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'GST No. ${voucher.clientGstin}',
            style: _bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        _ReferenceRow(
          label: 'PO.No.',
          value: voucher.poNo.isEmpty ? '-' : voucher.poNo,
        ),
      ],
    );
  }

  // ── Item Table ─────────────────────────────────────────────────────────────
  Widget _buildItemTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fixedWidth =
            _colSr + _colDateFrom + _colDateTo + _colQty + _colRate + _colAmount;
        final descriptionWidth =
            (constraints.maxWidth - fixedWidth - 2.0).clamp(0.0, double.infinity);

        return Container(
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(BorderSide(color: _black, width: 0.9)),
          ),
          child: Column(
            children: [
              _buildTableHeader(descriptionWidth),
              _buildTableDataRow(descriptionWidth),
              _buildTableBottom(descriptionWidth),
              _buildDeclarationRow(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(double descriptionWidth) {
    return Container(
      decoration: const BoxDecoration(
        color: _headerBg,
        border: Border(bottom: _borderSide),
      ),
      child: Row(
        children: [
          _HeaderCell('Sr. No', _colSr, centered: true),
          _HeaderCell('Date Fr.', _colDateFrom, centered: true),
          _HeaderCell('Date upto', _colDateTo, centered: true),
          _HeaderCell('Item Description', descriptionWidth),
          _HeaderCell('QTY', _colQty, centered: true),
          _HeaderCell('RATE', _colRate, centered: true),
          _HeaderCell('AMOUNT', _colAmount, centered: true, isLast: true),
        ],
      ),
    );
  }

  Widget _buildTableDataRow(double descriptionWidth) {
    final sortedRows = _sorted(voucher.rows);
    final fromDate = sortedRows.isNotEmpty ? sortedRows.first.fromDate : '';
    final toDate = sortedRows.isNotEmpty ? sortedRows.last.toDate : '';

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: _borderSide)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DataCell('1', _colSr, centered: true),
            _DataCell(_formatDate(fromDate), _colDateFrom, centered: true, fontSize: 10),
            _DataCell(_formatDate(toDate), _colDateTo, centered: true, fontSize: 10),
            _DescriptionCell(
              width: descriptionWidth,
              description: _multiline(voucher.itemDescription),
            ),
            _DataCell('', _colQty, centered: true),
            _DataCell('', _colRate, centered: true),
            _DataCell(
              voucher.baseTotal.toStringAsFixed(2),
              _colAmount,
              rightAligned: true,
              bold: true,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableBottom(double descriptionWidth) {
    final bankInfoWidth =
        _colSr + _colDateFrom + _colDateTo + descriptionWidth;
    final taxLabelWidth = _colQty + _colRate;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BankInfoPanel(width: bankInfoWidth, config: config),
          _TaxSummaryPanel(
            taxLabelWidth: taxLabelWidth,
            amountWidth: _colAmount,
            voucher: voucher,
          ),
        ],
      ),
    );
  }

  Widget _buildDeclarationRow() {
    return Container(
      decoration: const BoxDecoration(border: Border(top: _borderSide)),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        config.declarationText,
        style: _bodyStyle.copyWith(fontStyle: FontStyle.italic, fontSize: 8.5),
      ),
    );
  }

  // ── Below Table Section ────────────────────────────────────────────────────
  Widget _buildBelowTableSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _buildCertificationText()),
        _buildSignature(),
      ],
    );
  }

  Widget _buildCertificationText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '',
          style: _bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 9),
        ),
        const SizedBox(height: 2),
        Text(
          'Subject to Mumbai jurisdiction.',
          style: _bodyStyle.copyWith(fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildSignature() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
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
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static String _formatDate(String iso) {
    if (iso.isEmpty) return '-';
    if (iso.contains('-') && iso.length == 10) {
      final parts = iso.split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
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

// ── Reusable Widgets ───────────────────────────────────────────────────────────

class _ReferenceRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReferenceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Text(
            '$label :-  ',
            style: TaxInvoicePreview._bodyStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(value, style: TaxInvoicePreview._bodyStyle),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;
  final bool centered;
  final bool isLast;

  const _HeaderCell(
    this.text,
    this.width, {
    this.centered = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: isLast ? BorderSide.none : TaxInvoicePreview._borderSide,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.left,
        style: TaxInvoicePreview._bodyStyle.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final double width;
  final bool centered;
  final bool rightAligned;
  final bool bold;
  final bool isLast;
  final double? fontSize;

  const _DataCell(
    this.text,
    this.width, {
    this.centered = false,
    this.rightAligned = false,
    this.bold = false,
    this.isLast = false,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    TextAlign alignment;
    if (rightAligned) {
      alignment = TextAlign.right;
    } else if (centered) {
      alignment = TextAlign.center;
    } else {
      alignment = TextAlign.left;
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: isLast ? BorderSide.none : TaxInvoicePreview._borderSide,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Text(
        text,
        textAlign: alignment,
        style: TaxInvoicePreview._bodyStyle.copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class _DescriptionCell extends StatelessWidget {
  final double width;
  final String description;

  // ← change this value to increase/decrease the gap
  static const double _descVoucherSpacing = 80.0;

  const _DescriptionCell({required this.width, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        border: Border(right: TaxInvoicePreview._borderSide),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description, style: TaxInvoicePreview._bodyStyle),
          SizedBox(height: _descVoucherSpacing),
          const Text(
            '( Vouchers attached with this original bill )',
            style: TextStyle(
              fontSize: 8,
              fontStyle: FontStyle.italic,
              color: TaxInvoicePreview._black,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankInfoPanel extends StatelessWidget {
  final double width;
  final CompanyConfigModel config;

  const _BankInfoPanel({required this.width, required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        border: Border(right: TaxInvoicePreview._borderSide),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAN NO :-  ${config.pan}',
            style: TaxInvoicePreview._bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'GSTIN  :  ${config.gstin}          HSN: SAC99851',
            style: TaxInvoicePreview._bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Bank Details for   :  RTGS / NEFT',
            style: TaxInvoicePreview._bodyStyle.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          _BankDetailRow(label: 'Bank Name', value: config.bankName),
          _BankDetailRow(label: 'Branch', value: config.branch),
          _BankDetailRow(label: 'Account No.', value: config.accountNo),
          _BankDetailRow(label: 'IFSC Code', value: config.ifscCode),
        ],
      ),
    );
  }
}

class _BankDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _BankDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TaxInvoicePreview._bodyStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Flexible(
            child: Text(
              ':  $value',
              style: TaxInvoicePreview._bodyStyle.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxSummaryPanel extends StatelessWidget {
  final double taxLabelWidth;
  final double amountWidth;
  final VoucherModel voucher;

  const _TaxSummaryPanel({
    required this.taxLabelWidth,
    required this.amountWidth,
    required this.voucher,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TaxRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Total amount before Tax',
          value: voucher.baseTotal.toStringAsFixed(2),
        ),
        _TaxRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Add : CGST 9%',
          value: voucher.cgst.toStringAsFixed(2),
        ),
        _TaxRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Add : SGST 9%',
          value: voucher.sgst.toStringAsFixed(2),
        ),
        _TaxRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Total Tax Amount',
          value: voucher.totalTax.toStringAsFixed(2),
          bold: true,
        ),
        _TaxRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Round Up',
          value: '${voucher.roundOff >= 0 ? '+' : ''}${voucher.roundOff.toStringAsFixed(2)}',
        ),
        _GrandTotalRow(
          labelWidth: taxLabelWidth,
          amountWidth: amountWidth,
          label: 'Total Amount after Tax',
          value: '₹ ${voucher.finalTotal.toStringAsFixed(2)}',
        ),
      ],
    );
  }
}

class _TaxRow extends StatelessWidget {
  final double labelWidth;
  final double amountWidth;
  final String label;
  final String value;
  final bool bold;

  const _TaxRow({
    required this.labelWidth,
    required this.amountWidth,
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: TaxInvoicePreview._thinBorderSide),
      ),
      child: Row(
        children: [
          Container(
            width: labelWidth,
            decoration: const BoxDecoration(
              border: Border(right: TaxInvoicePreview._borderSide),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TaxInvoicePreview._bodyStyle.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            width: amountWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TaxInvoicePreview._bodyStyle.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrandTotalRow extends StatelessWidget {
  final double labelWidth;
  final double amountWidth;
  final String label;
  final String value;

  const _GrandTotalRow({
    required this.labelWidth,
    required this.amountWidth,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TaxInvoicePreview._grandTotalBg,
        border: Border(top: TaxInvoicePreview._borderSide),
      ),
      child: Row(
        children: [
          Container(
            width: labelWidth,
            decoration: const BoxDecoration(
              border: Border(right: TaxInvoicePreview._borderSide),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TaxInvoicePreview._bodyStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: amountWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TaxInvoicePreview._bodyStyle.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fallback Logo ──────────────────────────────────────────────────────────────
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: TaxInvoicePreview.headerHeight,  // consistent with headerHeight
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
}