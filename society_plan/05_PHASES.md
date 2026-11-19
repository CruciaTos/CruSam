# 05. Build Phases

Build every phase in order in one continuous run. Verify and report each phase, then continue automatically. Stop only for a blocker listed in `00_EXECUTION_RULES.md`, or after the Phase 9 final report.

Run verification from `crusam/`:

```bash
flutter analyze lib/features/society test/society lib/core/router/app_router.dart lib/features/shell/shell_screen.dart lib/core/sync/claude_follow_controller.dart
```

```bash
flutter test test/society
```

Phase 0 task 0.7 creates `test/society`.

---

## Phase 0. Workspace shell

**Result:** CruSam can switch to an empty Society workspace without changing CruSam behaviour.

| ID | Task | Files |
|---|---|---|
| 0.1 | Add `isSocietyLocation(String)` and `WorkspaceMemory` using `shared_preferences` keys `workspace.last_crusam_path` and `workspace.last_society_path` | `core/workspace_memory.dart` |
| 0.2 | Add credit constant exactly as written in section "Credit" below | `core/society_credit.dart` |
| 0.3 | Add `SocietyPlaceholderScreen(title)` saying `This section is being built.` | `shared/widgets/society_placeholder_screen.dart` |
| 0.4 | Add `societyRoutes` for every sidebar route, using `NoTransitionPage` | `society_routes.dart` |
| 0.5 | Add `WorkspaceSwitch` and a Phase 0 `SocietyPicker` shell that shows `No society selected` | `shared/widgets/workspace_switch.dart`, `shared/widgets/society_picker.dart` |
| 0.6 | Apply the exact shell, router and Follow Claude edits from `04_UI_SPEC.md` | allowed existing files |
| 0.7 | Add a route test for `isSocietyLocation` and memory fallback | `test/society/workspace_test.dart` |
| 0.8 | Add route table test proving every `_kSocietyNav` path has a route, by keeping a public `societyNavPaths` list in `society_routes.dart` | same test |

**Acceptance**

- Switching to Society opens Overview placeholder.
- Clicking several sidebar items works.
- Switching back returns to the last CruSam screen.
- Switching again returns to the last Society screen.
- `/society/anything-unknown` is not added.
- CruSam sidebar, titles, AI button and Follow Claude are unchanged outside Society.
- Follow Claude does not navigate away while inside Society.

---

## Phase 1. Database, society setup and shared UI

**Result:** Societies can be created, selected and edited.

| ID | Task | Files |
|---|---|---|
| 1.1 | Implement money, date and exception helpers exactly | `core/money.dart`, `core/society_date.dart`, `core/society_exception.dart` |
| 1.2 | Convert `02_SCHEMA.sql` to `m001Initial` | `data/migrations/m001_initial.dart` |
| 1.3 | Implement `SocietyDatabase` and `SocietyServices` | `data/society_database.dart`, `core/society_services.dart` |
| 1.4 | Add models and repository for societies, years, series, settings and audit | `data/models/society_models.dart`, `data/repositories/society_repository.dart` |
| 1.5 | Add full society seed from accounting section 4 | `data/seed/society_seed.dart` |
| 1.6 | Implement `SocietyAdminService` | `domain/society/society_admin_service.dart` |
| 1.7 | Implement `SocietyContext` and real `SocietyPicker` | `core/society_context.dart`, `shared/widgets/society_picker.dart` |
| 1.8 | Implement all shared widgets from UI section 2 that do not need later services | `shared/widgets/` |
| 1.9 | Build societies list, society form and Society Settings General section | `screens/societies/`, `screens/settings/` |
| 1.10 | Build setup-state Overview with society selection and empty states | `screens/overview/` |
| 1.11 | Tests | `test/society/money_test.dart`, `date_test.dart`, `society_seed_test.dart`, `society_admin_test.dart` |

**Tests must prove**

- `formatInr(123456789)` is `₹12,34,567.89`.
- `roundHalfUp(5, 2)` is `3`.
- `2026-03-31` is FY `2025-26`; `2026-04-01` is FY `2026-27`.
- Society creation seeds all listed groups, accounts, heads and series exactly once.
- Failed society creation leaves no partial rows.
- Two societies keep separate settings.

---

## Phase 2. Ledger

**Result:** Double-entry accounts and reports work before any billing exists.

