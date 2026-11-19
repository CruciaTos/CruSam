import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/core/money.dart';

void main() {
  group('roundHalfUp', () {
    test('proves roundHalfUp(5, 2) is 3', () {
      expect(roundHalfUp(5, 2), 3);
    });

    test('rounds correctly on various values', () {
      expect(roundHalfUp(4, 2), 2);
      expect(roundHalfUp(0, 5), 0);
      expect(roundHalfUp(1, 2), 1);
      expect(roundHalfUp(2, 3), 1);
      expect(roundHalfUp(5, 3), 2);
    });

    test('throws ArgumentError on non-positive denominator or negative numerator', () {
      expect(() => roundHalfUp(5, 0), throwsArgumentError);
      expect(() => roundHalfUp(5, -1), throwsArgumentError);
      expect(() => roundHalfUp(-5, 2), throwsArgumentError);
    });
  });

  group('formatInr', () {
    test('proves formatInr(123456789) is ₹12,34,567.89', () {
      expect(formatInr(123456789), '₹12,34,567.89');
    });

    test('formats zero and small amounts', () {
      expect(formatInr(0), '₹0.00');
      expect(formatInr(5), '₹0.05');
      expect(formatInr(50), '₹0.50');
      expect(formatInr(100), '₹1.00');
      expect(formatInr(100000), '₹1,000.00');
    });

    test('formats negative amounts with leading minus', () {
      expect(formatInr(-100000), '-₹1,000.00');
      expect(formatInr(-123456789), '-₹12,34,567.89');
    });

    test('formatPlainAmount omits symbol', () {
      expect(formatPlainAmount(123456789), '12,34,567.89');
      expect(formatPlainAmount(-50000), '-500.00');
    });
  });

  group('parsing helpers', () {
    test('parseRupeesToPaise handles commas and decimals', () {
      expect(parseRupeesToPaise('12,34,567.89'), 123456789);
      expect(parseRupeesToPaise('100'), 10000);
      expect(parseRupeesToPaise('0.5'), 50);
      expect(parseRupeesToPaise('-50.25'), -5025);
      expect(parseRupeesToPaise('invalid'), isNull);
      expect(parseRupeesToPaise(''), isNull);
    });

    test('parsePercentToBp converts percentages to basis points', () {
      expect(parsePercentToBp('12'), 1200);
      expect(parsePercentToBp('18.5'), 1850);
      expect(parsePercentToBp('0.05'), 5);
      expect(parsePercentToBp('invalid'), isNull);
    });

    test('parseAreaToCenti converts sq ft to centi units', () {
      expect(parseAreaToCenti('650'), 65000);
      expect(parseAreaToCenti('650.50'), 65050);
      expect(parseAreaToCenti('invalid'), isNull);
    });

    test('parseQuantityToMilli converts quantity to milli units', () {
      expect(parseQuantityToMilli('12.5'), 12500);
      expect(parseQuantityToMilli('12.500'), 12500);
      expect(parseQuantityToMilli('0.001'), 1);
    });
  });

  group('percentOf and areaAmount', () {
    test('percentOf computes basis points correctly', () {
      expect(percentOf(1000000, 1800), 180000); // 18% of 10,000.00 = 1,800.00
      expect(percentOf(1000000, 1200), 120000); // 12% of 10,000.00 = 1,200.00
    });

    test('areaAmount computes area charge', () {
      // 650 sq ft (65000 centi) at ₹3.00/sqft (300 paise) = 195000 paise (₹1,950.00)
      expect(areaAmount(65000, 300), 195000);
    });
  });
}
