String formatCurrency(double amount) {
  if (amount == 0) return '₹0.00';
  final s = amount.toStringAsFixed(2);
  final parts = s.split('.');
  String intPart = parts[0];
  final negative = intPart.startsWith('-');
  if (negative) intPart = intPart.substring(1);

  final result = StringBuffer();
  final len = intPart.length;
  for (int i = 0; i < len; i++) {
    if (i > 0) {
      final fromRight = len - i;
      if (fromRight == 3 || (fromRight > 3 && (fromRight - 3) % 2 == 0)) {
        result.write(',');
      }
    }
    result.write(intPart[i]);
  }
  return '${negative ? '-' : ''}₹$result.${parts[1]}';
}

String numberToWords(double amount) {
  final n = amount.round();
  if (n == 0) return 'Rupees Zero Only';

  const a = ['', 'One','Two','Three','Four','Five','Six','Seven','Eight','Nine','Ten',
    'Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
  const b = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];

  String fmt(int x) {
    if (x < 20) return a[x];
    if (x < 100) return b[x ~/ 10] + (x % 10 > 0 ? ' ${a[x % 10]}' : '');
    return '${a[x ~/ 100]} Hundred${x % 100 == 0 ? '' : ' ${fmt(x % 100)}'}';
  }

  int rem = n;
  final parts = <String>[];
  final crore = rem ~/ 10000000; rem %= 10000000;
  final lakh  = rem ~/ 100000;   rem %= 100000;
  final thou  = rem ~/ 1000;     rem %= 1000;
  if (crore > 0) parts.add('${fmt(crore)} Crore');
  if (lakh  > 0) parts.add('${fmt(lakh)} Lakh');
  if (thou  > 0) parts.add('${fmt(thou)} Thousand');
  if (rem   > 0) parts.add(fmt(rem));
  return 'Rupees ${parts.join(' ')} Only';
}