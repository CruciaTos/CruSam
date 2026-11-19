# 00. Execution Rules

Rules from `society_plan/00_EXECUTION_RULES.md` still apply except where this file overrides them: no commits/pushes/stashes, no `double` money, no silent catches, no TODO/fake data, no marking partial tasks done, report disagreements, one verification per phase.

## 1. Authority order

1. `society_plan/02_SCHEMA.sql` and `society_automation_plan/02_SCHEMA_M002.sql` for tables
2. `society_plan/03_ACCOUNTING_RULES.md` for every posting and calculation (unchanged)
3. `01_ARCHITECTURE.md` for structure
4. `02_TOOLS.md` for tool behaviour and safety
5. `03_PHASES.md` for order and acceptance

## 2. Allowed changes by phase

### Phase M0 (the move) may touch
- Create `packages/society_core/` (new package) and move files into it per `01_ARCHITECTURE.md` section 2.
- Edit every Society file's imports (mechanical rewrite). No logic edits except those listed in M0 tasks (injecting the DB path, the email sender interface, removing Flutter imports from engine models).
- Edit `crusam/pubspec.yaml` and `mcp-server/pubspec.yaml` **only** to add the path dependency `society_core`. No other dependency change. `pubspec.lock` changes caused by that are expected.
- Move `crusam/test/society/*` engine tests into `packages/society_core/test/`; keep widget/route tests in `crusam/test/society/`.

### Phases M1 to M5, M7, M8 may touch
- `mcp-server/lib/src/society/` (new), `mcp-server/lib/server.dart` (register group, bump version, extend instructions), `mcp-server/lib/src/config.dart` (society db path), `mcp-server/lib/src/ui_events.dart` (society focus events), `mcp-server/test/society/` (new), `mcp-server/extension/manifest.json`, `mcp-server/README.md`, `mcp-server/dist` docs, `mcp-server/tool/` build scripts if needed.

### Phase M6 (app side) may touch
- `crusam/lib/features/society/` (screens, settings tab, widgets)
- `crusam/lib/core/sync/db_change_watcher.dart` (watch society.db too)
- `crusam/lib/core/sync/claude_follow_controller.dart` (Society routes)
- `crusam/lib/features/shell/shell_screen.dart` (Follow Claude toggle visible in Society; activity banner)
- `crusam/lib/main.dart` only if the watcher registration needs it (note why)

### Never edit
CruSam non-Society tools in `mcp-server/lib/src/tools/*` (read for patterns, do not change), `packages/crusam_core`, existing aarti.db schema/migrations, salary/invoice logic, installer/updater files, `analysis_options.yaml`, Society accounting rules.

## 3. Extra forbidden actions

- Any Society write from the server that does not go through a `society_core` service method.
- Raw SQL in the server for Society writes. Raw SQL for reads is allowed **only** via `society_core` repositories or small read-only query helpers inside `society_core` (never in the server).
- Running Society migrations from the server. If `PRAGMA user_version` is not in the supported list, the server serves nothing for Society and says why (reads included).
- A write tool without `dry_run`, `preview_id` verification, access-setting check, `read_only` check, and audit entry. One shared `SocietyWriteGate` must enforce all five; tools must not re-implement them.
- Exposing year-end, restore, delete, financial-year, registration or accounting-setting tools.
- Returning more than 200 rows from any tool. Every list tool paginates (`limit` default 50, max 200, `cursor`).
- Putting secrets, bank account numbers in full, or email addresses in server logs. Server logs go to stderr only and never to stdout (stdout is the MCP channel).

## 4. Verification

Once per phase, from the right folders:

```bash
cd packages/society_core && dart analyze && dart test
cd crusam && flutter analyze lib/features/society test/society lib/core lib/features/shell && flutter test test/society
cd mcp-server && dart analyze && dart test
```

A phase that touches only one area still runs that area's commands and, at M0, M6 and M8, all three.

## 5. Stop and ask only when

- Moving a file into `society_core` would require a Flutter import that cannot be removed without changing behaviour.
- A Society service lacks a public method a tool needs and adding one would change existing behaviour.
- The supported `society.db` version list cannot be determined.
- A test expectation appears wrong.
- A tool would need a posting not covered by the accounting rules.
