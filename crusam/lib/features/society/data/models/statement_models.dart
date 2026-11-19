import 'package:flutter/foundation.dart';

@immutable
class StatementLine {
  final String code;
  final String name;
  final int amountPaise;
  final String? groupName;
  final bool isHeader;
  final bool isTotal;

  const StatementLine({
    required this.code,
    required this.name,
    required this.amountPaise,
    this.groupName,
    this.isHeader = false,
    this.isTotal = false,
  });
}

@immutable
class StatementGroup {
  final String title;
  final List<StatementLine> lines;
  final int totalPaise;

  const StatementGroup({
    required this.title,
    required this.lines,
    required this.totalPaise,
  });
}

@immutable
class IncomeExpenditureStatement {
  final String fromDate;
  final String toDate;
  final List<StatementGroup> incomeGroups;
  final List<StatementGroup> expenseGroups;
  final int totalIncomePaise;
  final int totalExpensePaise;
  final int netSurplusDeficitPaise; // income - expense: positive = surplus, negative = deficit

  const IncomeExpenditureStatement({
    required this.fromDate,
    required this.toDate,
    required this.incomeGroups,
    required this.expenseGroups,
    required this.totalIncomePaise,
    required this.totalExpensePaise,
    required this.netSurplusDeficitPaise,
  });

  bool get isSurplus => netSurplusDeficitPaise >= 0;
}

@immutable
class BalanceSheetStatement {
  final String asOfDate;
  final List<StatementGroup> assetGroups;
  final List<StatementGroup> liabilityGroups;
  final int totalAssetsPaise;
  final int totalLiabilitiesPaise;
  final int currentPeriodSurplusDeficitPaise;
  final bool isBalanced;

  const BalanceSheetStatement({
    required this.asOfDate,
    required this.assetGroups,
    required this.liabilityGroups,
    required this.totalAssetsPaise,
    required this.totalLiabilitiesPaise,
    this.currentPeriodSurplusDeficitPaise = 0,
    required this.isBalanced,
  });

  int get differencePaise => totalAssetsPaise - totalLiabilitiesPaise;
}

@immutable
class ReceiptsPaymentsStatement {
  final String fromDate;
  final String toDate;
  final int openingBalancePaise;
  final List<StatementLine> receipts;
  final int totalReceiptsPaise;
  final List<StatementLine> payments;
  final int totalPaymentsPaise;
  final int closingBalancePaise;

  const ReceiptsPaymentsStatement({
    required this.fromDate,
    required this.toDate,
    required this.openingBalancePaise,
    required this.receipts,
    required this.totalReceiptsPaise,
    required this.payments,
    required this.totalPaymentsPaise,
    required this.closingBalancePaise,
  });
}
