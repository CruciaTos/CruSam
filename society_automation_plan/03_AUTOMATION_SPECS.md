# 03. Automation Specifications

Every spec lists: trigger, algorithm, outputs per mode, edge cases, tests. Dates `YYYY-MM-DD`, money in paise. "Today" comes from an injectable `Clock` (add `automation/engine/clock.dart`) so tests are deterministic.

---

## S1. Draft bill run (kind `draftBillRun`, key `draft_run`)

**Trigger:** daily. For each active billing rule frequency in the society, find the next period that has no posted or draft run.

**Algorithm**
1. Period for each frequency: monthly = calendar month, quarterly = Apr-Jun/Jul-Sep/Oct-Dec/Jan-Mar, half-yearly = Apr-Sep/Oct-Mar, yearly = financial year (Indian FY from the society's `financial_years`).
2. A run is **due** when `today >= period_start - lead_days` (default 3).
3. Skip if a bill run (draft or posted, not cancelled) already exists for that period and rule set.
4. Skip and create task `automation_error`-style warning if any active unit has no applicable rule, or metered rules lack readings (those are reported by S2 instead).
5. Call `previewBillRun`; if preview has no blocking errors, call `createDraftRun`.

**Outputs:** suggest/auto: draft run created, task `draft_bill_run` (severity `action`, deeplink to the run) with total billed and unit count. **Never posts**, in any mode.

**Edge cases:** society with no units; period spanning a financial-year boundary (split is not supported: create task explaining and stop); run already drafted by hand (no duplicate); closed year.

**Tests:** monthly society creates exactly one draft; second scheduler run creates none; quarterly rule only drafts at quarter start minus lead; existing manual draft blocks automation; posting is never called (verify with a spy or by asserting no journal entries).

---

## S2. Meter reading assistant (kind `meterCheck`, key `meter_check`)

**Trigger:** daily, from the 20th of the month (setting `automation.meter.start_day`, default 20) until readings complete.

**Algorithm**
1. For each active metered meter, find the reading for the current period.
2. **Missing**: no reading entered. One summary task `missing_meter` per society per period ("12 of 80 meters have no reading") with deeplink to the meters screen filtered to missing. Per-meter detail lives on the screen, not as separate tasks.
3. **Odd** readings, for entered readings: flag when (a) reading is lower than previous without a recorded reset, (b) consumption is above `max(3 x average of last 6 periods, 50 units)`, (c) consumption is zero for a meter whose average is above 20 units. One summary task `odd_meter`.
4. **Estimate helper:** the Meters screen gets a button "Fill missing with average of last 3" that creates readings marked estimated (use the existing reading `source`/note field if present; otherwise note text `Estimated`). Always an explicit user click.

**Outputs:** tasks only. No readings are created automatically.

**Tests:** missing detection, each odd rule, no flag for a normal series, estimate helper uses average of last 3 and respects meter rollover.

---

## S3. Bank statement auto-match (kind `bankMatch`, key `bank_match`)

**Trigger:** after `importStatement` completes (hook from the import flow) and daily.

**Input:** `bank_statement_lines` not yet cleared and without an open or accepted proposal.

**Algorithm (pure, in `statement_matcher.dart`)**

For each credit line (money in):
1. Parse narration with `NarrationParser`: extract UPI id / payer id, cheque or UTR number, NEFT/IMPS tokens, and unit tokens like `A-101`, `FLAT 101`, `B/203` (normalise by removing spaces and slashes, upper-case).
2. Candidate scoring, take the highest, break ties by oldest dues:

| Signal | Points |
|---|---|
| Learned rule hit (`bank_match_rules`) for payer id | 60 |
| Learned rule hit for narration token | 40 |
| Unit token found in narration and unit exists | 45 |
| Fuzzy payer name vs. member/tenant name (token set ratio >= 0.85) | 25 (>= 0.7 gives 12) |
| Amount equals unit's total outstanding | 30 |
| Amount equals unit's latest bill total, or its monthly regular charge | 20 |
| Amount equals an open receipt draft/pending cheque for that unit | 35 |
| Amount is a multiple of the unit's regular charge (advance for N periods) | 12 |
| Line date within 0 to 45 days after the unit's latest bill date | 5 |

   Cap at 100. A single weak signal can never reach auto level.
3. Cross-match with existing records first: a credit line that equals an existing **uncleared** receipt (same amount, deposit/reference match) becomes proposal `existing_receipt` (score 95 when reference matches, else 70). This prevents double-booking receipts already keyed by hand.
4. For each debit line: match to uncleared `vendor_payments` by exact amount and date window (+/- 5 days) and cheque/UTR token, proposal `existing_payment`; else propose vendor by learned rule or fuzzy vendor-name match (`vendor_payment` with score). Bank charges and interest credit lines matched by keyword list (`CHARGES`, `SMS CHARGES`, `INT.PD`, `INTEREST`) propose an `ignore`-style expense/income account proposal using learned rule or settings default account.
5. Inter-account movements (both accounts are the society's own bank accounts, same amount, within 3 days) become `transfer` proposals.

**Outputs per mode**
- **suggest:** store proposals in `bank_match_proposals` (min suggest score default 60); create one task `bank_match` summarising counts ("23 matched, 5 need you"). Unmatched credits stay in the list; user can create an unidentified receipt in one click.
- **auto:** additionally, for proposals with score >= `min_auto_score` (default 98) **and** kind `existing_receipt` / `existing_payment` (i.e. just clearing something already recorded), call `BankService.clearLine`. For `receipt_for_unit` auto level requires score 100 only when learned payer-id rule **and** unit token **and** amount match all hold; then call `CollectionService.createReceipt` (payment mode from narration, reference from UTR) allocating oldest first with the society's existing allocation rule, then clear the line. Anything below stays a proposal. Daily cap `automation.bank_match.auto_cap` (default 30 postings per society per day); beyond the cap, remaining items stay proposals and a task explains.

**User actions** (Bank Match screen): Accept (executes the same service calls as auto), Change target (pick another unit/vendor, then Accept), Reject (never proposed again for that line), Create unidentified receipt, Ignore line. **Accept and Change-target learn:** upsert `bank_match_rules` (payer id first, else the most distinctive narration token), `hits += 1`. Rejecting a learned-rule proposal decrements hits and deactivates the rule at 0.

**Edge cases:** one payment covering several units (propose split only when amounts equal the sum of two units' outstanding; otherwise leave to the user); duplicate statement import (existing import dedupe must be honoured); reversed cheque (debit with `RTN`/`RETURN` token proposes reversing the receipt via the existing reverse flow, never automatic); line already cleared by hand (superseded).

**Tests:** each signal; threshold behaviour; auto only clears existing records and creates receipts only on the strict triple; daily cap; learning increments; rejecting stops resurfacing; duplicates not double-posted (run matcher twice); fictional narrations only.

---

## S4. Dues reminder ladder and promises (kind `reminders`, key `reminders`)

**Trigger:** daily at app open.

**Ladder (default, editable in settings, stored as JSON list)**

```json
[
  {"step": 1, "after_days_overdue": 7,  "min_outstanding_paise": 100000, "tone": "gentle"},
  {"step": 2, "after_days_overdue": 21, "min_outstanding_paise": 100000, "tone": "firm"},
  {"step": 3, "after_days_overdue": 45, "min_outstanding_paise": 100000, "tone": "final"}
]
```

**Algorithm**
1. Overdue days = days since the due date of the oldest unpaid bill of the unit.
2. A unit is eligible for step N when overdue days >= `after_days_overdue`, outstanding >= minimum, no reminder at step >= N was sent for the current oldest-unpaid bill (use `reminder_log`), no **open promise** whose `promise_date >= today`, and the unit has a usable email.
3. Units without email are listed in the task as "no email: print or call", never skipped silently.
4. Build a batch via the existing reminder batch structures. Tone chooses the template text (3 built-in templates in code, editable footer through existing document footer feature).

**Outputs:** suggest: task `reminder_batch` ("14 reminders ready to send") deeplinking to the Dues screen with the batch preselected and previewed. auto: call `CommunicationService.sendReminderBatch`, write `reminder_log` with `mode='auto'`; failures are already logged in `email_log` by the existing service and surface as a task.

**Promises:** Dues screen gets "Record promise" per unit (date, amount, note). Daily job: a promise whose date passed with outstanding not reduced by at least the promised amount since `promised_on` becomes `broken` and creates task `promise_due`; one that was paid becomes `kept`. Broken promise lifts the suppression so the ladder resumes.

**Tests:** step selection by days; suppression by promise; no repeat for same bill and step; minimum outstanding; no email path; broken/kept transitions; auto mode calls sender exactly once per unit-step.

---

## S5. Late-interest preview (kind `interestPreview`, key `interest_preview`)

**Trigger:** with S1 (when a bill run draft is created) and monthly otherwise.

**Algorithm:** call the existing interest calculation for all units as of the next bill date, group result: number of units charged, total interest, top 5 units. Create task `interest_preview` with that summary and a deeplink to the draft run. Interest is already included by the bill-run flow; this task only makes it visible before posting. Flag units where interest exceeds 50% of principal outstanding as odd.

**Tests:** summary matches `previewBillRun` interest totals; disabled interest setting produces no task.

---

## S6. Recurring expenses (kind `recurringExpense`, key `recurring_expense`)

**Template model:** `recurring_templates` (see schema). Created from an existing expense bill via "Make recurring" button (copies vendor, lines, narration) or from the Recurring screen.

**Trigger:** daily.

**Algorithm**
1. For each active expense template with `next_due <= today + 3`: determine amount by `amount_mode`: `fixed` uses `fixed_paise`; `last_bill` uses the vendor's most recent posted bill total (scale line amounts proportionally, round half up, fix rounding on the largest line); `ask` creates a task requiring an amount and stops.
2. Build an expense bill draft (an in-memory `ExpenseBillDraft`, validated by existing `ExpenseService` rules including TDS section and GST from the vendor master).
3. suggest: task `recurring_expense` ("Security agency bill due 05-Jul, expected Rs 41,300") with deeplink to the expense form prefilled (route query `template=ID`). auto: only when `trusted=1` **and** amount within `tolerance_bp` of the last bill (fixed templates always qualify) -> `postExpenseBill`. Otherwise stays a task.
4. After creation or posting, advance `next_due` by frequency (clamped to `day_of_month`) and set `last_generated`.

**Edge cases:** vendor inactive (skip, task), financial year closed, month-end dates (day 29-31 not allowed: constrained 1-28), duplicate bill number (the existing duplicate guard decides).

**Tests:** next_due advancement for each frequency; amount modes; tolerance gate; trusted gate; duplicate prevention on rerun; TDS applied through service.

---

## S7. Payment run (kind `paymentRun`, key `payment_run`)

**Trigger:** weekly (cadence 7 days) and on app open Mondays.

**Algorithm:** list posted expense bills with outstanding > 0 grouped by due date: overdue, due within 7 days, due within 30 days. Respect vendor advances (net off). Create one task `payment_run` summarising counts and totals with deeplink to Payments screen filtered to "due soon". The Payments screen gets a **batch payment** action: select several bills of one vendor or many vendors, choose bank account, create the payments through `ExpenseService.postPayment` per vendor, and export a payment advice sheet (Excel, reuse export helpers). **Never auto-pays.**

**Tests:** grouping buckets, advances netted, batch creates one payment per vendor with correct allocations and TDS handling.

---

## S8. Deadline tracker (kind `deadlines`, key `deadlines`)

Computes upcoming statutory/operational dates from society settings and data, creates tasks `gst_due`, `tds_due`, `fd_maturity`, `fd_interest` `lead_days` (default 7) ahead:

| Item | Rule |
|---|---|
| TDS deposit | 7th of the next month for the month's deducted TDS (use current-law constant in one named function so it is easy to update); task only if TDS payable > 0 |
| TDS return | quarterly: 31 Jul, 31 Oct, 31 Jan, 31 May |
| GST return | per society GST registration setting (monthly 11th/20th, or quarterly per setting); task only when GST registered |
| FD maturity | `fixed_deposits.maturity_date` |
| FD interest due | per `interest_frequency` since last accrual |
| Insurance/AMC renewals | from optional `custom` tasks the user adds (Inbox "Add reminder") |

Keep all dates in one `DeadlineCalendar` class with unit tests so a rule change touches one place. If a rule is not configured (for example GST registration unknown), create **no** task rather than a wrong one.

**Tests:** each rule on boundary dates, lead days, no task when not applicable, auto-resolve after the item is done.

---

## S9. Anomaly and duplicate detection (kind `anomalyScan`, key `anomaly_scan`)

**Trigger:** daily, and on demand ("Scan now").

Rules (each has `rule_key`, severity, message template). Each produces findings with a `fingerprint` of `rule_key + entity ids`:

| rule_key | Detects | Severity |
|---|---|---|
| `dup_vendor_bill` | same vendor, same bill number or same amount within 3 days | warning |
| `dup_receipt` | same unit, same amount, same reference/cheque number | error |
| `dup_unit_name` | two units with the same normalised number in one block | error |
| `receipt_over_outstanding` | receipt with a large unallocated advance (> 3x regular charge) | info |
| `negative_dues_unit` | unit with advance but also overdue bills unallocated | warning |
| `large_expense_outlier` | expense line > 4x vendor's trailing median | warning |
| `backdated_posting` | posting date earlier than the last posted date by more than 60 days | info |
| `trial_balance_diff` | debits != credits (must never occur; severity error) | error |
| `bank_ledger_mismatch` | bank account ledger balance vs. last statement closing balance differs and no recon in 30 days | warning |
| `member_no_contact` | active member with dues but no email and no phone | info |
| `unit_no_rule` | active unit that no billing rule applies to | warning |
| `fy_not_next` | within 30 days of FY end and next FY not created | info |

Findings page lets user Acknowledge (with note) or mark Fixed. A rescan marks findings **fixed automatically** when the condition clears; acknowledged ones stay acknowledged while the condition persists. One summary task `finding` per society counts open errors/warnings.

**Tests:** each rule positive and negative case; fingerprint prevents duplicates across scans; auto-fix on clear; acknowledged persists.

---

## S10. Month-end command centre (kind `monthEnd`, key `month_end`)

Builds a live checklist for a period (default: the month just finished, switchable). Each check is computed from data (state `done`/`pending`/`blocked`), unless the user manually overrides it (stored with `manual_override=1`, still shown with an "overridden" chip).

| check_key | Done when | Action button |
|---|---|---|
| `meters_complete` | no active metered meter lacks a reading for the period (N/A if no meters) | Open meters |
| `bills_posted` | a posted run exists for every due frequency in the period | Open draft / bill runs |
| `receipts_entered` | no unmatched/uncleared credits on statements dated in the period | Bank match |
| `unidentified_cleared` | zero open unidentified receipts older than the period end | Unidentified |
| `expenses_entered` | every active recurring template due in the period was generated; no open `recurring_expense` task | Recurring |
| `payments_reviewed` | no overdue expense bills past 30 days (info only, never blocks) | Payment run |
| `bank_reconciled` | each bank account has a reconciliation covering the period end | Reconciliation |
| `interest_reviewed` | interest preview task for the period resolved | Draft run |
| `fd_accrued` | FD interest accrued through period end for each FD | Fixed deposits |
| `tax_reviewed` | GST/TDS registers opened for the period (record view event) or marked N/A | GST & TDS |
| `reminders_sent` | reminder batch task resolved or none eligible | Dues |
| `findings_clear` | zero open error-severity findings | Findings |
| `backup_done` | a backup file written within the last 24 hours after the last posting | Backup |
| `statements_ready` | (informational) I&E/Balance sheet render without error for the period | Statements |

A summary percentage per society feeds the Portfolio. Month-end is **never blocking** for posting; it is guidance. When all non-informational checks are done, show a single "Month closed" banner and offer a "Bulk send statements" button (existing communication service).

**Tests:** each check state from fixture data; manual override persists; percentage maths; period switching.

---

## S11. Auto-backup (kind `autoBackup`, key `auto_backup`, default mode `auto`)

**Trigger:** every `every_hours` (default 24) while the app is open, and immediately after year-end close or restore.

**Algorithm:** if posting activity since last backup exists (compare `MAX(updated)` proxy: last audit_log id), call `BackupService.exportSociety`, write `<folder>/<society-slug>_<yyyyMMdd_HHmm>` using the same extension and format the manual backup already writes, verify by `inspect()` and compare counts, then prune files beyond `keep`. If folder unset, use `AppPaths` child `society_backups/`. On any failure create `backup_due` task (urgent).

**Tests:** writes and verifies; prunes to `keep`; skips when nothing changed; failure creates task; filename slug safe for Windows.

---

## S12. Smart import (no kind; user-driven helpers)

- **Column auto-mapping:** `ColumnMapper.suggest(importKind, headers)` scores each target field against each header with: exact normalised match (1.0), known synonym table (0.9; e.g. `flat no`, `unit`, `apt` -> unit number; `mob`, `phone`, `contact` -> mobile; `mail` -> email), token-set similarity (>=0.75 accepted). Show suggestions pre-filled and editable. Unmapped required fields block Import.
- **Saved templates:** after a successful import offer "Save this mapping" into `import_templates`; next import with the same headers auto-selects it.
- **Dry run:** every import first runs a no-write validation pass returning created/updated/skipped counts and per-row errors; only then shows an Import button. Reuse existing `ImportService` validation by adding a `dryRun` parameter (default false) to each import method; dry run executes the same code inside a transaction that is rolled back.
- **Error file:** failed rows exported to Excel with an `Error` column, same headers as input, so the user can fix and re-import only those.

**Tests:** mapper synonyms; template round-trip; dry run leaves tables unchanged; counts equal real run; error file contains only failed rows.

---

## S13. Fast entry and bulk operations

- **Meter grid:** single screen, one row per meter with previous reading, keyboard navigation (Tab/Enter moves down, arrows move, no mouse needed), inline consumption and odd-reading highlight, save all in one transaction.
- **Receipt batch (cheque deposit slip):** enter several cheques (unit, amount, cheque no, date, bank) in a grid, post all, print one deposit slip PDF. Each posts through `createReceipt`.
- **Bulk actions on Bills / Receipts lists:** multi-select -> send email, print PDF (existing bulk PDF), export Excel.
- **Quick receipt:** from Command Palette, "Receive from A-101" opens receipt form with unit and outstanding prefilled.

**Tests:** meter grid saves transactionally (one invalid row blocks all and reports the row); deposit batch posts N receipts and slip totals match.

---

## S14. Search and command palette

`SearchService.search(societyId, query)` returns up to 30 hits across indexed entities, ordered by exact label match, prefix, then keyword substring. Ctrl+K anywhere in Society opens the palette: type to search, Enter to open, plus **commands** matching verbs: `receive`, `new bill`, `new expense`, `go to <screen>`, `switch society <name>`, `month end`, `inbox`, `scan now`, `backup now`. Arrow keys, Esc to close, remembers last 5 choices.

**Tests:** ranking order; index touches on create; reindex rebuilds from scratch; palette command parsing.

---

## S15. Portfolio and Today (cross-society)

`PortfolioService.summary()` reads per society (sequentially, cached 60 s): open task counts by severity, month-end percent, total outstanding dues, bank unmatched count, last backup age, FY end days. **Today** screen lists the highest priority open tasks across all societies sorted by severity then due date, grouped "Overdue / Today / This week / Later". Portfolio is a table of societies with these metrics and red/amber/green chips (rules in UI spec). Clicking a row switches `SocietyContext` to that society and opens the relevant screen.

**Tests:** aggregation with two fixture societies, ordering, isolation (no cross-society leakage in counts).
