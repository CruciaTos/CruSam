// Tax + totals math for an invoice (voucher). This used to live as getters
// on VoucherNotifier; it is shared here so the app and the MCP server
// compute byte-identical totals.

class InvoiceRates {
  InvoiceRates._();
  static const double cgst = 0.09;
  static const double sgst = 0.09;
}

class InvoiceTotals {
  final double baseTotal;
  final double cgst;
  final double sgst;
  final double totalTax;
  final double rawTotal;
  final double finalTotal;
  final double roundOff;

  const InvoiceTotals._({
    required this.baseTotal,
    required this.cgst,
    required this.sgst,
    required this.totalTax,
    required this.rawTotal,
    required this.finalTotal,
    required this.roundOff,
  });

  /// base = sum of row amounts, CGST/SGST on base, final rounded to the
  /// nearest rupee, round-off = final - raw. Same order of operations as the
  /// original VoucherNotifier getters so floating-point results match.
  factory InvoiceTotals.fromAmounts(Iterable<double> amounts) {
    final base = amounts.fold<double>(0, (a, b) => a + b);
    final cgst = base * InvoiceRates.cgst;
    final sgst = base * InvoiceRates.sgst;
    final tax = cgst + sgst;
    final raw = base + tax;
    final fin = raw.roundToDouble();
    return InvoiceTotals._(
      baseTotal: base,
      cgst: cgst,
      sgst: sgst,
      totalTax: tax,
      rawTotal: raw,
      finalTotal: fin,
      roundOff: fin - raw,
    );
  }
}
