# 05. Build Phases

Build every phase in order in one continuous run. Verify and report each phase, then continue. Stop only for a blocker in `00_EXECUTION_RULES.md` or after the Phase A8 final report.

Verification, from `crusam/`, once per phase:

```bash
flutter analyze lib/features/society test/society lib/core/router/app_router.dart lib/features/shell/shell_screen.dart
flutter test test/society
```

The 114 existing tests must still pass. Test files go under `test/society/automation/` and use fictional data and an injected `Clock`.

---

## Phase A0. Foundation

**Result:** schema v2, engine, scheduler, tasks and settings work headlessly.

| ID | Task | Files |
|---|---|---|
| A0.1 | `m002Automation(Database)` from `02_SCHEMA_M002.sql` | `data/migrations/m002_automation.dart` |
| A0.2 | Bump `SocietyDatabase` to version 2 with `onUpgrade(1->2)` running m002, and `onCreate` running m001 then m002; same for `openForTest` | `data/society_database.dart` |
| A0.3 | `Clock` abstraction (`now()`, `today()`), default system clock, test fake | `automation/engine/clock.dart` |
| A0.4 | `AutomationKind`, `AutomationMode`, `AutomationDefinition`, registry list of all 11 definitions per architecture truth table | `automation/engine/automation_kind.dart`, `automation_mode.dart` |
| A0.5 | `AutomationSettings` read/write via existing settings API with defaults | `automation/engine/automation_settings.dart` |
| A0.6 | Models and `AutomationRepository` for runs, tasks, findings | `automation/data/` |
| A0.7 | `TaskService` (upsert with dedupe, resolve, snooze, dismiss, open count notifier, resolveWhere) | `automation/engine/task_service.dart` |
| A0.8 | `FindingService` (upsert by fingerprint, auto-fix on clear, acknowledge) | `automation/engine/finding_service.dart` |
| A0.9 | `AutomationRunner` (run, dedupe, error capture + `automation_error` task) and `AutomationScheduler` (startup delay, 30-minute timer, `runAllSocieties`, `runNow`) with an empty job registry | `automation/engine/automation_runner.dart`, `automation_scheduler.dart` |
| A0.10 | Register services in `SocietyServices`; start scheduler once from `SocietyContext` first society selection (read the file, add the smallest hook) | `core/society_services.dart`, `core/society_context.dart` if required (note in report) |
| A0.11 | Add new tables to the backup table list per schema notes; restore-as-new test | `domain/backup/backup_service.dart` |
| A0.12 | Tests | `test/society/automation/` |

**Tests must prove**
- A fresh DB and a DB upgraded from a v1 file both end at version 2 with identical new tables, and existing data survives upgrade.
- Task upsert with the same dedupe key updates; resolved tasks are not recreated for the same key and period; snooze hides until its date.
- Runner: two runs for the same period key produce one `ok` run and no duplicate tasks; a throwing job writes `error` and an `automation_error` task once per day.
- Scheduler skips inactive societies and closed years; `off` mode runs nothing.
- Backup and restore-as-new round-trips recurring templates, rules, promises, import templates and month-end checks with remapped ids.
- Dropping all m002 tables leaves the trial balance unchanged (books independent of automation).

---

## Phase A1. Inbox, Today, Portfolio, search and command palette

**Result:** the user sees what needs attention across societies and can jump anywhere with Ctrl+K.

| ID | Task | Files |
|---|---|---|
| A1.1 | `SearchService` (index maintenance, reindex, search with ranking, command parsing) | `automation/search/search_service.dart` |
| A1.2 | Index hooks: reindex on society select if empty; `touch` after create/update of units, people, vendors, bills, receipts, expense bills, payments. Add via optional listener in repositories or services, smallest possible hook | existing society services (note each in report) |
| A1.3 | `PortfolioService` with 60 s cache and per-society isolation | `automation/portfolio/portfolio_service.dart` |
| A1.4 | `TaskTile`, `ModeSelector`, `AttentionStrip`, `CommandPalette` widgets | `screens/automation/widgets/` |
| A1.5 | Inbox screen | `screens/automation/inbox_screen.dart` |
| A1.6 | Today screen | `screens/automation/today_screen.dart` |
| A1.7 | Portfolio screen | `screens/automation/portfolio_screen.dart` |
| A1.8 | Routes, nav entries, Inbox badge, Ctrl+K host in shell, attention strip on Overview | `society_routes.dart`, `shell_screen.dart`, overview screen |
| A1.9 | Tests incl. route table | `test/society/automation/` |

