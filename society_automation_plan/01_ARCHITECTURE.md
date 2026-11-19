# 01. Automation Architecture

## 1. Layers

```text
Screen widget
  -> Screen controller (ChangeNotifier owned by the screen)
    -> AutomationService / feature service (automation/)
      -> existing domain services (billing, collections, expenses, bank, communication, backup)
        -> repositories -> society.db
```

Automation code lives beside, not inside, the domain layer. It only **calls** domain services.

## 2. Folder map

```text
crusam/lib/features/society/
  automation/
    engine/
      automation_kind.dart        enum + metadata for every automation
      automation_mode.dart        off | suggest | auto
      automation_settings.dart    read/write per society via society_settings keys
      automation_scheduler.dart   timer + on-open runner
      automation_runner.dart      runs one job, dedupe, logging, error capture
      task_service.dart           inbox tasks: create/dedupe/resolve/snooze
      finding_service.dart        anomaly findings
    data/
      automation_models.dart
      automation_repository.dart  SQL only
    jobs/
      draft_bill_run_job.dart
      meter_check_job.dart
      bank_match_job.dart
      reminder_job.dart
      interest_preview_job.dart
      recurring_expense_job.dart
      payment_run_job.dart
      deadline_job.dart
      anomaly_job.dart
      backup_job.dart
      month_end_job.dart
    matching/
      statement_matcher.dart      pure scoring logic
      narration_parser.dart       extracts ref numbers, UPI ids, unit tokens
      name_matcher.dart           fuzzy member/unit/vendor matching
    month_end/
      month_end_service.dart      builds checklist from live data
    search/
      search_service.dart         global search index queries
    importing/
      column_mapper.dart          header auto-mapping
      import_template_service.dart
    portfolio/
      portfolio_service.dart      per-society reads aggregated
  screens/automation/
    today_screen.dart  inbox_screen.dart  portfolio_screen.dart
    month_end_screen.dart  automation_settings_screen.dart
    bank_match_screen.dart  recurring_screen.dart  findings_screen.dart
    widgets/ command_palette.dart  attention_strip.dart  task_tile.dart  mode_selector.dart
```

Tests mirror under `crusam/test/society/automation/`.

## 3. Core types

```dart
enum AutomationMode { off, suggest, auto }

enum AutomationKind {
  draftBillRun, meterCheck, bankMatch, reminders, interestPreview,
  recurringExpense, paymentRun, deadlines, anomalyScan, autoBackup, monthEnd,
}

class AutomationDefinition {
  final AutomationKind kind;
  final String key;              // stable settings/db key, e.g. 'bank_match'
  final String title;
  final String description;
  final bool canAuto;            // false = mode picker offers only off/suggest
  final AutomationMode defaultMode;
  final Duration cadence;        // how often the scheduler may run it
}
```

`canAuto` is **false** for: `meterCheck`, `interestPreview`, `deadlines`, `anomalyScan`, `monthEnd` (they only ever create tasks/findings). It is **true** for: `draftBillRun` (auto = create draft only, never post), `bankMatch` (auto = post receipts for exact matches only), `reminders` (auto = send), `recurringExpense` (auto = post bill when amount is within tolerance), `paymentRun` (never auto-pays: `canAuto` false), `autoBackup` (auto is its normal mode, default `auto`).

Final truth table, binding:

| Kind | off | suggest | auto | default |
|---|---|---|---|---|
| draftBillRun | nothing | task "Draft ready" + draft run created | same as suggest (draft only) | suggest |
| meterCheck | nothing | tasks for missing/odd readings | n/a | suggest |
| bankMatch | nothing | match proposals in Bank Match screen | post receipt for exact-reference matches, proposals for rest | suggest |
| reminders | nothing | ready-to-send batch task | send per ladder | suggest |
| interestPreview | nothing | task with interest preview | n/a | suggest |
| recurringExpense | nothing | draft expense bill tasks | post if within tolerance and vendor flagged trusted | suggest |
| paymentRun | nothing | task listing bills due | n/a | suggest |
| deadlines | nothing | tasks before due dates | n/a | suggest |
| anomalyScan | nothing | findings | n/a | suggest |
| autoBackup | nothing | task reminder to back up | write backup file | auto |
| monthEnd | nothing | checklist refreshed + task | n/a | suggest |

### Settings storage

Per society, in existing `society_settings` (key/value), keys:

```text
automation.<key>.mode            off|suggest|auto
automation.bank_match.min_auto_score      integer 0-100, default 98
automation.bank_match.min_suggest_score   default 60
automation.reminders.ladder_json          see specs
automation.recurring.tolerance_bp         default 1000 (10%)
automation.backup.folder                  path
automation.backup.keep                    default 14
automation.backup.every_hours             default 24
automation.draft_run.lead_days            default 3
automation.deadline.lead_days             default 7
```

