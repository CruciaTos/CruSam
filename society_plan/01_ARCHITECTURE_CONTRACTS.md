# 01. Architecture Contracts

## 1. Layers

```text
Screen widget
  -> Screen controller (ChangeNotifier owned by that screen)
    -> Domain service (rules, validation, transaction)
      -> Repository (SQL only)
        -> society.db
```

Rules:

- Widgets never import `sqflite`.
- Repositories contain no business decisions.
- Services own transactions.
- Reports are read-only services.
- `SocietyContext` and `WorkspaceMemory` are the only new global singletons.

## 2. Folder map

```text
crusam/lib/features/society/
  society_routes.dart
  core/
    money.dart
    society_date.dart
    society_exception.dart
    society_context.dart
    workspace_memory.dart
    society_credit.dart
    society_services.dart
  data/
    society_database.dart
    migrations/m001_initial.dart
    seed/society_seed.dart
    models/
    repositories/
  domain/
    society/
    ledger/
    members/
    billing/
    collections/
    other_income/
    expenses/
    bank/
    reports/
    year_end/
    imports/
    backup/
    communication/
  documents/
    pdf/
    excel/
  shared/
    widgets/
  screens/
    overview/ societies/ units/ members/ imports/ billing/ collections/
    other_income/ vendors/ expenses/ budget/ bank/ deposits/ tax/
    accounts/ reports/ settings/ about/
```

## 3. Core helpers

### `core/money.dart`

```dart
int roundHalfUp(int numerator, int denominator);
int percentOf(int amountPaise, int rateBp);
int areaAmount(int areaCenti, int ratePaise);
int quantityAmount(int quantityMilli, int ratePaise);
int? parseRupeesToPaise(String input);
int? parsePercentToBp(String input);
int? parseAreaToCenti(String input);
int? parseQuantityToMilli(String input);
String formatInr(int paise, {bool symbol = true});
String formatPlainAmount(int paise);
String formatPercentBp(int bp);
```

- `roundHalfUp` throws `ArgumentError` for a non-positive denominator or negative numerator.
- `formatInr(123456789)` returns `₹12,34,567.89`.
- Negative values use a leading minus: `-₹1,000.00`.
- Parsers accept commas and up to the type's decimal places. Empty or invalid input returns null.

### `core/society_date.dart`

```dart
String todayIso();
DateTime parseIsoDate(String value);
String toIsoDate(DateTime value);
String addDaysIso(String value, int days);
int daysInclusive(String from, String to);
String formatDisplayDate(String iso);
String? parseDisplayDate(String input);
String fyCodeForDate(String iso);
String fyStartForCode(String code);
String fyEndForCode(String code);
int monthsInclusive(String from, String to);
```

Dates use local calendar values only. Do not do UTC conversion.

### `core/society_exception.dart`

```dart
class SocietyException implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> details;
  const SocietyException(this.code, this.message, {this.details = const {}});
}
```

Required codes include: `not_found`, `duplicate`, `validation`, `unbalanced_entry`, `closed_year`, `before_books_start`, `inactive_account`, `wrong_society`, `in_use`, `missing_setting`, `blocking_preview`, `already_posted`, `already_reversed`.

## 4. Database

### `SocietyDatabase`

```dart
class SocietyDatabase {
  SocietyDatabase._();
  static final SocietyDatabase instance = SocietyDatabase._();

  Future<Database> get database;
  Future<void> close();

  static Future<Database> openForTest({String path = inMemoryDatabasePath});
}
```

Implementation:

- File: `AppPaths.childPath('society.db')` on Windows, Linux and macOS.
- Mobile path: `${await getDatabasesPath()}/society.db`.
- Initialize FFI on desktop the same way as `DatabaseHelper`.
- `version: 1`.
- `onConfigure`: `PRAGMA foreign_keys = ON` and `PRAGMA busy_timeout = 5000`.
- `onCreate`: run `m001Initial(db)` in one batch.
- Tests use `databaseFactoryFfi` with `singleInstance: false`.