**Acceptance**
- Ctrl+K opens the palette on any Society screen and never on CruSam screens.
- Searching a fictional unit finds it and opens its detail.
- Today lists tasks of all societies; Inbox lists only the selected society.
- Badge count updates when a task is marked done.
- Every new nav path has a real route (no placeholder).

---

## Phase A2. Month end, draft bill runs, meter assistant

| ID | Task | Files |
|---|---|---|
| A2.1 | `DraftBillRunJob` per spec S1 | `automation/jobs/draft_bill_run_job.dart` |
| A2.2 | `MeterCheckJob` and estimate helper per S2 | `automation/jobs/meter_check_job.dart` |
| A2.3 | Add needed read methods (units missing readings, period helpers) to existing repository/service with tests | billing/meter services |
| A2.4 | `InterestPreviewJob` per S5 | `automation/jobs/interest_preview_job.dart` |
| A2.5 | `MonthEndService` and `MonthEndJob` for all checks in S10 (checks whose source phases come later report `not_applicable` until those phases land; re-evaluate in A8) | `automation/month_end/`, `jobs/month_end_job.dart` |
| A2.6 | Month End screen, route | `screens/automation/month_end_screen.dart` |
| A2.7 | Meters screen: estimate helper button; bill runs banner | existing screens |
| A2.8 | Register jobs in scheduler registry | engine |
| A2.9 | Tests for S1, S2, S5, S10 | `test/society/automation/` |

**Acceptance:** with a seeded society, the scheduler creates one draft run and tasks; posting stays manual; month-end percent updates as meters and bills are completed.

---

## Phase A3. Bank statement auto-matching

| ID | Task | Files |
|---|---|---|
| A3.1 | `NarrationParser` | `automation/matching/narration_parser.dart` |
| A3.2 | `NameMatcher` (normalise, token-set ratio) | `automation/matching/name_matcher.dart` |
| A3.3 | `StatementMatcher` pure scoring per S3 with signal breakdown output | `automation/matching/statement_matcher.dart` |
| A3.4 | Repository methods: proposals, rules, line queries | `automation/data/` |
| A3.5 | `BankMatchJob` (suggest and auto behaviours, daily cap, learning) | `automation/jobs/bank_match_job.dart` |
| A3.6 | Accept/Change/Reject/Create-unidentified/Ignore actions calling existing services | `automation/matching/bank_match_actions.dart` |
| A3.7 | Hook job after `importStatement`; link from Reconciliation | bank service/screen |
| A3.8 | Bank Match screen with side panel and Accept-all | `screens/automation/bank_match_screen.dart` |
| A3.9 | Tests for S3 | `test/society/automation/` |

**Acceptance:** importing a fictional statement of 30 lines yields proposals; Accept posts a receipt allocated oldest-first and clears the line; accepting twice posts once; auto mode only clears pre-existing records and strict-triple receipts; rejected lines do not return.

---

## Phase A4. Dues ladder, promises, reminders

| ID | Task | Files |
|---|---|---|
| A4.1 | Ladder model, JSON settings, editor widget | `automation/jobs/`, settings screen section |
| A4.2 | `ReminderJob` per S4 with `reminder_log` | `automation/jobs/reminder_job.dart` |
| A4.3 | Promise repository/service, status transitions | `automation/data/`, `automation/engine/` |
| A4.4 | Dues screen: promise dialog, chip, ladder preview, preselected batch | `screens/collections/dues_screen.dart` |
| A4.5 | Tests for S4 | `test/society/automation/` |

**Acceptance:** a unit overdue 8 days with email gets step 1 only once; a promise suppresses reminders until broken; auto mode sends exactly once per unit-step; no-email units are listed in the task.

---

## Phase A5. Vendors, recurring expenses, payment runs, deadlines

| ID | Task | Files |
|---|---|---|
| A5.1 | Recurring template repository/service with amount modes and frequency advancement | `automation/engine/`, `data/` |
| A5.2 | `RecurringExpenseJob` per S6 | `automation/jobs/recurring_expense_job.dart` |
| A5.3 | Recurring screen and "Make recurring" on expense form; prefilled form via `template` query | `screens/automation/recurring_screen.dart`, expense form |
| A5.4 | `PaymentRunJob` and batch payment action with payment-advice Excel | `automation/jobs/payment_run_job.dart`, payments screen |
| A5.5 | `DeadlineCalendar` and `DeadlineJob` per S8 | `automation/jobs/deadline_job.dart` |
| A5.6 | Tests for S6, S7, S8 | `test/society/automation/` |

