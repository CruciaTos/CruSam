import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/society_exception.dart';
import '../../data/models/ledger_models.dart';
import '../ledger/ledger_service.dart';

class YearEndService {
  final Database db;
  final LedgerService ledger;

  YearEndService(this.db, this.ledger);

  // -------------------------------------------------------------
  // Preconditions Check
  // -------------------------------------------------------------
  Future<List<String>> checkPreconditions(int societyId, int fyId) async {
    final issues = <String>[];

    final fyRows = await db.query(
      'financial_years',
      where: 'society_id = ? AND id = ?',
      whereArgs: [societyId, fyId],
    );
    if (fyRows.isEmpty) throw const SocietyException('not_found', 'Financial year not found');
    final fy = fyRows.first;

    if (fy['status'] != 'open') {
      issues.add('Financial year is already closed');
    }

    // Check earlier open years
    final earlierOpen = await db.rawQuery('''
      SELECT code FROM financial_years
      WHERE society_id = ? AND start_date < ? AND status = 'open'
    ''', [societyId, fy['start_date']]);
    if (earlierOpen.isNotEmpty) {
      final codes = earlierOpen.map((r) => r['code']).join(', ');
      issues.add('Prior financial years ($codes) must be closed first');
    }

    // Check draft bills and draft bill runs
    final draftBills = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM bills
      WHERE society_id = ? AND fy_id = ? AND status = 'draft'
    ''', [societyId, fyId]);
    if ((draftBills.first['cnt'] as int? ?? 0) > 0) {
      issues.add('There are draft member bills in this financial year. Post or delete them before close.');
    }

    final draftRuns = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM bill_runs
      WHERE society_id = ? AND fy_id = ? AND status = 'draft'
    ''', [societyId, fyId]);
    if ((draftRuns.first['cnt'] as int? ?? 0) > 0) {
      issues.add('There are draft bill runs in this financial year. Post or delete them before close.');
    }

    // Check trial balance
    final tb = await ledger.trialBalance(societyId, fy['start_date'] as String, fy['end_date'] as String);
    if (!tb.isBalanced) {
      final diff = (tb.totalClosingDebitPaise - tb.totalClosingCreditPaise).abs();
      issues.add('Trial balance is out of balance. Difference: ₹${(diff / 100).toStringAsFixed(2)}');
    }

