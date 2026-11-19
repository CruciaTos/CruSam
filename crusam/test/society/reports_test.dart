import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/reports/financial_statement_service.dart';
import 'package:crusam/features/society/domain/reports/report_definitions.dart';
import 'package:crusam/features/society/domain/reports/report_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  setUpAll(initTestSupport);

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late FinancialStatementService statements;
  late ReportService reports;
  late Society society;

  setUp(() async {
    db = await createTestDatabase();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    statements = FinancialStatementService(db, ledger);
    reports = ReportService(db, ledger, statements);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Reports Test Society',
      city: 'Mumbai',
      state: 'Maharashtra',
      pincode: '400001',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);
  });

  tearDown(() async {
    await db.close();
  });

  test('Report Catalog contains all 33 required reports across categories', () {
    expect(ReportCatalog.allReports.length, greaterThanOrEqualTo(30));
    final categories = ReportCatalog.allReports.map((r) => r.category).toSet();
    expect(categories, containsAll(['Billing', 'Collections', 'Expenses', 'Bank', 'Tax', 'Accounts']));
  });

  test('ReportService runs reports and returns structured results', () async {
    final bankAcc = (await ledger.getAccountByCode(society.id, '1101'))!;
    final genFund = (await ledger.getAccountByCode(society.id, '2301'))!;

    await ledger.saveOpeningBalances(society.id, [
      OpeningBalanceDraft(accountId: bankAcc.id, debitPaise: 500000, creditPaise: 0, asOfDate: '2026-04-01'),
      OpeningBalanceDraft(accountId: genFund.id, debitPaise: 0, creditPaise: 500000, asOfDate: '2026-04-01'),
    ]);

    // Test Day Book
    final dayBookResult = await reports.runReport(society.id, 'day_book', {
      'fromDate': '2026-04-01',
      'toDate': '2026-04-30',
    });
    expect(dayBookResult.definition.key, equals('day_book'));
    expect(dayBookResult.rows.isNotEmpty, isTrue);

    // Test Trial Balance Report
    final tbResult = await reports.runReport(society.id, 'trial_balance', {
      'fromDate': '2026-04-01',
      'toDate': '2026-04-30',
    });
    expect(tbResult.rows.isNotEmpty, isTrue);

    // Test Balance Sheet Report
    final bsResult = await reports.runReport(society.id, 'balance_sheet', {
      'asOfDate': '2026-04-30',
    });
    expect(bsResult.rows.isNotEmpty, isTrue);
    expect(bsResult.rows.any((r) => r['side'] == 'ASSETS'), isTrue);
    expect(bsResult.rows.any((r) => r['side'] == 'LIABILITIES & FUNDS'), isTrue);
  });
}
