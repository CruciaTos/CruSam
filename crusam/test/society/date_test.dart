import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/core/society_date.dart';

void main() {
  group('financial year calculation', () {
    test('proves 2026-03-31 is FY 2025-26 and 2026-04-01 is FY 2026-27', () {
      expect(fyCodeForDate('2026-03-31'), '2025-26');
      expect(fyCodeForDate('2026-04-01'), '2026-27');
    });

    test('fyStartForCode and fyEndForCode return accurate bounds', () {
      expect(fyStartForCode('2026-27'), '2026-04-01');
      expect(fyEndForCode('2026-27'), '2027-03-31');
      expect(fyStartForCode('2025-26'), '2025-04-01');
      expect(fyEndForCode('2025-26'), '2026-03-31');
    });
  });

  group('date display and parsing', () {
    test('formats ISO to display dd/MM/yyyy', () {
      expect(formatDisplayDate('2026-04-01'), '01/04/2026');
      expect(formatDisplayDate('2026-12-31'), '31/12/2026');
    });

    test('parses display dd/MM/yyyy to ISO', () {
      expect(parseDisplayDate('01/04/2026'), '2026-04-01');
      expect(parseDisplayDate('31/12/2026'), '2026-12-31');
      expect(parseDisplayDate('invalid'), isNull);
      expect(parseDisplayDate('31/02/2026'), isNull); // non-existent date
    });
  });

  group('date math', () {
    test('addDaysIso computes correct offset', () {
      expect(addDaysIso('2026-04-01', 20), '2026-04-21');
      expect(addDaysIso('2026-04-30', 1), '2026-05-01');
    });

    test('daysInclusive calculates correct inclusive range', () {
      expect(daysInclusive('2026-04-01', '2026-04-01'), 1);
      expect(daysInclusive('2026-04-01', '2026-04-30'), 30);
    });

    test('monthsInclusive counts calendar months inclusive', () {
      expect(monthsInclusive('2026-04-01', '2026-04-30'), 1);
      expect(monthsInclusive('2026-04-01', '2026-06-30'), 3);
      expect(monthsInclusive('2026-04-01', '2027-03-31'), 12);
    });
  });
}
