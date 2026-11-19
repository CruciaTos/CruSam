# 01. Architecture

## 1. Target shape

```text
packages/society_core/            pure Dart: engine, data, documents. No Flutter. Used by BOTH:
        ^                    ^
        |                    |
crusam/ (Flutter app)     mcp-server/ (stdio server)
 screens, shell,           Society tool groups, previews,
 SocietyContext (UI),      write gate, Society DB connection
 Gmail sender
```

Both processes open the same `society.db` (SQLite, WAL not required; `busy_timeout=5000` as today). They never share memory. The app learns about server writes by watching the file (Phase M6).

## 2. What moves to `packages/society_core`

Current location is `crusam/lib/features/society/`. New package name `society_core`, library entry `lib/society_core.dart` plus `lib/src/...` mirroring the old folders.

| Old folder | Moves? | Notes |
|---|---|---|
| `core/` (money, society_date, society_exception, society_services, society_credit) | yes | `society_services` must not touch Flutter or `AppPaths` (see 3.2) |
| `core/society_context.dart` | **no** | `ChangeNotifier` UI singleton, stays in the app. Split any pure parts out first if services import it (check; services should not) |
| `core/workspace_memory.dart` | **no** | uses `shared_preferences`, UI only |
| `data/` (migrations, models, repositories, seed, society_database) | yes | see 3.1 and 3.2 |
| `domain/` all services | yes | see 3.3 for communication |
| `documents/pdf`, `documents/excel` | yes | see 3.4 |
| `screens/`, `shared/widgets/`, `society_routes.dart` | **no** | stay in app |
| `automation/` (if built) | engine parts yes, screens no | follow the same split: `automation/engine`, `data`, `jobs`, `matching`, `month_end`, `search`, `importing`, `portfolio` move; `screens/automation` stays |

Tests: `crusam/test/society/*_test.dart` for engine logic move to `packages/society_core/test/` (they use `SocietyDatabase.openForTest`). `workspace_test.dart` and any widget/route test stay in `crusam/test/society/`. After the move, `flutter test test/society` in `crusam/` still runs what remains and `dart test` in `packages/society_core` runs the 114-minus-N moved tests. The sum of passing tests must be at least the previous 114.

## 3. Making the engine pure Dart (M0 edits, exhaustive)

### 3.1 Flutter imports (4 files)
`data/models/bank_models.dart`, `data/models/statement_models.dart`, `domain/reports/report_definitions.dart` import `package:flutter/foundation.dart` only for `@immutable` (verify by grep for other symbols such as `listEquals`, `debugPrint`, `kDebugMode`). Replace with `package:meta/meta.dart` (`@immutable`) and `package:collection` equivalents. `meta` and `collection` are already transitive dependencies in the repo; add them to `society_core/pubspec.yaml` with the same versions the app resolves. This is the only allowed dependency addition besides the path dependency.

### 3.2 SQLite and paths
- Replace `package:sqflite/sqflite.dart` imports (23 files) with `package:sqflite_common/sqlite_api.dart` (Database, Transaction, DatabaseExecutor, ConflictAlgorithm are all there). `crusam_core` already does this.
- `SocietyDatabase` must not import `AppPaths`. Change to:

```dart
class SocietyDatabase {
  static Future<Database> open({required String path, bool readOnly = false});
  static Future<Database> openForTest({String path = inMemoryDatabasePath});
  static const int currentVersion;            // 1, or 2 once automation m002 exists
  static const List<int> supportedVersions;   // what the server may talk to
}
```
  The app passes `AppPaths.childPath('society.db')`; the server passes its configured path. Keep the singleton accessor `SocietyDatabase.instance` **in the app** as a thin wrapper (app file) that calls `open(path: AppPaths...)`, so existing app code keeps working with one import change. In the package, services take a `Database` through `SocietyServices` (constructor injection), as they already do for tests.
- `SocietyDatabase.open` runs migrations (`onCreate`/`onUpgrade`) as today. The **server must call a separate `SocietyDatabase.openExisting(path)`** that opens with `readOnly` or write mode but **never runs migrations** and throws `SocietyException('unsupported_schema')` unless `PRAGMA user_version` is in `supportedVersions`.

