import 'package:flutter_test/flutter_test.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/domain/collections/allocation_calculator.dart';

void main() {
  group('AllocationCalculator', () {
    test('autoAllocate allocates FIFO by bill due date and interest first', () {
      final lines = [
        const OpenBillLine(
          billId: 1,
          billNo: 'BILL/2026-27/0001',
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          billLineId: 101,
          lineNo: 1,
          chargeHeadId: 1,
          chargeHeadName: 'Maintenance',
          headKind: 'charge',
          isInterestBearing: true,
          payablePaise: 200000,
          allocatedPaise: 0,
        ),
        const OpenBillLine(
          billId: 1,
          billNo: 'BILL/2026-27/0001',
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          billLineId: 102,
          lineNo: 2,
          chargeHeadId: 2,
          chargeHeadName: 'Sinking Fund',
          headKind: 'charge',
          isInterestBearing: true,
          payablePaise: 50000,
          allocatedPaise: 0,
        ),
        const OpenBillLine(
          billId: 2,
          billNo: 'BILL/2026-27/0002',
          billDate: '2026-05-01',
          dueDate: '2026-05-20',
          billLineId: 201,
          lineNo: 1,
          chargeHeadId: 10,
          chargeHeadName: 'Late Payment Interest',
          headKind: 'interest',
          isInterestBearing: false,
          payablePaise: 1500, // ₹15.00
          allocatedPaise: 0,
        ),
        const OpenBillLine(
          billId: 2,
          billNo: 'BILL/2026-27/0002',
          billDate: '2026-05-01',
          dueDate: '2026-05-20',
          billLineId: 202,
          lineNo: 2,
          chargeHeadId: 1,
          chargeHeadName: 'Maintenance',
          headKind: 'charge',
          isInterestBearing: true,
          payablePaise: 200000,
          allocatedPaise: 0,
        ),
      ];

      // Auto-allocate ₹2,200.00 (220000 paise)
      final result = AllocationCalculator.autoAllocate(
        openLines: lines,
        availablePaise: 220000,
      );
      expect(result.allocations.length, 2);
      expect(result.unallocatedPaise, 0);
      expect(result.totalAllocatedPaise, 220000);

      expect(result.allocations[0].billLineId, 101);
      expect(result.allocations[0].amountPaise, 200000);

      expect(result.allocations[1].billLineId, 102);
      expect(result.allocations[1].amountPaise, 20000);
    });

    test('autoAllocate puts excess receipt into advance', () {
      final lines = [
        const OpenBillLine(
          billId: 1,
          billNo: 'BILL/2026-27/0001',
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          billLineId: 101,
          lineNo: 1,
          chargeHeadId: 1,
          chargeHeadName: 'Maintenance',
          headKind: 'charge',
          isInterestBearing: true,
          payablePaise: 100000,
          allocatedPaise: 0,
        ),
      ];

      // Pay ₹1,500.00 for ₹1,000.00 dues
      final result = AllocationCalculator.autoAllocate(
        openLines: lines,
        availablePaise: 150000,
      );
      expect(result.allocations.length, 1);
      expect(result.allocations[0].amountPaise, 100000);
      expect(result.totalAllocatedPaise, 100000);
      expect(result.unallocatedPaise, 50000); // ₹500 advance
    });

    test('validateCustomAllocations rejects over-allocation and negative amounts', () {
      final lines = [
        const OpenBillLine(
          billId: 1,
          billNo: 'BILL/2026-27/0001',
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          billLineId: 101,
          lineNo: 1,
          chargeHeadId: 1,
          chargeHeadName: 'Maintenance',
          headKind: 'charge',
          isInterestBearing: true,
          payablePaise: 100000,
          allocatedPaise: 20000, // 80000 open
        ),
      ];

      // Over-allocation on single line (> 80000)
      expect(
        () => AllocationCalculator.validateCustomAllocations(
          openLines: lines,
          drafts: [const AllocationDraft(billLineId: 101, amountPaise: 90000)],
          availablePaise: 100000,
        ),
        throwsA(isA<SocietyException>()),
      );

      // Negative amount
      expect(
        () => AllocationCalculator.validateCustomAllocations(
          openLines: lines,
          drafts: [const AllocationDraft(billLineId: 101, amountPaise: -100)],
          availablePaise: 100000,
        ),
        throwsA(isA<SocietyException>()),
      );

      // Allocations exceed available receipt amount
      expect(
        () => AllocationCalculator.validateCustomAllocations(
          openLines: lines,
          drafts: [const AllocationDraft(billLineId: 101, amountPaise: 80000)],
          availablePaise: 50000,
        ),
        throwsA(isA<SocietyException>()),
      );

      // Valid allocation
      final valid = AllocationCalculator.validateCustomAllocations(
        openLines: lines,
        drafts: [const AllocationDraft(billLineId: 101, amountPaise: 70000)],
        availablePaise: 100000,
      );
      expect(valid.allocations.length, 1);
      expect(valid.unallocatedPaise, 30000);
    });
  });
}
