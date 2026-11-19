# 00. Execution Rules

All rules in `society_plan/00_EXECUTION_RULES.md` **still apply** (work loop, forbidden actions, no commits, no dependency changes, no `double` money, no silent catches, no TODO/fake data, report disagreements). This file adds or overrides only what is listed here.

## 1. Authority order

1. `02_SCHEMA_M002.sql` for new tables and columns
2. `society_plan/02_SCHEMA.sql` and `society_plan/03_ACCOUNTING_RULES.md` for existing tables and every posting rule (unchanged, still binding)
3. `01_ARCHITECTURE.md` for structure and APIs
4. `03_AUTOMATION_SPECS.md` for behaviour
5. `05_PHASES.md` for order and acceptance
6. `04_UI_SPEC.md` for screens

## 2. Work loop

Same loop as the Society plan, using `society_automation_plan/PROGRESS.md`. Build Phase A0 to A8 in one continuous run. Run verification once per phase, not after every edit.

Verification, from `crusam/`:

```bash
flutter analyze lib/features/society test/society lib/core/router/app_router.dart lib/features/shell/shell_screen.dart
```

```bash
flutter test test/society
```

The existing 114 tests must keep passing at the end of every phase.

## 3. Allowed changes

New files only under:

```text
crusam/lib/features/society/automation/
crusam/lib/features/society/screens/automation/
crusam/test/society/automation/
```

Existing files you may edit, and only for the stated reason:

| File | Phase | Reason |
|---|---|---|
| `society/data/society_database.dart` | A0 | version 2, `onUpgrade`, same in `openForTest` |
| `society/data/migrations/` | A0 | add `m002_automation.dart` (new file) |
| `society/society_routes.dart` | A1+ | add routes and extend `societyNavPaths` |
| `society/core/society_services.dart` | A0 | register automation services |
| `society/domain/backup/backup_service.dart` | A0 | include new tables that must survive restore (see schema file notes) |
| `society/screens/overview/society_overview_screen.dart` | A1 | embed attention strip |
| `society/screens/bank/reconciliation_screen.dart`, `screens/collections/dues_screen.dart`, `screens/imports/import_screen.dart`, `screens/billing/meters_screen.dart`, `screens/billing/bill_runs_screen.dart` | A2 to A7 | add entry points to automation features; keep existing behaviour |
| `crusam/lib/features/shell/shell_screen.dart` | A1 | add nav entries, Ctrl+K host, Inbox badge. No other change |
| `society_automation_plan/PROGRESS.md` | every phase | status |

Do **not** edit: any other CruSam file, `pubspec.*`, `analysis_options.yaml`, generated plugin files, updater, MCP code, `packages/crusam_core`, existing migration `m001_initial.dart`, existing tests (add new ones; if an existing test must change, stop and ask).

If you need to touch a domain service for a hook (for example an `onPosted` callback), prefer adding an optional parameter or a new method. Never change an existing method's behaviour or signature in a breaking way.

## 4. Additional forbidden actions

- Posting, reversing or editing any financial record from automation code except by calling the existing public service method for that action.
- Auto-posting money unless that society's setting for that automation is `auto` (default is `suggest`; `off` disables).
- Sending email unless the society's reminder automation is `auto` or the user pressed Send.
- Running anything when the society is inactive or its financial year is closed.
- Doing work outside `society_id`. No cross-society reads except in the Portfolio services, which must read per society and aggregate.
- Background isolates or OS services. Timers only, and only while the app runs.
- Deleting or hiding Inbox history.
- Using real names, numbers or bank data in code or tests (fictional only).

## 5. Stop and ask only when

- A schema change beyond `02_SCHEMA_M002.sql` seems needed.
- A required existing service method does not exist or does not behave as `01_ARCHITECTURE.md` says.
- An automation would need a posting not covered by `society_plan/03_ACCOUNTING_RULES.md`.
- A test expectation appears wrong, or an existing test would have to change.
- Performance targets in A8 cannot be met without changing existing tables.