### 3.3 Communication (Gmail)
`communication_service.dart` imports the app's `GmailService`. Introduce in `society_core`:

```dart
abstract class SocietyEmailSender {
  Future<SendResult> sendPdfEmail({required String to, String? cc, required String subject,
      required String body, required List<EmailAttachment> attachments});
}
```
`CommunicationService` takes a `SocietyEmailSender`. The **app** supplies `GmailSocietyEmailSender` (wraps `GmailService.instance.sendPdfEmail`, file in `features/society/`). The **server** supplies `OutboxSocietyEmailSender` writing to the existing `email_outbox` table (see `tools/email.dart`) so the app sends it when open and the user has approved. Both implementations log to `email_log` through the service as today.

### 3.4 Documents
- `printing` package (`PdfGoogleFonts.openSans*` downloads fonts over the network) cannot be used in the server (no network). Introduce `abstract class PdfFonts { Future<pw.Font> regular(); Future<pw.Font> bold(); }` in `society_core`. The app implements it with `PdfGoogleFonts` (keeps current look). The server implements it with bundled font bytes: first check how `crusam_core/src/pdf` loads fonts for the existing server PDF tools and **reuse that approach**. PDF classes receive a `PdfFonts` argument (default is a required parameter, no hidden global).
- `excel` package is pure Dart; fine. `syncfusion_*` is not used by Society engine (verify).
- `dart:io` file writing stays in the callers (app or server), documents return bytes.

### 3.5 App-side rewiring
Replace `package:crusam/features/society/{core,data,domain,documents}/...` imports across app screens and tests with `package:society_core/society_core.dart` (or deep `package:society_core/src/...` only if the barrel would be unwieldy; prefer a small set of barrels: `models.dart`, `services.dart`, `documents.dart`). Mechanical; no logic changes. `SocietyContext` imports from the package.

## 4. Server-side structure (new)

```text
mcp-server/lib/src/society/
  society_db.dart          opens society.db (openExisting), version check, read-only flag, backup-before-first-write
  society_context.dart     SocietyToolContext: db, services (society_core), config, UiEvents, clock
  resolver.dart            society resolution (id or name), unit/vendor/member lookups with fuzzy ranking
  write_gate.dart          THE one gate: read_only env, society access setting, preview_id check, audit
  previews.dart            PreviewStore: create/verify/expire preview_id
  units.dart               paise<->rupees strings, dates, area/qty helpers
  tools/
    read_tools.dart        societies, overview, units, members, bills, receipts, ledger, reports, dues ...
    master_tools.dart      create/update unit, member, vendor (dry-run/confirm)
    billing_tools.dart     meter readings, draft bill run, post bill run, manual bill, reverse bill
    collection_tools.dart  receipts, unidentified receipts, credit/debit notes, reverse
    expense_tools.dart     expense bills, payments, reverse
    bank_tools.dart        statements, matching (basic), transfers, clear lines
    ledger_tools.dart      manual journal, reverse journal
    document_tools.dart    export bill/receipt/statement/report PDF/Excel, email via outbox
    automation_tools.dart  (M7 only)
  workflows_society.dart   prompts
mcp-server/test/society/    one test file per tool file + write_gate + previews + safety matrix
```

`server.dart` registers `SocietyTools` groups only when the Society DB is present and supported. If `society.db` is missing (user never opened Society) tools return a clear message `Society workspace has not been set up in the app yet`, and the rest of the server works unchanged. CruSam non-Society tools are not modified.

## 5. Society database location and config

Extend `ServerConfig` with `societyDbPath`: env `CRUSAM_SOCIETY_DB_PATH` (new optional manifest field, same pattern as `CRUSAM_DB_PATH`), default: same directory as `aarti.db`, file `society.db` (the app writes it with `AppPaths.childPath('society.db')`, which sits beside `aarti.db`; verify and note actual resolved path in the M1 report).

## 6. Write gate (single enforcement point)

```dart
class SocietyWriteGate {
  Future<GateResult> authorise({
    required int societyId,
    required WriteLevel level,          // draft | post | reverse
    required String toolName,
    required Map<String, Object?> normalisedArgs,
    required bool dryRun,
    String? previewId,
  });
  Future<void> audit(int societyId, String toolName, Map<String, Object?> summary);
}
```

