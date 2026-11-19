import 'dart:convert';
import '../../core/money.dart';

class InterestSegment {
  final String fromDate;
  final String toDate;
  final int days;
  final int basePaise;
  final int rateBp;

  const InterestSegment({
    required this.fromDate,
    required this.toDate,
    required this.days,
    required this.basePaise,
    required this.rateBp,
  });

  Map<String, Object?> toMap() => {
    'from_date': fromDate,
    'to_date': toDate,
    'days': days,
    'base_paise': basePaise,
    'rate_bp': rateBp,
  };

  factory InterestSegment.fromMap(Map<String, Object?> m) => InterestSegment(
    fromDate: m['from_date'] as String,
    toDate: m['to_date'] as String,
    days: m['days'] as int,
    basePaise: m['base_paise'] as int,
    rateBp: m['rate_bp'] as int,
  );
}

class BillInterestResult {
  final int sourceBillId;
  final String fromDate;
  final String toDate;
  final int amountPaise;
  final List<InterestSegment> segments;

  const BillInterestResult({
    required this.sourceBillId,
    required this.fromDate,
    required this.toDate,
    required this.amountPaise,
    required this.segments,
  });

  String get workingJson => jsonEncode(segments.map((s) => s.toMap()).toList());
}

class UnitInterestResult {
  final int unitId;
  final int totalInterestPaise;
  final List<BillInterestResult> billResults;

  const UnitInterestResult({
    required this.unitId,
    required this.totalInterestPaise,
    required this.billResults,
  });
}

class SourceBillLineInfo {
  final int lineId;
  final int amountPaise;
  final int payablePaise;
  final bool isInterestBearing;
  final List<LineAllocationInfo> allocations;

  const SourceBillLineInfo({
    required this.lineId,
    required this.amountPaise,
    required this.payablePaise,
    required this.isInterestBearing,
    required this.allocations,
  });
}

class LineAllocationInfo {
  final String allocationDate;
  final int allocatedPaise;

  const LineAllocationInfo({
    required this.allocationDate,
    required this.allocatedPaise,
  });
}

class SourceBillInfo {
  final int billId;
  final String billDate;
  final String dueDate;
  final String? lastAccruedToDate;
  final List<SourceBillLineInfo> lines;

  const SourceBillInfo({
    required this.billId,
    required this.billDate,
    required this.dueDate,
    this.lastAccruedToDate,
    required this.lines,
  });
}

class InterestCalculator {
  /// Calculates late payment interest for a single source bill.
  ///
  /// Inputs:
  /// - [bill]: source bill info with its lines and line allocations
  /// - [interestStartDate]: overall society setting `interest.start_date`
  /// - [graceDays]: `interest.grace_days`
  /// - [rateBp]: interest rate in basis points (e.g. 1200 for 12.00%)
  /// - [interestThrough]: target date up to which interest is calculated (typically `target_bill_date - 1 day`)
  static BillInterestResult? calculateForSourceBill({
    required SourceBillInfo bill,
    required String interestStartDate,
    required int graceDays,
    required int rateBp,
    required String interestThrough,
  }) {
    if (rateBp <= 0) return null;

    // 1. Calculate first_day = max(due_date + grace_days + 1, interest.start_date, last accrued to_date + 1)
    final dueParsed = DateTime.parse(bill.dueDate);
    final graceDue = dueParsed.add(Duration(days: graceDays + 1));
    final graceDueStr = _formatDate(graceDue);

    var firstDay = graceDueStr;
    if (interestStartDate.compareTo(firstDay) > 0) {
      firstDay = interestStartDate;
    }
    if (bill.lastAccruedToDate != null) {
      final nextAccrual = DateTime.parse(bill.lastAccruedToDate!).add(const Duration(days: 1));
      final nextAccrualStr = _formatDate(nextAccrual);
      if (nextAccrualStr.compareTo(firstDay) > 0) {
        firstDay = nextAccrualStr;
      }
    }

    final lastDay = interestThrough;
    if (firstDay.compareTo(lastDay) > 0) {
      return null;
    }

    // 2. Identify interest-bearing charge lines
    final ibLines = bill.lines.where((l) => l.isInterestBearing).toList();
    if (ibLines.isEmpty) return null;

    // 3. For each day from firstDay to lastDay:
    // base_on_day = sum over interest-bearing charge lines of:
    // max(line.payablePaise - sum(allocations where allocation_date <= day), 0)
    // If a line's allocations cover its full payable, its base is 0.
    final firstDt = DateTime.parse(firstDay);
    final lastDt = DateTime.parse(lastDay);

    final dailyBases = <int>[];
    final totalDays = lastDt.difference(firstDt).inDays + 1;

    for (var i = 0; i < totalDays; i++) {
      final currentDt = firstDt.add(Duration(days: i));
      final currentDayStr = _formatDate(currentDt);

      var dayBase = 0;
      for (final line in ibLines) {
        var allocOnDay = 0;
        for (final alloc in line.allocations) {
          if (alloc.allocationDate.compareTo(currentDayStr) <= 0) {
            allocOnDay += alloc.allocatedPaise;
          }
        }
        final rem = line.payablePaise - allocOnDay;
        if (rem > 0) {
          dayBase += rem;
        }
      }
      dailyBases.add(dayBase);
    }

    // 4. Group equal consecutive (base, rate) days into segments
    final segments = <InterestSegment>[];
    var segStartIdx = 0;

    while (segStartIdx < dailyBases.length) {
      final segBase = dailyBases[segStartIdx];
      var segEndIdx = segStartIdx;
      while (segEndIdx + 1 < dailyBases.length && dailyBases[segEndIdx + 1] == segBase) {
        segEndIdx++;
      }

      final segFrom = _formatDate(firstDt.add(Duration(days: segStartIdx)));
      final segTo = _formatDate(firstDt.add(Duration(days: segEndIdx)));
      final segDays = segEndIdx - segStartIdx + 1;

      segments.add(InterestSegment(
        fromDate: segFrom,
        toDate: segTo,
        days: segDays,
        basePaise: segBase,
        rateBp: rateBp,
      ));

      segStartIdx = segEndIdx + 1;
    }

    // 5. Calculate numerator = sum(base * rate_bp * days)
    // interest = roundHalfUp(numerator, 365 * 10000)
    var totalNumerator = 0;
    for (final seg in segments) {
      if (seg.basePaise > 0) {
        totalNumerator += seg.basePaise * seg.rateBp * seg.days;
      }
    }

    if (totalNumerator <= 0) {
      return null;
    }

    final interestPaise = roundHalfUp(totalNumerator, 365 * 10000);
    if (interestPaise <= 0) {
      return null;
    }

    return BillInterestResult(
      sourceBillId: bill.billId,
      fromDate: firstDay,
      toDate: lastDay,
      amountPaise: interestPaise,
      segments: segments,
    );
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
