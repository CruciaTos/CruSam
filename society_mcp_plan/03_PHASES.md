# 03. Build Phases

Build every phase in order in one continuous run. Verify and report each, then continue. Stop only for a blocker in `00_EXECUTION_RULES.md` or after the Phase M8 final report. Verification commands are in the rules file section 4.

---

## Phase M0. Extract `packages/society_core`

**Result:** the Society engine is a pure-Dart package used by the app; every existing Society test still passes; the app behaves exactly as before.

| ID | Task |
|---|---|
| M0.1 | Inventory: list every file under `core/ data/ domain/ documents/` and every import from `package:flutter`, `package:sqflite/`, `printing`, `shared_preferences`, `crusam/core/...`. Save the list into the M0 report. Confirm it matches architecture section 3 (4 flutter-foundation files, 23 `sqflite` imports, 7 `printing`, 1 `AppPaths`, 1 `GmailService`, `society_context`/`workspace_memory` stay). Stop and ask if there is anything else |
| M0.2 | Create `packages/society_core` with `pubspec.yaml` (deps: `sqflite_common`, `sqflite_common_ffi`, `pdf`, `excel`, `path`, `meta`, `collection`, `uuid` only if used; same versions as the app; dev: `test`), `analysis_options.yaml` copied from `crusam_core`, barrels in `lib/` |
| M0.3 | Move the folders per architecture section 2 with `git mv` semantics (preserve history by moving, not copy-delete). Fix `package:` imports inside the package |
| M0.4 | Replace Flutter-only imports per 3.1; replace `sqflite` imports per 3.2 |
| M0.5 | Refactor `SocietyDatabase` per 3.2 (`open`, `openExisting`, `openForTest`, `supportedVersions`); add the app-side wrapper `crusam/lib/features/society/data/app_society_database.dart` providing the old `instance` accessor |
| M0.6 | Add `SocietyEmailSender` and make `CommunicationService` depend on it; add the app's `GmailSocietyEmailSender`; wire in `SocietyServices` construction in the app |
| M0.7 | Add `PdfFonts`; thread it through all PDF classes; app implementation using `PdfGoogleFonts`; add a font-bytes implementation stub placeholder **only as an interface** here (server implementation comes in M4) |
| M0.8 | Rewrite app imports (screens, shared widgets, routes, shell, tests) to the package. Add path dependency `society_core` to `crusam/pubspec.yaml` and `mcp-server/pubspec.yaml` |
| M0.9 | Move engine tests to `packages/society_core/test/`; keep route/widget tests in the app. Add a test proving `SocietyDatabase.openExisting` refuses an unsupported `user_version` and never creates tables |
| M0.10 | Run all verification; confirm total passing tests >= 114 plus the new one; confirm app still builds (`flutter analyze` clean for the whole app; `flutter build windows --debug` if available, else report not run) |

**Acceptance:** `git grep "features/society/(core|data|domain|documents)"` returns nothing outside the package-history; `packages/society_core` has no `flutter` in its pubspec or imports (`grep -r "package:flutter" packages/society_core/lib` empty); app Society screens work unchanged (seeded run-through listed in report).

---

## Phase M1. Server plumbing

| ID | Task | Files |
|---|---|---|
| M1.1 | `ServerConfig.societyDbPath` + manifest field plumbing | `config.dart`, `config_test.dart` additions |
| M1.2 | `SocietyDb`: `openExisting`, version check, read-only mode, one-time `society.db` backup before first write (same naming and retention as the CruSam backup in `db.dart`), clear missing-DB message | `society/society_db.dart` |
| M1.3 | `SocietyToolContext` building `society_core` services on that DB with `OutboxSocietyEmailSender` (writes to `email_outbox`; reuse `EmailOutboxStore`) and injected clock | `society/society_context.dart` |
| M1.4 | `Resolver` (society by id/name with candidates; unit/vendor/member lookup) | `society/resolver.dart` |
| M1.5 | `units.dart` money/date parsing and result shaping (`paise` + `display`) | `society/units.dart` |
| M1.6 | `PreviewStore` and `SocietyWriteGate` exactly per architecture 6 and 7 | `society/previews.dart`, `society/write_gate.dart` |
| M1.7 | Pagination helper (`limit`, `cursor`) and error mapper (`SocietyException` -> error codes) | `society/` |
| M1.8 | `SocietyTools` registry: tool table with `WriteLevel`, and a test that fails if a write tool is registered without a table entry or without calling the gate | `society/tools/registry.dart` |
| M1.9 | Tests: gate order and codes, preview expiry/one-use/watermark staleness, resolver ambiguity, paise parsing, unsupported schema refusal, missing DB message | `test/society/` |