### `SocietyServices`

```dart
class SocietyServices {
  SocietyServices(this.db);
  final Database db;

  static Future<SocietyServices> instance();

  late final SocietyAdminService society;
  late final LedgerService ledger;
  late final MemberService members;
  late final BillingService billing;
  late final CollectionService collections;
  late final OtherIncomeService otherIncome;
  late final ExpenseService expenses;
  late final BankService bank;
  late final ReportService reports;
  late final YearEndService yearEnd;
  late final ImportService imports;
  late final BackupService backup;
  late final CommunicationService communication;
}
```

Create fields in the phase that introduces them. Do not create empty service classes early.

## 5. Shared result types

```dart
class PageRequest {
  final int limit;
  final int offset;
  final String search;
  const PageRequest({this.limit = 50, this.offset = 0, this.search = ''});
}

class PageResult<T> {
  final List<T> rows;
  final int total;
  const PageResult(this.rows, this.total);
}

class ValidationIssue {
  final String field;
  final String message;
  final int? rowNumber;
  const ValidationIssue(this.field, this.message, {this.rowNumber});
}
```

Models are immutable classes with `fromMap`, `toInsertMap` where needed, and explicit fields. Do not use `dynamic` outside map parsing.

## 6. Society and context

```dart
class SocietyDraft { /* societies table editable fields */ }
class SocietySummary { /* id, name, city, isActive, activeFyId, activeFyCode */ }

class SocietyAdminService {
  Future<List<SocietySummary>> listSocieties({bool includeInactive = false});
  Future<Society> getSociety(int societyId);
  Future<int> createSociety(SocietyDraft draft);
  Future<void> updateSociety(int societyId, SocietyDraft draft);
  Future<void> setSocietyActive(int societyId, bool active);
  Future<List<FinancialYear>> listFinancialYears(int societyId);
  Future<int> createNextFinancialYear(int societyId);
  Future<String?> getSetting(int societyId, String key);
  Future<void> setSettings(int societyId, Map<String, String?> values);
  Future<String?> getDatedSetting(int societyId, String key, String onDate);
  Future<void> addDatedSetting(int societyId, String key, String value, String from, {String? note});
  Future<void> writeAudit(DatabaseExecutor db, int? societyId, String action,
      String entityType, int? entityId, String summary);
}

class SocietyContext extends ChangeNotifier {
  static final SocietyContext instance = SocietyContext._();
  int? get societyId;
  Society? get society;
  FinancialYear? get financialYear;
  List<SocietySummary> get societies;
  bool get allSocieties;
  bool get loading;
  String? get error;

  Future<void> ensureLoaded();
  Future<void> reload();
  Future<void> selectSociety(int id);
  Future<void> selectAllSocieties();
  Future<void> selectFinancialYear(int fyId);
}
```

Persist `society.last_society_id` and `society.last_fy_id` in `app_settings`.

## 7. Ledger

```dart
class JournalLineDraft {
  final int accountId;
  final int debitPaise;
  final int creditPaise;
  final int? unitId;
  final int? vendorId;
  final int? partyId;
  final String? note;
}

class JournalDraft {
  final int societyId;
  final String entryDate;
  final String sourceType;
  final int? sourceId;
  final String narration;
  final List<JournalLineDraft> lines;
}

class PostedJournal {
  final int id;
  final int fyId;
  final String entryNo;
}

class LedgerService {
  Future<PostedJournal> post(Transaction txn, JournalDraft draft);
  Future<PostedJournal> postManual(JournalDraft draft);
  Future<PostedJournal> reverse(Transaction txn, int societyId, int entryId,
      String reversalDate, String reason);
  Future<void> reverseManual(int societyId, int entryId, String reversalDate, String reason);
  Future<int> accountIdForKey(DatabaseExecutor db, int societyId, String systemKey);
  Future<String> nextNumber(Transaction txn, int societyId, int fyId, String docType);
  Future<FinancialYear> requireOpenYear(DatabaseExecutor db, int societyId, String date);

  Future<List<AccountTreeGroup>> chartOfAccounts(int societyId, {bool includeInactive = false});
  Future<int> createGroup(int societyId, AccountGroupDraft draft);
  Future<int> createAccount(int societyId, AccountDraft draft);
  Future<void> updateAccount(int societyId, int accountId, AccountDraft draft);
  Future<void> setAccountActive(int societyId, int accountId, bool active);
  Future<void> saveOpeningBalances(int societyId, List<OpeningBalanceDraft> rows);

  Future<PageResult<JournalEntryRow>> listEntries(int societyId, JournalFilter filter, PageRequest page);
  Future<JournalEntryDetail> entryDetail(int societyId, int entryId);
  Future<LedgerResult> ledgerEnquiry(int societyId, LedgerFilter filter, PageRequest page);
  Future<TrialBalance> trialBalance(int societyId, String from, String to);
}
```

