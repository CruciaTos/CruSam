import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/society_database.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/imports/import_service.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/other_income/other_income_service.dart';
import 'package:crusam/features/society/domain/expenses/expense_service.dart';
import 'package:crusam/features/society/domain/bank/bank_service.dart';
import 'package:crusam/features/society/domain/reports/financial_statement_service.dart';
import 'package:crusam/features/society/domain/reports/report_service.dart';
import 'package:crusam/features/society/domain/year_end/year_end_service.dart';
import 'package:crusam/features/society/domain/communication/communication_service.dart';
import 'package:crusam/features/society/domain/backup/backup_service.dart';

class SocietyServices {
  final Database db;

  SocietyServices(this.db) {
    society = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);
    collection = CollectionService(db, ledgerService: ledger);
    otherIncome = OtherIncomeService(db, ledgerService: ledger);
    expenses = ExpenseService(db, ledgerService: ledger);
    bank = BankService(db, ledgerService: ledger);
    financialStatements = FinancialStatementService(db, ledger);
    reports = ReportService(db, ledger, financialStatements);
    yearEnd = YearEndService(db, ledger);
    communication = CommunicationService(db, billing, collection);
    backup = BackupService(db);
    import = ImportService(
      db,
      memberService: member,
      ledgerService: ledger,
      billingService: billing,
      collectionService: collection,
      expenseService: expenses,
    );
  }

  static SocietyServices? _instance;

  static Future<SocietyServices> instance() async {
    if (_instance != null) return _instance!;
    final database = await SocietyDatabase.instance.database;
    _instance = SocietyServices(database);
    return _instance!;
  }

  static void resetForTest(Database testDb) {
    _instance = SocietyServices(testDb);
  }

  late final SocietyAdminService society;
  late final LedgerService ledger;
  late final MemberService member;
  late final ImportService import;
  late final BillingService billing;
  late final CollectionService collection;
  late final OtherIncomeService otherIncome;
  late final ExpenseService expenses;
  late final BankService bank;
  late final FinancialStatementService financialStatements;
  late final ReportService reports;
  late final YearEndService yearEnd;
  late final CommunicationService communication;
  late final BackupService backup;
}
