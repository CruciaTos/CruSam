import '../../core/money.dart';
import '../../core/society_exception.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/member_models.dart';
import 'gst_calculator.dart';
import 'meter_calculator.dart';

class CalculatedLine {
  final ChargeHead head;
  final String lineKind;
  final String? description;
  final int? quantityMilli;
  final int? ratePaise;
  final int amountPaise;
  final int gstRateBp;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int payablePaise;
  final bool isInterestBearing;

  const CalculatedLine({
    required this.head,
    this.lineKind = 'charge',
    this.description,
    this.quantityMilli,
    this.ratePaise,
    required this.amountPaise,
    this.gstRateBp = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.roundOffPaise = 0,
    required this.payablePaise,
    required this.isInterestBearing,
  });
}

class CalculatedBill {
  final int unitId;
  final int subtotalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int totalPaise;
  final List<CalculatedLine> lines;

  const CalculatedBill({
    required this.unitId,
    required this.subtotalPaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    required this.lines,
  });
}

class BillCalculator {
  const BillCalculator();

  static int monthsForFrequency(String frequency) {
    switch (frequency.toLowerCase()) {
      case 'quarterly':
        return 3;
      case 'half_yearly':
        return 6;
      case 'yearly':
        return 12;
      case 'monthly':
      default:
        return 1;
    }
  }

