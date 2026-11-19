import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/domain/billing/gst_calculator.dart';

void main() {
  group('GstCalculator Tests', () {
    test('Society not GST registered results in zero GST', () {
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: false,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-04-01',
        months: 1,
        memberLimitPaise: 750000,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 800000,
            isGstApplicable: true,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.cgstPaise, equals(0));
      expect(res.first.sgstPaise, equals(0));
      expect(res.first.igstPaise, equals(0));
      expect(res.first.totalGstPaise, equals(0));
    });

    test('Bill date before effective date results in zero GST', () {
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: true,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-05-01',
        months: 1,
        memberLimitPaise: 750000,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 800000,
            isGstApplicable: true,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.totalGstPaise, equals(0));
    });

    test('Charge head not GST applicable results in zero GST', () {
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: true,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-04-01',
        months: 1,
        memberLimitPaise: 750000,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 800000,
            isGstApplicable: false,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.totalGstPaise, equals(0));
    });

    test('Monthly taxable at or below member limit (Rs 7,000 <= 7,500) gives zero GST', () {
      // Golden case: ₹7,000 (700000 paise) <= ₹7,500 (750000 paise) -> GST 0
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: true,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-04-01',
        months: 1,
        memberLimitPaise: 750000,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 700000,
            isGstApplicable: true,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.totalGstPaise, equals(0));
    });

    test('Monthly taxable exceeding limit (Rs 8,000 > 7,500) gives 18% GST (Rs 1,440 split 720/720)', () {
      // Golden case: ₹8,000 (800000 paise) > ₹7,500
      // 18% of 800000 = 144000 paise (₹1,440.00)
      // CGST = 72000 paise (₹720.00), SGST = 72000 paise (₹720.00)
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: true,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-04-01',
        months: 1,
        memberLimitPaise: 750000,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 800000,
            isGstApplicable: true,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.cgstPaise, equals(72000));
      expect(res.first.sgstPaise, equals(72000));
      expect(res.first.igstPaise, equals(0));
      expect(res.first.totalGstPaise, equals(144000));
    });

    test('Odd paise split: 101 paise GST splits into CGST 50 paise and SGST 51 paise', () {
      // Base: 561 paise at 18% produces 101 paise GST (561 * 1800 / 10000 = 100.98 -> 101 paise)
      // CGST = 101 ~/ 2 = 50 paise, SGST = 101 - 50 = 51 paise
      final res = GstCalculator.calculateMemberGst(
        societyGstRegistered: true,
        billDate: '2026-04-15',
        gstEffectiveFrom: '2026-04-01',
        months: 1,
        lines: [
          const GstLineInput(
            chargeHeadId: 1,
            amountPaise: 561,
            isGstApplicable: true,
            gstRateBp: 1800,
          ),
        ],
      );

      expect(res.first.totalGstPaise, equals(101));
      expect(res.first.cgstPaise, equals(50));
      expect(res.first.sgstPaise, equals(51));
    });
  });
}
