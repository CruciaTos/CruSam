import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/domain/billing/meter_calculator.dart';

void main() {
  group('MeterCalculator Tests', () {
    final slabs = [
      const MeterSlab(id: 1, meterTypeId: 1, seq: 1, upToMilli: 10000, ratePaise: 500),
      const MeterSlab(id: 2, meterTypeId: 1, seq: 2, upToMilli: 20000, ratePaise: 700),
      const MeterSlab(id: 3, meterTypeId: 1, seq: 3, upToMilli: null, ratePaise: 1000),
    ];

    test('Cumulative meter calculation tiers correctly', () {
      // 15 units (15000 milli):
      // Tier 1: 10 units * 500 = 5000 paise
      // Tier 2: 5 units * 700 = 3500 paise
      // Total = 8500 paise
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 15000,
        isCumulative: true,
        minimumPaise: 0,
        slabs: slabs,
      );
      expect(charge, equals(8500));
    });

    test('Cumulative meter with 3 tiers', () {
      // 25 units (25000 milli):
      // Tier 1: 10 * 500 = 5000
      // Tier 2: 10 * 700 = 7000
      // Tier 3: 5 * 1000 = 5000
      // Total = 17000 paise
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 25000,
        isCumulative: true,
        minimumPaise: 0,
        slabs: slabs,
      );
      expect(charge, equals(17000));
    });

    test('Non-cumulative meter prices entire consumption at tier rate', () {
      // 15 units (15000 milli) falls in slab 2 (up to 20000) at 700 paise/unit
      // 15 * 700 = 10500 paise
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 15000,
        isCumulative: false,
        minimumPaise: 0,
        slabs: slabs,
      );
      expect(charge, equals(10500));
    });

    test('Non-cumulative meter in tier 3 (unbounded)', () {
      // 25 units falls in slab 3 (rate 1000 paise)
      // 25 * 1000 = 25000 paise
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 25000,
        isCumulative: false,
        minimumPaise: 0,
        slabs: slabs,
      );
      expect(charge, equals(25000));
    });

    test('Enforces minimum charge', () {
      // 5 units (5000 milli) cumulative: 5 * 500 = 2500 paise.
      // Minimum is 5000 paise. Should return 5000 paise.
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 5000,
        isCumulative: true,
        minimumPaise: 5000,
        slabs: slabs,
      );
      expect(charge, equals(5000));
    });

    test('Negative consumption throws SocietyException', () {
      expect(
        () => MeterCalculator.calculateCharge(
          consumptionMilli: -500,
          isCumulative: true,
          minimumPaise: 0,
          slabs: slabs,
        ),
        throwsA(isA<SocietyException>()),
      );
    });

    test('Zero consumption returns minimum charge', () {
      final charge = MeterCalculator.calculateCharge(
        consumptionMilli: 0,
        isCumulative: true,
        minimumPaise: 2000,
        slabs: slabs,
      );
      expect(charge, equals(2000));
    });
  });
}
