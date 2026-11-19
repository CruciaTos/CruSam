# 00. Execution Rules

These rules are mandatory. They exist to keep implementation inside the agreed scope.

## 1. Authority order

When documents disagree, use this order:

1. `02_SCHEMA.sql` for tables and columns
2. `03_ACCOUNTING_RULES.md` for calculations and postings
3. `01_ARCHITECTURE_CONTRACTS.md` for code structure and APIs
4. `05_PHASES.md` for work order and acceptance
5. `04_UI_SPEC.md` for screens
6. `../SOCIETY_WORKSPACE_PLAN.md` for product summary

Report the disagreement in your phase report even if this order resolves it.

## 2. Work loop

**Build all phases in one continuous run, from the first unfinished phase through Phase 9.** Do not stop for approval between phases.

For every phase:

1. Read this file, `PROGRESS.md`, the phase section and every section it references.
2. Run `git status --short`. Record pre-existing changes. Do not touch them.
3. Do the tasks **in listed order**.
4. After each task, change its `PROGRESS.md` box from `[ ]` to `[x]`.
5. Run the phase verification once, after all tasks.
6. Fix failures caused by this phase. Do not start the next phase while this phase fails.
7. Write the phase report in `PROGRESS.md`.
8. Update `Current phase` in `PROGRESS.md` and continue immediately with the next phase.

After Phase 9, write the final report in section 9 and stop.

If the session or context ends, resume from `PROGRESS.md` at the first unchecked task. First inspect any partial files for that task.

Do not run analyze, tests or the app after every small edit.

## 3. Allowed changes

You may add files only under:

```text
crusam/lib/features/society/
crusam/test/society/
crusam/assets/society/           only if a phase names it
```

You may edit only these existing app files:

| File | Allowed phase | Purpose |
|---|---|---|
| `crusam/lib/core/router/app_router.dart` | 0 | Add Society routes |
| `crusam/lib/features/shell/shell_screen.dart` | 0 | Workspace navigation and top-bar controls |
| `crusam/lib/core/sync/claude_follow_controller.dart` | 0 | Stop Follow Claude leaving Society |
| `society_plan/PROGRESS.md` | every phase | Status and reports |

Do not edit any other existing file. This includes `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, generated plugin files, updater files, installer files, MCP code and `packages/crusam_core`.

If a task appears impossible without another edit, stop and ask.

## 4. Forbidden actions

Do not:

- Commit, push, stash, reset, clean, rebase or switch branches.
- Add, upgrade or remove dependencies.
- Run `dart format .` or format whole existing files.
- Refactor, rename or "clean up" existing CruSam code.
- Change CruSam database tables, `aarti.db`, salary logic, invoice logic, email settings or MCP tools.
- Add screens, fields, settings, services, reports or shortcuts not listed.
- Add resident login, phone screens, SMS, WhatsApp, online payment, cloud sync, AI, approvals or user roles.
- Use `double` for stored or calculated money.
- Put SQL in widgets or screen controllers.
- Read or write Society data without `society_id`.
- Edit or hard-delete posted financial records.
- Copy ADDA text, layout, icons, colours, logos, formats or data.
- Put real people, society names, phone numbers, bank numbers or balances in code or tests.
- Leave `TODO`, `FIXME`, fake data, disabled tests, or "coming soon" in a completed phase. The only exception is Phase 0 placeholders, and each later phase removes its own.
- Silently catch errors.
- Mark a task done if it is partial.

## 5. Stop and ask only when

Do not stop for routine progress, phase completion or small implementation choices that these documents already constrain. Stop the whole run if one of these blockers occurs, because later phases depend on correct earlier work:

- A schema change seems needed.
- An accounting case is not covered.
- A required existing API does not match the contract.
- A test's expected value seems wrong.
- A task requires a forbidden edit.
- Pre-existing failures block verification.
- The same failure survives two serious fix attempts.

Use this format:

```text
BLOCKED: Phase X, task X.Y
What I tried:
What is unclear or failing:
Files changed so far:
Decision needed:
```

## 6. Coding rules

- Dart SDK features already allowed by the project are fine.
- Imports inside Society use package paths: `package:crusam/features/society/...`.
- One public widget or service per file, unless the file is a small model group.
- Screen files stay under 500 lines. Move sections into the same feature's `widgets/` folder.
- Service methods are `Future` and take explicit `societyId`.
- Validate in services. Forms may also validate for good messages.
- User-visible failures use `SocietyException.message`.
- Controllers guard against updating after disposal.
- Dispose all controllers, focus nodes and listeners.
- No hard-coded user-visible money format. Use `formatInr`.
- No raw date display. Use `formatDisplayDate`, which shows `dd/MM/yyyy`.

## 7. Phase report

Add this under the phase in `PROGRESS.md`:

```text
Status: complete | blocked
Files added:
Existing files changed:
Acceptance checks:
- <check>: pass | fail
Analyze:
Tests:
Not run:
Scope changes: none
Questions:
```

## 8. Definition of done

A phase is done only if:

- Every task is complete.
- Every listed test exists and passes.
- `flutter analyze` reports no issues in Society files and allowed edited files.
- `git status --short` shows no unexpected paths.
- The report states what was not checked.

## 9. Final report

After Phase 9, add this at the top of `PROGRESS.md`, then stop:

```text
Overall status: complete | blocked
Phases complete:
Existing files changed:
Dependencies changed: none
Final analyze:
Final tests:
Final scope scan:
Manual checks not run:
Known issues:
Questions for owner:
```

Never claim the module is complete if any task, test or required check is unfinished.