**Acceptance:** with a seeded test `society.db`, a stub write tool is refused in each gate state with the right code, accepted in the right state, audited once.

---

## Phase M2. Read tools

| ID | Task |
|---|---|
| M2.1 | `society_list`, `society_get_overview` (extract overview computations from the screen into a `society_core` service method `OverviewService.summary(societyId)` used by both the screen and the tool; screen behaviour unchanged) |
| M2.2 | Units and members tools |
| M2.3 | Billing reads (bills, runs, meters, readings) |
| M2.4 | Collections reads (receipts, unidentified, dues report, unit statement) |
| M2.5 | Expense and vendor reads, budget reads |
| M2.6 | Bank and reconciliation reads, statement lines |
| M2.7 | Ledger, trial balance, statements, reports (`society_list_reports`, `society_run_report`), GST/TDS registers, chart of accounts, audit log |
| M2.8 | `society_search` (simple multi-repo version; upgraded by M7 if automation search exists) |
| M2.9 | Tests: every read tool against a seeded fictional society (reuse `society_core` test fixtures/seeds), pagination, caps, society isolation (second society's data never appears) |

**Acceptance:** every read tool returns correct values compared with direct service calls in the same test; no read tool opens a write transaction (assert via read-only DB handle in a test).

---

## Phase M3. Draft-level writes

| ID | Task |
|---|---|
| M3.1 | Master-data tools (units, members, vendors) with duplicate guard |
| M3.2 | `society_enter_meter_readings` with confidence handling and odd-value warnings |
| M3.3 | `society_preview_bill_run`, `society_create_draft_bill_run` |
| M3.4 | `society_create_unidentified_receipt` |
| M3.5 | `society_import_statement_rows` |
| M3.6 | Tests for every tool: dry-run changes nothing (table row counts equal before/after); real call needs preview id; `access=off` and `read_only` refuse; `access=drafts` allows; bad input rejected with row numbers; duplicates refused; `client_ref` idempotence |

---

## Phase M4. Posting, reversal, documents and email

| ID | Task |
|---|---|
| M4.1 | Collections posting: receipt (with duplicate guard and amount limit), resolve unidentified, allocate advance, credit/debit note |
| M4.2 | Billing posting: post bill run, manual bill; reverse bill |
| M4.3 | Expense posting: bill, payment, reversals (and expense draft if supported) |
| M4.4 | Bank and ledger posting: clear/unclear line, transfers, manual journal with balance check and trial-balance effect in preview, reversals |
| M4.5 | `PdfFonts` server implementation (bundled font, no network); `society_export_document` writing to the same export folder logic used by CruSam tools |
| M4.6 | `society_queue_email` through the outbox with all existing email safety rules |
| M4.7 | Safety matrix test: for **every** write tool x each of {read_only on, access off, access drafts, access full, no preview, stale preview, mismatched args, closed year, backdated, over limit} assert the expected code. Generate the test from the registry table |
| M4.8 | Accounting parity tests: the same operation performed through the tool and directly through the service on identical seeded DBs yields identical journal entries and trial balance (receipt, bill run, expense bill with TDS, payment, journal) |

**Acceptance:** trial balance balances after every tool in the test sequence; reversing everything returns outstanding to the starting values; no write path bypasses the gate (registry test green).

---

## Phase M5. Instructions and prompts

| ID | Task |
|---|---|
| M5.1 | Append Society instructions (02 section 4) to server instructions; keep the CruSam text unchanged; bump `serverVersion` to `1.5.0` |
| M5.2 | `workflows_society.dart` with all prompts in 02 section 5, registered like existing workflows |
| M5.3 | Tests: prompts list and render, instructions contain the safety lines (assert key sentences), version string |

---

## Phase M6. App side

| ID | Task | Files |
|---|---|---|
| M6.1 | Society Settings "Claude" tab: write-access radio (Off / Drafts only / Full) saved to `mcp.write_access`, max amount field, plain explanation, link to install guide | settings screen |
| M6.2 | `DbChangeWatcher` also watches `society.db`; bump `SocietyContext.revision`; list/detail controllers reload on revision | `core/sync/db_change_watcher.dart`, society screens/controllers |
| M6.3 | Claude activity: snackbar on new `mcp:claude` audit rows with View; "By Claude" chip on bill, receipt, expense bill, payment, journal detail screens | society screens |
| M6.4 | Follow Claude in Society per architecture 9; server side UiEvents for society routes | `claude_follow_controller.dart`, `shell_screen.dart`, `mcp-server/lib/src/ui_events.dart` |
| M6.5 | Tests: setting persistence, watcher triggers revision, follow controller allows Society routes and respects unsaved forms, CruSam follow behaviour unchanged (existing tests pass) | `crusam/test/` |

**Acceptance (manual, listed in report):** with the app open, a tool-created receipt appears without restarting, shows the chip, and the snackbar opens it; switching the setting to Off makes the server refuse real writes immediately (server re-reads the setting on every write).

---

## Phase M7. Automation bridge (conditional)

Run only if `society_core/lib/src/automation/` exists. Otherwise record "M7 skipped: automation plan not built" and continue.

| ID | Task |
|---|---|
| M7.1 | Read tools: `society_list_tasks`, `society_month_end_status`, `society_list_findings`, `society_list_bank_proposals`, `society_automation_status` (modes and last runs); `society_search` upgraded to `SearchService` |
| M7.2 | Write tools: `society_resolve_task` (draft level), `society_run_automation` (draft level; runs one kind once; respects that kind's mode: `off` refuses), `society_accept_bank_proposal` (post level, uses the same actions class as the app screen), `society_reject_bank_proposal` (draft level) |
| M7.3 | Never expose changing automation modes or thresholds (user does it in the app) |
| M7.4 | Prompts: `society_clear_inbox`, `society_review_bank_matches` |
| M7.5 | Tests including that `accept_bank_proposal` produces the same journal as the app action |

---

## Phase M8. Packaging, docs, final checks

| ID | Task |
|---|---|
| M8.1 | Update `extension/manifest.json`: version `1.5.0`, description and long description mention Society, new optional `society_db_path` user config mapped to `CRUSAM_SOCIETY_DB_PATH`; keep existing fields |
| M8.2 | Update `README.md`, `dist/HOW-TO-INSTALL.md` and installer copy: Society tools, write-access setting, safety model, error codes list |
| M8.3 | Build the extension with the existing `mcp-server/tool/` scripts; install into a scratch copy of Claude Desktop config only if scripts allow; otherwise report the exact command for the user. Do not publish or upload anything |
| M8.4 | End-to-end test script in `test/society/e2e_test.dart`: spawn the server over stdio against a seeded temp `society.db` and drive the MCP protocol: initialize, list tools (all prefixed), run a photo-style flow (meter readings dry-run -> real -> draft run -> post -> receipt dry-run -> real -> trial balance), assert results and that no stdout noise breaks the channel |
| M8.5 | Full verification of all three areas; final scan: no `TODO`/`FIXME`, no `double` money, no tool without gate, no raw SQL in `mcp-server/lib/src/society/`, `git status --short` shows only allowed paths |
| M8.6 | Final report in `PROGRESS.md`: files added/moved, test counts per area, tool count by level, what was skipped (M7?), known limits (previews reset on server restart, writes need DB lock availability) |

**Finish acceptance**
- Claude can, from a photo of a meter register, enter readings (draft), create a draft bill run, and (with Full access and the user's yes) post it and a receipt, with the app updating live.
- Every write tool is provably gated: the registry-driven safety matrix passes.
- Nothing in the 114 original tests regressed.
