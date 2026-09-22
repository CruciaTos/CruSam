import 'dart:convert';

class BankColumnWidthsSettings {
  final double amount;
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double beneficiary;
  final double place;
  final double bank;
  final double debitName;

  const BankColumnWidthsSettings({
    this.amount = 62,
    this.debitAc = 97,
    this.ifsc = 82,
    this.creditAc = 97,
    this.code = 38,
    this.beneficiary = 112,
    this.place = 76,
    this.bank = 97,
    this.debitName = 78,
  });

  factory BankColumnWidthsSettings.fromMap(Map<String, dynamic> m) =>
      BankColumnWidthsSettings(
        amount: (m['amount'] as num?)?.toDouble() ?? 62,
        debitAc: (m['debit_ac'] as num?)?.toDouble() ?? 97,
        ifsc: (m['ifsc'] as num?)?.toDouble() ?? 82,
        creditAc: (m['credit_ac'] as num?)?.toDouble() ?? 97,
        code: (m['code'] as num?)?.toDouble() ?? 38,
        beneficiary: (m['beneficiary'] as num?)?.toDouble() ?? 112,
        place: (m['place'] as num?)?.toDouble() ?? 76,
        bank: (m['bank'] as num?)?.toDouble() ?? 97,
        debitName: (m['debit_name'] as num?)?.toDouble() ?? 78,
      );

  factory BankColumnWidthsSettings.fromJson(String json) {
    try {
      return BankColumnWidthsSettings.fromMap(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return const BankColumnWidthsSettings();
    }
  }

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'debit_ac': debitAc,
        'ifsc': ifsc,
        'credit_ac': creditAc,
        'code': code,
        'beneficiary': beneficiary,
        'place': place,
        'bank': bank,
        'debit_name': debitName,
      };

  String toJson() => jsonEncode(toMap());

  BankColumnWidthsSettings copyWith({
    double? amount,
    double? debitAc,
    double? ifsc,
    double? creditAc,
    double? code,
    double? beneficiary,
    double? place,
    double? bank,
    double? debitName,
  }) =>
      BankColumnWidthsSettings(
        amount: amount ?? this.amount,
        debitAc: debitAc ?? this.debitAc,
        ifsc: ifsc ?? this.ifsc,
        creditAc: creditAc ?? this.creditAc,
        code: code ?? this.code,
        beneficiary: beneficiary ?? this.beneficiary,
        place: place ?? this.place,
        bank: bank ?? this.bank,
        debitName: debitName ?? this.debitName,
      );

  /// Ordered (label, width) pairs — consumed by the settings panel.
  List<(String label, double width)> get entries => [
        ('Amount', amount),
        ('Debit A/c', debitAc),
        ('IFSC', ifsc),
        ('Credit A/c', creditAc),
        ('Code', code),
        ('Beneficiary', beneficiary),
        ('Place', place),
        ('Bank', bank),
        ('Debit Name', debitName),
      ];

  double get totalWidth =>
      amount + debitAc + ifsc + creditAc + code + beneficiary + place + bank + debitName;
}