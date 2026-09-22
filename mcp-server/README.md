# CruSam MCP server

A local [MCP](https://modelcontextprotocol.io) server that lets Claude Desktop
read and write your CruSam data. Claude Desktop starts it as a child
process and talks to it over stdin/stdout. It opens no network port and
contacts no remote service.

The main use case is photographing a handwritten PO list and having Claude
create the invoice. Claude reads the image itself, matches names to
employees, shows you a dry run, and saves the invoice after you confirm.

## How it works

```
Claude Desktop ──stdio──> server.exe ──> aarti.db  (the same SQLite file the app uses)
                              │
                              └─ packages/crusam_core  (pure-Dart business logic, shared with the Flutter app)
```

- **Language:** Dart, using the `dart_mcp` package, which is maintained by
  the Dart team. It is not one of the SDKs published by the MCP project
  itself, but it is the only option that shares code with the app. The
  totals, tax, rounding, row building, salary formulas and saved-month
  storage all live in `packages/crusam_core`, and the Flutter app now calls
  the same code. An invoice made by Claude is therefore stored exactly as
  one made in the Voucher Builder.
- **stdout:** used only for the protocol. Logs go to stderr and, optionally,
  to a log file. Stray `print()` calls are redirected to the log.
- **App migrations:** never run. The server checks that the schema version is
  6 and that the required columns exist. If not, it stays read-only and says
  why.

## Safety

| What | How |
|---|---|
| Test data | During development the server uses `dev-data/aarti_dev.db`, a copy of your data. It is git-ignored because it holds real names and bank details. Each test works on its own throwaway copy of that copy, and the harness refuses to run against the real `aarti.db`. |
| Backups | Before the first write of each session, the server takes a consistent snapshot with `VACUUM INTO` and keeps the last 10 in `mcp_backups/` next to the database. |
| Confirmation | Creating or updating invoices supports `dry_run`. Deletes require `confirm: true`. Duplicates, near-duplicate clients and overwriting a saved salary month each need an explicit flag. |
| Read-only mode | Set `CRUSAM_READ_ONLY=true` to let Claude read everything but change nothing. |
| Deletes | Invoices, employees and clients are soft-deleted, as in the app. Saved salary months are deleted permanently, as the app also does. |

## Using it while the CruSam app is open

- **Locking:** SQLite locks the file only for the milliseconds a write takes.
  Both the server and the app now wait up to 5 seconds (`busy_timeout`)
  instead of failing. If the server still can't get the lock, it changes
  nothing and tells Claude to retry.
- **Live screens:** the app notices the server's writes within about a
  second and reloads what's on screen (an "Updated" pill shows it happened).
- **Follow Claude:** after each tool call the server records which screen
  shows the result (`ui_events` table). With Follow Claude on, the app pops
  up as a compact, always-on-top window next to Claude Desktop, opens that
  screen, highlights the row and says what Claude did. Salary steps show
  Claude's saved month on the salary screens; "Back to my month" restores
  the user's own. `show_in_app` points at a screen without changing data.
- **Open edits:** if an invoice is open in the Voucher Builder and you save it
  there after Claude changed it, the app's version wins.

## Setup

You need the Dart SDK that ships with Flutter
(`C:\Flutter\flutter_windows_3.41.4-stable\flutter\bin\dart.exe` on this PC).
From `mcp-server/`:

```powershell
dart pub get
# Development copy of your data (never the real file):
New-Item -ItemType Directory -Force dev-data
Copy-Item "$env:APPDATA\com.cructiatus\crusam\CruSam\aarti.db" dev-data\aarti_dev.db
dart test                  # 40 tests, all against throwaway copies
dart build cli             # -> build\cli\windows_x64\bundle\bin\server.exe (+ lib\sqlite3.dll)
```

Always point Claude Desktop at the built `server.exe`. Do not use
`dart run`: it prints "Running build hooks..." to stdout, which breaks the
protocol. Quit Claude Desktop before rebuilding, because Windows locks a
running `.exe`.

### Test with MCP Inspector first

Command-line mode, with no browser and no port:

```powershell
$exe = "C:\Soham\Kamachya_Goshti\CruSam\CruSam\mcp-server\build\cli\windows_x64\bundle\bin\server.exe"
$db  = "C:\Soham\Kamachya_Goshti\CruSam\CruSam\mcp-server\dev-data\aarti_dev.db"
npx -y @modelcontextprotocol/inspector --cli $exe -e CRUSAM_DB_PATH=$db --method tools/list
npx -y @modelcontextprotocol/inspector --cli $exe -e CRUSAM_DB_PATH=$db --method tools/call --tool-name match_employees --tool-arg 'names=["P.V. Lokesh","Mohd. Anas"]'
```

The interactive UI also works: run `npx @modelcontextprotocol/inspector $exe`.
It listens on localhost only. Set `CRUSAM_DB_PATH` in the UI's
environment panel.

## Settings (environment variables)

| Variable | Required | Meaning |
|---|---|---|
| `CRUSAM_DB_PATH` | no | Absolute path to the database. If empty, the server uses the CruSam app's own database for the current Windows user. The file must already exist; the server never creates one. |
| `CRUSAM_USER_EMAIL` | no | Stored in `created_by` / `updated_by`. Defaults to `claude-mcp`. |
| `CRUSAM_LOG_FILE` | no | Log file, appended to. Keep it outside `AppData` (see the note below). |
| `CRUSAM_READ_ONLY` | no | `true` blocks every write. |
| `CRUSAM_BACKUP_DIR` | no | Defaults to `<database folder>\mcp_backups`. |
| `CRUSAM_BACKUP_KEEP` | no | Defaults to 10. |
| `CRUSAM_EXPORT_DIR` | no | Folder for exported documents. Default: the folders set in the app (Profile → Export Paths), else Downloads. A tool's `output_dir` wins over both. |
| `CRUSAM_ASSETS_DIR` | no | Folder containing `assets/fonts` and `assets/images`. Found automatically next to `server.exe` (extension) or in the `crusam` source tree. |

## Installing on another laptop (one-click extension)

```powershell
powershell -ExecutionPolicy Bypass -File mcp-server\tool\package.ps1
```

This runs the tests, builds the server and produces
`mcp-server\dist\crusam.mcpb` (about 4 MB) plus `HOW-TO-INSTALL.md`. Send
both files. The other person double-clicks `crusam.mcpb` in Claude Desktop
and clicks Install.

- **Nothing else to install.** `server.exe` and `sqlite3.dll` depend only on
  standard Windows DLLs: no Dart, no Visual C++ runtime.
- **The database is found automatically.** When the path setting is left
  empty, the server uses `%APPDATA%\com.cructiatus\crusam\CruSam\aarti.db`,
  which is where the CruSam app stores its data for each Windows user. If the
  app has never been opened, the server says so.
- **Settings shown at install:** database path (optional), read-only, and
  email. The manifest is in `extension/manifest.json`, and the version must
  match `serverVersion` in `lib/server.dart`.
- **Updating:** bump both versions, re-run `package.ps1`, and send the new
  `.mcpb`. Installing it over the old one keeps the user's settings.

If you install the extension on this laptop as well, delete the manual
`crusam` entry from `claude_desktop_config.json`, or the tools appear twice.

## Connecting Claude Desktop manually (Windows, Microsoft Store build)

Your Claude Desktop is the Store (MSIX) version, so its config file is:

```
C:\Users\Soham\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json
```

(Claude Desktop → Settings → Developer → Edit Config opens the same file.)
Add an `mcpServers` key next to the existing `preferences` key, then fully
quit Claude Desktop from the system tray and start it again.

**Step 1: development copy.** Start here.

```json
{
  "mcpServers": {
    "crusam": {
      "command": "C:\\Soham\\Kamachya_Goshti\\CruSam\\CruSam\\mcp-server\\build\\cli\\windows_x64\\bundle\\bin\\server.exe",
      "args": [],
      "env": {
        "CRUSAM_DB_PATH": "C:\\Soham\\Kamachya_Goshti\\CruSam\\CruSam\\mcp-server\\dev-data\\aarti_dev.db",
        "CRUSAM_USER_EMAIL": "you@example.com",
        "CRUSAM_LOG_FILE": "C:\\Soham\\Kamachya_Goshti\\CruSam\\CruSam\\mcp-server\\dev-data\\crusam-mcp.log"
      }
    }
  },
  "preferences": { "...": "keep your existing preferences unchanged" }
}
```

**Step 2: switch to your real data.** Change only `CRUSAM_DB_PATH`:

```json
"CRUSAM_DB_PATH": "C:\\Users\\Soham\\AppData\\Roaming\\com.cructiatus\\crusam\\CruSam\\aarti.db"
```

For the first few sessions, consider also adding `"CRUSAM_READ_ONLY": "true"`
and removing it once you're comfortable. Backups will then appear in
`C:\Users\Soham\AppData\Roaming\com.cructiatus\crusam\CruSam\mcp_backups\`.

> **Store-app file virtualization (tested on this PC).** Processes that
> Claude Desktop starts run inside its app container. A write into an
> **existing** AppData folder, such as the one holding `aarti.db`, reaches
> the real file. The database and its backups were verified from outside
> the container, and `integrity_check` passed. A **new top-level folder**
> under `AppData\Roaming`, however, gets silently redirected into
> `...\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\`. So keep
> `CRUSAM_LOG_FILE` and any custom `CRUSAM_BACKUP_DIR` outside AppData, or
> inside the existing CruSam data folder.

## Ready-made workflows

In Claude Desktop, click **+** in the chat box → **CruSam** and pick a
workflow. If it asks for details (month, PO number…), fill them in, attach
the photo if it needs one, and send. Every workflow previews first and
saves, overwrites or emails only after you say yes.

| Workflow | Asks for | What Claude does |
|---|---|---|
| `invoices_from_image` | PO number, invoice date, bill number (all optional) + the photo | Reads the list, you confirm the reading, matches employees, previews totals and duplicates, saves, and offers the PDF and email |
| `salary_from_attendance` | month*, year + the attendance photo | Reads days worked, you confirm them, flags anything odd, calculates the month, asks for bill details and saves |
| `month_end` | month*, year, email_to | Saved month → final bill, statement and slips → bank disbursement → emails, one approved step at a time, then checks they were sent |
| `email_invoice` | invoice* (bill no, PO or id), to, include_bank_sheet | Finds the invoice, warns if already emailed, creates the PDF, shows the draft and sends through the app's Gmail |
| `whats_pending` | month, year (default this month) | Read-only checklist: invoices, emails, saved salary, disbursement, stuck emails, and suggested next steps |

The workflows live in `lib/src/workflows.dart`; a test checks that every
tool they mention exists.

## Suggested chat flow for the invoice image

> *(attach photo)* Create an invoice for this PO. Client is Diversey, date
> 2026-06-01, bill no AE/101/26-27.

Claude's steps:

1. Read the rows. "—n—" means the same period as the row above; `1.5/15.5.26`
   becomes 2026-05-01 to 2026-05-15.
2. Call `match_employees` once for all names and `find_clients` for the
   client.
3. Call `create_invoice` with `dry_run: true`, then show you the rows,
   totals and warnings.
4. After you say yes, call it again with `dry_run: false`.

Unclear rows, such as struck-out entries or ✗ marks, should be raised with
you rather than guessed.

## Tools

R = read-only, W = writes, D = destructive (asks for confirmation or
replaces data). `*` marks a required input. Dates are always `YYYY-MM-DD`,
and amounts are JSON numbers. Every tool returns compact JSON. Errors come
back as `isError` with one line per problem, each naming the field and
what to fix.

| | Tool | Input | Output |
|---|---|---|---|
| R | `get_app_overview` | none | record counts, conventions (tax, codes, item descriptions), company, server mode |
| R | `get_company_settings` | none | company fields |
| W | `update_company_settings` | any of company_name, address, gstin, pan, jurisdiction, declaration_text, bank_name, branch, account_no, ifsc_code, phone | updated fields and the new settings |
| R | `get_salary_formula_settings` | none | PF/ESIC/PT/employer constants |
| W | `update_salary_formula_settings` | any of pf_rate, pf_basic_threshold, pf_cap_amount, esic_rate, esic_gross_threshold, pt_* thresholds and amounts, employer_pf_rate, employer_esic_rate, attachment_b_per_employee | `{changes: {field: {from, to}}}` |
| R | `list_item_descriptions` | none | `{items: [{id, text, custom}]}` |
| W | `add_item_description` | text* | `{created, id, text}` |
| D | `delete_item_description` | id*, confirm* | custom items only |
| R | `find_clients` | query*, limit | `{matches: [{id?, name, address, gstin, email, source: saved\|invoice_history, invoice_count, score}]}` |
| R | `list_clients` | none | all known clients |
| W | `create_client` | name*, address, gstin, email, allow_similar | `{created, client}`; refuses names close to an existing client |
| W | `update_client` | id*, name, address, gstin, email | `{updated, client}` |
| D | `delete_client` | id*, confirm* | soft delete |
| R | `match_employees` | names*[], candidates | per name: `{input, confident, candidates: [{id, name, code, bank, has_bank_account, score}]}` and `needs_review` |
| R | `find_employees` | query*, code, limit | `{matches: [...]}` (also matches PF, UAN or account number) |
| R | `list_employees` | code, full, limit, offset | `{total, employees}` |
| R | `get_employee` | id* | every field, including bank and salary |
| W | `create_employee` | name*, code* (F&B/I&L/P&S/A&P), gender, sr_no, pf_no, uan_no, ifsc_code, account_number, bank_details, branch, sb_code, aarti_ac_no, zone, date_of_joining, basic_charges, other_charges, dry_run, allow_duplicate | `{created, employee, warnings?}` |
| W | `update_employee` | id*, any employee field, dry_run | `{changes: {field: {from, to}}}` |
| D | `delete_employee` | id*, confirm* | soft delete |
| R | `list_invoices` | client, date_from, date_to, status, bill_no, po_no, employee, include_deleted, limit, offset | `{total_matches, invoices: [{id, title, date, bill_no, po_no, client_name, dept_code, row_count, final_total, status}]}` |
| R | `get_invoice` | id* | header, client, totals, rows with bank details |
| W | `create_invoice` | title*, date*, rows* `[{employee_id, amount, from_date, to_date}]`, dry_run*, client_id or client_name, dept_code, item_description, bill_no, po_no, client_address/gstin/email overrides, allow_unlinked_employees, allow_duplicate | `{dry_run, created?, invoice: {id?, …, totals: {base_total, cgst_9pct, sgst_9pct, total_tax, round_off, final_total}, rows}, invoice_number, duplicates?, would_be_refused?, warnings?, defaults_applied?}` |
| D | `update_invoice` | id*, dry_run*, any create field (passing rows replaces all rows) | same shape as create |
| D | `delete_invoice` | id*, confirm* | soft delete |
| W | `calculate_salary_month` | month*, year*, attendance `[{employee_id, days}]`, default_days, company_code, apply_msw, msw_amount, include_employees, save, overwrite, snapshot_name, bill_no, po_no, bill_date, client_*, dept_code, item_description | `{period, totals: {attachment_a_*, attachment_b_total, invoice_total, total_net_salary, …}, employees: [...], saved, saved_salary_id?}` |
| R | `list_saved_salary_months` | none | `[{id, name, month, year, employees_worked, total_net_salary}]` |
| R | `get_saved_salary_month` | id, or month + year; include_employees | bill metadata, totals, employee lines |
| W | `rename_saved_salary_month` | id*, name* | none |
| D | `delete_saved_salary_month` | id*, confirm* | permanent, as in the app |
| R | `salary_analytics` | from/to (`YYYY-MM`), group_by (month\|employee), employee_id, code | aggregated days, gross, PF, ESIC, PT, MSW, deductions, net |
| R | `list_salary_disbursements` | month, year, status | batches with item count and total |
| R | `get_salary_disbursement` | id* | batch plus payment lines |
| W | `export_invoice_documents` | id*, documents (invoice_pdf, bank_disbursement_pdf, bank_disbursement_excel), output_dir | `{invoice_id, files: [{document, path, size_kb}]}` |
| W | `export_salary_documents` | month*, year*, documents (final_bill_pdf, salary_invoice_pdf, attachment_a_pdf, attachment_b_pdf, statement_pdf, statement_excel, slips_pdf), company_code, output_dir | `{period, company_code, invoice_total, files}` |
| W | `create_salary_disbursement` | month*, year*, dry_run*, employee_ids, output_dir | candidates, total; when saved, the batch id and its Excel file |
| W | `export_salary_disbursement_excel` | id*, output_dir | `{disbursement_id, file}`; marks the batch exported |
| D | `send_email` | entity_type*, entity_id, to, cc, subject, body, attachment_paths*, allow_resend, confirm* | `{outbox_id, status: queued, …}`. Invoices default to the app's subject, body and client email |
| R | `list_email_outbox` | status, limit | queued emails and their status/error |
| W | `cancel_email` | id* | cancels an email the app has not started sending |
| R | `list_email_log` | entity_type, entity_id, status, recipient, limit | emails the app has sent (from any screen) |

**Documents** are built by the same code as the app's export buttons (moved
into `crusam_core`), with the same fonts, margins, column widths and file
names. Files are never overwritten: an existing name gets `(1)`, `(2)`, ….
Excel files use the same layouts, rendered with the pure-Dart `excel`
package, because the app's Syncfusion library needs Flutter.

**Email** goes out through the Gmail account connected in the app (Profile).
The server has no Gmail access: `send_email` puts the email in a new
`email_outbox` table, and the running app sends it within about 30 seconds,
logging it in `email_log` exactly like its Send dialogs. If the app is
closed or Gmail isn't connected, the email waits in the queue. An email
interrupted mid-send is marked failed, never re-sent automatically.

**Duplicate rule for invoices:** a new invoice is refused if a non-deleted
invoice has the same `bill_no`, or the same client, date and final total,
unless `allow_duplicate: true`. Reusing a PO number only produces a warning,
because one PO is often billed in parts.

## Not covered yet

- **Drive sync:** deprecated.
- **Login, users, the updater, and backup restore:** deliberately left out.
- **Connecting Gmail** is done once in the app (Profile), not from Claude.

## Changes made to the CruSam app

Business logic the server needs was moved, not copied, into the pure-Dart
package `packages/crusam_core`, which the app now depends on (path
dependency). The old files in the app are one-line re-exports, so every
existing import keeps working.

- **Moved to core:** the invoice, employee, company, salary formula,
  margin, column-width, salary snapshot and disbursement models;
  `format_utils`; `pdf_col_widths`; the PDF builders (tax invoice bundle, bank
  disbursement, salary bill, statement, slips); and `SalaryFormulaEngine`.
- **New in core:** invoice totals and voucher factory, used by
  `voucher_notifier`; `SalaryMonthCalculator`, used by
  `salary_snapshot_notifier`; `SalarySnapshotStore`, used by
  `salary_snapshot_repository`; `EmployeeStore.formRow`, used by
  `employee_form_screen`; plus `ClientStore`, `EmailOutboxStore` and
  `FuzzyName`.
- **`ExportHooks`:** the PDF builders reach app services (asset loading, saved
  margins and column widths, the PDF saver, live salary days and MSW)
  through hooks set once at startup in `lib/shared/document_hooks.dart`. The
  `ExportPathTarget` enum moved with them.
- **Invoice date fix:** the invoice date you pick is now saved in
  `created_at`, which the app reads the date back from. Previously a
  back-dated invoice showed today's date after reopening.
- **Database:** `busy_timeout = 5000` so the app and the server wait for
  each other instead of failing. Two new additive tables: `clients` (address
  book) and `email_outbox`. No existing table or column changed.
- **New screen:** Clients in the sidebar, under Invoices.
- **Email outbox:** `lib/core/email/email_outbox_processor.dart`, started
  from `main.dart`, sends emails that Claude queued.

### Cleanup in app version 1.4.0

- **Google Drive sync removed** (deprecated). It still ran whenever a Gmail
  account was connected, queueing every employee and invoice save for
  upload to a shared Drive folder. The code, the Drive debug screen and the
  Drive text in Backup & Restore are gone. The `sync_*` tables and
  `cloud_id` columns are kept, so the database schema is unchanged.
- **Layout overflows fixed** on every screen and in the send dialogs, at
  window sizes from 960x520 up to 1920x1080, including during the sidebar
  collapse/expand animation. `test/overflow_scan_test.dart` renders every
  screen, and the main dialogs, with real data at those sizes and fails on
  any overflow. The Windows window can no longer be made smaller than
  960x520, and pages scroll instead of squeezing when the window is short.
- **Dead code removed:** unused screens (old login and landing pages),
  models and helpers, about 3,000 lines, plus the one-line re-export files
  from the core move. The app imports `crusam_core` directly.
- **Shared design tokens:** 13 screens had identical private copies of the
  same colours and text styles; they now share `core/theme/ink_tokens.dart`.
- **Invoice save is atomic:** a new invoice and its rows are written in one
  transaction.
- **Idle efficiency:** the animated background pauses while the app window
  isn't focused.

## Adding tools

Each tool group is one file in `lib/src/tools/`, implemented as a
`ToolGroup` that returns `ToolDef`s. Use `Args` for strict validation with
precise messages. Wrap writes in `ctx.store.write(...)`, which handles the
transaction, the backup, read-only mode and busy retries. Then add the group
to `buildToolGroups` in `lib/server.dart`, add tests under `test/` (the
`Harness` gives each test a throwaway database), and rebuild.
