int roundHalfUp(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'Denominator must be positive');
  }
  if (numerator < 0) {
    throw ArgumentError.value(numerator, 'numerator', 'Numerator must be non-negative');
  }
  return (numerator + denominator ~/ 2) ~/ denominator;
}

int _signedRoundHalfUp(int numerator, int denominator) {
  if (numerator < 0) {
    return -roundHalfUp(-numerator, denominator);
  }
  return roundHalfUp(numerator, denominator);
}

int percentOf(int amountPaise, int rateBp) {
  return _signedRoundHalfUp(amountPaise * rateBp, 10000);
}

int areaAmount(int areaCenti, int ratePaise) {
  return _signedRoundHalfUp(areaCenti * ratePaise, 100);
}

int quantityAmount(int quantityMilli, int ratePaise) {
  return _signedRoundHalfUp(quantityMilli * ratePaise, 1000);
}

int? parseRupeesToPaise(String input) {
  return _parseDecimalToUnits(input, decimals: 2);
}

int? parsePercentToBp(String input) {
  return _parseDecimalToUnits(input, decimals: 2);
}

int? parseAreaToCenti(String input) {
  return _parseDecimalToUnits(input, decimals: 2);
}

int? parseQuantityToMilli(String input) {
  return _parseDecimalToUnits(input, decimals: 3);
}

int? _parseDecimalToUnits(String input, {required int decimals}) {
  final trimmed = input.trim().replaceAll(',', '');
  if (trimmed.isEmpty) return null;

  final isNegative = trimmed.startsWith('-');
  final clean = isNegative ? trimmed.substring(1).trim() : trimmed;
  if (clean.isEmpty) return null;

  final parts = clean.split('.');
  if (parts.length > 2) return null;

  final wholeStr = parts[0];
  if (wholeStr.isNotEmpty && !RegExp(r'^\d+$').hasMatch(wholeStr)) {
    return null;
  }
  final whole = wholeStr.isEmpty ? 0 : int.tryParse(wholeStr);
  if (whole == null) return null;

  var frac = 0;
  if (parts.length == 2) {
    final fracStr = parts[1];
    if (fracStr.length > decimals) return null;
    if (fracStr.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracStr)) {
      return null;
    }
    final padded = fracStr.padRight(decimals, '0');
    frac = int.tryParse(padded) ?? 0;
  }

  var multiplier = 1;
  for (var i = 0; i < decimals; i++) {
    multiplier *= 10;
  }

  final total = whole * multiplier + frac;
  return isNegative ? -total : total;
}

String formatInr(int paise, {bool symbol = true}) {
  final isNegative = paise < 0;
  final absPaise = paise.abs();
  final rupees = absPaise ~/ 100;
  final remainder = absPaise % 100;

  final paiseStr = remainder.toString().padLeft(2, '0');
  final rupeesStr = _formatIndianRupees(rupees);

  final prefix = isNegative ? '-' : '';
  final sym = symbol ? '₹' : '';
  return '$prefix$sym$rupeesStr.$paiseStr';
}

String formatPaise(int paise, {bool symbol = true}) => formatInr(paise, symbol: symbol);

String formatPlainAmount(int paise) {
  return formatInr(paise, symbol: false);
}

String formatPercentBp(int bp) {
  final isNegative = bp < 0;
  final absBp = bp.abs();
  final whole = absBp ~/ 100;
  final rem = absBp % 100;
  final prefix = isNegative ? '-' : '';
  return '$prefix$whole.${rem.toString().padLeft(2, '0')}%';
}

String _formatIndianRupees(int amount) {
  final s = amount.toString();
  if (s.length <= 3) return s;

  final lastThree = s.substring(s.length - 3);
  final remaining = s.substring(0, s.length - 3);

  final buffer = StringBuffer();
  for (var i = 0; i < remaining.length; i++) {
    if (i > 0 && (remaining.length - i) % 2 == 0) {
      buffer.write(',');
    }
    buffer.write(remaining[i]);
  }
  buffer.write(',');
  buffer.write(lastThree);
  return buffer.toString();
}

String numberToWords(int paise) {
  if (paise == 0) return 'Zero Rupees Only';

  final rupees = paise ~/ 100;
  final paiseRemainder = paise % 100;

  String words = _convertChunk(rupees).trim();
  if (words.isEmpty) {
    words = 'Zero Rupees';
  } else {
    words = 'Rupees $words';
  }

  if (paiseRemainder > 0) {
    words += ' and ${_convertChunk(paiseRemainder).trim()} Paise';
  }

  return '$words Only';
}

String _convertChunk(int n) {
  if (n == 0) return '';

  const units = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
    'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
    'Seventeen', 'Eighteen', 'Nineteen'
  ];
  const tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
  ];

  if (n < 20) {
    return units[n];
  }
  if (n < 100) {
    return '${tens[n ~/ 10]} ${units[n % 10]}';
  }
  if (n < 1000) {
    return '${units[n ~/ 100]} Hundred ${_convertChunk(n % 100)}';
  }
  if (n < 100000) {
    return '${_convertChunk(n ~/ 1000)} Thousand ${_convertChunk(n % 1000)}';
  }
  if (n < 10000000) {
    return '${_convertChunk(n ~/ 100000)} Lakh ${_convertChunk(n % 100000)}';
  }
  return '${_convertChunk(n ~/ 10000000)} Crore ${_convertChunk(n % 10000000)}';
}
