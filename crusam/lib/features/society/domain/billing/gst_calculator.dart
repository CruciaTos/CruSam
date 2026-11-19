import '../../core/money.dart';

class GstLineInput {
  final int chargeHeadId;
  final int amountPaise;
  final bool isGstApplicable;
  final int gstRateBp;

  const GstLineInput({
    required this.chargeHeadId,
    required this.amountPaise,
    required this.isGstApplicable,
    required this.gstRateBp,
  });
}

class GstLineOutput {
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int gstRateBp;

  const GstLineOutput({
    required this.cgstPaise,
    required this.sgstPaise,
    this.igstPaise = 0,
    required this.gstRateBp,
  });

  int get totalGstPaise => cgstPaise + sgstPaise + igstPaise;
}

class GstCalculator {
  const GstCalculator();

  static List<GstLineOutput> calculateMemberGst({
    required bool societyGstRegistered,
    required String billDate,
    String? gstEffectiveFrom,
    required int months,
    int? memberLimitPaise, // e.g. 750000 (₹7,500/month)
    required List<GstLineInput> lines,
  }) {
    if (!societyGstRegistered || (gstEffectiveFrom != null && billDate.compareTo(gstEffectiveFrom) < 0)) {
      return lines.map((l) => const GstLineOutput(cgstPaise: 0, sgstPaise: 0, gstRateBp: 0)).toList();
    }

    // 1. Calculate sum of GST-applicable charges
    var applicableSum = 0;
    for (final line in lines) {
      if (line.isGstApplicable && line.gstRateBp > 0) {
        applicableSum += line.amountPaise;
      }
    }

    if (applicableSum == 0) {
      return lines.map((l) => const GstLineOutput(cgstPaise: 0, sgstPaise: 0, gstRateBp: 0)).toList();
    }

    // 2. Limit test: monthly_taxable = sum / months
    final m = months > 0 ? months : 1;
    final monthlyTaxable = applicableSum ~/ m;

    if (memberLimitPaise != null && memberLimitPaise > 0 && monthlyTaxable <= memberLimitPaise) {
      // Exempt under threshold
      return lines.map((l) => const GstLineOutput(cgstPaise: 0, sgstPaise: 0, gstRateBp: 0)).toList();
    }

    // 3. Taxable: calculate GST by line
    final result = <GstLineOutput>[];
    for (final line in lines) {
      if (!line.isGstApplicable || line.gstRateBp <= 0 || line.amountPaise <= 0) {
        result.add(const GstLineOutput(cgstPaise: 0, sgstPaise: 0, gstRateBp: 0));
        continue;
      }

      final totalGst = percentOf(line.amountPaise, line.gstRateBp);
      final cgst = totalGst ~/ 2;
      final sgst = totalGst - cgst;

      result.add(GstLineOutput(
        cgstPaise: cgst,
        sgstPaise: sgst,
        igstPaise: 0,
        gstRateBp: line.gstRateBp,
      ));
    }

    return result;
  }
}
