// lib/features/vouchers/models/pdf_col_widths.dart
//
// Relative column widths for the Expenses Statement and Bank Disbursement
// PDF tables. The PDF scales them to fill the usable page width, so only
// their proportions matter.

class VoucherColWidths {
  final double amount;
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double name;
  final double place;
  final double expenses;
  final double aarti;
  final double from;
  final double to;

  const VoucherColWidths({
    this.amount   = 55,
    this.debitAc  = 82,
    this.ifsc     = 68,
    this.creditAc = 86,
    this.code     = 30,
    this.name     = 95,
    this.place    = 65,
    this.expenses = 82,
    this.aarti    = 46,
    this.from     = 42,
    this.to       = 42,
  });
}

class BankColWidths {
  final double amount;
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double beneficiary;
  final double place;
  final double bank;
  final double debitName;
  final double from;
  final double to;

  const BankColWidths({
    this.amount      = 52,
    this.debitAc     = 87,
    this.ifsc        = 72,
    this.creditAc    = 87,
    this.code        = 38,
    this.beneficiary = 100,
    this.place       = 68,
    this.bank        = 87,
    this.debitName   = 68,
    this.from        = 44,
    this.to          = 44,
  });
}
