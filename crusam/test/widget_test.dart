// The app and the CruSam MCP server share invoice rules through
// crusam_core; these guard the values the app screens rely on.

import 'package:crusam/core/constants/app_constants.dart';
import 'package:crusam/shared/widgets/full_screen_loader.dart';
import 'package:crusam_core/crusam_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app tax rates are the shared invoice rates (CGST 9% + SGST 9%)', () {
    expect(AppConstants.cgstRate, InvoiceRates.cgst);
    expect(AppConstants.sgstRate, InvoiceRates.sgst);
    expect(AppConstants.cgstRate + AppConstants.sgstRate, closeTo(0.18, 1e-9));
  });

  test('invoice totals round the final amount to the rupee', () {
    final t = InvoiceTotals.fromAmounts([1000, 64]);
    expect(t.baseTotal, 1064);
    expect(t.finalTotal, 1256); // 1064 + 18% = 1255.52
    expect(t.finalTotal, t.finalTotal.roundToDouble());
  });

  test('hideLoader is safe when no loader is showing', () {
    expect(hideLoader, returnsNormally);
  });
}