Use the existing `SocietyAdminService.getSetting/setSettings`. Do not add settings columns.

## 4. Scheduler contract

```dart
class AutomationScheduler {
  static final instance;
  void start();   // called once when SocietyContext first has a society
  void stop();
  Future<void> runNow(int societyId, {AutomationKind? only});
  Future<void> runAllSocieties();   // used on app start and by the 30-min timer
}
```

Rules:

- Runs `runAllSocieties()` once shortly after Society workspace first opens (delay 3 s), then every 30 minutes while the app is open. `Timer.periodic`, no isolates.
- For each active society and each enabled kind: skip when `now - last_success < cadence`.
- **Dedupe key**: `(society_id, kind, period_key)`. `period_key` examples: `2026-06` (monthly), `2026-06-19` (daily), `bill-run:2026-07`. A job must be safe to run twice and produce the same tasks, not duplicates.
- Each job is wrapped by `AutomationRunner.run(...)`:
  1. insert `automation_runs` row `status='running'`
  2. execute inside try/catch
  3. on success set `status='ok'`, counts, `finished_at`
  4. on error set `status='error'`, `error_message`; **also** create an Inbox task of kind `automation_error` (deduped per kind per day). Never swallow silently.
- One job at a time per society. Societies processed sequentially to keep the UI responsive; yield with `await Future.delayed(Duration.zero)` between jobs.
- Closed financial year or inactive society: skip with `status='skipped'`.

## 5. Tasks and findings

- **Task** = something the user may need to do or approve. Kinds are listed in `02_SCHEMA_M002.sql`. Each has `severity` (`info`, `action`, `urgent`), `title`, `detail`, `deeplink` (an existing route path plus optional query), `dedupe_key`, `due_date`, `status` (`open`, `done`, `snoozed`, `dismissed`).
- `TaskService.upsert(...)` with the same `(society_id, dedupe_key)` updates the open task instead of adding another. A task resolved by the user is not recreated for the same dedupe key and period.
- **Finding** = a data-quality or anomaly record from `anomalyScan`, with `rule_key`, `entity_type`, `entity_id`, `severity`, `message`, `status` (`open`, `acknowledged`, `fixed`). Findings can create a task of kind `finding` (one per scan, summarising).
- Tasks auto-resolve when their condition clears (for example the unidentified receipt was resolved): jobs call `TaskService.resolveWhere(dedupeKeyPrefix, ...)`.

## 6. Reuse contract (existing services this plan depends on)

Phases must call these, not reimplement them. If a name differs slightly in code, use the real name and note it in the report:

| Need | Existing method |
|---|---|
| Preview / draft / post bill run | `BillingService.previewBillRun`, `createDraftRun`, `postDraftRun` |
| Meter readings | `BillingService.addMeterReading`, `ImportService.importMeterReadings` |
| Create receipt, allocate, reverse | `CollectionService.createReceipt`, `allocateAdvance`, `reverseReceipt` |
| Unidentified receipts | `CollectionService.createUnidentified`, `resolveUnidentified` |
| Statement import, clearing | `BankService.importStatement`, `clearLine`, `unclearLine`, `reconciliation` |
| Expense bill / payment | `ExpenseService.postExpenseBill`, `postPayment` |
| Reminder email / statements | `CommunicationService.sendReminderBatch`, `sendStatementEmail` |
| Backup | `BackupService.exportSociety`, `inspect` |
| Dues / ageing / GST / TDS | `ReportService.runReport`, `BankService.gstRegister`, `tdsRegister` |
| Settings | `SocietyAdminService.getSetting/setSettings` |
| Audit | `SocietyAdminService.writeAudit` |

If a read is needed that no service exposes (for example "units with no reading this month"), add a **new read method to the relevant repository/service** with a test. Do not query tables from `automation/jobs` directly except through `automation_repository.dart` for the new tables.

## 7. Audit and attribution

Automation-caused postings write `audit_log` with `actor = 'automation:<key>'` and `detail` stating the rule and score. The Inbox and receipt/bill detail screens show an "Automated" chip when `created_by_automation` is set in the matching audit row (read via audit_log, no schema change to existing tables).

## 8. Performance contract

- Every list screen added here paginates (page size 50) and never loads full history.
- Jobs process units/lines in chunks of 200 and yield between chunks.
- Search uses indexed `LIKE`/prefix queries on indexed columns, results capped at 30.
- New tables have the indexes listed in the schema file.
