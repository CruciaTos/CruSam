# CruSam Society MCP Layer: Build Instructions

Let **Claude Desktop** work inside the Society workspace the way it already works inside CruSam: look things up, read photos and statements, prepare entries, and post them after the user approves. This extends the existing `mcp-server/` (server `crusam`, tools like `create_invoice`, `send_email`, `show_in_app`). It does not create a second server.

## Start here

Read in this order before writing code:

1. [Execution rules](society_mcp_plan/00_EXECUTION_RULES.md)
2. [Progress tracker](society_mcp_plan/PROGRESS.md)
3. [Architecture](society_mcp_plan/01_ARCHITECTURE.md)
4. [Tool catalogue, safety and prompts](society_mcp_plan/02_TOOLS.md)
5. [Build phases](society_mcp_plan/03_PHASES.md)

Also read the existing server first: `mcp-server/lib/server.dart`, `lib/src/tool_kit.dart`, `lib/src/db.dart`, `lib/src/tools/invoices.dart` (best example of dry-run then confirm), `lib/src/tools/email.dart` (outbox pattern) and `lib/src/ui_events.dart`.

**Start at the first unfinished phase in `PROGRESS.md` and build through Phase M8 in one continuous run.** Verify and report each phase. Stop only for a blocker in the execution rules or after the final report.

## Dependencies on earlier plans

- `society_plan/` (Society workspace): **done**, required.
- `society_automation_plan/` (automation layer): **optional**. Phase M7 adds automation tools only if `automation/` exists under the Society feature when M7 starts. If it does not, mark M7 "skipped: automation not built" in `PROGRESS.md` and continue.

## The one big design decision

The MCP server is a separate Dart process. Society's accounting logic (double-entry posting, bill runs, allocations, interest, TDS) lives in the Flutter app's folder today. Claude must **never** post through a second copy of that logic: two implementations of accounting will drift and corrupt books.

Decision: **Phase M0 moves the pure-Dart Society engine into a shared package `packages/society_core`**, exactly like `packages/crusam_core` is already shared between the app and the MCP server. The app and the server then call the *same* services. UI stays in the app. The 114 existing tests move with the engine and must all pass unchanged in behaviour.

Rejected alternatives: (a) re-implementing posting inside the server (drift risk); (b) a request queue where the running app executes every Claude action (works only while the app is open, and reads would need it too). Email still uses the existing outbox because only the app can reach Gmail.

## Safety model (summary; details in `02_TOOLS.md`)

1. **Reads are always allowed.** Every Society read tool is read-only and bounded.
2. **Writes are gated per society** by a setting the user controls in the app: `Off`, `Drafts only` (default), `Full`. Drafts-only lets Claude prepare things (meter readings, draft bill runs, unidentified receipts, expense-bill drafts) but not post to the books.
3. **Every write is two steps**: `dry_run=true` returns a preview and a `preview_id`; the real write needs that `preview_id` and an explicit user go-ahead from the chat. Previews expire after 10 minutes or when the books change.
4. **Nothing is ever deleted or edited once posted.** Only the existing reverse flows, each needing a reason.
5. **Never exposed:** year-end close/reopen, restore backup, delete society, change financial-year dates, change GST/TDS registration, change settings that alter accounting. The user does those in the app.
6. Every Claude action is recorded in `audit_log` with actor `mcp:claude`, and the server backs up `society.db` before its first write each session.

## In scope

- Move Society engine to `packages/society_core` (M0)
- Society database access, society resolver, money/date parsing helpers, previews (M1)
- About 40 tools: read, draft, post, reverse, email-via-outbox (M2 to M4)
- Prompts/workflows for photos, bank statements, month-end, dues chase (M5)
- App side: write-access setting, live refresh when Claude changes data, Claude activity indicator, Follow Claude inside Society (M6)
- Automation bridge tools (M7, conditional)
- Tests, manifest/version bump, install docs, final scan (M8)

## Out of scope

Network access from the server, calling any LLM from the app, resident-facing anything, changing CruSam (non-Society) tools, a second MCP server, auto-approving anything, any tool that bypasses the dry-run/confirm rule.

## Finish condition

Complete when Phase M8 passes, all old and new tests pass in all three places (`packages/society_core`, `crusam/`, `mcp-server/`), the built extension installs, every write tool honours the access setting and dry-run rule (proved by tests), and `PROGRESS.md` holds every report.
