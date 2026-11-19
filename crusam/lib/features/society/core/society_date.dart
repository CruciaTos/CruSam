String todayIso() {
  final now = DateTime.now();
  return toIsoDate(now);
}

DateTime parseIsoDate(String value) {
  final parts = value.trim().split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid ISO date format, expected YYYY-MM-DD', value);
  }
  final year = int.parse(parts[0]);
  final month = int.parse(parts[1]);
  final day = int.parse(parts[2]);
  return DateTime(year, month, day);
}

String toIsoDate(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String addDaysIso(String value, int days) {
  final dt = parseIsoDate(value);
  final newDt = dt.add(Duration(days: days));
  return toIsoDate(newDt);
}

int daysInclusive(String from, String to) {
  final dtFrom = parseIsoDate(from);
  final dtTo = parseIsoDate(to);
  return dtTo.difference(dtFrom).inDays + 1;
}

String formatDisplayDate(String iso) {
  if (iso.trim().isEmpty) return '';
  try {
    final dt = parseIsoDate(iso);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  } catch (_) {
    return iso;
  }
}

String? parseDisplayDate(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('/');
  if (parts.length != 3) return null;

  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2200) return null;

  try {
    final dt = DateTime(y, m, d);
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return toIsoDate(dt);
  } catch (_) {
    return null;
  }
}

String fyCodeForDate(String iso) {
  final dt = parseIsoDate(iso);
  final year = dt.year;
  final month = dt.month;

  if (month >= 4) {
    final nextYear = (year + 1).toString().substring(2);
    return '$year-$nextYear';
  } else {
    final prevYear = year - 1;
    final currentYearShort = year.toString().substring(2);
    return '$prevYear-$currentYearShort';
  }
}

String fyStartForCode(String code) {
  final parts = code.trim().split('-');
  if (parts.length != 2) {
    throw FormatException('Invalid FY code, expected YYYY-YY', code);
  }
  return '${parts[0]}-04-01';
}

String fyEndForCode(String code) {
  final parts = code.trim().split('-');
  if (parts.length != 2) {
    throw FormatException('Invalid FY code, expected YYYY-YY', code);
  }
  final startYear = int.parse(parts[0]);
  final endYear = startYear + 1;
  return '$endYear-03-31';
}

int monthsInclusive(String from, String to) {
  final dtFrom = parseIsoDate(from);
  final dtTo = parseIsoDate(to);
  return (dtTo.year - dtFrom.year) * 12 + (dtTo.month - dtFrom.month) + 1;
}
