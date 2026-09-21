import 'package:crusam_core/crusam_core.dart';
import 'package:test/test.dart';

void main() {
  group('InvoiceTotals', () {
    test('matches an invoice the app saved (base 1064)', () {
      final t = InvoiceTotals.fromAmounts([1064]);
      // Values stored by the app for voucher #2 in the real database.
      expect(t.cgst, 95.75999999999999);
      expect(t.sgst, 95.75999999999999);
      expect(t.roundOff, 0.4800000000000182);
      expect(t.finalTotal, 1256);
    });

    test('rounds half up to the rupee', () {
      expect(InvoiceTotals.fromAmounts([1000, 500]).finalTotal, 1770);
      expect(InvoiceTotals.fromAmounts([]).finalTotal, 0);
    });
  });

  group('VoucherFactory', () {
    test('invoice date becomes created_at; same-day timestamps are kept', () {
      String c(String date, String existing) => VoucherFactory.createdAtFor(
          date: date, existingCreatedAt: existing, nowUtcIso: '2026-09-22T10:00:00.000Z');
      expect(c('2026-06-01', ''), '2026-06-01T00:00:00.000Z');
      expect(c('2026-09-22', ''), '2026-09-22T10:00:00.000Z');
      expect(c('2026-06-01', '2026-06-01T08:15:00.000Z'), '2026-06-01T08:15:00.000Z');
      expect(c('2026-06-02', '2026-06-01T08:15:00.000Z'), '2026-06-02T00:00:00.000Z');
      expect(c('', '2026-06-01T08:15:00.000Z'), '2026-06-01T08:15:00.000Z');
    });

    test('prepareForSave keeps identity fields and fills totals', () {
      final v = VoucherModel(
        date: '2026-06-01',
        cloudId: 'abc',
        createdBy: 'first@x',
        rows: const [VoucherRowModel(id: '1', amount: 1000)],
      );
      final p = VoucherFactory.prepareForSave(v,
          nowUtcIso: '2026-09-22T10:00:00.000Z', userEmail: 'me@x', newCloudId: () => 'new');
      expect(p.cloudId, 'abc');
      expect(p.createdBy, 'first@x');
      expect(p.updatedBy, 'me@x');
      expect(p.finalTotal, 1180);
      expect(p.status, VoucherStatus.saved);
    });
  });

  group('FuzzyName', () {
    test('handwriting-style variants rank the right person first', () {
      final pool = ['Pacharla Venkata Lokesh', 'Lokesh U', 'Pacharla Ramesh',
          'Mohammed Anas Shaikh', 'Rohitas', 'Rajesh Kumar Rawlo', 'Susantakumar Raulo'];
      expect(pool[FuzzyName.rank('P.V. Lokesh', pool).first.$1], 'Pacharla Venkata Lokesh');
      expect(pool[FuzzyName.rank('Mohd. Anas', pool).first.$1], 'Mohammed Anas Shaikh');
      expect(pool[FuzzyName.rank('Rajeshkumar Raulo', pool).first.$1], 'Rajesh Kumar Rawlo');
    });
  });

  group('SalaryMath', () {
    const math = SalaryMath(SalaryFormulaConfigModel());
    test('PF cap, ESIC eligibility and PT slabs', () {
      expect(math.pf(10000), 1200);
      expect(math.pf(20000), 1800);
      expect(math.esic(fullGrossSalary: 25000, earnedGross: 25000), 0);
      expect(math.esic(fullGrossSalary: 15000, earnedGross: 15000), 113);
      expect(math.pt(earnedGross: 9000, isFemale: false, isFeb: false), 175);
      expect(math.pt(earnedGross: 12000, isFemale: false, isFeb: true), 300);
      expect(math.pt(earnedGross: 20000, isFemale: true, isFeb: false), 0);
    });
  });
}