| ID | Task | Files |
|---|---|---|
| 2.1 | Add ledger models and repository | `data/models/ledger_models.dart`, `data/repositories/ledger_repository.dart` |
| 2.2 | Implement `LedgerService` posting, numbering, reversal and validation | `domain/ledger/ledger_service.dart` |
| 2.3 | Implement chart of accounts and opening balances | same service |
| 2.4 | Implement journal list, detail, ledger enquiry and trial balance | same service |
| 2.5 | Build Chart of Accounts screen | `screens/accounts/chart_of_accounts_screen.dart` and widgets |
| 2.6 | Build opening balances tab | `screens/accounts/widgets/opening_balances_tab.dart` |
| 2.7 | Build journal list, new and detail screens | `screens/accounts/journal_*.dart` |
| 2.8 | Build Ledger Enquiry and Trial Balance | `screens/accounts/ledger_enquiry_screen.dart`, `trial_balance_screen.dart` |
| 2.9 | Replace matching placeholders | `society_routes.dart` |
| 2.10 | Tests | `test/society/ledger_test.dart`, `test_support.dart` |

**Tests must prove**

- Every posting gate in accounting section 2.
- Number series increases per society and year.
- Reversal mirrors every line and nets to zero.
- Reversing twice fails.
- Trial balance balances.
- Inactive account and another society's account fail.
- Closed year rejects posting.

---

## Phase 3. Units, members and imports

**Result:** A society's units, people and opening member balances can be managed.

| ID | Task | Files |
|---|---|---|
| 3.1 | Add models and repository | `data/models/member_models.dart`, `data/repositories/member_repository.dart` |
| 3.2 | Implement `MemberService` | `domain/members/member_service.dart` |
| 3.3 | Build Unit Types and Blocks | `screens/units/unit_types_screen.dart` |
| 3.4 | Build Units list, form and detail Overview and People tabs | `screens/units/` |
| 3.5 | Build Members list and form | `screens/members/` |
| 3.6 | Implement `ImportService` for `units`, `people`, `opening_units`, `opening_ledger` | `domain/imports/` |
| 3.7 | Build Import screen | `screens/imports/import_screen.dart` |
| 3.8 | Add unit opening balance posting through `LedgerService` | `domain/members/member_service.dart` |
| 3.9 | Tests | `test/society/member_test.dart`, `import_test.dart` |

**Import columns**

| Type | Columns |
|---|---|
| `units` | Block*, Unit No*, Unit Type*, Area 1, Area 2, Floor, Occupancy*, Active |
| `people` | Block*, Unit No*, Full Name*, Role*, Primary Contact, Bill To, Phone, Email, Alternate Email, PAN, GSTIN, Address, Share Certificate No, From Date* |
| `opening_units` | Block*, Unit No*, Debit, Credit, As Of*, Narration |
| `opening_ledger` | Account Code*, Debit, Credit, As Of*, Narration |

`*` means required.

**Tests must prove**

- One active primary contact and one active bill-to per unit.
- Ownership transfer ends old assignments and keeps history.
- Unit with ledger history cannot be deleted. There is no hard-delete UI.
- 500-unit import works in one transaction.
- One bad row leaves no imported rows.
- Unit opening balances reconcile to Members Receivable.

---

## Phase 4. Billing

**Result:** Rules generate correct bills and post them.

| ID | Task | Files |
|---|---|---|
| 4.1 | Add billing models and repository | `data/models/billing_models.dart`, `data/repositories/billing_repository.dart` |
| 4.2 | Implement pure calculators | `domain/billing/bill_calculator.dart`, `meter_calculator.dart`, `gst_calculator.dart` |
| 4.3 | Implement `BillingService` setup methods | `domain/billing/billing_service.dart` |
| 4.4 | Implement run preview, draft, edit, cancel and post | same service |
| 4.5 | Implement manual and debit-note bill posting, without collection yet | same service |
| 4.6 | Build Charge Heads, Billing Rules and Meter screens | `screens/billing/` |
| 4.7 | Build New Bill Run wizard and detail | `screens/billing/bill_run_*.dart` |
| 4.8 | Build Bills list, manual bill and detail | `screens/billing/bill*.dart` |
| 4.9 | Add member bill PDF | `documents/pdf/member_bill_pdf.dart` |
| 4.10 | Add meter reading import | `domain/imports/` |
| 4.11 | Tests | `test/society/billing_test.dart`, `meter_test.dart`, `gst_test.dart`, first part of `golden_scenario_test.dart` |

Interest calculation is added in Phase 5. Until then, bill runs have no interest line.

**Tests must prove**

- April golden bill values.
- Unit-type rule beats general rule.
- Effective dates work.
- Percent rule uses calculated base heads.
- Quarterly bill multiplies by 3.
- Duplicate run is blocked.
- Missing bill-to blocks posting.
- Bill and journal totals match.
- Cumulative and non-cumulative meters.
- Every GST golden case.

---

