import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/society_exception.dart';
import '../../data/models/statement_models.dart';
import '../ledger/ledger_service.dart';

class FinancialStatementService {
  final Database db;
  final LedgerService ledgerService;

  FinancialStatementService(this.db, this.ledgerService);

  // ----------------------------------------------------------------------
  // 1. Income and Expenditure Statement
  // ----------------------------------------------------------------------
  Future<IncomeExpenditureStatement> incomeAndExpenditure(
    int societyId,
    String fromDate,
    String toDate,
  ) async {
    final tb = await ledgerService.trialBalance(societyId, fromDate, toDate);

    // Income accounts: code starts with '3'
    // Display balance = credit - debit for income
    final incomeRows = tb.rows.where((r) => r.accountCode.startsWith('3')).toList();
    final expenseRows = tb.rows.where((r) => r.accountCode.startsWith('4')).toList();

    // Group income accounts
    final incomeGroupMap = <String, List<StatementLine>>{};
    for (final r in incomeRows) {
      final bal = (r.closingCreditPaise - r.closingDebitPaise) - (r.openingCreditPaise - r.openingDebitPaise);
      if (bal != 0 || r.debitPaise != 0 || r.creditPaise != 0) {
        final grp = r.groupName;
        incomeGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
          code: r.accountCode,
          name: r.accountName,
          amountPaise: bal,
          groupName: grp,
        ));
      }
    }

    final incomeGroups = incomeGroupMap.entries.map((e) {
      final grpTotal = e.value.fold<int>(0, (sum, line) => sum + line.amountPaise);
      return StatementGroup(title: e.key, lines: e.value, totalPaise: grpTotal);
    }).toList();

    final totalIncome = incomeGroups.fold<int>(0, (sum, g) => sum + g.totalPaise);

    // Group expense accounts: code starts with '4'
    // Display balance = debit - credit for expense
    final expenseGroupMap = <String, List<StatementLine>>{};
    for (final r in expenseRows) {
      final bal = (r.closingDebitPaise - r.closingCreditPaise) - (r.openingDebitPaise - r.openingCreditPaise);
      if (bal != 0 || r.debitPaise != 0 || r.creditPaise != 0) {
        final grp = r.groupName;
        expenseGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
          code: r.accountCode,
          name: r.accountName,
          amountPaise: bal,
          groupName: grp,
        ));
      }
    }

    final expenseGroups = expenseGroupMap.entries.map((e) {
      final grpTotal = e.value.fold<int>(0, (sum, line) => sum + line.amountPaise);
      return StatementGroup(title: e.key, lines: e.value, totalPaise: grpTotal);
    }).toList();

    final totalExpense = expenseGroups.fold<int>(0, (sum, g) => sum + g.totalPaise);
    final netSurplusDeficit = totalIncome - totalExpense;

    return IncomeExpenditureStatement(
      fromDate: fromDate,
      toDate: toDate,
      incomeGroups: incomeGroups,
      expenseGroups: expenseGroups,
      totalIncomePaise: totalIncome,
      totalExpensePaise: totalExpense,
      netSurplusDeficitPaise: netSurplusDeficit,
    );
  }

  // ----------------------------------------------------------------------
  // 2. Balance Sheet Statement
  // ----------------------------------------------------------------------
  Future<BalanceSheetStatement> balanceSheet(
    int societyId,
    String asOfDate,
  ) async {
    // 1. Get ledger trial balance as of asOfDate
    final tb = await ledgerService.trialBalance(societyId, '1900-01-01', asOfDate);

    // Check financial year status as of date to know if current period is closed
    final fyRows = await db.rawQuery('''
      SELECT id, status, closing_entry_id FROM financial_years
      WHERE society_id = ? AND start_date <= ? AND end_date >= ?
    ''', [societyId, asOfDate, asOfDate]);

    final bool isFyClosed = fyRows.isNotEmpty && fyRows.first['status'] == 'closed';

    // 2. Separate member advances and member receivables by unit
    // Accounting Rule: Credit balances in members_receivable by unit show under liabilities
    // as Advances from Members. Debit balances show under assets.
    final memberRecAcc = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');
    final unitBalRows = await db.rawQuery('''
      SELECT jl.unit_id,
             COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as balance_paise
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND jl.account_id = ? AND je.entry_date <= ?
        AND jl.unit_id IS NOT NULL
      GROUP BY jl.unit_id
    ''', [societyId, memberRecAcc, asOfDate]);

    int memberDebitPaise = 0;
    int memberAdvancePaise = 0;

    if (unitBalRows.isNotEmpty) {
      for (final r in unitBalRows) {
        final bal = r['balance_paise'] as int? ?? 0;
        if (bal > 0) {
          memberDebitPaise += bal;
        } else if (bal < 0) {
          memberAdvancePaise += (-bal);
        }
      }
    } else {
      // If no unit breakdown, use account net balance
      final recRow = tb.rows.where((r) => r.accountId == memberRecAcc);
      if (recRow.isNotEmpty) {
        final bal = recRow.first.closingDebitPaise - recRow.first.closingCreditPaise;
        if (bal >= 0) {
          memberDebitPaise = bal;
        } else {
          memberAdvancePaise = -bal;
        }
      }
    }

    // 3. Separate vendor advances and payables by vendor
    // Accounting Rule: Debit balances in vendors_payable by vendor show under assets as Advances to Vendors.
    final vendorPayableAcc = await ledgerService.accountIdForKey(db, societyId, 'vendors_payable');
    final vendorBalRows = await db.rawQuery('''
      SELECT jl.vendor_id,
             COALESCE(SUM(jl.credit_paise - jl.debit_paise), 0) as balance_paise
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND jl.account_id = ? AND je.entry_date <= ?
        AND jl.vendor_id IS NOT NULL
      GROUP BY jl.vendor_id
    ''', [societyId, vendorPayableAcc, asOfDate]);

    int vendorCreditPaise = 0;
    int vendorAdvancePaise = 0;

    if (vendorBalRows.isNotEmpty) {
      for (final r in vendorBalRows) {
        final bal = r['balance_paise'] as int? ?? 0;
        if (bal > 0) {
          vendorCreditPaise += bal;
        } else if (bal < 0) {
          vendorAdvancePaise += (-bal);
        }
      }
    } else {
      final payRow = tb.rows.where((r) => r.accountId == vendorPayableAcc);
      if (payRow.isNotEmpty) {
        final bal = payRow.first.closingCreditPaise - payRow.first.closingDebitPaise;
        if (bal >= 0) {
          vendorCreditPaise = bal;
        } else {
          vendorAdvancePaise = -bal;
        }
      }
    }

    // 4. Build Asset Groups (code starts with '1')
    final assetGroupMap = <String, List<StatementLine>>{};
    for (final r in tb.rows.where((r) => r.accountCode.startsWith('1'))) {
      if (r.accountId == memberRecAcc) {
        // Handled via memberDebitPaise
        continue;
      }
      final bal = r.closingDebitPaise - r.closingCreditPaise;
      if (bal != 0) {
        final grp = r.groupName;
        assetGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
          code: r.accountCode,
          name: r.accountName,
          amountPaise: bal,
          groupName: grp,
        ));
      }
    }

    if (memberDebitPaise > 0) {
      final grp = 'Receivables';
      assetGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
        code: '1201',
        name: 'Members Receivable',
        amountPaise: memberDebitPaise,
        groupName: grp,
      ));
    }

    if (vendorAdvancePaise > 0) {
      final grp = 'Advances & Deposits';
      assetGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
        code: '1701',
        name: 'Advances to Vendors',
        amountPaise: vendorAdvancePaise,
        groupName: grp,
      ));
    }

    final assetGroups = assetGroupMap.entries.map((e) {
      final total = e.value.fold<int>(0, (sum, l) => sum + l.amountPaise);
      return StatementGroup(title: e.key, lines: e.value, totalPaise: total);
    }).toList();

    final totalAssets = assetGroups.fold<int>(0, (sum, g) => sum + g.totalPaise);

    // 5. Build Liability and Fund Groups (code starts with '2')
    final liabilityGroupMap = <String, List<StatementLine>>{};
    for (final r in tb.rows.where((r) => r.accountCode.startsWith('2'))) {
      if (r.accountId == vendorPayableAcc) {
        // Handled via vendorCreditPaise
        continue;
      }
      final bal = r.closingCreditPaise - r.closingDebitPaise;
      if (bal != 0) {
        final grp = r.groupName;
        liabilityGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
          code: r.accountCode,
          name: r.accountName,
          amountPaise: bal,
          groupName: grp,
        ));
      }
    }

    if (vendorCreditPaise > 0) {
      final grp = 'Current Liabilities';
      liabilityGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
        code: '2501',
        name: 'Vendors Payable',
        amountPaise: vendorCreditPaise,
        groupName: grp,
      ));
    }

    if (memberAdvancePaise > 0) {
      final grp = 'Current Liabilities';
      liabilityGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
        code: '2403',
        name: 'Advances from Members',
        amountPaise: memberAdvancePaise,
        groupName: grp,
      ));
    }

    // 6. Current period surplus/deficit if year is NOT closed yet
    int currentPeriodSurplusDeficit = 0;
    if (!isFyClosed) {
      final totalIncomePaise = tb.rows
          .where((r) => r.accountCode.startsWith('3'))
          .fold<int>(0, (sum, r) => sum + (r.closingCreditPaise - r.closingDebitPaise));
      final totalExpensePaise = tb.rows
          .where((r) => r.accountCode.startsWith('4'))
          .fold<int>(0, (sum, r) => sum + (r.closingDebitPaise - r.closingCreditPaise));

      currentPeriodSurplusDeficit = totalIncomePaise - totalExpensePaise;

      if (currentPeriodSurplusDeficit != 0) {
        final grp = 'Reserves & Surplus';
        final isDeficit = currentPeriodSurplusDeficit < 0;
        liabilityGroupMap.putIfAbsent(grp, () => []).add(StatementLine(
          code: '2801-CURR',
          name: isDeficit
              ? 'Current Period Deficit'
              : 'Current Period Surplus',
          amountPaise: currentPeriodSurplusDeficit,
          groupName: grp,
        ));
      }
    }

    final liabilityGroups = liabilityGroupMap.entries.map((e) {
      final total = e.value.fold<int>(0, (sum, l) => sum + l.amountPaise);
      return StatementGroup(title: e.key, lines: e.value, totalPaise: total);
    }).toList();

    final totalLiabilities = liabilityGroups.fold<int>(0, (sum, g) => sum + g.totalPaise);

    return BalanceSheetStatement(
      asOfDate: asOfDate,
      assetGroups: assetGroups,
      liabilityGroups: liabilityGroups,
      totalAssetsPaise: totalAssets,
      totalLiabilitiesPaise: totalLiabilities,
      currentPeriodSurplusDeficitPaise: currentPeriodSurplusDeficit,
      isBalanced: totalAssets == totalLiabilities,
    );
  }

  // ----------------------------------------------------------------------
  // 3. Receipts and Payments Statement
  // ----------------------------------------------------------------------
  Future<ReceiptsPaymentsStatement> receiptsAndPayments(
    int societyId,
    String fromDate,
    String toDate,
  ) async {
    // 1. Identify bank and cash accounts (under group 1100 or accountType in ('bank', 'cash'))
    final bankAccounts = await db.rawQuery('''
      SELECT a.id, a.code, a.name
      FROM accounts a
      JOIN account_groups g ON g.id = a.group_id
      WHERE a.society_id = ? AND (g.code = '1100' OR a.account_kind IN ('bank', 'cash'))
    ''', [societyId]);

    final bankAccIds = bankAccounts.map((a) => a['id'] as int).toSet();
    if (bankAccIds.isEmpty) {
      return ReceiptsPaymentsStatement(
        fromDate: fromDate,
        toDate: toDate,
        openingBalancePaise: 0,
        receipts: const [],
        totalReceiptsPaise: 0,
        payments: const [],
        totalPaymentsPaise: 0,
        closingBalancePaise: 0,
      );
    }

    final placeholders = List.filled(bankAccIds.length, '?').join(',');

    // 2. Opening balance of all bank/cash accounts prior to fromDate (or opening_balance on fromDate)
    final openingRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as opening_paise
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND jl.account_id IN ($placeholders)
        AND (je.entry_date < ? OR (je.entry_date = ? AND je.source_type IN ('opening', 'opening_balance')))
    ''', [societyId, ...bankAccIds, fromDate, fromDate]);

    final openingBalance = openingRows.first['opening_paise'] as int? ?? 0;

    // 3. Receipts: debits into bank/cash accounts in period, grouped by contra account
    final receiptRows = await db.rawQuery('''
      SELECT contra.code as contra_code, contra.name as contra_name,
             COALESCE(SUM(contra_line.credit_paise), 0) as amount_paise
      FROM journal_lines bank_line
      JOIN journal_entries je ON je.id = bank_line.entry_id
      JOIN journal_lines contra_line ON contra_line.entry_id = je.id AND contra_line.id != bank_line.id
      JOIN accounts contra ON contra.id = contra_line.account_id
      WHERE bank_line.society_id = ? AND bank_line.account_id IN ($placeholders)
        AND bank_line.debit_paise > 0
        AND contra_line.credit_paise > 0
        AND contra_line.account_id NOT IN ($placeholders)
        AND je.source_type NOT IN ('opening', 'opening_balance')
        AND je.entry_date >= ? AND je.entry_date <= ?
      GROUP BY contra.id
      ORDER BY contra.code
    ''', [societyId, ...bankAccIds, ...bankAccIds, fromDate, toDate]);

    final receipts = receiptRows.map((r) => StatementLine(
      code: r['contra_code'] as String,
      name: r['contra_name'] as String,
      amountPaise: r['amount_paise'] as int,
    )).toList();

    final totalReceipts = receipts.fold<int>(0, (sum, r) => sum + r.amountPaise);

    // 4. Payments: credits out of bank/cash accounts in period, grouped by contra account
    final paymentRows = await db.rawQuery('''
      SELECT contra.code as contra_code, contra.name as contra_name,
             COALESCE(SUM(contra_line.debit_paise), 0) as amount_paise
      FROM journal_lines bank_line
      JOIN journal_entries je ON je.id = bank_line.entry_id
      JOIN journal_lines contra_line ON contra_line.entry_id = je.id AND contra_line.id != bank_line.id
      JOIN accounts contra ON contra.id = contra_line.account_id
      WHERE bank_line.society_id = ? AND bank_line.account_id IN ($placeholders)
        AND bank_line.credit_paise > 0
        AND contra_line.debit_paise > 0
        AND contra_line.account_id NOT IN ($placeholders)
        AND je.source_type NOT IN ('opening', 'opening_balance')
        AND je.entry_date >= ? AND je.entry_date <= ?
      GROUP BY contra.id
      ORDER BY contra.code
    ''', [societyId, ...bankAccIds, ...bankAccIds, fromDate, toDate]);

    final payments = paymentRows.map((r) => StatementLine(
      code: r['contra_code'] as String,
      name: r['contra_name'] as String,
      amountPaise: r['amount_paise'] as int,
    )).toList();

    final totalPayments = payments.fold<int>(0, (sum, p) => sum + p.amountPaise);
    final closingBalance = openingBalance + totalReceipts - totalPayments;

    return ReceiptsPaymentsStatement(
      fromDate: fromDate,
      toDate: toDate,
      openingBalancePaise: openingBalance,
      receipts: receipts,
      totalReceiptsPaise: totalReceipts,
      payments: payments,
      totalPaymentsPaise: totalPayments,
      closingBalancePaise: closingBalance,
    );
  }
}