`post` is the only code allowed to insert `journal_entries` or `journal_lines`, except `reverse`, which calls the same internal insert.

## 8. Members

```dart
class MemberService {
  Future<List<Block>> listBlocks(int societyId);
  Future<int> saveBlock(int societyId, BlockDraft draft);
  Future<List<UnitType>> listUnitTypes(int societyId);
  Future<int> saveUnitType(int societyId, UnitTypeDraft draft);

  Future<PageResult<UnitRow>> listUnits(int societyId, UnitFilter filter, PageRequest page);
  Future<UnitDetail> unitDetail(int societyId, int unitId);
  Future<int> createUnit(int societyId, UnitDraft draft);
  Future<void> updateUnit(int societyId, int unitId, UnitDraft draft);
  Future<void> setUnitActive(int societyId, int unitId, bool active);

  Future<PageResult<PersonRow>> listPeople(int societyId, PersonFilter filter, PageRequest page);
  Future<int> savePerson(int societyId, PersonDraft draft);
  Future<void> assignPerson(int societyId, UnitPersonDraft draft);
  Future<void> endAssignment(int societyId, int unitPersonId, String toDate);
  Future<void> transferOwnership(int societyId, OwnershipTransferDraft draft);
}
```

## 9. Billing

```dart
class BillingService {
  Future<List<ChargeHeadRow>> listHeads(int societyId);
  Future<int> saveHead(int societyId, ChargeHeadDraft draft);
  Future<List<BillingRuleRow>> listRules(int societyId, RuleFilter filter);
  Future<int> saveRule(int societyId, BillingRuleDraft draft);
  Future<void> endRule(int societyId, int ruleId, String effectiveTo);

  Future<int> saveMeterType(int societyId, MeterTypeDraft draft);
  Future<int> saveMeter(int societyId, MeterDraft draft);
  Future<void> saveReadings(int societyId, List<MeterReadingDraft> rows);

  Future<BillRunPreview> previewRun(int societyId, BillRunDraft draft);
  Future<int> saveDraftRun(int societyId, BillRunDraft draft);
  Future<BillRunPreview> loadRun(int societyId, int runId);
  Future<void> updateDraftLine(int societyId, int billLineId, DraftLineEdit edit);
  Future<void> cancelDraftRun(int societyId, int runId);
  Future<BillRunPostResult> postRun(int societyId, int runId);

  Future<int> postManualBill(int societyId, ManualBillDraft draft);
  Future<void> reverseBill(int societyId, int billId, String date, String reason);
  Future<PageResult<BillRow>> listBills(int societyId, BillFilter filter, PageRequest page);
  Future<BillDetail> billDetail(int societyId, int billId);
}
```

Pure calculators live in `domain/billing/`:

```dart
BillCalculationResult calculateBill(BillCalculationInput input);
int calculateMeterCharge(MeterChargeInput input);
InterestResult calculateInterest(InterestInput input);
GstSplit splitMemberGst(int gstPaise);
```

They do no database work and are unit tested directly.

## 10. Collections

