import '../../core/society_exception.dart';
import '../../data/models/collection_models.dart';

class AllocationResult {
  final List<AllocationDraft> allocations;
  final int totalAllocatedPaise;
  final int unallocatedPaise;

  const AllocationResult({
    required this.allocations,
    required this.totalAllocatedPaise,
    required this.unallocatedPaise,
  });
}

class AllocationCalculator {
  /// Auto-allocates [availablePaise] across [openLines] in FIFO order:
  /// 1. Bills by due_date, bill_date, id (assumed already sorted in [openLines])
  /// 2. Within a bill, interest lines first, then by line_no
  /// Any remaining money is unallocated and stays as advance.
  static AllocationResult autoAllocate({
    required List<OpenBillLine> openLines,
    required int availablePaise,
  }) {
    if (availablePaise <= 0) {
      return const AllocationResult(
        allocations: [],
        totalAllocatedPaise: 0,
        unallocatedPaise: 0,
      );
    }

    var remainingToAllocate = availablePaise;
    final allocations = <AllocationDraft>[];
    var totalAllocated = 0;

    for (final line in openLines) {
      if (remainingToAllocate <= 0) break;
      final lineRem = line.remainingPaise;
      if (lineRem <= 0) continue;

      final toAlloc = remainingToAllocate < lineRem ? remainingToAllocate : lineRem;
      allocations.add(AllocationDraft(
        billLineId: line.billLineId,
        amountPaise: toAlloc,
      ));
      totalAllocated += toAlloc;
      remainingToAllocate -= toAlloc;
    }

    return AllocationResult(
      allocations: allocations,
      totalAllocatedPaise: totalAllocated,
      unallocatedPaise: remainingToAllocate,
    );
  }

  /// Validates user-provided custom allocations against [openLines] and [availablePaise].
  /// Throws [SocietyException] if invalid.
  static AllocationResult validateCustomAllocations({
    required List<OpenBillLine> openLines,
    required List<AllocationDraft> drafts,
    required int availablePaise,
  }) {
    final linesMap = {for (final l in openLines) l.billLineId: l};
    final seen = <int>{};
    var totalAllocated = 0;

    for (final d in drafts) {
      if (d.amountPaise <= 0) {
        throw const SocietyException(
          'validation',
          'Each allocation amount must be greater than zero',
        );
      }
      if (seen.contains(d.billLineId)) {
        throw const SocietyException(
          'validation',
          'Duplicate allocation for the same bill line',
        );
      }
      seen.add(d.billLineId);

      final line = linesMap[d.billLineId];
      if (line == null) {
        throw const SocietyException(
          'not_found',
          'Selected bill line does not belong to open bills of this unit',
        );
      }

      if (d.amountPaise > line.remainingPaise) {
        throw SocietyException(
          'over_allocation',
          'Allocation of ${d.amountPaise} paise exceeds remaining payable of ${line.remainingPaise} paise on "${line.chargeHeadName}"',
        );
      }

      totalAllocated += d.amountPaise;
    }

    if (totalAllocated > availablePaise) {
      throw SocietyException(
        'over_allocation',
        'Total allocation ($totalAllocated paise) exceeds available receipt amount ($availablePaise paise)',
      );
    }

    return AllocationResult(
      allocations: drafts,
      totalAllocatedPaise: totalAllocated,
      unallocatedPaise: availablePaise - totalAllocated,
    );
  }
}