## Phase 5. Collections and interest

**Result:** Receipts, advances, credit notes, dues and interest work.

| ID | Task | Files |
|---|---|---|
| 5.1 | Add collection models and repository | `data/models/collection_models.dart`, `data/repositories/collection_repository.dart` |
| 5.2 | Implement allocation calculator | `domain/collections/allocation_calculator.dart` |
| 5.3 | Implement receipts, advance allocation and reversal | `domain/collections/collection_service.dart` |
| 5.4 | Implement credit and debit notes | same service |
| 5.5 | Implement unidentified receipts | same service |
| 5.6 | Implement pure interest calculator and bill-run integration | `domain/billing/interest_calculator.dart`, `billing_service.dart` |
| 5.7 | Implement unit statement, dues and ageing | `collection_service.dart` |
| 5.8 | Build Receipts list, form, bulk grid and detail | `screens/collections/` |
| 5.9 | Build Notes, Unidentified and Dues screens | `screens/collections/` |
| 5.10 | Finish unit Statement, Bills and Receipts tabs | `screens/units/` |
| 5.11 | Add receipt, credit note and statement PDFs | `documents/pdf/` |
| 5.12 | Add receipt import | `domain/imports/` |
| 5.13 | Tests | `test/society/allocation_test.dart`, `collection_test.dart`, `interest_test.dart`, extend golden test |

**Tests must prove**

- Golden receipt and April trial balance.
- A-101 interest ₹4.85.
- A-102 interest ₹10.65.
- Part-payment interest ₹8.21.
- Rupee rounding ₹2,630.00 with ₹0.15 round-off.
- Interest never included on interest, GST or round-off.
- Excess receipt stays as advance and can later be allocated.
- Over-allocation is rejected.
- Bounced cheque reverses receipt and restores due.
- Bill with allocations cannot be reversed.
- Sum of unit balances equals Members Receivable.

---

## Phase 6. Other income, vendors and expenses

**Result:** Non-member income and payables work.

| ID | Task | Files |
|---|---|---|
| 6.1 | Add models and repositories | `data/models/other_income_models.dart`, `expense_models.dart`; matching repositories |
| 6.2 | Implement `OtherIncomeService` | `domain/other_income/other_income_service.dart` |
| 6.3 | Implement `ExpenseService` vendors, bills, debit notes and payments | `domain/expenses/expense_service.dart` |
| 6.4 | Implement advances, TDS, statements, budget and comparison | same service |
| 6.5 | Build Other Income tabs and forms | `screens/other_income/` |
| 6.6 | Build Vendors screens | `screens/vendors/` |
| 6.7 | Build Expense Bills and Payments screens | `screens/expenses/` |
| 6.8 | Build Budget and Expense Comparison | `screens/budget/`, `screens/expenses/` |
| 6.9 | Add vendor, bill, budget imports | `domain/imports/` |
| 6.10 | Add payment voucher PDF | `documents/pdf/` |
| 6.11 | Tests | `test/society/other_income_test.dart`, `expense_test.dart`, `budget_test.dart`, extend golden test |

**Tests must prove**

- Golden vendor bill and payment.
- Trial balance total ₹56,215.00.
- Same-state and inter-state GST.
- Duplicate vendor bill number is rejected.
- Payment cannot exceed open payable unless excess is posted as advance.
- Advance adjustment balances.
- Budget variance is correct.
- Vendor balances equal Vendors Payable.

---

## Phase 7. Bank, deposits and tax

**Result:** Bank work and tax registers are complete.

| ID | Task | Files |
|---|---|---|
| 7.1 | Add bank models and repository | `data/models/bank_models.dart`, `data/repositories/bank_repository.dart` |
| 7.2 | Implement bank accounts and transfers | `domain/bank/bank_service.dart` |
| 7.3 | Implement bank book and reconciliation | same service |
| 7.4 | Implement statement import with columns: Date*, Description, Reference, Withdrawal, Deposit, Balance | same service and `domain/imports/` |
| 7.5 | Implement FD open, interest and close | same service |
| 7.6 | Implement GST and TDS registers | same service |
| 7.7 | Build Bank, Transfers and Reconciliation | `screens/bank/` |
| 7.8 | Build Fixed Deposits and GST & TDS | `screens/deposits/`, `screens/tax/` |
| 7.9 | Add reconciliation PDF and Excel | `documents/` |
| 7.10 | Tests | `test/society/bank_test.dart`, `reconciliation_test.dart`, `fd_test.dart`, `tax_test.dart` |

**Tests must prove**

