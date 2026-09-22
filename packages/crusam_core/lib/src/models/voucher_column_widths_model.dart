import 'dart:convert';

class VoucherColumnWidthsSettings {
  final double sr;
  final double debitAc;
  final double ifsc;
  final double creditAc;
  final double code;
  final double name;
  final double place;
  final double bank;
  final double from;
  final double to;
  final double amount;

  const VoucherColumnWidthsSettings({
    this.sr = 24,
    this.debitAc = 88,
    this.ifsc = 72,
    this.creditAc = 90,
    this.code = 34,
    this.name = 105,
    this.place = 72,
    this.bank = 90,
    this.from = 44,
    this.to = 44,
    this.amount = 58,
  });

  factory VoucherColumnWidthsSettings.fromMap(Map<String, dynamic> m) =>
      VoucherColumnWidthsSettings(
        sr: (m['sr'] as num?)?.toDouble() ?? 24,
        debitAc: (m['debit_ac'] as num?)?.toDouble() ?? 88,
        ifsc: (m['ifsc'] as num?)?.toDouble() ?? 72,
        creditAc: (m['credit_ac'] as num?)?.toDouble() ?? 90,
        code: (m['code'] as num?)?.toDouble() ?? 34,
        name: (m['name'] as num?)?.toDouble() ?? 105,
        place: (m['place'] as num?)?.toDouble() ?? 72,
        bank: (m['bank'] as num?)?.toDouble() ?? 90,
        from: (m['from'] as num?)?.toDouble() ?? 44,
        to: (m['to'] as num?)?.toDouble() ?? 44,
        amount: (m['amount'] as num?)?.toDouble() ?? 58,
      );

  factory VoucherColumnWidthsSettings.fromJson(String json) {
    try {
      return VoucherColumnWidthsSettings.fromMap(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return const VoucherColumnWidthsSettings();
    }
  }

  Map<String, dynamic> toMap() => {
        'sr': sr,
        'debit_ac': debitAc,
        'ifsc': ifsc,
        'credit_ac': creditAc,
        'code': code,
        'name': name,
        'place': place,
        'bank': bank,
        'from': from,
        'to': to,
        'amount': amount,
      };

  String toJson() => jsonEncode(toMap());

  VoucherColumnWidthsSettings copyWith({
    double? sr,
    double? debitAc,
    double? ifsc,
    double? creditAc,
    double? code,
    double? name,
    double? place,
    double? bank,
    double? from,
    double? to,
    double? amount,
  }) =>
      VoucherColumnWidthsSettings(
        sr: sr ?? this.sr,
        debitAc: debitAc ?? this.debitAc,
        ifsc: ifsc ?? this.ifsc,
        creditAc: creditAc ?? this.creditAc,
        code: code ?? this.code,
        name: name ?? this.name,
        place: place ?? this.place,
        bank: bank ?? this.bank,
        from: from ?? this.from,
        to: to ?? this.to,
        amount: amount ?? this.amount,
      );

  /// Ordered (label, width) pairs — consumed by the settings panel.
  List<(String label, double width)> get entries => [
        ('Sr.', sr),
        ('Debit A/c', debitAc),
        ('IFSC', ifsc),
        ('Credit A/c', creditAc),
        ('Code', code),
        ('Name', name),
        ('Place', place),
        ('Bank', bank),
        ('Fr.', from),
        ('To', to),
        ('Amount', amount),
      ];

  double get totalWidth =>
      sr + debitAc + ifsc + creditAc + code + name + place + bank + from + to + amount;
}