```dart
class CollectionService {
  Future<OpenDues> openDues(int societyId, int unitId);
  Future<List<AllocationDraft>> suggestAllocation(int societyId, int unitId, int amountPaise);
  Future<int> postReceipt(int societyId, ReceiptDraft draft);
  Future<void> allocateAdvance(int societyId, int unitId, String date, List<AllocationDraft> rows);
  Future<void> reverseReceipt(int societyId, int receiptId, String date, String kind, String reason);
  Future<PageResult<ReceiptRow>> listReceipts(int societyId, ReceiptFilter filter, PageRequest page);

  Future<int> postCreditNote(int societyId, CreditNoteDraft draft);
  Future<void> reverseCreditNote(int societyId, int noteId, String date, String reason);
  Future<int> postDebitNote(int societyId, ManualBillDraft draft);

  Future<int> postUnidentified(int societyId, UnidentifiedDraft draft);
  Future<int> resolveUnidentified(int societyId, int unidentifiedId, ResolveUnidentifiedDraft draft);
  Future<void> reverseUnidentified(int societyId, int unidentifiedId, String date, String reason);

  Future<UnitStatement> unitStatement(int societyId, int unitId, String from, String to);
  Future<PageResult<DueRow>> dues(int societyId, DueFilter filter, PageRequest page);
  Future<AgeingReport> ageing(int societyId, String asOf);
}
```

Ageing buckets: `0-30`, `31-60`, `61-90`, `91-180`, `181+` days past due date.

## 11. Other income and expenses

```dart
class OtherIncomeService {
  Future<int> saveParty(int societyId, PartyDraft draft);
  Future<PageResult<PartyRow>> listParties(int societyId, PartyFilter filter, PageRequest page);
  Future<int> postInvoice(int societyId, OtherInvoiceDraft draft);
  Future<int> postReceipt(int societyId, OtherReceiptDraft draft);
  Future<void> reverseInvoice(int societyId, int invoiceId, String date, String reason);
  Future<void> reverseReceipt(int societyId, int receiptId, String date, String reason);
  Future<PartyStatement> partyStatement(int societyId, int partyId, String from, String to);
}

class ExpenseService {
  Future<int> saveVendor(int societyId, VendorDraft draft);
  Future<PageResult<VendorRow>> listVendors(int societyId, VendorFilter filter, PageRequest page);
  Future<VendorDetail> vendorDetail(int societyId, int vendorId);
  Future<int> postExpenseBill(int societyId, ExpenseBillDraft draft);
  Future<int> postVendorDebitNote(int societyId, ExpenseBillDraft draft);
  Future<int> postPayment(int societyId, VendorPaymentDraft draft);
  Future<void> reverseExpenseBill(int societyId, int billId, String date, String reason);
  Future<void> reversePayment(int societyId, int paymentId, String date, String reason);
  Future<void> adjustVendorAdvance(int societyId, VendorAdvanceAdjustmentDraft draft);
  Future<VendorStatement> vendorStatement(int societyId, int vendorId, String from, String to);
  Future<void> saveBudget(int societyId, int fyId, List<BudgetDraft> rows);
  Future<void> copyBudget(int societyId, int fromFyId, int toFyId);
  Future<BudgetReport> budgetReport(int societyId, int fyId, String asOf);
  Future<ExpenseComparison> expenseComparison(int societyId, ComparisonRequest request);
}
```

## 12. Bank, reports and year-end