Checks, in order, each with a distinct error code Claude can read and explain:

1. `read_only`: global env flag set -> refuse any non-dry-run.
2. `schema`: unsupported version -> refuse everything (even dry-run).
3. `society_inactive` / `year_closed`: society inactive, or posting date in a closed financial year (use the same `requireOpenYear` rule the services use; do not duplicate dates logic).
4. `access`: society setting `mcp.write_access` (`off` | `drafts` | `full`, default `drafts`): `off` refuses non-dry-run; `drafts` allows only `WriteLevel.draft`; `full` allows all three. Dry-runs are always allowed unless `off`.
5. `preview`: a non-dry-run needs a valid, unexpired `previewId` created for **identical normalised arguments**, in this society, **and the ledger watermark unchanged** (`MAX(journal_entries.id)` plus `MAX(audit_log.id)` captured at preview time). Otherwise `preview_stale`: ask Claude to preview again.
6. On success the tool runs the `society_core` service call **inside the service's own transaction**, then `audit()` writes `audit_log` actor `mcp:claude`, tool name and a short summary (ids, totals; no personal data beyond ids).

`WriteLevel` per tool is declared once in the tool definition table in `02_TOOLS.md`. A test must assert that for every registered write tool the gate was invoked (enumerate the registry; fail if a write tool is not in the table).

## 7. Preview contract

`PreviewStore` holds in memory: `previewId` (random uuid), society id, tool name, SHA-256 of canonical JSON of normalised args, watermark, `expiresAt` (10 minutes), `used` flag. A confirmed write consumes it (one use). The server restarting invalidates previews (acceptable). Dry-run responses always include: `preview_id`, `expires_in_seconds`, a human summary (`will_create`, totals in rupees), `warnings`, and the exact `next_step` sentence: "Show this to the user and wait for their go-ahead, then call again with dry_run=false and preview_id."

## 8. Money, dates, ids in tool I/O

- Amounts in tools are **rupee strings or numbers with at most 2 decimals** (`"12500.50"`); the server converts with `parseRupeesToPaise` and **returns** `{"paise": 1250050, "display": "Rs 12,500.50"}` style pairs on money fields so Claude never has to convert. Reject more than 2 decimals, negatives where not allowed, NaN, and exponent forms.
- Dates `YYYY-MM-DD`; reject others with an example. Indian handwritten formats are the model's job to normalise (instructions say so), not the server's.
- Every entity returned includes its numeric `id` and a human label. Tools accept `society` as **id or exact/clear unique name**; ambiguous names return candidates, never guess.

## 9. App-side pieces (M6)

- **Write-access setting** in Society Settings (new "Claude" tab or section): radio Off / Drafts only / Full, with explanation and a link to the install guide. Stored in `society_settings` key `mcp.write_access`. Per society.
- **Live refresh:** `DbChangeWatcher` also watches `society.db` mtime/WAL; on change notify `SocietyContext` listeners and any open screen controller to reload (screens already reload on `SocietyContext.revision`; if not, add a `revision` counter and have list/detail controllers listen).
- **Claude activity:** when `audit_log` shows new rows with actor `mcp:claude`, show a snackbar "Claude posted receipt R-2026-00043" with [View]. Rows created by Claude show a small "By Claude" chip on bill/receipt/expense/payment detail screens (read from audit_log; no schema change).
- **Follow Claude in Society:** show the existing toggle in Society. Server tools call `UiEvents` with society routes (`/society/receipts/<id>` etc.) plus `society_id`; `ClaudeFollowController` allows navigation within Society, switches `SocietyContext` to the event's society, and may leave Society for a CruSam route only if the user enabled Follow (remove the unconditional `return false` added for Society; keep a guard that never navigates while a Society form has unsaved changes, same rule as `_editingRoutes`).

## 10. Compatibility rules

- Server and app versions can differ. The server checks `user_version`; the app checks nothing about the server. A newer app upgrading `society.db` (e.g. automation m002) makes an older server refuse with a clear "update the CruSam extension" message.
- Old extension + new app, or the reverse, must never corrupt data: the server never migrates and never writes unknown columns.
