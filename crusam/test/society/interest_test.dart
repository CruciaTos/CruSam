import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/domain/billing/interest_calculator.dart';

void main() {
  group('InterestCalculator', () {
    test('calculateForSourceBill calculates interest correctly with single segment', () {
      // Bill: ₹1,000.00 (100000 paise) due 2026-04-20
      // Rate: 12% (1200 bp)
      // Interest through: 2026-04-30 (10 days: 2026-04-21 to 2026-04-30)
      // Numerator = 100000 * 1200 * 10 = 1,200,000,000
      // Denominator = 365 * 10000 = 3,650,000
      // 1200000000 / 3650000 = 328.767... -> roundHalfUp = 329 paise (₹3.29)
      final bill = const SourceBillInfo(
        billId: 1,
        billDate: '2026-04-01',
        dueDate: '2026-04-20',
        lines: [
          SourceBillLineInfo(
            lineId: 101,
            amountPaise: 100000,
            payablePaise: 100000,
            isInterestBearing: true,
            allocations: [],
          ),
        ],
      );

      final result = InterestCalculator.calculateForSourceBill(
        bill: bill,
        interestStartDate: '2026-04-01',
        graceDays: 0,
        rateBp: 1200,
        interestThrough: '2026-04-30',
      );

      expect(result, isNotNull);
      expect(result!.amountPaise, 329);
      expect(result.segments.length, 1);
      expect(result.segments.first.days, 10);
      expect(result.segments.first.basePaise, 100000);
    });

    test('calculateForSourceBill handles part payment by splitting into segments', () {
      // Bill due 2026-04-20. Total interest-bearing = ₹1,000.00 (100000 paise)
      // On 2026-04-25, ₹400.00 is paid (40000 paise allocated).
      // Segment 1 (2026-04-21 to 2026-04-24): 4 days at ₹1,000.00 (100000 paise)
      // Segment 2 (2026-04-25 to 2026-04-30): 6 days at ₹600.00 (60000 paise)
      // Numerator = (100000 * 1200 * 4) + (60000 * 1200 * 6)
      //           = 480,000,000 + 432,000,000 = 912,000,000
      // Denominator = 3,650,000
      // 912000000 / 3650000 = 249.863... -> roundHalfUp = 250 paise (₹2.50)
      final bill = const SourceBillInfo(
        billId: 1,
        billDate: '2026-04-01',
        dueDate: '2026-04-20',
        lines: [
          SourceBillLineInfo(
            lineId: 101,
            amountPaise: 100000,
            payablePaise: 100000,
            isInterestBearing: true,
            allocations: [
              LineAllocationInfo(
                allocationDate: '2026-04-25',
                allocatedPaise: 40000,
              ),
            ],
          ),
        ],
      );

      final result = InterestCalculator.calculateForSourceBill(
        bill: bill,
        interestStartDate: '2026-04-01',
        graceDays: 0,
        rateBp: 1200,
        interestThrough: '2026-04-30',
      );

      expect(result, isNotNull);
      expect(result!.amountPaise, 250);
      expect(result.segments.length, 2);
      expect(result.segments[0].days, 4);
      expect(result.segments[0].basePaise, 100000);
      expect(result.segments[1].days, 6);
      expect(result.segments[1].basePaise, 60000);
    });

    test('calculateForSourceBill returns null if paid within grace period or before due date', () {
      final bill = const SourceBillInfo(
        billId: 1,
        billDate: '2026-04-01',
        dueDate: '2026-04-20',
        lines: [
          SourceBillLineInfo(
            lineId: 101,
            amountPaise: 100000,
            payablePaise: 100000,
            isInterestBearing: true,
            allocations: [],
          ),
        ],
      );

      // Grace period of 15 days makes first overdue day = 2026-05-06
      // Interest through 2026-04-30 is before grace expires -> null
      final result = InterestCalculator.calculateForSourceBill(
        bill: bill,
        interestStartDate: '2026-04-01',
        graceDays: 15,
        rateBp: 1200,
        interestThrough: '2026-04-30',
      );

      expect(result, isNull);
    });

    test('roundHalfUp matches exact integer paise accounting rules', () {
      expect(roundHalfUp(15, 10), 2); // 1.5 -> 2
      expect(roundHalfUp(25, 10), 3); // 2.5 -> 3
      expect(roundHalfUp(14, 10), 1); // 1.4 -> 1
    });
  });
}