**Acceptance:** a monthly template creates one prefilled draft task at next_due minus 3 days; trusted template within tolerance auto-posts in Auto mode only; batch pay creates correct per-vendor payments; deadline tasks appear only when applicable.

---

## Phase A6. Anomaly and data-quality scan

| ID | Task | Files |
|---|---|---|
| A6.1 | Add read queries each rule needs (via repositories, tested) | existing/new repositories |
| A6.2 | `AnomalyJob` with all 12 rules in S9, each as its own small class | `automation/jobs/anomaly_job.dart`, `automation/jobs/rules/` |
| A6.3 | Findings screen, route, "Scan now" | `screens/automation/findings_screen.dart` |
| A6.4 | Tests for every rule (positive and negative) and fingerprint behaviour | `test/society/automation/` |

**Acceptance:** seeded duplicates are found once; fixing the cause auto-marks the finding fixed on rescan; an unbalanced trial balance (constructed in a test DB) is reported as error.

---

## Phase A7. Smart import and fast entry

| ID | Task | Files |
|---|---|---|
| A7.1 | `ColumnMapper` with synonym table | `automation/importing/column_mapper.dart` |
| A7.2 | `ImportTemplateService` | `automation/importing/import_template_service.dart` |
| A7.3 | Add `dryRun` parameter (default false) to every `ImportService` import method (transaction + rollback) | `domain/imports/import_service.dart` |
| A7.4 | Import screen: auto-mapping, saved templates, dry-run step, error-file export | `screens/imports/import_screen.dart` |
| A7.5 | Meter grid mode with keyboard navigation | `screens/billing/meters_screen.dart` or new widget in `screens/automation/widgets/` |
| A7.6 | Cheque deposit batch screen/dialog and deposit slip PDF | `screens/collections/`, `documents/pdf/deposit_slip_pdf.dart` |
| A7.7 | Bulk actions on Bills and Receipts lists | existing list screens |
| A7.8 | Tests for S12, S13 | `test/society/automation/` |

**Acceptance:** importing a file with differently named headers maps automatically; a dry run changes nothing; the error file contains only failed rows; meter grid saves all rows or none.

---

## Phase A8. Auto-backup, performance, settings, finish

| ID | Task | Files |
|---|---|---|
| A8.1 | `BackupJob` per S11, settings fields, status in Settings > Backup | `automation/jobs/backup_job.dart` |
| A8.2 | Automation Settings screen and route (all cards, confirm dialogs, run history, ladder editor if not already) | `screens/automation/automation_settings_screen.dart` |
| A8.3 | Re-evaluate month-end checks that depended on later phases; remove any `not_applicable` stand-ins | `automation/month_end/` |
| A8.4 | Performance pass: add missing indexes only as new `CREATE INDEX IF NOT EXISTS` in m002 (new migration step is not allowed, so extend m002 before release since it has not shipped; note in report), paginate list screens added here, chunk jobs | various |
| A8.5 | Benchmark test: 1,000 units, 12 months of bills and receipts, 5,000 statement lines. Targets: scheduler full pass for one society < 8 s; bank match for 5,000 lines < 10 s; search < 100 ms; Today screen data load for 20 societies < 2 s | `test/society/automation/performance_test.dart` |
| A8.6 | Full-cycle integration test: simulate one month across a seeded society using the injected clock: meters, draft run, post, statement import, auto-match (suggest then accept), reminders, recurring bill, anomaly scan, month-end 100%, backup; assert trial balance balanced and unchanged by automation-only actions | `test/society/automation/full_cycle_test.dart` |
| A8.7 | Final scan: forbidden markers (`TODO`, `FIXME`, `coming soon`, `double` in money paths), unused files, every new route real, analyze clean, all tests pass | report |

**Acceptance**
- Every automation has a working Off / Suggest / Auto control honoured by its job.
- Nothing posts money in Suggest mode; verified by test.
- Performance targets met or the shortfall reported with numbers.
- `git status --short` shows only allowed files.

Write the final report in `PROGRESS.md`: files added, existing files edited with reason, test counts, benchmark numbers, known limits.