    // Check opening balance adjustment account (2899)
    final adjRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as adj_bal
      FROM journal_lines jl
      JOIN accounts a ON a.id = jl.account_id
      JOIN journal_entries je ON je.id = jl.entry_id
      WHERE jl.society_id = ? AND a.code = '2899' AND je.entry_date <= ?
    ''', [societyId, fy['end_date']]);
    final adjBal = adjRows.first['adj_bal'] as int? ?? 0;
    if (adjBal != 0) {
      issues.add('WARNING: Opening balance adjustment account (2899) has an unadjusted balance of ₹${(adjBal.abs() / 100).toStringAsFixed(2)}');
    }

    return issues;
  }

  // -------------------------------------------------------------
  // Close Financial Year
  // -------------------------------------------------------------
  Future<int> closeYear(
    int societyId,
    int fyId, {
    Map<int, int>? fundAppropriations, // fundAccountId -> amountPaise
    String? confirmation,
  }) async {
    final issues = await checkPreconditions(societyId, fyId);
    final blockingIssues = issues.where((i) => !i.startsWith('WARNING:')).toList();
    if (blockingIssues.isNotEmpty) {
      throw SocietyException('close_precondition_failed', blockingIssues.first);
    }

    final hasWarning = issues.any((i) => i.startsWith('WARNING:'));
    if (hasWarning && confirmation != 'CLOSE') {
      throw const SocietyException('confirmation_required', 'Opening adjustment is non-zero. Confirmation "CLOSE" required.');
    }

    return await db.transaction((txn) async {
      final fyRows = await txn.query('financial_years', where: 'id = ?', whereArgs: [fyId]);
      final fy = fyRows.first;
      final startDate = fy['start_date'] as String;
      final endDate = fy['end_date'] as String;

      // Ensure next financial year exists, or create it automatically
      final nextYear = await txn.rawQuery('''
        SELECT id FROM financial_years
        WHERE society_id = ? AND start_date > ?
        ORDER BY start_date ASC LIMIT 1
      ''', [societyId, startDate]);

      if (nextYear.isEmpty) {
        // Auto-create next financial year (e.g. 2026-04-01 -> 2027-04-01 to 2028-03-31)
        final nextStart = DateTime.parse(endDate).add(const Duration(days: 1));
        final nextEnd = DateTime(nextStart.year + 1, 3, 31);
        final nextCode = '${nextStart.year}-${(nextStart.year + 1).toString().substring(2)}';

        final newFyId = await txn.insert('financial_years', {
          'society_id': societyId,
          'code': nextCode,
          'start_date': nextStart.toIso8601String().substring(0, 10),
          'end_date': nextEnd.toIso8601String().substring(0, 10),
          'status': 'open',
        });

        // Copy number series for new financial year
        final seriesRows = await txn.rawQuery('''
          SELECT doc_type, prefix FROM number_series
          WHERE society_id = ? AND fy_id = ?
        ''', [societyId, fyId]);
        for (final s in seriesRows) {
          await txn.insert('number_series', {
            'society_id': societyId,
            'fy_id': newFyId,
            'doc_type': s['doc_type'],
            'prefix': s['prefix'],
            'next_no': 1,
          });
        }
      }

      final incExpAccId = await ledger.accountIdForKey(txn, societyId, 'income_expenditure');

      // 1. Optional appropriations from 2801 to specific funds
      if (fundAppropriations != null && fundAppropriations.isNotEmpty) {
        for (final entry in fundAppropriations.entries) {
          final fundAccId = entry.key;
          final amt = entry.value;
          if (amt <= 0) continue;

          await ledger.post(txn, JournalDraft(
            societyId: societyId,
            entryDate: endDate,
            sourceType: 'fund_appropriation',
            narration: 'Fund Appropriation from Income & Expenditure to Fund',
            lines: [
              JournalLineDraft(
                accountId: incExpAccId,
                debitPaise: amt,
                creditPaise: 0,
                note: 'Appropriation to fund',
              ),
              JournalLineDraft(
                accountId: fundAccId,
                debitPaise: 0,
                creditPaise: amt,
                note: 'Appropriation from I&E',
              ),
            ],
          ));
        }
      }

      // 2. Fetch income and expense balances for the year
      // Income: code starts with '3'. Expense: code starts with '4'.
      final accountBalances = await txn.rawQuery('''
        SELECT a.id, a.code, a.name,
               COALESCE(SUM(jl.debit_paise), 0) as dr_paise,
               COALESCE(SUM(jl.credit_paise), 0) as cr_paise
        FROM accounts a
        JOIN journal_lines jl ON jl.account_id = a.id
        JOIN journal_entries je ON je.id = jl.entry_id
        WHERE a.society_id = ?
          AND (a.code LIKE '3%' OR a.code LIKE '4%')
          AND je.entry_date >= ? AND je.entry_date <= ?
        GROUP BY a.id
      ''', [societyId, startDate, endDate]);

      final closingLines = <JournalLineDraft>[];
      int totalDebits = 0;
      int totalCredits = 0;

      for (final row in accountBalances) {
        final accId = row['id'] as int;
        final code = row['code'] as String;
        final name = row['name'] as String;
        final dr = row['dr_paise'] as int;
        final cr = row['cr_paise'] as int;

        if (code.startsWith('3')) {
          // Income account: normal balance is credit - debit
          final netCredit = cr - dr;
          if (netCredit > 0) {
            // Debit income account to close
            closingLines.add(JournalLineDraft(
              accountId: accId,
              debitPaise: netCredit,
              creditPaise: 0,
              note: 'Close $name to I&E',
            ));
            totalDebits += netCredit;
          } else if (netCredit < 0) {
            final netDebit = -netCredit;
            closingLines.add(JournalLineDraft(
              accountId: accId,
              debitPaise: 0,
              creditPaise: netDebit,
              note: 'Close $name to I&E',
            ));
            totalCredits += netDebit;
          }
        } else if (code.startsWith('4')) {
          // Expense account: normal balance is debit - credit
          final netDebit = dr - cr;
          if (netDebit > 0) {
            // Credit expense account to close
            closingLines.add(JournalLineDraft(
              accountId: accId,
              debitPaise: 0,
              creditPaise: netDebit,
              note: 'Close $name to I&E',
            ));
            totalCredits += netDebit;
          } else if (netDebit < 0) {
            final netCredit = -netDebit;
            closingLines.add(JournalLineDraft(
              accountId: accId,
              debitPaise: netCredit,
              creditPaise: 0,
              note: 'Close $name to I&E',
            ));
            totalDebits += netCredit;
          }
        }
      }

      // Net difference goes to Income and Expenditure Account (2801)
      if (totalDebits > totalCredits) {
        // Income debits > Expense credits: Surplus!
        final surplus = totalDebits - totalCredits;
        closingLines.add(JournalLineDraft(
          accountId: incExpAccId,
          debitPaise: 0,
          creditPaise: surplus,
          note: 'Net Surplus for the Year',
        ));
      } else if (totalCredits > totalDebits) {
        // Expense credits > Income debits: Deficit!
        final deficit = totalCredits - totalDebits;
        closingLines.add(JournalLineDraft(
          accountId: incExpAccId,
          debitPaise: deficit,
          creditPaise: 0,
          note: 'Net Deficit for the Year',
        ));
      }

      int? closingEntryId;
      if (closingLines.isNotEmpty) {
        final posted = await ledger.post(txn, JournalDraft(
          societyId: societyId,
          entryDate: endDate,
          sourceType: 'year_close',
          narration: 'Year End Closing Entry for FY ${fy['code']}',
          lines: closingLines,
        ));
        closingEntryId = posted.id;
      }

      // 3. Mark year as closed
      await txn.update(
        'financial_years',
        {
          'status': 'closed',
          'closing_entry_id': closingEntryId,
          'closed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [fyId],
      );

      return closingEntryId ?? 0;
    });
  }

  // -------------------------------------------------------------
  // Reopen Financial Year
  // -------------------------------------------------------------
  Future<void> reopenYear(
    int societyId,
    int fyId,
    String confirmation,
  ) async {
    if (confirmation != 'REOPEN') {
      throw const SocietyException('confirmation_required', 'Type "REOPEN" to confirm reopening this financial year');
    }

    final fyRows = await db.query('financial_years', where: 'society_id = ? AND id = ?', whereArgs: [societyId, fyId]);
    if (fyRows.isEmpty) throw const SocietyException('not_found', 'Financial year not found');
    final fy = fyRows.first;

    if (fy['status'] != 'closed') {
      throw const SocietyException('validation', 'Financial year is not closed');
    }

    // Rule: Reopen only allowed for the latest closed year
    final laterClosed = await db.rawQuery('''
      SELECT code FROM financial_years
      WHERE society_id = ? AND start_date > ? AND status = 'closed'
    ''', [societyId, fy['start_date']]);
    if (laterClosed.isNotEmpty) {
      throw SocietyException('reopen_blocked', 'Cannot reopen this financial year because a later year (${laterClosed.first['code']}) is already closed.');
    }

    await db.transaction((txn) async {
      final closingEntryId = fy['closing_entry_id'] as int?;

      // Set year back to open first so reversal entry can be posted in this financial year
      await txn.update(
        'financial_years',
        {
          'status': 'open',
          'closing_entry_id': null,
          'closed_at': null,
        },
        where: 'id = ?',
        whereArgs: [fyId],
      );

      // Reverse closing entry if present
      if (closingEntryId != null) {
        await ledger.reverse(
          txn,
          societyId,
          closingEntryId,
          fy['end_date'] as String,
          'Reopened Financial Year ${fy['code']}',
        );
      }

      // Reverse any fund appropriations in this year
      final appropriations = await txn.rawQuery('''
        SELECT id FROM journal_entries
        WHERE society_id = ? AND source_type = 'fund_appropriation'
          AND entry_date >= ? AND entry_date <= ? AND status = 'posted'
      ''', [societyId, fy['start_date'], fy['end_date']]);

      for (final a in appropriations) {
        await ledger.reverse(
          txn,
          societyId,
          a['id'] as int,
          fy['end_date'] as String,
          'Reopened Financial Year ${fy['code']} - reversed appropriation',
        );
      }
    });
  }
}