- Transfer cannot use the same account.
- Cleared transfer cannot be reversed.
- Reconciliation formula.
- Clear and unclear work.
- FD open, accrual, receipt and close all balance.
- GST and TDS totals tie to their ledger accounts.

---

## Phase 8. Statements, reports and year-end

**Result:** Accounts can be reported and closed.

| ID | Task | Files |
|---|---|---|
| 8.1 | Implement statement calculations | `domain/reports/financial_statement_service.dart` |
| 8.2 | Implement report definitions and runners | `domain/reports/report_service.dart`, `report_definitions.dart` |
| 8.3 | Implement `YearEndService` | `domain/year_end/year_end_service.dart` |
| 8.4 | Build Financial Statements screen | `screens/accounts/financial_statements_screen.dart` |
| 8.5 | Build Reports screen | `screens/reports/` |
| 8.6 | Build Year End screen | `screens/accounts/year_end_screen.dart` |
| 8.7 | Add generic report PDF and Excel | `documents/pdf/report_pdf.dart`, `documents/excel/report_excel.dart` |
| 8.8 | Replace Overview with real data | `screens/overview/` |
| 8.9 | Tests | `test/society/statements_test.dart`, `reports_test.dart`, `year_end_test.dart`, finish golden test |

**Report catalogue**

| Category | `reportKey` |
|---|---|
| Billing | `billing_register`, `bill_detail`, `head_billing`, `reversed_bills` |
| Collections | `collection_register`, `mode_collection`, `member_dues`, `unit_ageing`, `member_advances`, `pending_cheques`, `unit_balances`, `refundable_deposits` |
| Expenses | `expense_register`, `itemized_expenses`, `vendor_statement`, `payables_ageing`, `budget_actual`, `expense_comparison` |
| Bank | `cash_book`, `bank_book`, `cash_flow`, `deposit_slip`, `bank_reconciliation`, `fd_register`, `fd_maturity` |
| Tax | `gst_output`, `gst_input`, `gst_payable`, `tds_payable`, `tds_paid` |
| Accounts | `day_book`, `general_ledger`, `trial_balance`, `income_expenditure`, `balance_sheet`, `receipts_payments`, `fund_movement` |

**Tests must prove**

- Golden balance sheet balances before and after close.
- Golden close entry and deficit ₹5,110.00.
- Balance sheet total ₹46,215.00.
- Closed year rejects new posting.
- Reopen works only for the latest closed year.
- Reports tie to their source totals.
- Advance and vendor-debit presentation rules work.

---

## Phase 9. Documents, communication, backup and finish

**Result:** The module is usable from setup through backup.

| ID | Task | Files |
|---|---|---|
| 9.1 | Add remaining Excel exports and bulk bill print | `documents/` |
| 9.2 | Implement `CommunicationService` for bill, receipt, statement and reminders | `domain/communication/communication_service.dart` |
| 9.3 | Add email dialog and log view | `shared/widgets/send_email_dialog.dart`, `screens/settings/` |
| 9.4 | Complete Billing, Interest, GST & TDS, Numbering, Documents and Email settings | `screens/settings/` |
| 9.5 | Implement society backup and restore-as-new | `domain/backup/backup_service.dart` |
| 9.6 | Add Backup settings | `screens/settings/` |
| 9.7 | Build About & Credits and Overview credit link | `screens/about/`, `screens/overview/` |
| 9.8 | Remove every remaining placeholder route | `society_routes.dart`, remove placeholder if unused |
| 9.9 | Add full sample-year test | `test/society/full_year_test.dart`, `backup_test.dart`, `communication_test.dart` |
| 9.10 | Final scope scan and report | `PROGRESS.md` |

### Credit

```dart
const kAddaCreditText =
    'With thanks to ADDA for permitting us to refer to its product while designing this module.';
```

The owner will replace this with ADDA's approved wording if needed. Use plain text. Do not add ADDA logos or imply endorsement.

**Final scan**

Run and report these from the repository root:

```bash
git status --short
```

```bash
grep -RInE "TODO|FIXME|coming soon|being built|double .*paise|paise.*double" crusam/lib/features/society crusam/test/society
```

Any hit must be fixed or explained.

**Tests must prove**

- A full sample year runs from setup through close.
- Backup restores to a new society with matching trial balance.
- Restoring does not change the source society.
- Email failures are logged and do not change accounting data.

**Manual acceptance list for owner**

1. Create a society and bank account.
2. Add units and members by import.
3. Create rules and post a bill run.
4. Add receipts and check statement balance.
5. Add expense bill and payment.
6. Reconcile a bank account.
7. View statements and export them.
8. Back up and restore as a copy.
9. Close the year on test data.
10. Switch back to CruSam and confirm existing work is unchanged.
