import 'dart:math';

import '../../core/money.dart';
import '../../core/society_exception.dart';
import '../../data/models/billing_models.dart';

class MeterCalculator {
  const MeterCalculator();

  static int calculateCharge({
    required int consumptionMilli,
    required bool isCumulative,
    required int minimumPaise,
    required List<MeterSlab> slabs,
  }) {
    if (consumptionMilli < 0) {
      throw const SocietyException('validation', 'Negative meter consumption is not permitted');
    }

    if (consumptionMilli == 0) {
      return minimumPaise;
    }

    if (slabs.isEmpty) {
      return minimumPaise;
    }

    // Sort slabs by sequence
    final sorted = List<MeterSlab>.from(slabs)..sort((a, b) => a.seq.compareTo(b.seq));

    int rawPaise = 0;

    if (isCumulative) {
      var remaining = consumptionMilli;
      var previousLimit = 0;

      for (final slab in sorted) {
        if (remaining <= 0) break;

        final upTo = slab.upToMilli;
        int qtyInTier;

        if (upTo == null) {
          // Final unbounded slab
          qtyInTier = remaining;
        } else {
          final tierCapacity = upTo - previousLimit;
          if (tierCapacity <= 0) continue;
          qtyInTier = min(remaining, tierCapacity);
          previousLimit = upTo;
        }

        final tierAmount = roundHalfUp(qtyInTier * slab.ratePaise, 1000);
        rawPaise += tierAmount;
        remaining -= qtyInTier;
      }
    } else {
      // Non-cumulative: whole quantity is priced at the rate of the tier it falls in
      MeterSlab? selectedSlab;
      for (final slab in sorted) {
        if (slab.upToMilli == null || consumptionMilli <= slab.upToMilli!) {
          selectedSlab = slab;
          break;
        }
      }
      selectedSlab ??= sorted.last;
      rawPaise = roundHalfUp(consumptionMilli * selectedSlab.ratePaise, 1000);
    }

    return max(rawPaise, minimumPaise);
  }
}