  static CalculatedBill calculateUnitBill({
    required UnitRow unit,
    required String billDate,
    required String frequency,
    required List<BillingRule> activeRules,
    required Map<int, ChargeHead> headsMap,
    required Map<int, MeterType> meterTypesMap,
    required Map<int, int> meterConsumptions, // meterTypeId -> consumptionMilli
    required bool societyGstRegistered,
    String? gstEffectiveFrom,
    int? memberGstLimitPaise,
    String roundMode = 'none', // 'none' or 'rupee'
    int lateInterestPaise = 0,
    ChargeHead? lateInterestHead,
  }) {
    final months = monthsForFrequency(frequency);

    // 1. Pick one rule per charge head:
    // - effective_from <= billDate and (effective_to is null or effective_to >= billDate)
    // - rule with matching unit_type_id beats general rule (unit_type_id == null)
    // - if occupancy_filter set and does not match unit.occupancy, skip rule
    final candidateRules = <int, List<BillingRule>>{};
    for (final r in activeRules) {
      if (!r.isActive) continue;
      if (r.effectiveFrom.compareTo(billDate) > 0) continue;
      if (r.effectiveTo != null && r.effectiveTo!.compareTo(billDate) < 0) continue;
      if (r.occupancyFilter != null && r.occupancyFilter != unit.occupancy) continue;

      candidateRules.putIfAbsent(r.chargeHeadId, () => []).add(r);
    }

    final selectedRules = <BillingRule>[];
    for (final entry in candidateRules.entries) {
      final list = entry.value;
      BillingRule? chosen;

      // Check unit_type_id match
      final specific = list.where((r) => r.unitTypeId == unit.unitTypeId).toList();
      final general = list.where((r) => r.unitTypeId == null).toList();

      if (specific.length > 1) {
        throw SocietyException('rule_conflict', 'Multiple specific billing rules match head ID ${entry.key}');
      } else if (specific.length == 1) {
        chosen = specific.first;
      } else if (general.length > 1) {
        throw SocietyException('rule_conflict', 'Multiple general billing rules match head ID ${entry.key}');
      } else if (general.length == 1) {
        chosen = general.first;
      }

      if (chosen != null) {
        selectedRules.add(chosen);
      }
    }

    // Separate into non-percentage and percentage rules
    final nonPercentRules = selectedRules.where((r) => r.ruleType != 'percent_of_heads').toList();
    final percentRules = selectedRules.where((r) => r.ruleType == 'percent_of_heads').toList();

    // Sort non-percent rules by charge head sort_order
    nonPercentRules.sort((a, b) {
      final sa = headsMap[a.chargeHeadId]?.sortOrder ?? 0;
      final sb = headsMap[b.chargeHeadId]?.sortOrder ?? 0;
      return sa.compareTo(sb);
    });

    final rawAmounts = <int, int>{}; // headId -> amountPaise
    final linesDraft = <Map<String, Object?>>[];

    // 2. Calculate non-percentage heads
    for (final rule in nonPercentRules) {
      final head = headsMap[rule.chargeHeadId];
      if (head == null) continue;

      int amount = 0;
      String? desc;
      int? qty;
      int? rate;

      if (rule.ruleType == 'area_and_fixed') {
        final a1Amount = areaAmount(unit.area1Centi, rule.rate1Paise);
        final a2Amount = areaAmount(unit.area2Centi, rule.rate2Paise);
        final perMonth = a1Amount + a2Amount + rule.fixedPaise;
        amount = months * perMonth;
        rate = rule.rate1Paise > 0 ? rule.rate1Paise : rule.fixedPaise;
      } else if (rule.ruleType == 'metered_slab') {
        if (rule.meterTypeId == null) {
          throw SocietyException('missing_meter', 'Billing rule for "${head.name}" requires a meter type');
        }
        final mType = meterTypesMap[rule.meterTypeId!];
        if (mType == null) {
          throw SocietyException('missing_meter', 'Meter type ${rule.meterTypeId} not found');
        }

        final consumption = meterConsumptions[rule.meterTypeId!];
        if (consumption == null) {
          throw SocietyException('missing_reading', 'Missing meter reading for unit ${unit.unitNo} (${mType.name})');
        }

        amount = MeterCalculator.calculateCharge(
          consumptionMilli: consumption,
          isCumulative: mType.isCumulative,
          minimumPaise: mType.minimumPaise,
          slabs: mType.slabs,
        );
        qty = consumption;
      }

      if (amount > 0) {
        rawAmounts[head.id] = amount;
        linesDraft.add({
          'head': head,
          'amount': amount,
          'desc': desc,
          'qty': qty,
          'rate': rate,
        });
      }
    }

    // 3. Calculate percentage heads
    for (final rule in percentRules) {
      final head = headsMap[rule.chargeHeadId];
      if (head == null) continue;

      var baseSum = 0;
      for (final baseId in rule.baseHeadIds) {
        baseSum += rawAmounts[baseId] ?? 0;
      }

      final amount = percentOf(baseSum, rule.percentBp);
      if (amount > 0) {
        rawAmounts[head.id] = amount;
        linesDraft.add({
          'head': head,
          'amount': amount,
          'rate': rule.percentBp,
        });
      }
    }

    // Add late interest line if present
    if (lateInterestPaise > 0 && lateInterestHead != null) {
      linesDraft.add({
        'head': lateInterestHead,
        'amount': lateInterestPaise,
        'desc': 'Late Payment Interest',
        'qty': null,
        'rate': null,
      });
    }

    if (linesDraft.isEmpty) {
      return CalculatedBill(
        unitId: unit.id,
        subtotalPaise: 0,
        cgstPaise: 0,
        sgstPaise: 0,
        igstPaise: 0,
        roundOffPaise: 0,
        totalPaise: 0,
        lines: const [],
      );
    }

    // 4. GST Calculation
    final gstInputs = linesDraft.map((d) {
      final h = d['head'] as ChargeHead;
      final amt = d['amount'] as int;
      return GstLineInput(
        chargeHeadId: h.id,
        amountPaise: amt,
        isGstApplicable: h.isGstApplicable,
        gstRateBp: h.defaultGstRateBp ?? 0,
      );
    }).toList();

    final gstOutputs = GstCalculator.calculateMemberGst(
      societyGstRegistered: societyGstRegistered,
      billDate: billDate,
      gstEffectiveFrom: gstEffectiveFrom,
      months: months,
      memberLimitPaise: memberGstLimitPaise,
      lines: gstInputs,
    );

    // 5. Build raw lines before rounding
    var subtotal = 0;
    var totalCgst = 0;
    var totalSgst = 0;

    for (var i = 0; i < linesDraft.length; i++) {
      final d = linesDraft[i];
      final gst = gstOutputs[i];
      final amt = d['amount'] as int;
      subtotal += amt;
      totalCgst += gst.cgstPaise;
      totalSgst += gst.sgstPaise;
    }

    final rawTotal = subtotal + totalCgst + totalSgst;
    var roundOff = 0;

    if (roundMode.toLowerCase() == 'rupee') {
      final targetTotal = roundHalfUp(rawTotal, 100) * 100;
      roundOff = targetTotal - rawTotal;
    }

    final finalTotal = rawTotal + roundOff;

    final resultLines = <CalculatedLine>[];
    for (var i = 0; i < linesDraft.length; i++) {
      final d = linesDraft[i];
      final gst = gstOutputs[i];
      final h = d['head'] as ChargeHead;
      final amt = d['amount'] as int;
      final isLast = i == linesDraft.length - 1;
      final lineRoundOff = isLast ? roundOff : 0;
      final linePayable = amt + gst.cgstPaise + gst.sgstPaise + lineRoundOff;

      resultLines.add(CalculatedLine(
        head: h,
        lineKind: h.headKind,
        description: d['desc'] as String?,
        quantityMilli: d['qty'] as int?,
        ratePaise: d['rate'] as int?,
        amountPaise: amt,
        gstRateBp: gst.gstRateBp,
        cgstPaise: gst.cgstPaise,
        sgstPaise: gst.sgstPaise,
        igstPaise: 0,
        roundOffPaise: lineRoundOff,
        payablePaise: linePayable,
        isInterestBearing: h.isInterestBearing,
      ));
    }

    return CalculatedBill(
      unitId: unit.id,
      subtotalPaise: subtotal,
      cgstPaise: totalCgst,
      sgstPaise: totalSgst,
      igstPaise: 0,
      roundOffPaise: roundOff,
      totalPaise: finalTotal,
      lines: resultLines,
    );
  }
}