```dart
class BankService {
  Future<List<BankAccountRow>> listBankAccounts(int societyId);
  Future<int> createBankAccount(int societyId, BankAccountDraft draft);
  Future<void> updateBankAccount(int societyId, int bankAccountId, BankAccountDraft draft);
  Future<int> postTransfer(int societyId, BankTransferDraft draft);
  Future<void> reverseTransfer(int societyId, int transferId, String date, String reason);
  Future<PageResult<BankBookRow>> bankBook(int societyId, BankBookFilter filter, PageRequest page);
  Future<int> importStatement(int societyId, int bankAccountId, String fileName, List<StatementLineDraft> rows);
  Future<ReconciliationView> reconciliation(int societyId, int bankAccountId, String asOf);
  Future<void> clearLine(int societyId, int journalLineId, String clearedDate, {int? statementLineId});
  Future<void> unclearLine(int societyId, int journalLineId);
  Future<int> openFixedDeposit(int societyId, FixedDepositDraft draft);
  Future<void> postFdTransaction(int societyId, FdTransactionDraft draft);
  Future<TaxRegister> gstRegister(int societyId, String from, String to);
  Future<TaxRegister> tdsRegister(int societyId, String from, String to);
}

class ReportService {
  List<ReportDefinition> definitions();
  Future<ReportTable> run(int societyId, String reportKey, ReportParams params);
  Future<IncomeExpenditure> incomeExpenditure(int societyId, String from, String to);
  Future<BalanceSheet> balanceSheet(int societyId, String asOf);
  Future<ReceiptsPayments> receiptsPayments(int societyId, String from, String to);
  Future<OverviewData> societyOverview(int societyId, String asOf);
  Future<List<AllSocietiesRow>> allSocietiesOverview(String asOf);
}

class YearEndService {
  Future<YearEndCheck> check(int societyId, int fyId);
  Future<void> close(int societyId, int fyId, List<AppropriationDraft> rows, {String? confirmation});
  Future<void> reopen(int societyId, int fyId, String confirmation);
}
```

Bank reconciliation:

```text
book_balance = account debit - credit through as_of
uncleared_receipts = uncleared debit lines through as_of
uncleared_payments = uncleared credit lines through as_of
expected_statement_balance = book_balance - uncleared_receipts + uncleared_payments
difference = entered_or_imported_statement_balance - expected_statement_balance
```

A statement line may auto-suggest a book line when the amount matches and dates are within 3 days. The user must confirm. If `reference` matches `instrument_no`, list it first.

## 13. Imports, documents, email and backup

```dart
class ImportService {
  Uint8List templateBytes(String importType);
  Future<ImportPreview> preview(int societyId, String importType, Uint8List bytes, String fileName);
  Future<int> commit(int societyId, ImportPreview preview);
}
```

Import types: `units`, `people`, `opening_ledger`, `opening_units`, `opening_vendors`, `vendors`, `bills`, `receipts`, `meter_readings`, `budget`, `journals`.

Rules: read `.xlsx` with `excel`; generate templates with `syncfusion_flutter_xlsio`; never commit if any row has an error; validate all rows before writing.

Documents:

- PDF uses the `pdf` package and A4.
- Use `PdfHouseStyle.ensureLoaded`, `PdfHouseStyle.newDocument` and `PdfHouseStyle.pageFooter` when they fit.
- Do not call CruSam's `letterhead` or `signature`, because they need the company profile.
- Save PDFs with `PdfFileSaver.save(bytes, fileName: name, target: ExportPathTarget.general)`.
- Save Excel with a `file_selector` save dialog.
- Email uses `GmailService.instance.sendAttachmentsEmail` and `GeneratedDocument` from `package:crusam/shared/models/generated_document.dart`.
- Handle `GmailNotSignedInException` and `GmailSendException`, then write a row in Society `email_log`.

```dart
class BackupService {
  Future<Uint8List> exportSociety(int societyId);
  Future<BackupPreview> inspect(Uint8List bytes);
  Future<int> restoreAsNewSociety(BackupPreview preview, String newName);
}
```

Backup format: gzip-compressed JSON containing `format = crusam_society_backup`, `version = 1`, `exported_at`, and rows from every Society table for that society. Restore creates a new society and remaps every id. It never overwrites an existing society.

## 14. Test helpers

`test/society/test_support.dart` provides:

```dart
void initSocietyTests();
Future<SocietyServices> newTestServices();
Future<SampleSociety> createSampleHeights(SocietyServices s);
Future<int> balanceOfKey(SocietyServices s, int societyId, String key);
```

Every test uses a fresh database. Do not share state between tests.
