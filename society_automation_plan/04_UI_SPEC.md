# 04. UI Specification

Follow the existing Society look: use `SocietyPage`, `SocietyDataTable`, `SocietyFilterBar`, `StatusChip`, `SocietyEmptyView`, `SocietyErrorView`, `MoneyField`, and existing amber/slate theme tokens. Do not introduce new colours except the three status tones below. Every screen needs loading, empty and error states. Phone width is unchanged (mobile shell untouched).

## 1. Navigation changes (`shell_screen.dart`, Phase A1 only)

Add to `_kSocietyNav`, directly after `Overview`:

```dart
_Route('/society/today',     Icons.today_outlined,            'Today'),
_Route('/society/inbox',     Icons.inbox_outlined,            'Inbox'),
_Route('/society/portfolio', Icons.dashboard_customize_outlined, 'Portfolio'),
_Route('/society/month-end', Icons.event_available_outlined,  'Month End'),
```

Add one group **Automation** after `Accounts`:

| Route | Icon | Label |
|---|---|---|
| `/society/bank-match` | `Icons.auto_fix_high_outlined` | Bank Match |
| `/society/recurring` | `Icons.repeat_outlined` | Recurring |
| `/society/findings` | `Icons.rule_folder_outlined` | Findings |
| `/society/automation` | `Icons.smart_toy_outlined` | Automation Settings |

The `Inbox` item shows a small count badge (open `action` + `urgent` tasks for the selected society, capped `99+`). The badge refreshes when `TaskService` notifies (a `ValueNotifier<int>` exposed by `TaskService.openCount`).

Add a `CallbackShortcuts` / `Shortcuts` wrapper in the Society body area of the shell for **Ctrl+K** that opens the command palette. It must be active only on Society routes and must not interfere with text fields (Ctrl+K is not a text-edit shortcut). Do not change CruSam-side behaviour.

Extend `societyNavPaths` and `societyRoutes` for every new route, mapped to real screens in the phase that builds them. A phase must not ship a route that shows a placeholder: add each route in the phase that delivers its screen, and update the route-table test then.

## 2. Status tones

| Tone | Meaning | Use |
|---|---|---|
| Green | all good | month-end 100%, no open tasks |
| Amber | needs action | open `action` tasks, month-end 40-99% |
| Red | urgent | open `urgent` tasks, error findings, backup older than 3 days, month-end < 40% in the last 10 days of the month |

Reuse `StatusChip` with these three tones.

## 3. Screens

### Today (`/society/today`)
All societies. Header: date, "N things need you". Groups: Overdue, Today, This week, Later. Row (`TaskTile`): severity dot, society name chip, title, detail line, due date, actions [Open] [Snooze v] [Done]. Snooze menu: Tomorrow, 3 days, Next week. Empty state: "Nothing needs you today." with a "Scan now" button.

### Inbox (`/society/inbox`)
Selected society only. Filter chips by kind group (Billing, Bank, Dues, Vendors, Deadlines, Data quality, System) and status (Open, Snoozed, Done). Bulk select -> Done / Snooze / Dismiss. "Add reminder" button creates a `custom` task (title, due date, note). History is kept; Done/Dismissed are viewable, never deleted.

### Portfolio (`/society/portfolio`)
Table, one row per active society: Name, Month-end %, Open tasks (U/A), Dues outstanding, Unmatched bank lines, Last backup, FY ends in, Status chip. Sort by status then name. Row click switches society and goes to Today filtered to that society. Footer totals row for dues and open tasks.

### Month End (`/society/month-end`)
Period selector (month dropdown, defaults to the last completed month), progress bar with percent, checklist list from spec S10. Each row: status icon, title, detail ("3 meters missing"), action button deeplinking to the relevant screen, overflow menu "Mark done manually / Mark not applicable / Reset". Bottom: "Bulk send statements" enabled when all required checks done.

### Bank Match (`/society/bank-match`)
Left: statement selector and counts (matched, review, unmatched, cleared). Main table of proposals sorted by score desc: Date, Narration, Amount (credit green / debit red), Proposed target (unit/vendor/account chip), Score bar with number, Reason text, actions [Accept] [Change] [Reject] [More v] (More: create unidentified receipt, ignore). Top toolbar: "Accept all >= 98" (confirm dialog listing count and total), "Re-run matching", "Import statement" (existing flow). Selecting a row opens a side panel showing the unit's dues, last receipts, and why the score was given (list of signals with points).

### Recurring (`/society/recurring`)
Table of templates: Name, Vendor, Frequency, Next due, Amount mode, Trusted toggle, Active toggle. Form dialog for create/edit with vendor picker, lines editor reused from expense form, frequency, day of month (1-28), amount mode. "Generate now" row action. Show last 3 generated bills per template in an expandable row.

### Findings (`/society/findings`)
Table: Severity, Rule, Message, Entity (link), First seen, Status. Row actions: Open entity, Acknowledge (note), Mark fixed. Filter by severity and status. Toolbar "Scan now".

### Automation Settings (`/society/automation`)
One card per automation from `AutomationKind` with: title, one-line description, `ModeSelector` (segmented Off / Suggest / Auto, Auto disabled with tooltip when `canAuto` is false), last run time and result chip, "Run now" button, and an expandable "Details" section for that automation's numeric settings (thresholds, ladder editor, tolerance, backup folder picker, keep count). A banner at top explains: "Auto mode posts or sends without asking. Suggest mode never changes your books." Switching any automation to Auto shows a confirm dialog naming exactly what it will do (text from the truth table in architecture section 3). Recent runs table (last 20) with status and counts.

### Command palette (Ctrl+K)
Centered 560-wide overlay, text field autofocus, results list with icon per entity type, sublabel in muted text, keyboard navigation, `Enter` open, `Esc` close. Section headings "Go to", "Commands", "Recent". Matches all spec S14 commands.

### Attention strip on Overview
Add under the overview header: a single row card "Needs attention" showing up to 3 top open tasks for the selected society with [Open] and a "View all" link to Inbox. When none: a quiet "All clear" line.

### Embedded entry points (existing screens)
- Meters: toolbar button "Fill missing with last-3 average" and the grid mode toggle.
- Bill runs: banner when a draft run was created by automation ("Draft prepared automatically on <date>. Review and post.").
- Dues: "Record promise" per unit, "Reminder ladder preview" button, promise chip per unit.
- Reconciliation and Bank: link "Auto-match this statement".
- Import: auto-mapping step, saved mapping selector, Dry run step, "Download error file".
- Expense form: "Make recurring" action.
- Payments: "Batch pay" action.
- Receipts: "Cheque deposit batch" action.
- Settings > Backup tab: shows auto-backup status and a link to Automation Settings.

## 4. Wording rules
Plain, short, sentence case. Say what will happen: "Post 12 receipts totalling Rs 84,200?" Never mention "AI". Use "Automation" and "suggestion".
